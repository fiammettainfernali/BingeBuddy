import Foundation

/// Anime charts via Kitsu (kitsu.io) — an independent anime DB, used because Jikan's aggregate
/// endpoints (season/top charts) intermittently 504. Each Kitsu title is converted to its
/// MyAnimeList id so tapping/adding/recommendations continue to use our Jikan flow.
struct KitsuProvider: Sendable {
    private let base = "https://kitsu.io/api/edge"

    /// This season's currently-airing anime, most popular first.
    func trending() async throws -> [MediaSearchResult] {
        let (year, season) = Self.currentSeason()
        return try await chart(filters: [
            URLQueryItem(name: "filter[seasonYear]", value: String(year)),
            URLQueryItem(name: "filter[season]", value: season),
            URLQueryItem(name: "sort", value: "-userCount")
        ])
    }

    /// All-time most popular anime.
    func popular() async throws -> [MediaSearchResult] {
        try await chart(filters: [URLQueryItem(name: "sort", value: "-userCount")])
    }

    static func currentSeason(now: Date = Date()) -> (year: Int, season: String) {
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        switch cal.component(.month, from: now) {
        case 1...3: return (year, "winter")
        case 4...6: return (year, "spring")
        case 7...9: return (year, "summer")
        default: return (year, "fall")
        }
    }

    private func chart(filters: [URLQueryItem]) async throws -> [MediaSearchResult] {
        let limit = 20
        var all: [MediaSearchResult] = []
        var seen = Set<String>()
        // Kitsu caps a page at 20; page through until we've got the whole list (or a sane max).
        for pageIndex in 0..<7 {
            let (results, rawCount) = try await fetchPage(filters: filters, limit: limit, offset: pageIndex * limit)
            for item in results where seen.insert(item.id).inserted { all.append(item) }
            if rawCount < limit { break }   // last page
        }
        return all
    }

    private func fetchPage(filters: [URLQueryItem], limit: Int, offset: Int) async throws -> ([MediaSearchResult], Int) {
        var components = URLComponents(string: base + "/anime")
        components?.queryItems = filters + [
            URLQueryItem(name: "page[limit]", value: String(limit)),
            URLQueryItem(name: "page[offset]", value: String(offset)),
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

        let results = decoded.data.compactMap { anime -> MediaSearchResult? in
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
        return (results, decoded.data.count)
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
