import SwiftUI

/// Upcoming air dates for everything you're watching (yours + shared), grouped by day.
struct UpcomingCalendarView: View {
    @EnvironmentObject private var store: LibraryStore

    private struct Entry: Identifiable {
        let show: LibraryItem
        let airing: EpisodeAiring
        var id: String { show.mediaKey + airing.label + airing.date.description }
    }

    @State private var entries: [Entry] = []
    @State private var isLoading = true
    @State private var loadedKey: String?

    private let service = MetadataService()
    private let horizon: TimeInterval = 56 * 24 * 3600   // 8 weeks out

    /// Everything airing-relevant: personal + shared, watching, series only.
    private var watchingShows: [LibraryItem] {
        var seen = Set<String>()
        return (store.myPersonal + store.togetherItems)
            .filter { $0.state == .watching && $0.mediaType != .movie }
            .filter { seen.insert($0.mediaKey).inserted }
    }

    private var watchingKey: String {
        watchingShows.map(\.mediaKey).sorted().joined(separator: ",")
    }

    private var groupedByDay: [(day: Date, entries: [Entry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.airing.date) }
        return groups.keys.sorted().map { day in
            (day, groups[day]!.sorted { $0.show.title < $1.show.title })
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                ProgressView("Checking air dates…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing scheduled",
                    systemImage: "calendar",
                    description: Text("No upcoming episodes found for the shows you're watching."))
            } else {
                List {
                    ForEach(groupedByDay, id: \.day) { group in
                        Section(Self.dayFormatter.string(from: group.day)) {
                            ForEach(group.entries) { entry in
                                NavigationLink(value: entry.show.asSearchResult) {
                                    HStack(spacing: 12) {
                                        PosterImage(url: entry.show.posterURL, width: 40, height: 60)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.show.title).font(.headline).lineLimit(1)
                                            Text(entry.airing.label)
                                                .font(.caption).foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Upcoming")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard loadedKey != watchingKey else { return }
            await load()
            loadedKey = watchingKey
        }
        .refreshable { await load() }
    }

    private func load() async {
        if entries.isEmpty { isLoading = true }
        let shows = watchingShows
        let cutoff = Date().addingTimeInterval(horizon)
        let service = self.service

        var collected: [Entry] = []
        await withTaskGroup(of: (LibraryItem, [EpisodeAiring]).self) { group in
            for show in shows {
                let result = show.asSearchResult
                group.addTask { (show, await service.upcomingAirings(for: result)) }
            }
            for await (show, airings) in group {
                for airing in airings where airing.date <= cutoff {
                    collected.append(Entry(show: show, airing: airing))
                }
            }
        }
        entries = collected.sorted { $0.airing.date < $1.airing.date }
        isLoading = false
    }
}
