import SwiftUI

struct TogetherView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var session: Session
    @State private var segment: Segment = .shared
    @State private var pick: LibraryItem?

    /// Candidates for date-night: shared want/watching + titles you both want.
    private var dateNightPool: [LibraryItem] {
        var seen = Set<String>()
        var pool: [LibraryItem] = []
        let candidates = store.matches
            + store.togetherItems.filter { $0.state == .wantToWatch || $0.state == .watching }
        for item in candidates where seen.insert(item.mediaKey).inserted {
            pool.append(item)
        }
        return pool
    }

    private func spin() {
        pick = dateNightPool.randomElement()
    }

    enum Segment: String, CaseIterable, Identifiable {
        case shared = "Shared"
        case matches = "Matches"
        case partner = "Partner"
        case forUs = "For Us"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.household == nil {
                    ContentUnavailableView(
                        "Set up your household",
                        systemImage: "person.2",
                        description: Text("Create or join a household in the Profile tab to see your shared picks."))
                } else if session.partnerName == nil {
                    ContentUnavailableView(
                        "Waiting for your partner",
                        systemImage: "hourglass",
                        description: Text("Once your partner joins your household, their list and your matches show up here."))
                } else {
                    VStack(spacing: 0) {
                        Picker("Segment", selection: $segment) {
                            ForEach(Segment.allCases) { Text(label(for: $0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding([.horizontal, .top])

                        switch segment {
                        case .shared: sharedList
                        case .matches: matchesList
                        case .partner: partnerList
                        case .forUs:
                            RecommendationsView(title: "For Us",
                                                seeds: store.ourSeeds,
                                                exclude: store.householdExclusion)
                        }
                    }
                }
            }
            .navigationTitle("Together")
            .navigationDestination(for: MediaSearchResult.self) { DetailView(result: $0) }
            .toolbar {
                if session.partnerName != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { spin() } label: {
                            Image(systemName: "shuffle")
                        }
                        .disabled(dateNightPool.isEmpty)
                    }
                }
            }
            .sheet(item: $pick) { picked in
                DateNightSheet(item: picked) { pick = dateNightPool.randomElement() }
            }
        }
    }

    private func label(for segment: Segment) -> String {
        switch segment {
        case .shared: return "Shared"
        case .matches: return "Matches"
        case .partner: return session.partnerName ?? "Partner"
        case .forUs: return "For Us"
        }
    }

    @ViewBuilder private var sharedList: some View {
        let all = store.togetherItems
        let active = all
            .filter { $0.state == .wantToWatch || $0.state == .watching }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        let done = all
            .filter { $0.state == .finished || $0.state == .dropped }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }

        if all.isEmpty {
            ContentUnavailableView(
                "No shared titles yet",
                systemImage: "heart",
                description: Text("Open any title and tap “Add to Watch Together” to start a shared list you both control."))
        } else {
            List {
                if !active.isEmpty {
                    Section("Up next") {
                        ForEach(active) { item in
                            NavigationLink(value: item.asSearchResult) {
                                ItemRow(item: item, subtitle: statusLine(item))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if item.mediaType != .movie {
                                    Button {
                                        let cap = item.totalEpisodes > 0 ? item.totalEpisodes : Int.max
                                        let next = min(item.currentEpisode + 1, cap)
                                        store.setProgress(item, season: item.currentSeason, episode: next)
                                    } label: {
                                        Label("+1 Ep", systemImage: "plus")
                                    }
                                    .tint(.indigo)
                                }
                            }
                        }
                    }
                }
                if !done.isEmpty {
                    Section("Finished & dropped") {
                        ForEach(done) { item in
                            NavigationLink(value: item.asSearchResult) {
                                ItemRow(item: item, subtitle: statusLine(item))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder private var matchesList: some View {
        let matches = store.matches
        if matches.isEmpty {
            ContentUnavailableView(
                "No matches yet",
                systemImage: "heart.slash",
                description: Text("When a title is on both your Want lists, it shows up here as a pick for movie night."))
        } else {
            List(matches) { item in
                NavigationLink(value: item.asSearchResult) {
                    ItemRow(item: item, subtitle: "On both your Want lists")
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder private var partnerList: some View {
        let items = store.partnerPersonal.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        if items.isEmpty {
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "rectangle.stack",
                description: Text("\(session.partnerName ?? "Your partner")'s titles will appear here."))
        } else {
            List(items) { item in
                NavigationLink(value: item.asSearchResult) {
                    ItemRow(item: item, subtitle: statusLine(item))
                }
            }
            .listStyle(.plain)
        }
    }

    private func statusLine(_ item: LibraryItem) -> String {
        var line = item.state.label
        if item.state == .watching && item.mediaType != .movie {
            line += item.totalSeasons > 1
                ? " · S\(item.currentSeason) E\(item.currentEpisode)"
                : " · Ep \(item.currentEpisode)"
        }
        if item.rating > 0 {
            line += " · \(item.rating)★"
        }
        return line
    }
}

private struct ItemRow: View {
    let item: LibraryItem
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: item.posterURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(2)
                Text(item.mediaType.label + (item.year.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct DateNightSheet: View {
    let item: LibraryItem
    let onSpinAgain: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("Tonight, watch…")
                .font(.headline)
                .foregroundStyle(.secondary)

            PosterImage(url: item.posterURL, width: 150, height: 225)

            Text(item.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(item.mediaType.label + (item.year.map { " · \($0)" } ?? ""))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button { onSpinAgain() } label: {
                    Label("Spin again", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { dismiss() } label: {
                    Text("Let's watch!").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(28)
        .presentationDetents([.medium])
    }
}
