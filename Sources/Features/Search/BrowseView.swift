import SwiftUI

/// The idle Search screen: discovery carousels (For You / Trending / Popular).
/// Lives inside a NavigationStack that handles `MediaSearchResult` destinations.
struct BrowseView: View {
    let scope: SearchScope

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var session: Session

    @State private var forYou: [MediaSearchResult] = []
    @State private var trending: [MediaSearchResult] = []
    @State private var popular: [MediaSearchResult] = []
    @State private var isLoading = true
    @State private var loadedScope: SearchScope?
    @State private var loadedSeedKey: String?

    private let service = MetadataService()
    private let engine = RecommendationEngine()

    /// For You depends only on your library (not the current scope).
    private var seedKey: String {
        store.mySeeds.map(\.mediaKey).sorted().joined(separator: ",")
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if forYou.isEmpty && trending.isEmpty && popular.isEmpty {
                ContentUnavailableView("Nothing to browse",
                                       systemImage: "sparkles",
                                       description: Text("Search above to find something."))
                    .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    Carousel(title: "For You", items: forYou, onHide: hideForYou)
                    Carousel(title: "Trending this week", items: trending)
                    Carousel(title: scope == .anime ? "Most popular" : "Popular movies", items: popular)
                }
                .padding(.vertical)
            }
        }
        // Trending/Popular reload only when the scope changes; For You reloads when your library
        // changes. Neither reloads on a plain navigation-back, preserving scroll.
        .task {
            if loadedScope != scope { await loadTrendingPopular(); loadedScope = scope }
            if loadedSeedKey != seedKey { await loadForYou(); loadedSeedKey = seedKey }
        }
        .onChange(of: scope) { _, newScope in
            Task { await loadTrendingPopular(); loadedScope = newScope }
        }
        .onChange(of: seedKey) { _, newKey in
            Task { await loadForYou(); loadedSeedKey = newKey }
        }
    }

    private func loadTrendingPopular() async {
        isLoading = true
        trending = await service.trending(scope: scope)
        popular = await service.popular(scope: scope)
        isLoading = false
    }

    private func loadForYou() async {
        guard session.household != nil, !store.mySeeds.isEmpty else {
            forYou = []
            return
        }
        let recs = await engine.recommendations(seeds: store.mySeeds, exclude: store.myExclusion, limit: 40)
        // Don't wipe existing picks if a refresh came back empty (e.g. a rate-limit hiccup).
        if !recs.isEmpty || forYou.isEmpty {
            forYou = recs.map(\.result)
        }
    }

    private func hideForYou(_ item: MediaSearchResult) {
        forYou.removeAll { $0.id == item.id }
        store.hide(mediaKey: item.id)
    }
}

private struct Carousel: View {
    let title: String
    let items: [MediaSearchResult]
    var onHide: ((MediaSearchResult) -> Void)? = nil

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3.bold()).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            if let onHide {
                                NavigationLink(value: item) { PosterCard(item: item) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) { onHide(item) } label: {
                                            Label("Not interested", systemImage: "hand.thumbsdown")
                                        }
                                    }
                            } else {
                                NavigationLink(value: item) { PosterCard(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct PosterCard: View {
    let item: MediaSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: item.posterURL, width: 110, height: 165)
            Text(item.title)
                .font(.caption)
                .lineLimit(2)
                .frame(width: 110, alignment: .leading)
        }
    }
}
