import Foundation
import FirebaseFirestore

/// A title in a user's library, stored in Firestore under their household.
struct LibraryItem: Codable, Identifiable {
    @DocumentID var docId: String?
    var ownerUid: String = ""
    var scope: String = "personal"          // "personal" | "together"
    var mediaKey: String = ""               // "source-sourceId"
    var title: String = ""
    var mediaTypeRaw: String = MediaType.movie.rawValue
    var stateRaw: String = WatchState.wantToWatch.rawValue
    var overview: String = ""
    var posterURL: String?
    var year: String?
    var rating: Int = 0
    var currentSeason: Int = 1
    var currentEpisode: Int = 0
    var totalSeasons: Int = 0
    var totalEpisodes: Int = 0
    var genres: [String] = []
    var source: String = ""
    var sourceId: String = ""
    var note: String = ""
    var lastAiredSeason: Int?      // latest aired episode (TMDB TV), for catch-up on airing shows
    var lastAiredEpisode: Int?
    @ServerTimestamp var addedAt: Date?
    @ServerTimestamp var updatedAt: Date?

    var id: String { docId ?? mediaKey }
    var mediaType: MediaType { MediaType(rawValue: mediaTypeRaw) ?? .movie }

    var state: WatchState {
        get { WatchState(rawValue: stateRaw) ?? .wantToWatch }
        set { stateRaw = newValue.rawValue }
    }

    var asSearchResult: MediaSearchResult {
        MediaSearchResult(source: source, sourceId: sourceId, title: title,
                          mediaType: mediaType, year: year, posterURL: posterURL, overview: overview)
    }
}

/// Live, syncing view of the whole household's library (both members + shared items).
@MainActor
final class LibraryStore: ObservableObject {
    @Published var allItems: [LibraryItem] = []
    @Published var hiddenRecs: Set<String> = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var prefsListener: ListenerRegistration?
    private var householdId: String?
    private var uid: String?

    // MARK: - Derived slices

    /// My own personal library.
    var myPersonal: [LibraryItem] {
        guard let uid else { return [] }
        return allItems.filter { $0.ownerUid == uid && $0.scope == "personal" }
    }

    /// My partner's personal library (read-only "her portal").
    var partnerPersonal: [LibraryItem] {
        guard let uid else { return [] }
        return allItems.filter { $0.ownerUid != uid && $0.scope == "personal" }
    }

    /// The shared "watch together" list (one copy, both can edit).
    var togetherItems: [LibraryItem] {
        allItems.filter { $0.scope == "together" }
    }

    /// Titles on BOTH want-to-watch lists — "what should we watch together?"
    var matches: [LibraryItem] {
        let mineWant = Set(myPersonal.filter { $0.state == .wantToWatch }.map(\.mediaKey))
        let theirsWant = Set(partnerPersonal.filter { $0.state == .wantToWatch }.map(\.mediaKey))
        let common = mineWant.intersection(theirsWant)
        return myPersonal.filter { common.contains($0.mediaKey) }
    }

    // MARK: - Recommendation seeds / exclusions

    /// Rank a title's strength as a taste signal (higher = stronger).
    /// Pure function — nonisolated so tests (and anything else) can call it directly.
    nonisolated static func seedWeight(_ item: LibraryItem) -> Int {
        var weight = item.rating
        switch item.state {
        case .finished: weight += 3
        case .watching: weight += 2
        case .wantToWatch: weight += 1
        case .dropped: weight -= 10
        }
        return weight
    }

    /// All non-dropped titles, strongest taste signals first.
    private func seeds(from items: [LibraryItem]) -> [LibraryItem] {
        items.filter { $0.state != .dropped }
            .sorted {
                let lhs = Self.seedWeight($0), rhs = Self.seedWeight($1)
                if lhs != rhs { return lhs > rhs }
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
    }

    /// What to base my personal "For You" picks on.
    var mySeeds: [LibraryItem] { seeds(from: myPersonal) }

    /// What to base couple "For Us" picks on.
    var ourSeeds: [LibraryItem] { seeds(from: myPersonal + partnerPersonal) }

    /// Don't recommend things I already track or have hidden.
    var myExclusion: Set<String> {
        Set(myPersonal.map(\.mediaKey)).union(hiddenRecs)
    }

    /// Don't recommend anything already in the household or hidden.
    var householdExclusion: Set<String> {
        Set((myPersonal + partnerPersonal + togetherItems).map(\.mediaKey)).union(hiddenRecs)
    }

    // MARK: - Lifecycle

    func configure(householdId: String?, uid: String?) {
        guard householdId != self.householdId || uid != self.uid else { return }
        self.householdId = householdId
        self.uid = uid
        subscribe()
    }

    private func subscribe() {
        listener?.remove()
        prefsListener?.remove()
        allItems = []
        hiddenRecs = []
        guard let householdId else { return }
        listener = db.collection("households").document(householdId).collection("items")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.allItems = snapshot.documents.compactMap { try? $0.data(as: LibraryItem.self) }
            }
        guard let uid else { return }
        prefsListener = db.collection("households").document(householdId)
            .collection("prefs").document(uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                let hidden = (snapshot?.data()?["hiddenRecs"] as? [String]) ?? []
                self.hiddenRecs = Set(hidden)
            }
    }

    /// Hide a recommendation so it won't be suggested again.
    func hide(mediaKey: String) {
        guard let householdId, let uid else { return }
        db.collection("households").document(householdId)
            .collection("prefs").document(uid)
            .setData(["hiddenRecs": FieldValue.arrayUnion([mediaKey])], merge: true)
    }

    func contains(mediaKey: String) -> Bool {
        myPersonal.contains { $0.mediaKey == mediaKey }
    }

    func item(forKey mediaKey: String) -> LibraryItem? {
        myPersonal.first { $0.mediaKey == mediaKey }
    }

    func togetherItem(forKey mediaKey: String) -> LibraryItem? {
        togetherItems.first { $0.mediaKey == mediaKey }
    }

    // MARK: - Mutations (operate on my personal library)

    func add(result: MediaSearchResult, state: WatchState, details: MediaDetails?) {
        guard let householdId, let uid, !contains(mediaKey: result.id) else { return }
        let docId = "\(uid)__\(result.id)"
        var data: [String: Any] = [
            "ownerUid": uid,
            "scope": "personal",
            "mediaKey": result.id,
            "title": result.title,
            "mediaTypeRaw": result.mediaType.rawValue,
            "stateRaw": state.rawValue,
            "overview": result.overview,
            "rating": 0,
            "currentSeason": 1,
            "currentEpisode": 0,
            "totalSeasons": details?.totalSeasons ?? 0,
            "totalEpisodes": details?.totalEpisodes ?? 0,
            "genres": details?.genres ?? [],
            "source": result.source,
            "sourceId": result.sourceId,
            "note": "",
            "addedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let poster = result.posterURL { data["posterURL"] = poster }
        if let year = result.year { data["year"] = year }

        db.collection("households").document(householdId)
            .collection("items").document(docId).setData(data, merge: true) { error in
                if error != nil {
                    Task { @MainActor in ErrorCenter.shared.report("Couldn't add the title — check your connection.") }
                }
            }
    }

    func addTogether(result: MediaSearchResult, details: MediaDetails?) {
        guard let householdId, let uid,
              !togetherItems.contains(where: { $0.mediaKey == result.id }) else { return }
        let docId = "together__\(result.id)"
        var data: [String: Any] = [
            "ownerUid": uid,
            "scope": "together",
            "mediaKey": result.id,
            "title": result.title,
            "mediaTypeRaw": result.mediaType.rawValue,
            "stateRaw": WatchState.wantToWatch.rawValue,
            "overview": result.overview,
            "rating": 0,
            "currentSeason": 1,
            "currentEpisode": 0,
            "totalSeasons": details?.totalSeasons ?? 0,
            "totalEpisodes": details?.totalEpisodes ?? 0,
            "genres": details?.genres ?? [],
            "source": result.source,
            "sourceId": result.sourceId,
            "note": "",
            "addedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let poster = result.posterURL { data["posterURL"] = poster }
        if let year = result.year { data["year"] = year }

        db.collection("households").document(householdId)
            .collection("items").document(docId).setData(data, merge: true) { error in
                if error != nil {
                    Task { @MainActor in ErrorCenter.shared.report("Couldn't add to Together — check your connection.") }
                }
            }
    }

    /// Bulk-add imported titles (batched writes). Titles already in the library are skipped.
    func importItems(_ candidates: [ImportCandidate]) async -> (added: Int, skipped: Int) {
        guard let householdId, let uid else { return (0, candidates.count) }
        let existing = Set(myPersonal.map(\.mediaKey))
        let fresh = candidates.filter { !existing.contains($0.mediaKey) }
        let itemsRef = db.collection("households").document(householdId).collection("items")

        var added = 0
        var index = 0
        while index < fresh.count {
            let chunk = Array(fresh[index..<min(index + 300, fresh.count)])
            let batch = db.batch()
            for candidate in chunk {
                var data: [String: Any] = [
                    "ownerUid": uid,
                    "scope": "personal",
                    "mediaKey": candidate.mediaKey,
                    "title": candidate.title,
                    "mediaTypeRaw": MediaType.anime.rawValue,
                    "stateRaw": candidate.state.rawValue,
                    "overview": candidate.overview,
                    "rating": candidate.rating,
                    "currentSeason": 1,
                    "currentEpisode": candidate.episode,
                    "totalSeasons": candidate.totalEpisodes > 0 ? 1 : 0,
                    "totalEpisodes": candidate.totalEpisodes,
                    "genres": candidate.genres,
                    "source": candidate.source,
                    "sourceId": candidate.sourceId,
                    "note": "",
                    "addedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                if let poster = candidate.posterURL { data["posterURL"] = poster }
                if let year = candidate.year { data["year"] = year }
                batch.setData(data, forDocument: itemsRef.document("\(uid)__\(candidate.mediaKey)"), merge: true)
            }
            do {
                try await batch.commit()
                added += chunk.count
            } catch {
                ErrorCenter.shared.report("Import stopped partway — check your connection and try again.")
                break
            }
            index += 300
        }
        return (added, candidates.count - fresh.count)
    }

    func setState(_ item: LibraryItem, to state: WatchState) {
        update(item, ["stateRaw": state.rawValue])
    }

    func setRating(_ item: LibraryItem, to rating: Int) {
        update(item, ["rating": rating])
    }

    func setProgress(_ item: LibraryItem, season: Int, episode: Int) {
        update(item, ["currentSeason": season, "currentEpisode": episode])
    }

    /// Sync stored metadata with freshly-fetched details: fills gaps AND updates stale values
    /// (e.g. an airing anime that finished, or a TV show that gained a season). Only writes
    /// when something actually changed, and never overwrites good data with empty values.
    func refresh(_ item: LibraryItem, with details: MediaDetails) {
        var fields: [String: Any] = [:]
        if details.totalEpisodes > 0 && details.totalEpisodes != item.totalEpisodes {
            fields["totalEpisodes"] = details.totalEpisodes
        }
        if details.totalSeasons > 0 && details.totalSeasons != item.totalSeasons {
            fields["totalSeasons"] = details.totalSeasons
        }
        if !details.genres.isEmpty && details.genres != item.genres {
            fields["genres"] = details.genres
        }
        if let poster = details.result.posterURL, poster != item.posterURL {
            fields["posterURL"] = poster
        }
        if !details.result.overview.isEmpty && details.result.overview != item.overview {
            fields["overview"] = details.result.overview
        }
        if let season = details.lastAiredSeason, season != item.lastAiredSeason {
            fields["lastAiredSeason"] = season
        }
        if let episode = details.lastAiredEpisode, episode != item.lastAiredEpisode {
            fields["lastAiredEpisode"] = episode
        }
        guard !fields.isEmpty else { return }
        update(item, fields, touch: false)   // a metadata sync isn't user activity
    }

    func remove(_ item: LibraryItem) {
        guard let householdId, let id = item.docId else { return }
        db.collection("households").document(householdId)
            .collection("items").document(id).delete { error in
                if error != nil {
                    Task { @MainActor in ErrorCenter.shared.report("Couldn't remove the title — check your connection.") }
                }
            }
    }

    private func update(_ item: LibraryItem, _ fields: [String: Any], touch: Bool = true) {
        guard let householdId, let id = item.docId else { return }
        var data = fields
        if touch { data["updatedAt"] = FieldValue.serverTimestamp() }
        db.collection("households").document(householdId)
            .collection("items").document(id).updateData(data) { error in
                if error != nil {
                    Task { @MainActor in ErrorCenter.shared.report("Couldn't save changes — check your connection.") }
                }
            }
    }
}
