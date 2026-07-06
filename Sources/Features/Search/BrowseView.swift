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

    private let service = MetadataService()
    private let engine = RecommendationEngine()

    /// Seed For You from the titles matching the current scope, so the Anime tab shows anime picks.
    private var scopedSeeds: [LibraryItem] {
        switch scope {
        case .anime: return store.mySeeds.filter { $0.mediaType == .anime }
        case .moviesTV: return store.mySeeds.filter { $0.mediaType == .movie || $0.mediaType == .tv }
        }
    }

    private var seedKey: String {
        scope.rawValue + "|" + scopedSeeds.map(\.mediaKey).sorted().joined(separator: ",")
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
                    Carousel(title: scope == .anime ? "This Season" : "Trending this week", items: trending)
                    Carousel(title: scope == .anime ? "Most Popular" : "Popular movies", items: popular)
                }
                .padding(.vertical)
            }
        }
        .refreshable {
            await loadTrendingPopular()
            await loadForYou()
        }
        // .task(id:) reliably re-runs when the scope/library changes. On a genuine scope change we
        // clear first (so the previous scope's items don't linger); on a plain reappear we keep
        // what's there and just refresh in place, so nothing blanks out.
        .task(id: scope) {
            if loadedScope != scope {
                trending = []
                popular = []
                forYou = []
                loadedScope = scope
            }
            await loadTrendingPopular()
        }
        .task(id: seedKey) {
            await loadForYou()
        }
    }

    private func loadTrendingPopular() async {
        if trending.isEmpty && popular.isEmpty { isLoading = true }
        async let trendingTask = service.trending(scope: scope)
        async let popularTask = service.popular(scope: scope)
        let newTrending = await trendingTask
        if !newTrending.isEmpty || trending.isEmpty { trending = newTrending }
        isLoading = false
        let newPopular = await popularTask
        if !newPopular.isEmpty || popular.isEmpty { popular = newPopular }
    }

    private func loadForYou() async {
        guard session.household != nil, !scopedSeeds.isEmpty else {
            forYou = []
            return
        }
        let recs = await engine.recommendations(seeds: scopedSeeds, exclude: store.myExclusion, limit: 40)
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
