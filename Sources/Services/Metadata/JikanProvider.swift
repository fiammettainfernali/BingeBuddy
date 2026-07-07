import Foundation

/// Serializes Jikan requests so bursts (e.g. loading recommendations) don't hit its rate limit.
/// Each caller reserves its own time slot *synchronously* before sleeping, so concurrent callers
/// are truly spaced out (no reentrancy burst).
private actor JikanThrottle {
    static let shared = JikanThrottle()
    private var nextAllowed = Date.distantPast
    private let minInterval: TimeInterval = 0.55   // < 2 req/sec, safely under Jikan's limit

    func acquire() async {
        let now = Date()
        let slot = max(now, nextAllowed)
        nextAllowed = slot.addingTimeInterval(minInterval)   // reserve before any await
        let delay = slot.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

/// Anime via the Jikan API (MyAnimeList). Free, no key. Our primary anime source
/// (AniList has had stability outages).
struct JikanProvider: Sendable {
    private let base = "https://api.jikan.moe/v4"

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(string: base + path)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw MetadataError.badURL }

        // Jikan/MyAnimeList intermittently returns 429/5xx; back off and retry a few times.
        for attempt in 0..<3 {
            await JikanThrottle.shared.acquire()
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse else { throw MetadataError.badResponse }
                if [429, 500, 502, 503, 504].contains(http.statusCode) {
                    try? await Task.sleep(nanoseconds: UInt64(0.8 * Double(attempt + 1) * 1_000_000_000))
                    continue
                }
                guard (200..<300).contains(http.statusCode) else { throw MetadataError.badResponse }
                return try JSONDecoder().decode(T.self, from: data)
            } catch is DecodingError {
                throw MetadataError.decoding
            } catch {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw MetadataError.badResponse
    }

    func search(_ query: String) async throws -> [MediaSearchResult] {
        let response: JikanListResponse = try await get("/anime", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "sfw", value: "true")
        ])
        return response.data.map { $0.asSearchResult }
    }

    func details(sourceId: String) async throws -> MediaDetails {
        let response: JikanSingleResponse = try await get("/anime/\(sourceId)")
        let anime = response.data
        let episodes = anime.episodes ?? 0
        let seasons = episodes > 0 ? [SeasonInfo(number: 1, name: "Episodes", episodeCount: episodes)] : []
        return MediaDetails(
            result: anime.asSearchResult,
            totalSeasons: episodes > 0 ? 1 : 0,
            totalEpisodes: episodes,
            genres: (anime.genres ?? []).map { $0.name },
            seasons: seasons)
    }

    func recommendations(sourceId: String) async throws -> [MediaSearchResult] {
        let response: JikanRecResponse = try await get("/anime/\(sourceId)/recommendations")
        return response.data.prefix(20).map { $0.entry.asSearchResult }
    }

    /// If the anime is currently airing with a known broadcast day, returns the weekday (1=Sun...7=Sat).
    func airingWeekday(animeId: String) async -> Int? {
        guard let response: JikanSingleResponse = try? await get("/anime/\(animeId)") else { return nil }
        let anime = response.data
        guard anime.airing == true, let day = anime.broadcast?.day else { return nil }
        return Self.weekday(from: day)
    }

    private static func weekday(from day: String) -> Int? {
        switch day.lowercased() {
        case "sundays": return 1
        case "mondays": return 2
        case "tuesdays": return 3
        case "wednesdays": return 4
        case "thursdays": return 5
        case "fridays": return 6
        case "saturdays": return 7
        default: return nil
        }
    }

    /// Streaming platforms with direct links (e.g. Crunchyroll, HIDIVE).
    func streaming(animeId: String) async throws -> [WatchProvider] {
        let response: JikanStreamingResponse = try await get("/anime/\(animeId)/streaming")
        return response.data.map { WatchProvider(name: $0.name, logoURL: nil, url: $0.url) }
    }

    /// One page (100 eps) of an anime's episode list, with the total page count.
    func episodes(animeId: String, page: Int) async throws -> (episodes: [EpisodeInfo], lastPage: Int) {
        let response: JikanEpisodesResponse = try await get("/anime/\(animeId)/episodes", query: [
            URLQueryItem(name: "page", value: String(page))
        ])
        let iso = ISO8601DateFormatter()
        let episodes = response.data.map { ep in
            EpisodeInfo(number: ep.mal_id,
                        title: ep.title,
                        airDate: ep.aired.flatMap { iso.date(from: $0) })
        }
        return (episodes, response.pagination?.last_visible_page ?? 1)
    }

    func trending(page: Int = 1) async throws -> [MediaSearchResult] {
        let response: JikanListResponse = try await get("/seasons/now", query: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sfw", value: "true")
        ])
        return response.data.map { $0.asSearchResult }
    }

    func popular(page: Int = 1) async throws -> [MediaSearchResult] {
        // Plain /top/anime (by score) — the ?filter=bypopularity variant has been 504-ing on MAL.
        let response: JikanListResponse = try await get("/top/anime", query: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sfw", value: "true")
        ])
        return response.data.map { $0.asSearchResult }
    }
}

// MARK: - Jikan DTOs

private struct JikanListResponse: Decodable { let data: [JikanAnime] }

private struct JikanStreamingResponse: Decodable { let data: [JikanStreamingLink] }
private struct JikanStreamingLink: Decodable { let name: String; let url: String? }

private struct JikanEpisodesResponse: Decodable {
    let data: [JikanEpisode]
    let pagination: JikanEpisodesPagination?
}
private struct JikanEpisode: Decodable {
    let mal_id: Int
    let title: String?
    let aired: String?
}
private struct JikanEpisodesPagination: Decodable { let last_visible_page: Int? }
private struct JikanSingleResponse: Decodable { let data: JikanAnime }
private struct JikanRecResponse: Decodable { let data: [JikanRecEntry] }
private struct JikanRecEntry: Decodable { let entry: JikanAnime }

private struct JikanGenre: Decodable { let name: String }
private struct JikanImageSet: Decodable { let image_url: String?; let large_image_url: String? }
private struct JikanImages: Decodable { let jpg: JikanImageSet? }
private struct JikanAiredFrom: Decodable { let year: Int? }
private struct JikanAiredProp: Decodable { let from: JikanAiredFrom? }
private struct JikanAired: Decodable { let prop: JikanAiredProp? }

private struct JikanBroadcast: Decodable { let day: String? }

private struct JikanAnime: Decodable {
    let mal_id: Int
    let title: String?
    let title_english: String?
    let synopsis: String?
    let episodes: Int?
    let year: Int?
    let images: JikanImages?
    let genres: [JikanGenre]?
    let aired: JikanAired?
    let airing: Bool?
    let broadcast: JikanBroadcast?

    var asSearchResult: MediaSearchResult {
        let resolvedYear = year ?? aired?.prop?.from?.year
        return MediaSearchResult(
            source: "jikan",
            sourceId: String(mal_id),
            title: title_english ?? title ?? "Untitled",
            mediaType: .anime,
            year: resolvedYear.map(String.init),
            posterURL: images?.jpg?.large_image_url ?? images?.jpg?.image_url,
            overview: synopsis ?? "")
    }
}
