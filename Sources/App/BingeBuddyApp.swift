import SwiftUI
import SwiftData

@main
struct BingeBuddyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: WatchItem.self)
    }
}
