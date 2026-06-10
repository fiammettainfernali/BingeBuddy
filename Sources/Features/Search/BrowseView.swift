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
    @State private var loadedKey: String?

    private let service = MetadataService()
    private let engine = RecommendationEngine()

    private var seedKey: String {
        scope.rawValue + "|" + store.mySeeds.map(\.mediaKey).sorted().joined()
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
        // Only (re)load when the scope or your library actually changes — not every time you
        // come back from a detail screen — so scroll position is preserved.
        .task {
            guard loadedKey != seedKey else { return }
            await load()
            loadedKey = seedKey
        }
    }

    private func load() async {
        isLoading = true
        async let trendingTask = service.trending(scope: scope)
        async let popularTask = service.popular(scope: scope)
        trending = await trendingTask
        popular = await popularTask

        if session.household != nil && !store.mySeeds.isEmpty {
            let recs = await engine.recommendations(seeds: store.mySeeds, exclude: store.myExclusion, limit: 40)
            forYou = recs.map(\.result)
        } else {
            forYou = []
        }
        isLoading = false
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
