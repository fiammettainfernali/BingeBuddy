import SwiftUI
import AuthenticationServices

struct ProfileView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var notifications: NotificationManager
    @State private var name = ""
    @State private var joinCode = ""
    @State private var currentNonce: String?
    @State private var exportURL: URL?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if session.isLoading {
                    ProgressView("Connecting…")
                } else if let household = session.household {
                    pairedView(household)
                } else {
                    pairingView
                }
            }
            .navigationTitle("Profile")
            .task { await notifications.refreshStatus() }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if session.appleLinked {
                Label("Backed up with your Apple ID", systemImage: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
                Text("Your library survives reinstalls and phone upgrades.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    let nonce = Session.randomNonce()
                    currentNonce = nonce
                    request.requestedScopes = []
                    request.nonce = Session.sha256(nonce)
                } onCompletion: { result in
                    guard case .success(let auth) = result,
                          let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = credential.identityToken,
                          let token = String(data: tokenData, encoding: .utf8),
                          let nonce = currentNonce else { return }
                    Task { await session.linkWithApple(idToken: token, rawNonce: nonce) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)
                Text("Without this, your library is tied to this one phone — sign in so it survives reinstalls and upgrades.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dataSection: some View {
        Section("Your data") {
            NavigationLink {
                ImportView()
            } label: {
                Label("Import from other trackers", systemImage: "square.and.arrow.down")
            }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share BingeBuddy-Export.json", systemImage: "doc.badge.arrow.up")
                }
            } else {
                Button {
                    exportURL = makeExport()
                } label: {
                    Label("Export my data", systemImage: "square.and.arrow.up")
                }
            }

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete my account", systemImage: "trash")
            }
            .disabled(session.isBusy)
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete my account and data", role: .destructive) {
                    Task { await session.deleteAccount() }
                }
            } message: {
                Text("Removes your library, suggestions, and account from the cloud. Your partner's own data stays. Your on-device vault is not affected. This can't be undone.")
            }
        }
    }

    /// Writes the user's library (personal + shared) to a JSON file for sharing/backup.
    private func makeExport() -> URL? {
        struct ExportItem: Codable {
            let scope, title, mediaType, state: String
            let year: String?
            let rating, currentSeason, currentEpisode, totalSeasons, totalEpisodes: Int
            let genres: [String]
            let note, source, sourceId, mediaKey: String
            let addedAt, updatedAt: String?

            init(_ item: LibraryItem) {
                let iso = ISO8601DateFormatter()
                scope = item.scope
                title = item.title
                mediaType = item.mediaTypeRaw
                state = item.stateRaw
                year = item.year
                rating = item.rating
                currentSeason = item.currentSeason
                currentEpisode = item.currentEpisode
                totalSeasons = item.totalSeasons
                totalEpisodes = item.totalEpisodes
                genres = item.genres
                note = item.note
                source = item.source
                sourceId = item.sourceId
                mediaKey = item.mediaKey
                addedAt = item.addedAt.map(iso.string(from:))
                updatedAt = item.updatedAt.map(iso.string(from:))
            }
        }
        let payload = (store.myPersonal + store.togetherItems).map(ExportItem.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BingeBuddy-Export.json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            if notifications.authorized {
                Label("Episode reminders on", systemImage: "bell.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task {
                        await notifications.requestAuthorization()
                        await notifications.scheduleEpisodeReminders(for: store.myPersonal, force: true)
                    }
                } label: {
                    Label("Get reminders for new episodes", systemImage: "bell")
                }
            }
            Text("Reminds you when a new episode airs for TV series you're watching.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Paired

    private func pairedView(_ household: Household) -> some View {
        Form {
            Section("You") {
                LabeledContent("Name", value: session.myName)
            }

            Section("Household") {
                if let partner = session.partnerName {
                    LabeledContent("Partner", value: partner)
                } else {
                    Text("Waiting for your partner to join…")
                        .foregroundStyle(.secondary)
                }
            }

            if session.partnerName == nil, let code = household.id {
                Section("Invite your partner") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share this code so they can join:")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Text(code)
                                .font(.system(.title, design: .monospaced).bold())
                                .textSelection(.enabled)
                            Spacer()
                            ShareLink(item: "Join our BingeBuddy household with code: \(code)") {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await session.leaveHousehold() }
                } label: {
                    Text("Leave household")
                }
                .disabled(session.isBusy)
            }

            accountSection
            notificationsSection
            vaultSection
            dataSection
        }
    }

    // MARK: - Vault

    private var vaultSection: some View {
        Section("Private") {
            NavigationLink {
                VaultContainerView()
            } label: {
                Label("Vault", systemImage: "lock.fill")
            }
        }
    }

    // MARK: - Pairing

    private var pairingView: some View {
        Form {
            Section("Your name") {
                TextField("e.g. Jesse", text: $name)
                    .textInputAutocapitalization(.words)
            }

            Section("Start fresh") {
                Button {
                    Task { await session.createHousehold(myName: name) }
                } label: {
                    Label("Create a household", systemImage: "house.fill")
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || session.isBusy)
            }

            Section("Join your partner") {
                TextField("Enter their code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    Task { await session.joinHousehold(code: joinCode, myName: name) }
                } label: {
                    Label("Join household", systemImage: "person.2.fill")
                }
                .disabled(
                    name.trimmingCharacters(in: .whitespaces).isEmpty
                    || joinCode.trimmingCharacters(in: .whitespaces).isEmpty
                    || session.isBusy)
            }

            if let error = session.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            accountSection
            notificationsSection
            vaultSection
            dataSection
        }
    }
}
