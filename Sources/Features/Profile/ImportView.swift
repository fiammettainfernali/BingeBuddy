import SwiftUI
import UniformTypeIdentifiers

/// Import watch history from other trackers into the personal library.
struct ImportView: View {
    @EnvironmentObject private var store: LibraryStore

    private enum Phase: Equatable {
        case idle
        case working(String)
        case done(added: Int, skipped: Int)
        case failed(String)
    }

    @State private var phase: Phase = .idle
    @State private var anilistUsername = ""
    @State private var showFilePicker = false

    private let importer = ImportService()

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    var body: some View {
        Form {
            Section {
                TextField("AniList username", text: $anilistUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await runAniListImport() }
                } label: {
                    Label("Import from AniList", systemImage: "square.and.arrow.down")
                }
                .disabled(anilistUsername.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            } header: {
                Text("AniList")
            } footer: {
                Text("Pulls your public anime list — watching, completed, planning, scores, and episode progress.")
            }

            Section {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Choose export file…", systemImage: "doc.badge.arrow.up")
                }
                .disabled(isWorking)
            } header: {
                Text("MyAnimeList")
            } footer: {
                Text("On myanimelist.net: Profile → Anime List → Export. Pick the downloaded file here (.xml or .xml.gz both work).")
            }

            switch phase {
            case .idle:
                Section {
                    Text("Titles already in your library are skipped, so importing twice is safe. TV & movie import is coming later.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .working(let message):
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(message).foregroundStyle(.secondary)
                    }
                }
            case .done(let added, let skipped):
                Section {
                    Label("Imported \(added) title\(added == 1 ? "" : "s")"
                          + (skipped > 0 ? " · \(skipped) already in your library" : ""),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .failed(let message):
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            Task { await runMALImport(url: url) }
        }
    }

    private func runAniListImport() async {
        let username = anilistUsername.trimmingCharacters(in: .whitespaces)
        phase = .working("Fetching \(username)'s list…")
        do {
            let candidates = try await importer.fromAniList(username: username)
            phase = .working("Adding \(candidates.count) titles…")
            let result = await store.importItems(candidates)
            phase = .done(added: result.added, skipped: result.skipped)
        } catch {
            phase = .failed("Couldn't load that AniList profile. Check the username — the profile and its lists must be public.")
        }
    }

    private func runMALImport(url: URL) async {
        phase = .working("Reading export file…")
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let raw = try Data(contentsOf: url)
            phase = .working("Matching titles…")
            let candidates = try await importer.fromMALExport(raw)
            phase = .working("Adding \(candidates.count) titles…")
            let result = await store.importItems(candidates)
            phase = .done(added: result.added, skipped: result.skipped)
        } catch {
            phase = .failed("Couldn't read that file. Make sure it's the MyAnimeList export (.xml or .xml.gz).")
        }
    }
}
