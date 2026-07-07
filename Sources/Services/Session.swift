import Foundation
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import Security

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
    @Published var appleLinked = false

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
            refreshAppleLinked()
            try await loadHousehold(for: user.uid)
        } catch {
            errorMessage = "Couldn't connect. Check your internet and reopen the app."
        }
        isLoading = false
    }

    // MARK: - Sign in with Apple (account linking)

    private func refreshAppleLinked() {
        appleLinked = Auth.auth().currentUser?.providerData
            .contains { $0.providerID == "apple.com" } ?? false
    }

    /// Link the Apple credential to the CURRENT (anonymous) account so the uid — and all
    /// Firestore data keyed to it — stays exactly the same. If this Apple ID already owns an
    /// account (e.g. the app was reinstalled), sign into that account instead, recovering it.
    func linkWithApple(idToken: String, rawNonce: String) async {
        isBusy = true
        errorMessage = nil
        let credential = OAuthProvider.appleCredential(withIDToken: idToken,
                                                       rawNonce: rawNonce,
                                                       fullName: nil)
        do {
            if let current = Auth.auth().currentUser {
                _ = try await current.link(with: credential)
            } else {
                _ = try await Auth.auth().signIn(with: credential)
            }
            refreshAppleLinked()
        } catch let error as NSError where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
            // This Apple ID already has an account — switch to it (data recovery path).
            let updated = (error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential) ?? credential
            do {
                let result = try await Auth.auth().signIn(with: updated)
                uid = result.user.uid
                householdListener?.remove()
                household = nil
                refreshAppleLinked()
                try await loadHousehold(for: result.user.uid)
            } catch {
                errorMessage = "Couldn't sign in with Apple. Try again."
            }
        } catch {
            errorMessage = "Couldn't link your Apple ID. Try again."
        }
        isBusy = false
    }

    // MARK: - Sign in with Apple nonce helpers

    /// Random nonce for the Apple request; its SHA-256 goes to Apple, the raw value to Firebase.
    static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Unable to generate nonce")
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
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

    // MARK: - Account deletion

    /// Permanently removes this user's cloud data and auth account. If they're the last
    /// household member, the whole household (including shared items) is removed too.
    /// The local vault is untouched. Returns true on success.
    @discardableResult
    func deleteAccount() async -> Bool {
        guard let uid else { return false }
        isBusy = true
        errorMessage = nil
        do {
            if let householdId = household?.id {
                let householdRef = db.collection("households").document(householdId)
                let isLastMember = (household?.memberUids.count ?? 1) <= 1

                let items = householdRef.collection("items")
                let suggestions = householdRef.collection("suggestions")
                if isLastMember {
                    try await deleteAll(items)
                    try await deleteAll(suggestions)
                    try await deleteAll(householdRef.collection("prefs"))
                } else {
                    try await deleteAll(items.whereField("ownerUid", isEqualTo: uid)
                                             .whereField("scope", isEqualTo: "personal"))
                    try await deleteAll(suggestions.whereField("toUid", isEqualTo: uid))
                    try await deleteAll(suggestions.whereField("fromUid", isEqualTo: uid))
                    try await householdRef.collection("prefs").document(uid).delete()
                }

                householdListener?.remove()
                if isLastMember {
                    try await householdRef.delete()
                } else {
                    try await householdRef.updateData([
                        "memberUids": FieldValue.arrayRemove([uid]),
                        "memberNames.\(uid)": FieldValue.delete()
                    ])
                }
                household = nil
            }

            try await Auth.auth().currentUser?.delete()
            self.uid = nil
            appleLinked = false
            isBusy = false
            await bootstrap()   // fresh anonymous account; app returns to setup
            return true
        } catch let error as NSError where error.code == AuthErrorCode.requiresRecentLogin.rawValue {
            errorMessage = "For security, sign in with Apple again first, then retry deleting."
        } catch {
            errorMessage = "Couldn't delete your account. Check your connection and try again."
        }
        isBusy = false
        return false
    }

    /// Delete every document a query returns, in batches under Firestore's 500-write limit.
    private func deleteAll(_ query: Query) async throws {
        while true {
            let snapshot = try await query.limit(to: 400).getDocuments()
            guard !snapshot.isEmpty else { return }
            let batch = db.batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            if snapshot.documents.count < 400 { return }
        }
    }
}
