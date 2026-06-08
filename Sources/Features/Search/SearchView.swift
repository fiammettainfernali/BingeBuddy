import SwiftUI
import SwiftData

struct SearchView: View {
    @Query private var items: [WatchItem]
    @State private var query = ""
    @State private var scope: SearchScope = .moviesTV
    @State private var results: [MediaSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = MetadataService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Scope", selection: $scope) {
                    ForEach(SearchScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                .onChange(of: scope) { _, _ in
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Task { await runSearch() }
                    }
                }

                content
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Show, movie, or anime")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .navigationDestination(for: MediaSearchResult.self) { DetailView(result: $0) }
        }
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            Spacer()
            ProgressView("Searching…")
            Spacer()
        } else if let errorMessage {
            ContentUnavailableView("Something went wrong",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(errorMessage))
        } else if results.isEmpty {
            ContentUnavailableView("Find something to watch",
                                   systemImage: "magnifyingglass",
                                   description: Text("Search movies, TV, and anime."))
        } else {
            List(results) { result in
                NavigationLink(value: result) {
                    SearchRow(result: result, inLibrary: items.contains { $0.id == result.id })
                }
            }
            .listStyle(.plain)
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            results = try await service.search(trimmed, scope: scope)
        } catch {
            results = []
            errorMessage = "Couldn't load results. Check your connection and try again."
        }
        isLoading = false
    }
}

private struct SearchRow: View {
    let result: MediaSearchResult
    let inLibrary: Bool

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: result.posterURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title).font(.headline).lineLimit(2)
                Text(result.mediaType.label + (result.year.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                if inLibrary {
                    Label("In your library", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
