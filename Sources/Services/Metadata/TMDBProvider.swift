import Foundation

/// Movies + TV via The Movie Database (v4 bearer token auth).
struct TMDBProvider: MediaProvider, Sendable {
    private let token = Secrets.tmdbReadToken
    private let base = "https://api.themoviedb.org/3"
    private let imageBase = "https://image.tmdb.org/t/p/w500"

    private static let ymd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(string: base + path)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw MetadataError.badURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")

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
        let response: TMDBSearchResponse = try await get("/search/multi", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false")
        ])
        return response.results.compactMap { item in
            guard let type = item.mediaTypeEnum else { return nil }
            let title = item.title ?? item.name ?? "Untitled"
            let date = item.release_date ?? item.first_air_date
            let year = date?.split(separator: "-").first.map(String.init)
            let poster = item.poster_path.map { imageBase + $0 }
            return MediaSearchResult(
                source: "tmdb",
                sourceId: String(item.id),
                title: title,
                mediaType: type,
                year: year,
                posterURL: poster,
                overview: item.overview ?? ""
            )
        }
    }

    func details(sourceId: String, mediaType: MediaType) async throws -> MediaDetails {
        if mediaType == .tv {
            let d: TMDBTVDetails = try await get("/tv/\(sourceId)")
            let seasons = (d.seasons ?? [])
                .filter { $0.season_number > 0 }
                .map { SeasonInfo(number: $0.season_number,
                                  name: $0.name ?? "Season \($0.season_number)",
                                  episodeCount: $0.episode_count ?? 0) }
            let year = d.first_air_date?.split(separator: "-").first.map(String.init)
            let result = MediaSearchResult(
                source: "tmdb", sourceId: sourceId, title: d.name ?? "Untitled",
                mediaType: .tv, year: year,
                posterURL: d.poster_path.map { imageBase + $0 }, overview: d.overview ?? "")

            var nextDate: Date?
            var nextLabel: String?
            if let next = d.next_episode_to_air,
               let airStr = next.air_date,
               let date = Self.ymd.date(from: airStr) {
                nextDate = date
                let title = next.name.map { " — \($0)" } ?? ""
                nextLabel = "S\(next.season_number ?? 0) E\(next.episode_number ?? 0)\(title) airs today"
            }

            return MediaDetails(
                result: result,
                totalSeasons: d.number_of_seasons ?? seasons.count,
                totalEpisodes: d.number_of_episodes ?? 0,
                genres: (d.genres ?? []).map { $0.name },
                seasons: seasons,
                nextEpisodeAirDate: nextDate,
                nextEpisodeLabel: nextLabel,
                lastAiredSeason: d.last_episode_to_air?.season_number,
                lastAiredEpisode: d.last_episode_to_air?.episode_number)
        } else {
            let d: TMDBMovieDetails = try await get("/movie/\(sourceId)")
            let year = d.release_date?.split(separator: "-").first.map(String.init)
            let result = MediaSearchResult(
                source: "tmdb", sourceId: sourceId, title: d.title ?? "Untitled",
                mediaType: .movie, year: year,
                posterURL: d.poster_path.map { imageBase + $0 }, overview: d.overview ?? "")
            return MediaDetails(
                result: result, totalSeasons: 0, totalEpisodes: 0,
                genres: (d.genres ?? []).map { $0.name }, seasons: [])
        }
    }

    func recommendations(sourceId: String, mediaType: MediaType) async throws -> [MediaSearchResult] {
        let path = mediaType == .tv ? "/tv/\(sourceId)/recommendations" : "/movie/\(sourceId)/recommendations"
        let response: TMDBSearchResponse = try await get(path)
        return response.results.map { item in
            let title = item.title ?? item.name ?? "Untitled"
            let date = item.release_date ?? item.first_air_date
            let year = date?.split(separator: "-").first.map(String.init)
            let poster = item.poster_path.map { imageBase + $0 }
            return MediaSearchResult(source: "tmdb", sourceId: String(item.id), title: title,
                                     mediaType: mediaType, year: year, posterURL: poster,
                                     overview: item.overview ?? "")
        }
    }

    /// Streaming availability in the user's region (flatrate/free/ads tiers).
    func watchProviders(sourceId: String, mediaType: MediaType, region: String) async throws -> WatchAvailability? {
        let path = mediaType == .tv ? "/tv/\(sourceId)/watch/providers" : "/movie/\(sourceId)/watch/providers"
        let response: TMDBWatchResponse = try await get(path)
        guard let regional = response.results?[region] else { return nil }
        let raw = (regional.flatrate ?? []) + (regional.free ?? []) + (regional.ads ?? [])
        var seen = Set<String>()
        let providers = raw.compactMap { provider -> WatchProvider? in
            guard seen.insert(provider.provider_name).inserted else { return nil }
            return WatchProvider(name: provider.provider_name,
                                 logoURL: provider.logo_path.map { "https://image.tmdb.org/t/p/w92" + $0 },
                                 url: nil)
        }
        return WatchAvailability(providers: providers,
                                 moreLink: regional.link,
                                 attribution: "Streaming data by JustWatch")
    }

    /// Full episode list for one season of a TV series.
    func episodes(tvId: String, season: Int) async throws -> [EpisodeInfo] {
        let d: TMDBSeasonDetails = try await get("/tv/\(tvId)/season/\(season)")
        return (d.episodes ?? []).map { ep in
            EpisodeInfo(number: ep.episode_number ?? 0,
                        title: ep.name,
                        airDate: ep.air_date.flatMap { Self.ymd.date(from: $0) })
        }
    }

    /// Future air dates for the current/next season of a TV series.
    func upcomingEpisodes(tvId: String) async throws -> [EpisodeAiring] {
        let d: TMDBTVDetails = try await get("/tv/\(tvId)")
        guard let next = d.next_episode_to_air, let season = next.season_number else { return [] }
        let seasonDetails: TMDBSeasonDetails = try await get("/tv/\(tvId)/season/\(season)")
        let today = Calendar.current.startOfDay(for: Date())
        return (seasonDetails.episodes ?? []).compactMap { ep in
            guard let airStr = ep.air_date,
                  let date = Self.ymd.date(from: airStr),
                  date >= today else { return nil }
            let name = ep.name.map { " — \($0)" } ?? ""
            return EpisodeAiring(date: date, label: "S\(season) E\(ep.episode_number ?? 0)\(name) airs today")
        }
    }

    func trending(page: Int = 1) async throws -> [MediaSearchResult] {
        let response: TMDBSearchResponse = try await get("/trending/all/week",
            query: [URLQueryItem(name: "page", value: String(page))])
        return response.results.compactMap { item in
            guard let type = item.mediaTypeEnum else { return nil }
            let title = item.title ?? item.name ?? "Untitled"
            let date = item.release_date ?? item.first_air_date
            let year = date?.split(separator: "-").first.map(String.init)
            let poster = item.poster_path.map { imageBase + $0 }
            return MediaSearchResult(source: "tmdb", sourceId: String(item.id), title: title,
                                     mediaType: type, year: year, posterURL: poster,
                                     overview: item.overview ?? "")
        }
    }

    func popular(mediaType: MediaType, page: Int = 1) async throws -> [MediaSearchResult] {
        let path = mediaType == .tv ? "/tv/popular" : "/movie/popular"
        let response: TMDBSearchResponse = try await get(path,
            query: [URLQueryItem(name: "page", value: String(page))])
        return response.results.map { item in
            let title = item.title ?? item.name ?? "Untitled"
            let date = item.release_date ?? item.first_air_date
            let year = date?.split(separator: "-").first.map(String.init)
            let poster = item.poster_path.map { imageBase + $0 }
            return MediaSearchResult(source: "tmdb", sourceId: String(item.id), title: title,
                                     mediaType: mediaType, year: year, posterURL: poster,
                                     overview: item.overview ?? "")
        }
    }
}

// MARK: - TMDB DTOs

private struct TMDBSearchResponse: Decodable {
    let results: [TMDBSearchItem]
}

private struct TMDBSearchItem: Decodable {
    let id: Int
    let media_type: String?
    let title: String?
    let name: String?
    let overview: String?
    let poster_path: String?
    let release_date: String?
    let first_air_date: String?

    var mediaTypeEnum: MediaType? {
        switch media_type {
        case "movie": return .movie
        case "tv": return .tv
        default: return nil
        }
    }
}

private struct TMDBGenre: Decodable { let name: String }

private struct TMDBSeason: Decodable {
    let season_number: Int
    let name: String?
    let episode_count: Int?
}

private struct TMDBNextEpisode: Decodable {
    let air_date: String?
    let episode_number: Int?
    let season_number: Int?
    let name: String?
}

private struct TMDBWatchResponse: Decodable { let results: [String: TMDBWatchRegion]? }
private struct TMDBWatchRegion: Decodable {
    let link: String?
    let flatrate: [TMDBWatchProviderDTO]?
    let free: [TMDBWatchProviderDTO]?
    let ads: [TMDBWatchProviderDTO]?
}
private struct TMDBWatchProviderDTO: Decodable {
    let provider_name: String
    let logo_path: String?
}

private struct TMDBSeasonEpisode: Decodable {
    let air_date: String?
    let episode_number: Int?
    let name: String?
}

private struct TMDBSeasonDetails: Decodable {
    let episodes: [TMDBSeasonEpisode]?
}

private struct TMDBTVDetails: Decodable {
    let name: String?
    let overview: String?
    let poster_path: String?
    let first_air_date: String?
    let number_of_seasons: Int?
    let number_of_episodes: Int?
    let genres: [TMDBGenre]?
    let seasons: [TMDBSeason]?
    let next_episode_to_air: TMDBNextEpisode?
    let last_episode_to_air: TMDBNextEpisode?
}

private struct TMDBMovieDetails: Decodable {
    let title: String?
    let overview: String?
    let poster_path: String?
    let release_date: String?
    let genres: [TMDBGenre]?
}
