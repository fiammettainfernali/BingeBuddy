import SwiftUI
import SwiftData
import FirebaseCore

@main
struct BingeBuddyApp: App {
    let container: ModelContainer
    @StateObject private var session = Session()
    @StateObject private var library = LibraryStore()
    @StateObject private var suggestions = SuggestionStore()
    @StateObject private var vault = VaultManager()
    @StateObject private var notifications = NotificationManager()

    init() {
        FirebaseApp.configure()
        do {
            // SwiftData stays local-only (reserved for the on-device vault); Firestore syncs the rest.
            let config = ModelConfiguration(cloudKitDatabase: .none)
            container = try ModelContainer(for: WatchItem.self, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(library)
                .environmentObject(suggestions)
                .environmentObject(vault)
                .environmentObject(notifications)
                .task { await session.bootstrap() }
        }
        .modelContainer(container)
    }
}
