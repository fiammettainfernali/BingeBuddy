import Foundation

/// Routes search/detail requests to the right provider and normalizes the results.
struct MetadataService {
    private let tmdb = TMDBProvider()
    private let anilist = AniListProvider()

    func search(_ query: String, scope: SearchScope) async throws -> [MediaSearchResult] {
        switch scope {
        case .moviesTV: return try await tmdb.search(query)
        case .anime: return try await anilist.search(query)
        }
    }

    func details(for result: MediaSearchResult) async throws -> MediaDetails {
        switch result.source {
        case "anilist": return try await anilist.details(sourceId: result.sourceId, mediaType: .anime)
        default: return try await tmdb.details(sourceId: result.sourceId, mediaType: result.mediaType)
        }
    }
}
