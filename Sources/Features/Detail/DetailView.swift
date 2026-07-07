import SwiftUI

struct DetailView: View {
    let result: MediaSearchResult

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var suggestions: SuggestionStore
    @State private var details: MediaDetails?
    @State private var isLoadingDetails = true
    @State private var didSuggest = false

    private let service = MetadataService()

    private var existing: LibraryItem? { store.item(forKey: result.id) }
    private var togetherItem: LibraryItem? { store.togetherItem(forKey: result.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let item = existing {
                    controls(for: item)
                } else {
                    addSection
                }
                togetherSection
                synopsis
            }
            .padding()
        }
        .navigationTitle(result.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.partnerName != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sendSuggestion()
                    } label: {
                        Image(systemName: "paperplane")
                    }
                }
            }
        }
        .alert("Sent to \(session.partnerName ?? "your partner")", isPresented: $didSuggest) {
            Button("OK", role: .cancel) {}
        }
        .task { await loadDetails() }
    }

    @ViewBuilder private var togetherSection: some View {
        if session.partnerName != nil {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                Text("Watch Together").font(.headline)
                if let item = togetherItem {
                    Picker("Status", selection: Binding(
                        get: { item.state },
                        set: { store.setState(item, to: $0) }
                    )) {
                        ForEach(WatchState.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if item.state == .watching {
                        if item.totalSeasons > 1 {
                            Stepper("Season \(item.currentSeason)", value: Binding(
                                get: { item.currentSeason },
                                set: { store.setProgress(item, season: max(1, $0), episode: item.currentEpisode) }
                            ), in: 1...item.totalSeasons)
                        }
                        Stepper("Episode \(item.currentEpisode)", value: Binding(
                            get: { item.currentEpisode },
                            set: { store.setProgress(item, season: item.currentSeason, episode: max(0, $0)) }
                        ), in: 0...(item.totalEpisodes > 0 ? item.totalEpisodes : 9999))
                        if result.mediaType != .movie {
                            NavigationLink {
                                EpisodeListView(result: result, together: true,
                                                seasons: details?.seasons ?? [],
                                                initialSeason: item.currentSeason,
                                                initialEpisode: item.currentEpisode)
                            } label: {
                                Label("Episode checklist", systemImage: "checklist")
                            }
                        }
                    }

                    Button(role: .destructive) {
                        store.remove(item)
                    } label: {
                        Label("Remove from Together", systemImage: "heart.slash")
                    }
                } else {
                    Button {
                        store.addTogether(result: result, details: details)
                    } label: {
                        Label("Add to Watch Together", systemImage: "heart")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func sendSuggestion() {
        guard let toUid = session.partnerUid, let fromUid = session.uid else { return }
        suggestions.send(result: result, toUid: toUid, fromUid: fromUid,
                         fromName: session.myName, message: "")
        didSuggest = true
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PosterImage(url: result.posterURL, width: 120, height: 180)
            VStack(alignment: .leading, spacing: 8) {
                Text(result.title).font(.title3.bold())
                Text(result.mediaType.label + (result.year.map { " · \($0)" } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let details, !details.genres.isEmpty {
                    Text(details.genres.prefix(3).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let details, details.totalEpisodes > 0 {
                    Text("\(details.totalSeasons) season\(details.totalSeasons == 1 ? "" : "s") · \(details.totalEpisodes) episodes")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if isLoadingDetails {
                    ProgressView().controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.household == nil {
                Label("Set up your household in the Profile tab to start adding titles.",
                      systemImage: "person.2")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Add to your library").font(.headline)
                ForEach(WatchState.allCases) { state in
                    Button {
                        store.add(result: result, state: state, details: details)
                    } label: {
                        Label(state.label, systemImage: state.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func controls(for item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Status").font(.headline)
                Picker("Status", selection: Binding(
                    get: { item.state },
                    set: { store.setState(item, to: $0) }
                )) {
                    ForEach(WatchState.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your rating").font(.headline)
                StarRating(rating: item.rating) { store.setRating(item, to: $0) }
            }

            if item.state == .watching {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Progress").font(.headline)
                    if item.totalSeasons > 1 {
                        Stepper("Season \(item.currentSeason)", value: Binding(
                            get: { item.currentSeason },
                            set: { store.setProgress(item, season: max(1, $0), episode: item.currentEpisode) }
                        ), in: 1...item.totalSeasons)
                    }
                    Stepper("Episode \(item.currentEpisode)", value: Binding(
                        get: { item.currentEpisode },
                        set: { store.setProgress(item, season: item.currentSeason, episode: max(0, $0)) }
                    ), in: 0...(item.totalEpisodes > 0 ? item.totalEpisodes : 9999))
                    if result.mediaType != .movie {
                        NavigationLink {
                            EpisodeListView(result: result, together: false,
                                            seasons: details?.seasons ?? [],
                                            initialSeason: item.currentSeason,
                                            initialEpisode: item.currentEpisode)
                        } label: {
                            Label("Episode checklist", systemImage: "checklist")
                        }
                        .padding(.top, 4)
                    }
                }
            }

            Button(role: .destructive) {
                store.remove(item)
            } label: {
                Label("Remove from library", systemImage: "trash")
            }
        }
    }

    @ViewBuilder private var synopsis: some View {
        if !result.overview.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Synopsis").font(.headline)
                Text(result.overview).font(.body).foregroundStyle(.secondary)
            }
        }
    }

    private func loadDetails() async {
        isLoadingDetails = true
        details = try? await service.details(for: result)
        isLoadingDetails = false
        // Keep stored metadata in sync (stale episode counts, new seasons, poster changes).
        if let details {
            if let item = existing { store.refresh(item, with: details) }
            if let shared = togetherItem { store.refresh(shared, with: details) }
        }
    }
}

private struct StarRating: View {
    let rating: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                    .onTapGesture { onChange(rating == value ? 0 : value) }
            }
        }
    }
}
