import Foundation
import WidgetKit

/// Keeps the home-screen widget's snapshot in sync with the library: the shows you're
/// watching (most recently touched first) with a "next episode" line and a cached poster.
enum WidgetDataWriter {
    static func update(from items: [LibraryItem]) async {
        guard WidgetStore.containerURL != nil else { return }   // no App Group → no widget

        let watching = items
            .filter { $0.state == .watching && $0.mediaType != .movie }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .prefix(4)

        var shows: [UpNextShow] = []
        for item in watching {
            let next = item.totalEpisodes > 0
                ? min(item.currentEpisode + 1, item.totalEpisodes)
                : item.currentEpisode + 1
            let subtitle = item.totalSeasons > 1
                ? "Next: S\(item.currentSeason) E\(next)"
                : "Next: Episode \(next)"
            let posterFile = await cachePoster(for: item)
            shows.append(UpNextShow(key: item.mediaKey, title: item.title,
                                    subtitle: subtitle, posterFile: posterFile))
        }

        WidgetStore.saveShows(shows)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Downloads the poster into the shared container (once per title). Stored as-is —
    /// source posters are small (~50–150 KB), and skipping re-encoding removes a whole
    /// class of failure modes.
    private static func cachePoster(for item: LibraryItem) async -> String? {
        guard let poster = item.posterURL, let url = URL(string: poster) else { return nil }
        let safeKey = item.mediaKey.replacingOccurrences(of: "/", with: "_")
        let file = "poster-\(safeKey).jpg"
        guard let destination = WidgetStore.posterURL(file) else { return nil }
        if FileManager.default.fileExists(atPath: destination.path) { return file }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              !data.isEmpty else { return nil }
        do {
            try data.write(to: destination, options: [.atomic, .noFileProtection])
            return file
        } catch {
            return nil
        }
    }
}
