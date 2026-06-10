import Foundation
import SwiftUI

struct Recommendation: Identifiable {
    let result: MediaSearchResult
    let reason: String
    var id: String { result.id }
}

/// Content-based recommendations: pull "similar" titles from the seeds the user liked,
/// rank by how many seeds surfaced each candidate, and drop anything already tracked.
struct RecommendationEngine {
    private let service = MetadataService()

    func recommendations(seeds: [LibraryItem], exclude: Set<String>,
                         maxSeeds: Int = 14, limit: Int = 60) async -> [Recommendation] {
        let chosen = Array(seeds.prefix(maxSeeds))
        guard !chosen.isEmpty else { return [] }
        let service = self.service

        var counts: [String: Int] = [:]
        var data: [String: MediaSearchResult] = [:]
        var reasons: [String: String] = [:]

        await withTaskGroup(of: (String, [MediaSearchResult]).self) { group in
            for seed in chosen {
                let result = seed.asSearchResult
                let seedTitle = seed.title
                group.addTask {
                    let recs = (try? await service.recommendations(for: result)) ?? []
                    return (seedTitle, recs)
                }
            }
            for await (seedTitle, recs) in group {
                for rec in recs where !exclude.contains(rec.id) {
                    counts[rec.id, default: 0] += 1
                    if data[rec.id] == nil {
                        data[rec.id] = rec
                        reasons[rec.id] = "Because you liked \(seedTitle)"
                    }
                }
            }
        }

        let ranked = counts.keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        return ranked.prefix(limit).compactMap { key in
            guard let result = data[key] else { return nil }
            return Recommendation(result: result, reason: reasons[key] ?? "Recommended for you")
        }
    }
}

/// Reusable recommendations list. Lives inside a NavigationStack that handles
/// `MediaSearchResult` destinations.
struct RecommendationsView: View {
    let title: String
    let seeds: [LibraryItem]
    let exclude: Set<String>

    @EnvironmentObject private var store: LibraryStore
    @State private var recommendations: [Recommendation] = []
    @State private var isLoading = true
    @State private var loadedKey: String?

    private let engine = RecommendationEngine()
    private var seedKey: String {
        title + seeds.map(\.mediaKey).sorted().joined(separator: ",") + "|\(exclude.count)"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Finding picks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if recommendations.isEmpty {
                ContentUnavailableView(
                    "No picks yet",
                    systemImage: "sparkles",
                    description: Text("Finish or rate a few titles and we'll suggest more."))
            } else {
                List {
                    Section(title) {
                        ForEach(recommendations) { rec in
                            NavigationLink(value: rec.result) { RecommendationRow(rec: rec) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { hide(rec) } label: {
                                        Label("Not interested", systemImage: "hand.thumbsdown")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            guard loadedKey != seedKey else { return }
            await load()
            loadedKey = seedKey
        }
        .onChange(of: seedKey) { _, newKey in
            Task {
                await load()
                loadedKey = newKey
            }
        }
    }

    private func hide(_ rec: Recommendation) {
        recommendations.removeAll { $0.result.id == rec.result.id }
        store.hide(mediaKey: rec.result.id)
    }

    private func load() async {
        if recommendations.isEmpty { isLoading = true }
        let recs = await engine.recommendations(seeds: seeds, exclude: exclude)
        // Keep existing picks if a refresh returned empty (e.g. a rate-limit hiccup).
        if !recs.isEmpty || recommendations.isEmpty {
            recommendations = recs
        }
        isLoading = false
    }
}

private struct RecommendationRow: View {
    let rec: Recommendation

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: rec.result.posterURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.result.title).font(.headline).lineLimit(2)
                Text(rec.result.mediaType.label + (rec.result.year.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text(rec.reason).font(.caption2).italic().foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
