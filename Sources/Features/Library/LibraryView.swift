import SwiftUI
import SwiftData

enum LibrarySort: String, CaseIterable, Identifiable {
    case updated = "Recently Updated"
    case title = "Title"
    case rating = "Rating"
    case year = "Year"

    var id: String { rawValue }
}

struct LibraryView: View {
    @Query(sort: \WatchItem.updatedAt, order: .reverse) private var items: [WatchItem]

    @State private var selectedState: WatchState = .watching
    @State private var typeFilter: MediaType?
    @State private var genreFilter: String?
    @State private var sort: LibrarySort = .updated
    @State private var searchText = ""

    private var availableGenres: [String] {
        Set(items.flatMap { $0.genres }).sorted()
    }

    private var filtersActive: Bool {
        typeFilter != nil || genreFilter != nil || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var visible: [WatchItem] {
        var result = items.filter { $0.state == selectedState }

        if let typeFilter {
            result = result.filter { $0.mediaType == typeFilter }
        }
        if let genreFilter {
            result = result.filter { $0.genres.contains(genreFilter) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }

        switch sort {
        case .updated:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .title:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .rating:
            result.sort { $0.rating > $1.rating }
        case .year:
            result.sort { ($0.year ?? "") > ($1.year ?? "") }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("State", selection: $selectedState) {
                    ForEach(WatchState.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if visible.isEmpty {
                    ContentUnavailableView(
                        filtersActive ? "No matches" : "Nothing here yet",
                        systemImage: filtersActive ? "line.3.horizontal.decrease.circle" : selectedState.systemImage,
                        description: Text(filtersActive
                                          ? "Try clearing filters or changing the status tab."
                                          : "Add titles from the Search tab."))
                } else {
                    List {
                        ForEach(visible) { item in
                            NavigationLink(value: item) { LibraryRow(item: item) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Filter your library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .navigationDestination(for: WatchItem.self) { item in
                DetailView(result: item.asSearchResult)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $typeFilter) {
                Text("All Types").tag(MediaType?.none)
                ForEach(MediaType.allCases, id: \.self) { type in
                    Text(type.label).tag(MediaType?.some(type))
                }
            }

            if !availableGenres.isEmpty {
                Picker("Genre", selection: $genreFilter) {
                    Text("All Genres").tag(String?.none)
                    ForEach(availableGenres, id: \.self) { genre in
                        Text(genre).tag(String?.some(genre))
                    }
                }
            }

            Picker("Sort by", selection: $sort) {
                ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
            }

            if typeFilter != nil || genreFilter != nil {
                Divider()
                Button(role: .destructive) {
                    typeFilter = nil
                    genreFilter = nil
                } label: {
                    Label("Clear filters", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Filter",
                  systemImage: (typeFilter != nil || genreFilter != nil)
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
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
