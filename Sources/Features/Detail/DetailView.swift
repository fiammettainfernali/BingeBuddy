import SwiftUI
import SwiftData

struct DetailView: View {
    let result: MediaSearchResult

    @Environment(\.modelContext) private var context
    @Query private var allItems: [WatchItem]
    @State private var details: MediaDetails?
    @State private var isLoadingDetails = true

    private let service = MetadataService()

    private var existing: WatchItem? { allItems.first { $0.id == result.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let item = existing {
                    LibraryControls(item: item)
                } else {
                    addSection
                }
                synopsis
            }
            .padding()
        }
        .navigationTitle(result.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetails() }
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
            Text("Add to your library").font(.headline)
            ForEach(WatchState.allCases) { state in
                Button {
                    add(state: state)
                } label: {
                    Label(state.label, systemImage: state.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
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

        // Backfill totals/genres on an already-saved item once details arrive.
        if let item = existing, let details {
            if item.totalEpisodes == 0 { item.totalEpisodes = details.totalEpisodes }
            if item.totalSeasons == 0 { item.totalSeasons = details.totalSeasons }
            if item.genres.isEmpty { item.genres = details.genres }
            try? context.save()
        }
    }

    private func add(state: WatchState) {
        guard existing == nil else { return }   // no unique constraint under CloudKit
        let item = WatchItem(
            id: result.id,
            title: result.title,
            mediaType: result.mediaType,
            state: state,
            overview: result.overview,
            posterURL: result.posterURL,
            year: result.year,
            totalSeasons: details?.totalSeasons ?? 0,
            totalEpisodes: details?.totalEpisodes ?? 0,
            genres: details?.genres ?? [],
            source: result.source,
            sourceId: result.sourceId)
        context.insert(item)
        try? context.save()
    }
}

private struct LibraryControls: View {
    @Bindable var item: WatchItem
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Status").font(.headline)
                Picker("Status", selection: Binding(
                    get: { item.state },
                    set: { item.state = $0; touch() }
                )) {
                    ForEach(WatchState.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your rating").font(.headline)
                StarRating(rating: Binding(
                    get: { item.rating },
                    set: { item.rating = $0; touch() }
                ))
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

            Button(role: .destructive) {
                context.delete(item)
                try? context.save()
            } label: {
                Label("Remove from library", systemImage: "trash")
            }
        }
    }

    private func touch() {
        item.updatedAt = .now
        try? context.save()
    }
}

private struct StarRating: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                    .onTapGesture { rating = (rating == value) ? 0 : value }
            }
        }
    }
}
