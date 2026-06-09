import Foundation
import FirebaseFirestore

/// A show idea sent from one partner to the other.
struct Suggestion: Codable, Identifiable {
    @DocumentID var docId: String?
    var fromUid: String = ""
    var fromName: String = ""
    var toUid: String = ""
    var mediaKey: String = ""
    var title: String = ""
    var posterURL: String?
    var mediaTypeRaw: String = MediaType.movie.rawValue
    var year: String?
    var overview: String = ""
    var source: String = ""
    var sourceId: String = ""
    var message: String = ""
    var status: String = "pending"          // pending | accepted | dismissed
    @ServerTimestamp var createdAt: Date?

    var id: String { docId ?? mediaKey }
    var mediaType: MediaType { MediaType(rawValue: mediaTypeRaw) ?? .movie }

    var asSearchResult: MediaSearchResult {
        MediaSearchResult(source: source, sourceId: sourceId, title: title,
                          mediaType: mediaType, year: year, posterURL: posterURL, overview: overview)
    }
}

@MainActor
final class SuggestionStore: ObservableObject {
    @Published var incoming: [Suggestion] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var householdId: String?
    private var uid: String?

    var pendingCount: Int { incoming.filter { $0.status == "pending" }.count }

    func configure(householdId: String?, uid: String?) {
        guard householdId != self.householdId || uid != self.uid else { return }
        self.householdId = householdId
        self.uid = uid
        subscribe()
    }

    private func subscribe() {
        listener?.remove()
        incoming = []
        guard let householdId, let uid else { return }
        listener = db.collection("households").document(householdId).collection("suggestions")
            .whereField("toUid", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.incoming = snapshot.documents.compactMap { try? $0.data(as: Suggestion.self) }
            }
    }

    func send(result: MediaSearchResult, toUid: String, fromUid: String, fromName: String, message: String) {
        guard let householdId else { return }
        var data: [String: Any] = [
            "fromUid": fromUid,
            "fromName": fromName,
            "toUid": toUid,
            "mediaKey": result.id,
            "title": result.title,
            "mediaTypeRaw": result.mediaType.rawValue,
            "overview": result.overview,
            "source": result.source,
            "sourceId": result.sourceId,
            "message": message,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let poster = result.posterURL { data["posterURL"] = poster }
        if let year = result.year { data["year"] = year }

        db.collection("households").document(householdId)
            .collection("suggestions").addDocument(data: data)
    }

    func dismiss(_ suggestion: Suggestion) {
        guard let householdId, let id = suggestion.docId else { return }
        db.collection("households").document(householdId)
            .collection("suggestions").document(id).delete()
    }
}
