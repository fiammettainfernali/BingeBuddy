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
