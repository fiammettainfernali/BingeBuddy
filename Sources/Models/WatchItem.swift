import Foundation
import SwiftData

/// A title in someone's library, with their personal state, rating, and progress.
/// Metadata is denormalized onto the item for Phase 1 (simple + offline-friendly).
///
/// CloudKit rules: no `.unique` constraints, and every stored property must be optional
/// or have a default value — hence the defaults below.
@Model
final class WatchItem {
    /// Stable id: "<source>-<sourceId>", e.g. "tmdb-1399" or "anilist-21".
    /// (Dedup is enforced in code, since CloudKit disallows unique constraints.)
    var id: String = ""

    var title: String = ""
    var mediaTypeRaw: String = MediaType.movie.rawValue
    var stateRaw: String = WatchState.wantToWatch.rawValue
    var overview: String = ""
    var posterURL: String?
    var year: String?
    var rating: Int = 0            // 0 = unrated, otherwise 1...5
    var currentSeason: Int = 1
    var currentEpisode: Int = 0
    var totalSeasons: Int = 0
    var totalEpisodes: Int = 0
    var genres: [String] = []
    var source: String = ""        // "tmdb" | "anilist"
    var sourceId: String = ""
    var note: String = ""
    var addedAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: String,
        title: String,
        mediaType: MediaType,
        state: WatchState,
        overview: String = "",
        posterURL: String? = nil,
        year: String? = nil,
        rating: Int = 0,
        currentSeason: Int = 1,
        currentEpisode: Int = 0,
        totalSeasons: Int = 0,
        totalEpisodes: Int = 0,
        genres: [String] = [],
        source: String,
        sourceId: String,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.mediaTypeRaw = mediaType.rawValue
        self.stateRaw = state.rawValue
        self.overview = overview
        self.posterURL = posterURL
        self.year = year
        self.rating = rating
        self.currentSeason = currentSeason
        self.currentEpisode = currentEpisode
        self.totalSeasons = totalSeasons
        self.totalEpisodes = totalEpisodes
        self.genres = genres
        self.source = source
        self.sourceId = sourceId
        self.note = note
        self.addedAt = Date()
        self.updatedAt = Date()
    }

    var mediaType: MediaType { MediaType(rawValue: mediaTypeRaw) ?? .movie }

    var state: WatchState {
        get { WatchState(rawValue: stateRaw) ?? .wantToWatch }
        set { stateRaw = newValue.rawValue }
    }

    /// Convert back to a search-result shape so the detail screen can be reused.
    var asSearchResult: MediaSearchResult {
        MediaSearchResult(
            source: source,
            sourceId: sourceId,
            title: title,
            mediaType: mediaType,
            year: year,
            posterURL: posterURL,
            overview: overview
        )
    }
}
