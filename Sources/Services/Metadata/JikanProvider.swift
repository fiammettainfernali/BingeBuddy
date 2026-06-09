import Foundation

/// Anime via the Jikan API (MyAnimeList). Free, no key. Our primary anime source
/// (AniList has had stability outages).
struct JikanProvider: Sendable {
    private let base = "https://api.jikan.moe/v4"

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(string: base + path)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw MetadataError.badURL }
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

    func trending() async throws -> [MediaSearchResult] {
        let response: JikanListResponse = try await get("/seasons/now", query: [
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "sfw", value: "true")
        ])
        return response.data.map { $0.asSearchResult }
    }

    func popular() async throws -> [MediaSearchResult] {
        let response: JikanListResponse = try await get("/top/anime", query: [
            URLQueryItem(name: "filter", value: "bypopularity"),
            URLQueryItem(name: "limit", value: "25"),
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
