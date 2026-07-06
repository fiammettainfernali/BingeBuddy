import SwiftUI

enum LibrarySort: String, CaseIterable, Identifiable {
    case updated = "Recently Updated"
    case title = "Title"
    case rating = "Rating"
    case year = "Year"

    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var session: Session

    @State private var selectedState: WatchState = .watching
    @State private var typeFilter: MediaType?
    @State private var genreFilter: String?
    @State private var sort: LibrarySort = .updated
    @State private var searchText = ""

    private var personalItems: [LibraryItem] {
        store.myPersonal
    }

    private var availableGenres: [String] {
        Set(personalItems.flatMap { $0.genres }).sorted()
    }

    private var filtersActive: Bool {
        typeFilter != nil || genreFilter != nil || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var visible: [LibraryItem] {
        var result = personalItems.filter { $0.state == selectedState }

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
            result.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
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
            Group {
                if session.household == nil {
                    ContentUnavailableView(
                        "Set up your household",
                        systemImage: "person.2",
                        description: Text("Go to the Profile tab to create or join a household. Your library syncs once you're set up."))
                } else {
                    VStack(spacing: 0) {
                        Picker("State", selection: $selectedState) {
                            ForEach(WatchState.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding([.horizontal, .top])

                        filterBar

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
                                    NavigationLink(value: item.asSearchResult) { LibraryRow(item: item) }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            if item.totalEpisodes > 0 {
                                                Button {
                                                    let next = min(item.currentEpisode + 1, item.totalEpisodes)
                                                    store.setProgress(item, season: item.currentSeason, episode: next)
                                                } label: {
                                                    Label("+1 Ep", systemImage: "plus")
                                                }
                                                .tint(.indigo)
                                            }
                                        }
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Filter your library")
            .navigationDestination(for: MediaSearchResult.self) { DetailView(result: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { CatchUpView() } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Type", selection: $typeFilter) {
                        Text("All Types").tag(MediaType?.none)
                        ForEach(MediaType.allCases, id: \.self) { type in
                            Text(type.label).tag(MediaType?.some(type))
                        }
                    }
                } label: {
                    FilterChip(title: "Type", value: typeFilter?.label ?? "All", active: typeFilter != nil)
                }

                if !availableGenres.isEmpty {
                    Menu {
                        Picker("Genre", selection: $genreFilter) {
                            Text("All Genres").tag(String?.none)
                            ForEach(availableGenres, id: \.self) { genre in
                                Text(genre).tag(String?.some(genre))
                            }
                        }
                    } label: {
                        FilterChip(title: "Genre", value: genreFilter ?? "All", active: genreFilter != nil)
                    }
                }

                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    FilterChip(title: "Sort", value: sort.rawValue, active: false)
                }

                if typeFilter != nil || genreFilter != nil {
                    Button {
                        typeFilter = nil
                        genreFilter = nil
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }
                    .tint(.red)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

private struct FilterChip: View {
    let title: String
    let value: String
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("\(title):").foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(active ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
        )
        .foregroundStyle(active ? Color.accentColor : Color.primary)
    }
}

private struct LibraryRow: View {
    let item: LibraryItem

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
