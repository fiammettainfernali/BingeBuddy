import SwiftUI

/// Shows the shows you're behind on — what to catch up on.
/// Pushed within the Library navigation stack (reuses its MediaSearchResult destination).
struct CatchUpView: View {
    @EnvironmentObject private var store: LibraryStore

    private var behind: [LibraryItem] {
        store.myPersonal
            .filter { $0.state == .watching && $0.totalEpisodes > 0 && $0.currentEpisode < $0.totalEpisodes }
            .sorted { ($0.totalEpisodes - $0.currentEpisode) > ($1.totalEpisodes - $1.currentEpisode) }
    }

    var body: some View {
        Group {
            if behind.isEmpty {
                ContentUnavailableView(
                    "All caught up!",
                    systemImage: "checkmark.circle.fill",
                    description: Text("You're up to date on everything you're watching."))
            } else {
                List(behind) { item in
                    NavigationLink(value: item.asSearchResult) {
                        HStack(spacing: 12) {
                            PosterImage(url: item.posterURL)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline).lineLimit(2)
                                Text("On S\(item.currentSeason) · E\(item.currentEpisode) of \(item.totalEpisodes)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(item.totalEpisodes - item.currentEpisode) to go")
                                    .font(.caption2.bold()).foregroundStyle(.orange)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Catch Up")
        .navigationBarTitleDisplayMode(.inline)
    }
}
