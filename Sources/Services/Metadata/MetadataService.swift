import Foundation

/// Routes search/detail requests to the right provider and normalizes the results.
struct MetadataService: Sendable {
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

    func recommendations(for result: MediaSearchResult) async throws -> [MediaSearchResult] {
        switch result.source {
        case "anilist": return try await anilist.recommendations(sourceId: result.sourceId)
        default: return try await tmdb.recommendations(sourceId: result.sourceId, mediaType: result.mediaType)
        }
    }

    func trending(scope: SearchScope) async throws -> [MediaSearchResult] {
        switch scope {
        case .moviesTV: return try await tmdb.trending()
        case .anime: return try await anilist.trending()
        }
    }

    func popular(scope: SearchScope) async throws -> [MediaSearchResult] {
        switch scope {
        case .moviesTV: return try await tmdb.popular(mediaType: .movie)
        case .anime: return try await anilist.popular()
        }
    }
}
