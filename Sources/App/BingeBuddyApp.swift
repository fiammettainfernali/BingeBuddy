import SwiftUI
import SwiftData

@main
struct BingeBuddyApp: App {
    let container: ModelContainer

    init() {
        do {
            // .automatic picks up the CloudKit container from the app's entitlements,
            // syncing each user's library to their own private iCloud database.
            let config = ModelConfiguration(cloudKitDatabase: .automatic)
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
