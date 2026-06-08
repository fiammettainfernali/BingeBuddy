import SwiftUI

/// Phase 0 shell: the five tabs that will hold the real features.
/// Each tab is a placeholder for now — we're proving the build pipeline first.
struct RootView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var library: LibraryStore

    private var configKey: String { "\(session.uid ?? "")|\(session.household?.id ?? "")" }

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "rectangle.stack.fill") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            PlaceholderTab(
                title: "Together",
                systemImage: "heart.fill",
                message: "Stuff you watch as a couple — and your match list."
            )
            .tabItem { Label("Together", systemImage: "heart.fill") }

            PlaceholderTab(
                title: "Inbox",
                systemImage: "tray.fill",
                message: "Show ideas your partner sends you."
            )
            .tabItem { Label("Inbox", systemImage: "tray.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
        .task(id: configKey) {
            library.configure(householdId: session.household?.id, uid: session.uid)
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    RootView()
}
