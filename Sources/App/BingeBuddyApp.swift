import SwiftUI
import SwiftData
import FirebaseCore

@main
struct BingeBuddyApp: App {
    let container: ModelContainer
    @StateObject private var session = Session()

    init() {
        FirebaseApp.configure()
        do {
            // SwiftData stays local-only (vault + cache); Firestore handles sync + sharing.
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
                .task { await session.bootstrap() }
        }
        .modelContainer(container)
    }
}
