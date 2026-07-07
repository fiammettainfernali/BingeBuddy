import Foundation

/// Anime via the AniList GraphQL API (no key required).
struct AniListProvider: MediaProvider, Sendable {
    private let endpoint = URL(string: "https://graphql.anilist.co")!

    private func post<T: Decodable>(query: String, variables: [String: Any]) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables])

        let (data, response) = try await URLSession.shared.data(for: request)
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
        let gql = """
        query ($search: String) {
          Page(perPage: 25) {
            media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
              id
              title { romaji english }
              coverImage { large }
              seasonYear
              description(asHtml: false)
              episodes
            }
          }
        }
        """
        let response: AniListSearchResponse = try await post(query: gql, variables: ["search": query])
        return response.data.Page.media.map { $0.asSearchResult }
    }

    func details(sourceId: String, mediaType: MediaType) async throws -> MediaDetails {
        let gql = """
        query ($id: Int) {
          Media(id: $id, type: ANIME) {
            id
            title { romaji english }
            coverImage { large }
            seasonYear
            description(asHtml: false)
            episodes
            genres
          }
        }
        """
        let response: AniListMediaResponse = try await post(
            query: gql, variables: ["id": Int(sourceId) ?? 0])
        let media = response.data.Media
        let episodes = media.episodes ?? 0
        let seasons = episodes > 0 ? [SeasonInfo(number: 1, name: "Episodes", episodeCount: episodes)] : []
        return MediaDetails(
            result: media.asSearchResult,
            totalSeasons: episodes > 0 ? 1 : 0,
            totalEpisodes: episodes,
            genres: media.genres ?? [],
            seasons: seasons)
    }

    func recommendations(sourceId: String) async throws -> [MediaSearchResult] {
        let gql = """
        query ($id: Int) {
          Media(id: $id, type: ANIME) {
            recommendations(sort: RATING_DESC, perPage: 15) {
              nodes {
                mediaRecommendation {
                  id
                  title { romaji english }
                  coverImage { large }
                  seasonYear
                  description(asHtml: false)
                  episodes
                }
              }
            }
          }
        }
        """
        let response: AniListRecResponse = try await post(
            query: gql, variables: ["id": Int(sourceId) ?? 0])
        return response.data.Media.recommendations.nodes.compactMap { $0.mediaRecommendation?.asSearchResult }
    }

    /// The MyAnimeList id for an AniList id — bridges legacy library items to Jikan.
    func malId(anilistId: String) async throws -> Int? {
        let gql = "query ($id: Int) { Media(id: $id, type: ANIME) { idMal } }"
        let response: ALMalResponse = try await post(query: gql, variables: ["id": Int(anilistId) ?? 0])
        return response.data.Media.idMal
    }

    /// Episode list built from AniList's airing schedule (numbers + air dates, titles when
    /// a licensed stream provides them). Fallback for titles Jikan can't serve.
    func episodes(anilistId: String) async throws -> [EpisodeInfo] {
        try await episodeList(idField: "id", id: Int(anilistId) ?? 0)
    }

    func episodes(malId: String) async throws -> [EpisodeInfo] {
        try await episodeList(idField: "idMal", id: Int(malId) ?? 0)
    }

    private func episodeList(idField: String, id: Int) async throws -> [EpisodeInfo] {
        var airDates: [Int: Int] = [:]      // episode number → earliest airingAt
        var titles: [Int: String] = [:]
        var page = 1
        while page <= 12 {                   // 50/page → up to 600 episodes
            let gql = """
            query ($id: Int, $page: Int) {
              Media(\(idField): $id, type: ANIME) {
                streamingEpisodes { title }
                airingSchedule(page: $page, perPage: 50) {
                  pageInfo { hasNextPage }
                  nodes { episode airingAt }
                }
              }
            }
            """
            let response: ALEpResponse = try await post(query: gql, variables: ["id": id, "page": page])
            let media = response.data.Media
            if page == 1, let streams = media.streamingEpisodes {
                titles = Self.parseStreamingTitles(streams)
            }
            for node in media.airingSchedule?.nodes ?? [] where airDates[node.episode] == nil {
                airDates[node.episode] = node.airingAt
            }
            if media.airingSchedule?.pageInfo?.hasNextPage != true { break }
            page += 1
        }
        return airDates.keys.sorted().map { number in
            EpisodeInfo(number: number,
                        title: titles[number],
                        airDate: airDates[number].map { Date(timeIntervalSince1970: TimeInterval($0)) })
        }
    }

    /// Streaming titles look like "Episode 12 - The Title"; extract number + clean name.
    private static func parseStreamingTitles(_ eps: [ALStreamEp]) -> [Int: String] {
        var titles: [Int: String] = [:]
        for (index, ep) in eps.enumerated() {
            guard let raw = ep.title else { continue }
            var number = index + 1
            var name = raw
            if raw.lowercased().hasPrefix("episode "), let sep = raw.range(of: " - ") {
                let numPart = raw[raw.index(raw.startIndex, offsetBy: 8)..<sep.lowerBound]
                if let parsed = Int(numPart.trimmingCharacters(in: .whitespaces)) { number = parsed }
                name = String(raw[sep.upperBound...])
            }
            titles[number] = name
        }
        return titles
    }

    func trending() async throws -> [MediaSearchResult] {
        try await page(sort: "TRENDING_DESC")
    }

    func popular() async throws -> [MediaSearchResult] {
        try await page(sort: "POPULARITY_DESC")
    }

    private func page(sort: String) async throws -> [MediaSearchResult] {
        let gql = """
        query {
          Page(perPage: 25) {
            media(sort: \(sort), type: ANIME) {
              id
              title { romaji english }
              coverImage { large }
              seasonYear
              description(asHtml: false)
              episodes
            }
          }
        }
        """
        let response: AniListSearchResponse = try await post(query: gql, variables: [:])
        return response.data.Page.media.map { $0.asSearchResult }
    }
}

// MARK: - AniList DTOs

private struct AniListRecNode: Decodable { let mediaRecommendation: AniListMedia? }
private struct AniListRecommendations: Decodable { let nodes: [AniListRecNode] }
private struct AniListRecMedia: Decodable { let recommendations: AniListRecommendations }
private struct AniListRecData: Decodable { let Media: AniListRecMedia }
private struct AniListRecResponse: Decodable { let data: AniListRecData }

private struct AniListTitle: Decodable {
    let romaji: String?
    let english: String?
}

private struct AniListCover: Decodable { let large: String? }

private struct AniListMedia: Decodable {
    let id: Int
    let title: AniListTitle
    let coverImage: AniListCover
    let seasonYear: Int?
    let description: String?
    let episodes: Int?
    let genres: [String]?

    var asSearchResult: MediaSearchResult {
        MediaSearchResult(
            source: "anilist",
            sourceId: String(id),
            title: title.english ?? title.romaji ?? "Untitled",
            mediaType: .anime,
            year: seasonYear.map(String.init),
            posterURL: coverImage.large,
            overview: (description ?? "").strippingHTML)
    }
}

private struct ALMalMedia: Decodable { let idMal: Int? }
private struct ALMalData: Decodable { let Media: ALMalMedia }
private struct ALMalResponse: Decodable { let data: ALMalData }

struct ALStreamEp: Decodable { let title: String? }
private struct ALSchedNode: Decodable { let episode: Int; let airingAt: Int }
private struct ALPageInfo: Decodable { let hasNextPage: Bool? }
private struct ALSched: Decodable { let pageInfo: ALPageInfo?; let nodes: [ALSchedNode] }
private struct ALEpMedia: Decodable {
    let streamingEpisodes: [ALStreamEp]?
    let airingSchedule: ALSched?
}
private struct ALEpData: Decodable { let Media: ALEpMedia }
private struct ALEpResponse: Decodable { let data: ALEpData }

private struct AniListPage: Decodable { let media: [AniListMedia] }
private struct AniListSearchData: Decodable { let Page: AniListPage }
private struct AniListSearchResponse: Decodable { let data: AniListSearchData }
private struct AniListMediaData: Decodable { let Media: AniListMedia }
private struct AniListMediaResponse: Decodable { let data: AniListMediaData }
