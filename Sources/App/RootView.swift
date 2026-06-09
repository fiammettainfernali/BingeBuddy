import SwiftUI

/// The five main tabs of the app.
struct RootView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var suggestions: SuggestionStore

    private var configKey: String { "\(session.uid ?? "")|\(session.household?.id ?? "")" }

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
    }
}

