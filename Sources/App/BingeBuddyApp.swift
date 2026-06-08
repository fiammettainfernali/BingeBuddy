import SwiftUI
import SwiftData
import FirebaseCore

@main
struct BingeBuddyApp: App {
    let container: ModelContainer

    init() {
        FirebaseApp.configure()
        do {
            // SwiftData stays local-only now; Firebase/Firestore handles sync + sharing.
            let config = ModelConfiguration(cloudKitDatabase: .none)
            container = try ModelContainer(for: WatchItem.self, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
