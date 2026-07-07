import Foundation

/// One show in the home-screen widget. Compiled into BOTH the app (writer) and the
/// widget extension (reader) — keep it dependency-free.
struct UpNextShow: Codable, Identifiable {
    let key: String
    let title: String
    let subtitle: String
    let posterFile: String?
    var id: String { key }
}

/// Reads/writes the widget snapshot in the shared App Group container.
enum WidgetStore {
    static let appGroup = "group.com.jessesmith.bingebuddy"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("upnext.json")
    }

    static func posterURL(_ file: String) -> URL? {
        containerURL?.appendingPathComponent(file)
    }

    static func loadShows() -> [UpNextShow] {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([UpNextShow].self, from: data)) ?? []
    }

    static func saveShows(_ shows: [UpNextShow]) {
        guard let url = snapshotURL, let data = try? JSONEncoder().encode(shows) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
