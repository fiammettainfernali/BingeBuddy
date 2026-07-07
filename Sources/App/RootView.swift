import SwiftUI

/// The five main tabs of the app.
struct RootView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var suggestions: SuggestionStore
    @EnvironmentObject private var notifications: NotificationManager
    @ObservedObject private var errors = ErrorCenter.shared

    private var configKey: String { "\(session.uid ?? "")|\(session.household?.id ?? "")" }

    private var watchingKey: String {
        library.myPersonal
            .filter { $0.state == .watching && $0.source == "tmdb" && $0.mediaType == .tv }
            .map(\.mediaKey).sorted().joined()
    }

    /// Changes when watching shows or their progress change — drives widget refreshes.
    private var widgetKey: String {
        library.myPersonal
            .filter { $0.state == .watching && $0.mediaType != .movie }
            .map { "\($0.mediaKey):\($0.currentSeason):\($0.currentEpisode)" }
            .sorted().joined()
    }

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "rectangle.stack.fill") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            TogetherView()
                .tabItem { Label("Together", systemImage: "heart.fill") }

            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray.fill") }
                .badge(suggestions.pendingCount)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
        .task(id: configKey) {
            library.configure(householdId: session.household?.id, uid: session.uid)
            suggestions.configure(householdId: session.household?.id, uid: session.uid)
        }
        .task(id: watchingKey) {
            await notifications.refreshStatus()
            await notifications.scheduleEpisodeReminders(for: library.myPersonal)
        }
        .task(id: widgetKey) {
            await WidgetDataWriter.update(from: library.myPersonal)
        }
        .alert("Something didn't save", isPresented: Binding(
            get: { errors.message != nil },
            set: { if !$0 { errors.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errors.message ?? "")
        }
    }
}

