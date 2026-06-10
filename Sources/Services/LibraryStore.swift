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

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
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
    private func seedWeight(_ item: LibraryItem) -> Int {
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
                let lhs = seedWeight($0), rhs = seedWeight($1)
                if lhs != rhs { return lhs > rhs }
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
    }

    /// What to base my personal "For You" picks on.
    var mySeeds: [LibraryItem] { seeds(from: myPersonal) }

    /// What to base couple "For Us" picks on.
    var ourSeeds: [LibraryItem] { seeds(from: myPersonal + partnerPersonal) }

    /// Don't recommend things I already track.
    var myExclusion: Set<String> { Set(myPersonal.map(\.mediaKey)) }

    /// Don't recommend anything already in the household.
    var householdExclusion: Set<String> {
        Set((myPersonal + partnerPersonal + togetherItems).map(\.mediaKey))
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
        allItems = []
        guard let householdId else { return }
        listener = db.collection("households").document(householdId).collection("items")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.allItems = snapshot.documents.compactMap { try? $0.data(as: LibraryItem.self) }
            }
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
            .collection("items").document(docId).setData(data, merge: true)
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
            .collection("items").document(docId).setData(data, merge: true)
    }

    func setState(_ item: LibraryItem, to state: WatchState) {
        var fields: [String: Any] = ["stateRaw": state.rawValue]
        // Finishing a series fills progress to the end so you don't tap through every episode.
        if state == .finished && item.totalEpisodes > 0 {
            fields["currentEpisode"] = item.totalEpisodes
            if item.totalSeasons > 0 { fields["currentSeason"] = item.totalSeasons }
        }
        update(item, fields)
    }

    func setRating(_ item: LibraryItem, to rating: Int) {
        update(item, ["rating": rating])
    }

    func setProgress(_ item: LibraryItem, season: Int, episode: Int) {
        update(item, ["currentSeason": season, "currentEpisode": episode])
    }

    func backfill(_ item: LibraryItem, with details: MediaDetails) {
        var fields: [String: Any] = [:]
        if item.totalEpisodes == 0 { fields["totalEpisodes"] = details.totalEpisodes }
        if item.totalSeasons == 0 { fields["totalSeasons"] = details.totalSeasons }
        if item.genres.isEmpty && !details.genres.isEmpty { fields["genres"] = details.genres }
        guard !fields.isEmpty else { return }
        update(item, fields)
    }

    func remove(_ item: LibraryItem) {
        guard let householdId, let id = item.docId else { return }
        db.collection("households").document(householdId)
            .collection("items").document(id).delete()
    }

    private func update(_ item: LibraryItem, _ fields: [String: Any]) {
        guard let householdId, let id = item.docId else { return }
        var data = fields
        data["updatedAt"] = FieldValue.serverTimestamp()
        db.collection("households").document(householdId)
            .collection("items").document(id).updateData(data)
    }
}
