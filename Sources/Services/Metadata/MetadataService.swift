import Foundation

/// Session-lived cache of AniList-id → MAL-id resolutions (legacy library items).
actor MalIdCache {
    static let shared = MalIdCache()
    private var cache: [String: Int] = [:]

    func resolve(anilistId: String, using provider: AniListProvider) async -> Int? {
        if let cached = cache[anilistId] { return cached }
        guard let resolved = (try? await provider.malId(anilistId: anilistId)) ?? nil else { return nil }
        cache[anilistId] = resolved
        return resolved
    }
}

/// Routes search/detail requests to the right provider and normalizes the results.
struct MetadataService: Sendable {
    private let tmdb = TMDBProvider()
    private let jikan = JikanProvider()
    private let kitsu = KitsuProvider()       // anime charts (Jikan's chart endpoints are flaky)
    private let anilist = AniListProvider()   // legacy: resolves anime added before the Jikan switch

    func search(_ query: String, scope: SearchScope) async throws -> [MediaSearchResult] {
        switch scope {
        case .moviesTV: return try await tmdb.search(query)
        case .anime: return try await jikan.search(query)
        }
    }

    func details(for result: MediaSearchResult) async throws -> MediaDetails {
        switch result.source {
        case "jikan": return try await jikan.details(sourceId: result.sourceId)
        case "anilist": return try await anilist.details(sourceId: result.sourceId, mediaType: .anime)
        default: return try await tmdb.details(sourceId: result.sourceId, mediaType: result.mediaType)
        }
    }

    func recommendations(for result: MediaSearchResult) async throws -> [MediaSearchResult] {
        switch result.source {
        case "jikan": return try await jikan.recommendations(sourceId: result.sourceId)
        case "anilist": return try await anilist.recommendations(sourceId: result.sourceId)
        default: return try await tmdb.recommendations(sourceId: result.sourceId, mediaType: result.mediaType)
        }
    }

    /// Episode checklist for one season (TV) or one 100-episode page (anime).
    /// `lastPage` is always 1 for TV.
    ///
    /// Anime uses a fallback chain: Jikan (titles + dates when MAL has them and the endpoint
    /// cooperates) → AniList airing schedule (numbers + dates). Legacy AniList-era items are
    /// bridged to their MAL id first, so they get the full experience without re-adding.
    func episodes(for result: MediaSearchResult, season: Int, page: Int = 1)
        async throws -> (episodes: [EpisodeInfo], lastPage: Int) {
        switch result.source {
        case "jikan":
            if let fetched = try? await jikan.episodes(animeId: result.sourceId, page: page),
               !fetched.episodes.isEmpty {
                return fetched
            }
            let fallback = (try? await anilist.episodes(malId: result.sourceId)) ?? []
            return Self.paged(fallback, page: page)
        case "anilist":
            if let mal = await MalIdCache.shared.resolve(anilistId: result.sourceId, using: anilist),
               let fetched = try? await jikan.episodes(animeId: String(mal), page: page),
               !fetched.episodes.isEmpty {
                return fetched
            }
            let fallback = (try? await anilist.episodes(anilistId: result.sourceId)) ?? []
            return Self.paged(fallback, page: page)
        case "tmdb" where result.mediaType == .tv:
            return (try await tmdb.episodes(tvId: result.sourceId, season: season), 1)
        default:
            return ([], 1)
        }
    }

    /// Slice a full episode list into 100-episode pages (matching Jikan's paging).
    static func paged(_ episodes: [EpisodeInfo], page: Int) -> (episodes: [EpisodeInfo], lastPage: Int) {
        guard !episodes.isEmpty else { return ([], 1) }
        let perPage = 100
        let lastPage = (episodes.count + perPage - 1) / perPage
        let clamped = min(max(page, 1), lastPage)
        let start = (clamped - 1) * perPage
        return (Array(episodes[start..<min(start + perPage, episodes.count)]), lastPage)
    }

    /// How to schedule episode reminders for a given title.
    func episodeSchedule(for result: MediaSearchResult) async -> EpisodeSchedule {
        if result.source == "jikan" {
            if let weekday = await jikan.airingWeekday(animeId: result.sourceId) {
                return .weekly(weekday: weekday, label: "New episode of \(result.title) airs today")
            }
            return .none
        }
        if result.source == "tmdb" && result.mediaType == .tv {
            let episodes = (try? await tmdb.upcomingEpisodes(tvId: result.sourceId)) ?? []
            return episodes.isEmpty ? .none : .dates(episodes)
        }
        return .none
    }

    func trending(scope: SearchScope) async -> [MediaSearchResult] {
        switch scope {
        case .anime: return (try? await kitsu.trending()) ?? []
        case .moviesTV:
            return await collect(pages: 3) { (try? await tmdb.trending(page: $0)) ?? [] }
        }
    }

    func popular(scope: SearchScope) async -> [MediaSearchResult] {
        switch scope {
        case .anime: return (try? await kitsu.popular()) ?? []
        case .moviesTV:
            return await collect(pages: 3) { (try? await tmdb.popular(mediaType: .movie, page: $0)) ?? [] }
        }
    }

    /// Fetch several pages in order and concatenate, dropping duplicates.
    private func collect(pages: Int, _ fetch: (Int) async -> [MediaSearchResult]) async -> [MediaSearchResult] {
        var all: [MediaSearchResult] = []
        var seen = Set<String>()
        for page in 1...pages {
            let items = await fetch(page)
            if items.isEmpty { break }
            for item in items where seen.insert(item.id).inserted { all.append(item) }
        }
        return all
    }
}
