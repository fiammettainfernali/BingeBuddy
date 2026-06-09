import Foundation
import FirebaseAuth
import FirebaseFirestore

/// A shared "household" linking two people's devices.
struct Household: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var memberUids: [String]
    var memberNames: [String: String]
    var createdAt: Date?
}

/// Owns auth + household state for the whole app.
@MainActor
final class Session: ObservableObject {
    @Published var uid: String?
    @Published var household: Household?
    @Published var isLoading = true
    @Published var isBusy = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var householdListener: ListenerRegistration?

    var myName: String {
        guard let uid, let name = household?.memberNames[uid] else { return "Me" }
        return name
    }

    var partnerName: String? {
        guard let uid, let household else { return nil }
        for (memberUid, name) in household.memberNames where memberUid != uid {
            return name
        }
        return nil
    }

    var partnerUid: String? {
        guard let uid, let household else { return nil }
        return household.memberUids.first { $0 != uid }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        do {
            let user = try await ensureSignedIn()
            uid = user.uid
            try await loadHousehold(for: user.uid)
        } catch {
            errorMessage = "Couldn't connect. Check your internet and reopen the app."
        }
        isLoading = false
    }

    private func ensureSignedIn() async throws -> User {
        if let current = Auth.auth().currentUser { return current }
        let result = try await Auth.auth().signInAnonymously()
        return result.user
    }

    private func loadHousehold(for uid: String) async throws {
        let snapshot = try await db.collection("households")
            .whereField("memberUids", arrayContains: uid)
            .limit(to: 1)
            .getDocuments()
        if let doc = snapshot.documents.first {
            household = try doc.data(as: Household.self)
            listenToHousehold(id: doc.documentID)
        }
    }

    private func listenToHousehold(id: String) {
        householdListener?.remove()
        householdListener = db.collection("households").document(id)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot, snapshot.exists else { return }
                self.household = try? snapshot.data(as: Household.self)
            }
    }

    // MARK: - Pairing

    func createHousehold(myName: String) async {
        guard let uid, !myName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isBusy = true
        errorMessage = nil
        let code = Self.randomCode()
        do {
            try await db.collection("households").document(code).setData([
                "name": "Our Household",
                "memberUids": [uid],
                "memberNames": [uid: myName],
                "createdAt": FieldValue.serverTimestamp()
            ])
            try await loadHousehold(for: uid)
        } catch {
            errorMessage = "Couldn't create the household. Try again."
        }
        isBusy = false
    }

    func joinHousehold(code: String, myName: String) async {
        guard let uid, !myName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let cleanCode = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleanCode.isEmpty else { return }
        isBusy = true
        errorMessage = nil
        let ref = db.collection("households").document(cleanCode)
        do {
            let doc = try await ref.getDocument()
            guard doc.exists else {
                errorMessage = "No household found with that code."
                isBusy = false
                return
            }
            try await ref.updateData([
                "memberUids": FieldValue.arrayUnion([uid]),
                "memberNames.\(uid)": myName
            ])
            try await loadHousehold(for: uid)
        } catch {
            errorMessage = "Couldn't join. Double-check the code and try again."
        }
        isBusy = false
    }

    func leaveHousehold() async {
        guard let uid, let id = household?.id else { return }
        isBusy = true
        do {
            try await db.collection("households").document(id).updateData([
                "memberUids": FieldValue.arrayRemove([uid]),
                "memberNames.\(uid)": FieldValue.delete()
            ])
            householdListener?.remove()
            household = nil
        } catch {
            errorMessage = "Couldn't leave the household."
        }
        isBusy = false
    }

    private static func randomCode(length: Int = 6) -> String {
        let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   // no ambiguous chars
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
