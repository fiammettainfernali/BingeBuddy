import SwiftUI

/// Shows the shows you're behind on — what to catch up on.
/// Pushed within the Library navigation stack (reuses its MediaSearchResult destination).
struct CatchUpView: View {
    @EnvironmentObject private var store: LibraryStore

    /// Finished-run shows with a known total you haven't reached.
    private var behindCounted: [LibraryItem] {
        store.myPersonal
            .filter { $0.state == .watching && $0.totalEpisodes > 0 && $0.currentEpisode < $0.totalEpisodes }
            .sorted { ($0.totalEpisodes - $0.currentEpisode) > ($1.totalEpisodes - $1.currentEpisode) }
    }

    /// Airing shows where episodes have aired past your progress (needs the last-aired
    /// signal, refreshed whenever you open a title's detail).
    private var behindAiring: [LibraryItem] {
        store.myPersonal.filter { item in
            guard item.state == .watching, item.totalEpisodes == 0,
                  let season = item.lastAiredSeason, let episode = item.lastAiredEpisode,
                  episode > 0 else { return false }
            return (item.currentSeason, item.currentEpisode) < (season, episode)
        }
    }

    var body: some View {
        Group {
            if behindCounted.isEmpty && behindAiring.isEmpty {
                ContentUnavailableView(
                    "All caught up!",
                    systemImage: "checkmark.circle.fill",
                    description: Text("You're up to date on everything you're watching."))
            } else {
                List {
                    if !behindAiring.isEmpty {
                        Section("New episodes out") {
                            ForEach(behindAiring) { item in
                                row(item, note: "New episodes since S\(item.currentSeason) E\(item.currentEpisode)")
                            }
                        }
                    }
                    if !behindCounted.isEmpty {
                        Section("Behind") {
                            ForEach(behindCounted) { item in
                                row(item, note: "\(item.totalEpisodes - item.currentEpisode) to go")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Catch Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ item: LibraryItem, note: String) -> some View {
        NavigationLink(value: item.asSearchResult) {
            HStack(spacing: 12) {
                PosterImage(url: item.posterURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline).lineLimit(2)
                    Text("On S\(item.currentSeason) · E\(item.currentEpisode)"
                         + (item.totalEpisodes > 0 ? " of \(item.totalEpisodes)" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(note)
                        .font(.caption2.bold()).foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }
}
