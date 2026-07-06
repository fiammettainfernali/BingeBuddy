import Foundation

/// Serializes Jikan requests so bursts (e.g. loading recommendations) don't hit its rate limit.
private actor JikanThrottle {
    static let shared = JikanThrottle()
    private var lastRequest = Date.distantPast
    private let minInterval: TimeInterval = 0.4   // ~2.5 requests/sec, under Jikan's limit

    func acquire() async {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minInterval {
            try? await Task.sleep(nanoseconds: UInt64((minInterval - elapsed) * 1_000_000_000))
        }
        lastRequest = Date()
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
        await JikanThrottle.shared.acquire()
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MetadataError.badResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MetadataError.decoding
        }
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

    func trending(page: Int = 1) async throws -> [MediaSearchResult] {
        let response: JikanListResponse = try await get("/seasons/now", query: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sfw", value: "true")
        ])
        return response.data.map { $0.asSearchResult }
    }

    func popular(page: Int = 1) async throws -> [MediaSearchResult] {
        let response: JikanListResponse = try await get("/top/anime", query: [
            URLQueryItem(name: "filter", value: "bypopularity"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sfw", value: "true")
        ])
        return response.data.map { $0.asSearchResult }
    }
}

// MARK: - Jikan DTOs

private struct JikanListResponse: Decodable { let data: [JikanAnime] }
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
