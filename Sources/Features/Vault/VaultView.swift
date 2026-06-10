import SwiftUI
import SwiftData

/// Shows the gate until unlocked, then the vault contents. Re-locks on exit.
struct VaultContainerView: View {
    @EnvironmentObject private var vault: VaultManager

    var body: some View {
        Group {
            if vault.isUnlocked {
                VaultView()
            } else {
                VaultGateView()
            }
        }
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vault.lock() }
    }
}

/// The unlocked vault: a private, on-device-only library.
struct VaultView: View {
    @EnvironmentObject private var vault: VaultManager
    @Environment(\.modelContext) private var context
    @Query(sort: \WatchItem.updatedAt, order: .reverse) private var items: [WatchItem]
    @State private var selectedState: WatchState = .watching
    @State private var showSearch = false

    private var filtered: [WatchItem] { items.filter { $0.state == selectedState } }

    var body: some View {
        VStack(spacing: 0) {
            Picker("State", selection: $selectedState) {
                ForEach(WatchState.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            if filtered.isEmpty {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "lock.fill",
                    description: Text("Tap + to add a private title. It stays on this device only."))
            } else {
                List {
                    ForEach(filtered) { item in
                        NavigationLink(value: item) { VaultRow(item: item) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { vault.lock() } label: { Label("Lock", systemImage: "lock") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSearch = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showSearch) { VaultSearchView() }
        .navigationDestination(for: WatchItem.self) { VaultItemDetail(item: $0) }
    }
}

private struct VaultRow: View {
    let item: WatchItem

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: item.posterURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(2)
                Text(item.mediaType.label + (item.year.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                if item.state == .watching && item.totalEpisodes > 0 {
                    Text("S\(item.currentSeason) · E\(item.currentEpisode)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// Search + add titles into the vault (writes to local SwiftData).
private struct VaultSearchView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [WatchItem]

    @State private var query = ""
    @State private var scope: SearchScope = .moviesTV
    @State private var results: [MediaSearchResult] = []
    @State private var isLoading = false

    private let service = MetadataService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Scope", selection: $scope) {
                    ForEach(SearchScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if isLoading {
                    Spacer(); ProgressView("Searching…"); Spacer()
                } else if results.isEmpty {
                    ContentUnavailableView("Search to add", systemImage: "magnifyingglass",
                                           description: Text("Find a title to add privately."))
                } else {
                    List(results) { result in
                        HStack(spacing: 12) {
                            PosterImage(url: result.posterURL)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title).font(.headline).lineLimit(2)
                                Text(result.mediaType.label + (result.year.map { " · \($0)" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if contains(result) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("Add") { add(result) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add to Vault")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Show, movie, or anime")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func contains(_ result: MediaSearchResult) -> Bool {
        existing.contains { $0.id == result.id }
    }

    private func add(_ result: MediaSearchResult) {
        Task {
            let details = try? await service.details(for: result)
            let item = WatchItem(
                id: result.id, title: result.title, mediaType: result.mediaType,
                state: .wantToWatch, overview: result.overview, posterURL: result.posterURL,
                year: result.year, totalSeasons: details?.totalSeasons ?? 0,
                totalEpisodes: details?.totalEpisodes ?? 0, genres: details?.genres ?? [],
                source: result.source, sourceId: result.sourceId)
            context.insert(item)
            try? context.save()
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        results = (try? await service.search(trimmed, scope: scope)) ?? []
        isLoading = false
    }
}

/// Edit a vault item (local SwiftData).
private struct VaultItemDetail: View {
    @Bindable var item: WatchItem
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    PosterImage(url: item.posterURL, width: 120, height: 180)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title).font(.title3.bold())
                        Text(item.mediaType.label + (item.year.map { " · \($0)" } ?? ""))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Status").font(.headline)
                    Picker("Status", selection: Binding(
                        get: { item.state },
                        set: { newValue in
                            item.state = newValue
                            if newValue == .finished && item.totalEpisodes > 0 {
                                item.currentEpisode = item.totalEpisodes
                                if item.totalSeasons > 0 { item.currentSeason = item.totalSeasons }
                            }
                            touch()
                        }
                    )) {
                        ForEach(WatchState.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your rating").font(.headline)
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { value in
                            Image(systemName: value <= item.rating ? "star.fill" : "star")
                                .font(.title2).foregroundStyle(.yellow)
                                .onTapGesture { item.rating = (item.rating == value) ? 0 : value; touch() }
                        }
                    }
                }

                if item.totalEpisodes > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Progress").font(.headline)
                        Stepper("Season \(item.currentSeason)", value: Binding(
                            get: { item.currentSeason },
                            set: { item.currentSeason = max(1, $0); touch() }
                        ), in: 1...max(1, item.totalSeasons))
                        Stepper("Episode \(item.currentEpisode)", value: Binding(
                            get: { item.currentEpisode },
                            set: { item.currentEpisode = max(0, $0); touch() }
                        ), in: 0...max(0, item.totalEpisodes))
                    }
                }

                if !item.overview.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Synopsis").font(.headline)
                        Text(item.overview).font(.body).foregroundStyle(.secondary)
                    }
                }

                Button(role: .destructive) {
                    context.delete(item)
                    try? context.save()
                } label: {
                    Label("Remove from vault", systemImage: "trash")
                }
            }
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func touch() {
        item.updatedAt = .now
        try? context.save()
    }
}
