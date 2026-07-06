import Foundation

/// Anime charts via Kitsu (kitsu.io) — an independent anime DB, used because Jikan's aggregate
/// endpoints (season/top charts) intermittently 504. Each Kitsu title is converted to its
/// MyAnimeList id so tapping/adding/recommendations continue to use our Jikan flow.
struct KitsuProvider: Sendable {
    private let base = "https://kitsu.io/api/edge"

    func trending() async throws -> [MediaSearchResult] { try await chart(sort: "-averageRating") }
    func popular() async throws -> [MediaSearchResult] { try await chart(sort: "-userCount") }

    private func chart(sort: String) async throws -> [MediaSearchResult] {
        var components = URLComponents(string: base + "/anime")
        components?.queryItems = [
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "page[limit]", value: "20"),
            URLQueryItem(name: "include", value: "mappings")
        ]
        guard let url = components?.url else { throw MetadataError.badURL }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MetadataError.badResponse
        }
        let decoded = try JSONDecoder().decode(KitsuResponse.self, from: data)

        // Build mapping-resource-id -> MAL id from the sideloaded "included" resources.
        var malByMappingId: [String: String] = [:]
        for inc in decoded.included ?? [] where inc.type == "mappings" {
            if inc.attributes?.externalSite == "myanimelist/anime", let ext = inc.attributes?.externalId {
                malByMappingId[inc.id] = ext
            }
        }

        return decoded.data.compactMap { anime -> MediaSearchResult? in
            let refs = anime.relationships?.mappings?.data ?? []
            guard let malId = refs.compactMap({ malByMappingId[$0.id] }).first else { return nil }
            let attrs = anime.attributes
            let year = attrs.startDate.map { String($0.prefix(4)) }
            return MediaSearchResult(
                source: "jikan",
                sourceId: malId,
                title: attrs.canonicalTitle ?? "Untitled",
                mediaType: .anime,
                year: year,
                posterURL: attrs.posterImage?.large ?? attrs.posterImage?.original,
                overview: attrs.synopsis ?? "")
        }
    }
}

// MARK: - Kitsu (JSON:API) DTOs

private struct KitsuResponse: Decodable {
    let data: [KitsuAnime]
    let included: [KitsuIncluded]?
}

private struct KitsuAnime: Decodable {
    let id: String
    let attributes: KitsuAttributes
    let relationships: KitsuRelationships?
}

private struct KitsuAttributes: Decodable {
    let canonicalTitle: String?
    let synopsis: String?
    let startDate: String?
    let posterImage: KitsuPoster?
}

private struct KitsuPoster: Decodable {
    let large: String?
    let original: String?
}

private struct KitsuRelationships: Decodable {
    let mappings: KitsuRelData?
}

private struct KitsuRelData: Decodable {
    let data: [KitsuRef]?
}

private struct KitsuRef: Decodable {
    let id: String
    let type: String
}

private struct KitsuIncluded: Decodable {
    let id: String
    let type: String
    let attributes: KitsuIncludedAttrs?
}

private struct KitsuIncludedAttrs: Decodable {
    let externalSite: String?
    let externalId: String?
}
