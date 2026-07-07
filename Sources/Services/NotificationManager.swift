import Foundation
import UserNotifications

/// Schedules local reminders for the next episode of shows you're currently watching.
///
/// Note: local notifications work without a server, but only the *known* next episode can be
/// scheduled. When that episode airs, the following one is scheduled the next time you open the
/// app — so keep opening BingeBuddy now and then and reminders stay current.
@MainActor
final class NotificationManager: ObservableObject {
    @Published var authorized = false

    private let service = MetadataService()

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorized = settings.authorizationStatus == .authorized
    }

    func requestAuthorization() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorized = granted
    }

    private let lastScheduleKeyDefault = "notifications.lastScheduleKey"
    private let lastScheduleDateDefault = "notifications.lastScheduleDate"

    /// Reschedule reminders for every upcoming episode of the shows you're watching.
    /// These fire even when the app is closed.
    ///
    /// Scheduling fetches details for every watching show, so it's budgeted: it only re-runs
    /// when the watching list actually changed or the last run is over ~20h old (once a day).
    /// Pass `force: true` to bypass (e.g. right after the user enables reminders).
    func scheduleEpisodeReminders(for items: [LibraryItem], force: Bool = false) async {
        guard authorized else { return }

        let watching = items.filter {
            $0.state == .watching && ($0.mediaType == .tv || $0.mediaType == .anime)
        }

        let defaults = UserDefaults.standard
        let key = watching.map(\.mediaKey).sorted().joined(separator: ",")
        let lastKey = defaults.string(forKey: lastScheduleKeyDefault)
        let lastRun = defaults.object(forKey: lastScheduleDateDefault) as? Date ?? .distantPast
        if !force && key == lastKey && Date().timeIntervalSince(lastRun) < 20 * 3600 {
            return
        }

        let center = UNUserNotificationCenter.current()

        // Clear our previously-scheduled episode reminders before re-adding.
        let pending = await center.pendingNotificationRequests()
        let ourIds = pending.filter { $0.identifier.hasPrefix("ep-") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ourIds)
        var scheduled = 0
        for item in watching where scheduled < 50 {   // stay under iOS's 64 pending limit
            switch await service.episodeSchedule(for: item.asSearchResult) {
            case .dates(let airings):
                for airing in airings.prefix(8) where scheduled < 50 {
                    var comps = Calendar.current.dateComponents([.year, .month, .day], from: airing.date)
                    comps.hour = 9
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    await addReminder(id: "ep-\(item.mediaKey)-\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)",
                                      title: "New episode: \(item.title)", body: airing.label, trigger: trigger)
                    scheduled += 1
                }
            case .weekly(let weekday, let label):
                var comps = DateComponents()
                comps.weekday = weekday
                comps.hour = 9
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                await addReminder(id: "ep-\(item.mediaKey)-weekly",
                                  title: "New episode: \(item.title)", body: label, trigger: trigger)
                scheduled += 1
            case .none:
                break
            }
        }

        defaults.set(key, forKey: lastScheduleKeyDefault)
        defaults.set(Date(), forKey: lastScheduleDateDefault)
    }

    private func addReminder(id: String, title: String, body: String, trigger: UNNotificationTrigger) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
