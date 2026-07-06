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

    /// Reschedule a reminder for the next episode of each currently-watching TV series.
    func scheduleEpisodeReminders(for items: [LibraryItem]) async {
        guard authorized else { return }
        let center = UNUserNotificationCenter.current()

        // Clear our previously-scheduled episode reminders before re-adding.
        let pending = await center.pendingNotificationRequests()
        let ourIds = pending.filter { $0.identifier.hasPrefix("ep-") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ourIds)

        let watching = items.filter {
            $0.state == .watching && $0.source == "tmdb" && $0.mediaType == .tv
        }
        for item in watching {
            guard let details = try? await service.details(for: item.asSearchResult),
                  let airDate = details.nextEpisodeAirDate, airDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "New episode: \(item.title)"
            content.body = details.nextEpisodeLabel ?? "A new episode airs today."
            content.sound = .default

            var comps = Calendar.current.dateComponents([.year, .month, .day], from: airDate)
            comps.hour = 9   // air_date has no time; remind at 9am
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "ep-\(item.mediaKey)",
                                                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
