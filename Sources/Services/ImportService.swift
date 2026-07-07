import Foundation
import Compression

/// One title ready to be written into the library during an import.
struct ImportCandidate: Sendable {
    let mediaKey: String
    let source: String
    let sourceId: String
    let title: String
    let state: WatchState
    let rating: Int          // 0–5 stars
    let episode: Int
    let totalEpisodes: Int
    let genres: [String]
    let posterURL: String?
    let year: String?
    let overview: String
}

/// Builds import candidates from other trackers (AniList profile, MAL export file).
struct ImportService {
    private let anilist = AniListProvider()

    // MARK: - AniList (by username)

    func fromAniList(username: String) async throws -> [ImportCandidate] {
        let entries = try await anilist.userAnimeList(userName: username)
        return entries.map { entry in
            candidate(media: entry.media,
                      state: Self.state(fromAniList: entry.status),
                      score10: entry.score10,
                      progress: entry.progress,
                      fallbackTitle: entry.media.title)
        }
    }

    // MARK: - MyAnimeList (export file)

    func fromMALExport(_ raw: Data) async throws -> [ImportCandidate] {
        let data = Self.gunzip(raw) ?? raw
        let entries = MALExportParser.parse(data)
        guard !entries.isEmpty else { throw MetadataError.decoding }

        // Enrich with posters/genres via AniList's batch MAL-id lookup (best effort).
        let malIds = entries.compactMap { Int($0.malId) }
        let enrichment = (try? await anilist.mediaByMalIds(malIds)) ?? [:]

        return entries.map { entry in
            if let mal = Int(entry.malId), let media = enrichment[mal] {
                return candidate(media: media,
                                 state: Self.state(fromMAL: entry.status),
                                 score10: entry.score10,
                                 progress: entry.watchedEpisodes,
                                 fallbackTitle: entry.title)
            }
            // No enrichment match: import with what the file gives us.
            return ImportCandidate(
                mediaKey: "jikan-\(entry.malId)", source: "jikan", sourceId: entry.malId,
                title: entry.title,
                state: Self.state(fromMAL: entry.status),
                rating: Self.stars(fromScore10: entry.score10),
                episode: entry.watchedEpisodes,
                totalEpisodes: entry.totalEpisodes,
                genres: [], posterURL: nil, year: nil, overview: "")
        }
    }

    // MARK: - Shared assembly

    private func candidate(media: ALMediaLite, state: WatchState,
                           score10: Int, progress: Int, fallbackTitle: String) -> ImportCandidate {
        // Prefer MAL-keyed storage (matches the app's anime source); AniList key as fallback.
        let (source, sourceId): (String, String) = media.idMal.map { ("jikan", String($0)) }
            ?? ("anilist", String(media.id))
        var episode = progress
        if state == .finished && media.episodes > 0 { episode = media.episodes }
        return ImportCandidate(
            mediaKey: "\(source)-\(sourceId)", source: source, sourceId: sourceId,
            title: media.title.isEmpty ? fallbackTitle : media.title,
            state: state,
            rating: Self.stars(fromScore10: score10),
            episode: episode,
            totalEpisodes: media.episodes,
            genres: media.genres,
            posterURL: media.posterURL,
            year: media.year,
            overview: media.overview)
    }

    // MARK: - Mapping (pure, tested)

    static func state(fromAniList status: String) -> WatchState {
        switch status.uppercased() {
        case "CURRENT", "REPEATING", "PAUSED": return .watching
        case "COMPLETED": return .finished
        case "DROPPED": return .dropped
        default: return .wantToWatch   // PLANNING
        }
    }

    static func state(fromMAL status: String) -> WatchState {
        switch status.lowercased() {
        case "watching", "on-hold", "1", "3": return .watching
        case "completed", "2": return .finished
        case "dropped", "4": return .dropped
        default: return .wantToWatch   // "plan to watch" / 6
        }
    }

    /// MAL/AniList 0–10 scores → 0–5 stars (7/10 ≈ 4★).
    static func stars(fromScore10 score: Int) -> Int {
        guard score > 0 else { return 0 }
        return min(5, (score + 1) / 2)
    }

    // MARK: - gzip (MAL exports download as .xml.gz)

    static func gunzip(_ data: Data) -> Data? {
        guard data.count > 18, data[0] == 0x1f, data[1] == 0x8b else { return nil }
        let flags = data[3]
        var index = 10
        if flags & 0x04 != 0 {                       // FEXTRA
            guard index + 2 <= data.count else { return nil }
            let extraLength = Int(data[index]) | (Int(data[index + 1]) << 8)
            index += 2 + extraLength
        }
        if flags & 0x08 != 0 {                       // FNAME (null-terminated)
            while index < data.count, data[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x10 != 0 {                       // FCOMMENT
            while index < data.count, data[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { index += 2 }          // FHCRC
        guard index < data.count - 8 else { return nil }

        let deflated = data.subdata(in: index..<(data.count - 8))
        let capacity = max(deflated.count * 25, 8_000_000)
        return deflated.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Data? in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { destination.deallocate() }
            let written = compression_decode_buffer(destination, capacity,
                                                    base, deflated.count,
                                                    nil, COMPRESSION_ZLIB)
            guard written > 0 else { return nil }
            return Data(bytes: destination, count: written)
        }
    }
}

// MARK: - MAL export XML

struct MALExportEntry {
    var malId = ""
    var title = ""
    var status = ""
    var score10 = 0
    var watchedEpisodes = 0
    var totalEpisodes = 0
}

/// Parses MyAnimeList's official export format (<myanimelist><anime>…</anime>…).
final class MALExportParser: NSObject, XMLParserDelegate {
    private var entries: [MALExportEntry] = []
    private var current: MALExportEntry?
    private var text = ""

    static func parse(_ data: Data) -> [MALExportEntry] {
        let delegate = MALExportParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "anime" { current = MALExportEntry() }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "series_animedb_id": current?.malId = value
        case "series_title": current?.title = value
        case "series_episodes": current?.totalEpisodes = Int(value) ?? 0
        case "my_watched_episodes": current?.watchedEpisodes = Int(value) ?? 0
        case "my_score": current?.score10 = Int(value) ?? 0
        case "my_status": current?.status = value
        case "anime":
            if let entry = current, !entry.malId.isEmpty { entries.append(entry) }
            current = nil
        default: break
        }
    }
}
