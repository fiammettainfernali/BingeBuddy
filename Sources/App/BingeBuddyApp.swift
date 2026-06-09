import SwiftUI
import SwiftData
import FirebaseCore

@main
struct BingeBuddyApp: App {
    let container: ModelContainer
    @StateObject private var session = Session()
    @StateObject private var library = LibraryStore()
    @StateObject private var suggestions = SuggestionStore()

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
                .task { await session.bootstrap() }
        }
        .modelContainer(container)
    }
}
