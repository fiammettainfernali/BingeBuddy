import Foundation

/// A normalized search hit, the same shape whether it came from TMDB or AniList.
struct MediaSearchResult: Identifiable, Hashable, Sendable {
    let source: String
    let sourceId: String
    let title: String
    let mediaType: MediaType
    let year: String?
    let posterURL: String?
    let overview: String

    var id: String { "\(source)-\(sourceId)" }
}

struct SeasonInfo: Hashable, Sendable {
    let number: Int
    let name: String
    let episodeCount: Int
}

struct MediaDetails: Sendable {
    let result: MediaSearchResult
    let totalSeasons: Int
    let totalEpisodes: Int
    let genres: [String]
    let seasons: [SeasonInfo]
    var nextEpisodeAirDate: Date? = nil
    var nextEpisodeLabel: String? = nil
    var lastAiredSeason: Int? = nil
    var lastAiredEpisode: Int? = nil
}

struct EpisodeAiring: Sendable {
    let date: Date
    let label: String
}

/// One episode in a checklist.
struct EpisodeInfo: Identifiable, Sendable {
    let number: Int
    let title: String?
    let airDate: Date?
    var id: Int { number }
}

/// One place a title can be streamed.
struct WatchProvider: Identifiable, Sendable {
    let name: String
    let logoURL: String?
    let url: String?          // tappable deep link when the source provides one
    var id: String { name }
}

/// Where a title is available to stream, plus attribution/overflow links.
struct WatchAvailability: Sendable {
    let providers: [WatchProvider]
    let moreLink: String?     // full listing page (TMDB/JustWatch)
    let attribution: String?  // required credit line for the data source
}

/// Pure watermark math for the episode checklist. Progress is linear (a watermark of
/// season/episode), so "checking" an episode marks everything up to it as watched.
enum EpisodeProgress {
    /// Is (season, episode) covered by the watermark?
    static func isWatched(season: Int, episode: Int,
                          currentSeason: Int, currentEpisode: Int) -> Bool {
        season < currentSeason || (season == currentSeason && episode <= currentEpisode)
    }

    /// The new watermark after tapping (season, episode): tapping the exact watermark
    /// rewinds one episode (crossing season boundaries using known episode counts);
    /// tapping anything else moves the watermark straight there.
    static func watermarkAfterTap(season: Int, episode: Int,
                                  currentSeason: Int, currentEpisode: Int,
                                  seasons: [SeasonInfo]) -> (season: Int, episode: Int) {
        if season == currentSeason && episode == currentEpisode {
            if episode > 1 { return (season, episode - 1) }
            if season > 1 {
                let previousCount = seasons.first { $0.number == season - 1 }?.episodeCount ?? 0
                return (season - 1, previousCount)
            }
            return (season, 0)
        }
        return (season, episode)
    }
}

/// How to schedule reminders for a show's upcoming episodes.
enum EpisodeSchedule: Sendable {
    case dates([EpisodeAiring])              // concrete upcoming air dates (TMDB TV)
    case weekly(weekday: Int, label: String) // recurring weekly (currently-airing anime)
    case none
}

enum SearchScope: String, CaseIterable, Identifiable, Hashable {
    case moviesTV = "Movies & TV"
    case anime = "Anime"

    var id: String { rawValue }
}

enum MetadataError: Error {
    case badURL
    case badResponse
    case decoding
}

protocol MediaProvider {
    func search(_ query: String) async throws -> [MediaSearchResult]
    func details(sourceId: String, mediaType: MediaType) async throws -> MediaDetails
}

extension String {
    /// Strip HTML tags / common entities (AniList descriptions contain them).
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
