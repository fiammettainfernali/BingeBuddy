import SwiftUI

/// Per-episode checklist with titles and air dates. Progress is the same watermark the
/// steppers/+1-swipe use, so everything stays in sync (including the shared Together copy).
struct EpisodeListView: View {
    let result: MediaSearchResult
    let together: Bool

    @EnvironmentObject private var store: LibraryStore
    @State private var seasons: [SeasonInfo]
    @State private var selectedSeason: Int
    @State private var page: Int
    @State private var lastPage = 1
    @State private var episodes: [EpisodeInfo] = []
    @State private var isLoading = true

    private let service = MetadataService()

    init(result: MediaSearchResult, together: Bool,
         seasons: [SeasonInfo], initialSeason: Int, initialEpisode: Int) {
        self.result = result
        self.together = together
        _seasons = State(initialValue: seasons)
        _selectedSeason = State(initialValue: max(1, initialSeason))
        // Long anime: start on the page that contains the current episode.
        _page = State(initialValue: max(1, (max(initialEpisode, 1) - 1) / 100 + 1))
    }

    private var item: LibraryItem? {
        together ? store.togetherItem(forKey: result.id) : store.item(forKey: result.id)
    }

    private var isAnime: Bool { result.mediaType == .anime }

    var body: some View {
        List {
            if !isAnime && seasons.count > 1 {
                Picker("Season", selection: $selectedSeason) {
                    ForEach(seasons, id: \.number) { season in
                        Text(season.name).tag(season.number)
                    }
                }
                .pickerStyle(.menu)
            }

            if isLoading && episodes.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if episodes.isEmpty {
                Text("An episode list isn't available for this title.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(episodes) { episode in
                    episodeRow(episode)
                }
            }

            if isAnime && lastPage > 1 {
                pageControls
            }

            Section {
                Text("Tapping an episode marks everything up to it as watched. Tapping the last watched episode unchecks it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(together ? "Episodes · Together" : "Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(selectedSeason)|\(page)") { await load() }
        .onChange(of: selectedSeason) { _, _ in page = 1 }
        .refreshable { await load() }
    }

    private func episodeRow(_ episode: EpisodeInfo) -> some View {
        let watched = isWatched(episode)
        let isFuture = (episode.airDate ?? .distantPast) > Date()
        return Button {
            tap(episode)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: watched ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(watched ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("E\(episode.number)" + (episode.title.map { " · \($0)" } ?? ""))
                        .lineLimit(2)
                    if let date = episode.airDate {
                        Text(isFuture
                             ? "Airs \(date.formatted(date: .abbreviated, time: .omitted))"
                             : date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(isFuture ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .opacity(isFuture && !watched ? 0.6 : 1)
        .disabled(item == nil)
    }

    private var pageControls: some View {
        HStack {
            Button { page -= 1 } label: { Label("Earlier", systemImage: "chevron.left") }
                .disabled(page <= 1)
            Spacer()
            Text("Page \(page) of \(lastPage)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { page += 1 } label: { Label("Later", systemImage: "chevron.right") }
                .disabled(page >= lastPage)
        }
        .buttonStyle(.borderless)
    }

    private func isWatched(_ episode: EpisodeInfo) -> Bool {
        guard let item else { return false }
        return EpisodeProgress.isWatched(
            season: isAnime ? 1 : selectedSeason, episode: episode.number,
            currentSeason: item.currentSeason, currentEpisode: item.currentEpisode)
    }

    private func tap(_ episode: EpisodeInfo) {
        guard let item else { return }
        let next = EpisodeProgress.watermarkAfterTap(
            season: isAnime ? 1 : selectedSeason, episode: episode.number,
            currentSeason: item.currentSeason, currentEpisode: item.currentEpisode,
            seasons: seasons)
        store.setProgress(item, season: max(1, next.season), episode: max(0, next.episode))
    }

    private func load() async {
        isLoading = true
        // Opened before the detail screen finished loading? Fetch the season list ourselves.
        if !isAnime && seasons.isEmpty {
            if let details = try? await service.details(for: result) {
                seasons = details.seasons
            }
        }
        if let fetched = try? await service.episodes(for: result, season: selectedSeason, page: page) {
            episodes = fetched.episodes
            lastPage = fetched.lastPage
        } else {
            episodes = []
        }
        isLoading = false
    }
}
