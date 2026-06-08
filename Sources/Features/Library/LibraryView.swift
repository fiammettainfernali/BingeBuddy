import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \WatchItem.updatedAt, order: .reverse) private var items: [WatchItem]
    @State private var selectedState: WatchState = .watching

    private var filtered: [WatchItem] {
        items.filter { $0.state == selectedState }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("State", selection: $selectedState) {
                    ForEach(WatchState.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if filtered.isEmpty {
                    ContentUnavailableView("Nothing here yet",
                                           systemImage: selectedState.systemImage,
                                           description: Text("Add titles from the Search tab."))
                } else {
                    List {
                        ForEach(filtered) { item in
                            NavigationLink(value: item) { LibraryRow(item: item) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: WatchItem.self) { item in
                DetailView(result: item.asSearchResult)
            }
        }
    }
}

private struct LibraryRow: View {
    let item: WatchItem

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: item.posterURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(2)
                Text(item.mediaType.label + (item.year.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                if item.rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<item.rating, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                }
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
