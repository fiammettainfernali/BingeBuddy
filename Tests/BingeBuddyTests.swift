import XCTest

/// Unit tests for the pure logic that the blind-build workflow can't catch by tapping around:
/// recommendation ranking, taste-seed weighting, and season math.
final class BingeBuddyTests: XCTestCase {

    // MARK: - Helpers

    private func media(_ id: String, title: String = "Title") -> MediaSearchResult {
        MediaSearchResult(source: "tmdb", sourceId: id, title: title,
                          mediaType: .tv, year: "2024", posterURL: nil, overview: "")
    }

    private func item(state: WatchState, rating: Int = 0) -> LibraryItem {
        var item = LibraryItem()
        item.stateRaw = state.rawValue
        item.rating = rating
        return item
    }

    // MARK: - RecommendationEngine.rank

    func testRankOrdersByHowManySeedsSurfacedACandidate() {
        let shared = media("1", title: "Shared Pick")
        let solo = media("2", title: "Solo Pick")
        let ranked = RecommendationEngine.rank([
            ("Seed A", [shared, solo]),
            ("Seed B", [shared])
        ], exclude: [], limit: 10)

        XCTAssertEqual(ranked.first?.result.id, "tmdb-1")
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked.first?.reason, "Because you liked Seed A")
    }

    func testRankExcludesTrackedAndHiddenTitles() {
        let tracked = media("1")
        let fresh = media("2")
        let ranked = RecommendationEngine.rank([
            ("Seed", [tracked, fresh])
        ], exclude: ["tmdb-1"], limit: 10)

        XCTAssertEqual(ranked.map(\.result.id), ["tmdb-2"])
    }

    func testRankRespectsLimit() {
        let recs = (1...20).map { media("\($0)") }
        let ranked = RecommendationEngine.rank([("Seed", recs)], exclude: [], limit: 5)
        XCTAssertEqual(ranked.count, 5)
    }

    func testRankWithNoInputIsEmpty() {
        XCTAssertTrue(RecommendationEngine.rank([], exclude: [], limit: 10).isEmpty)
    }

    func testRankDeduplicatesAcrossSeeds() {
        let same = media("1")
        let ranked = RecommendationEngine.rank([
            ("Seed A", [same]),
            ("Seed B", [same]),
            ("Seed C", [same])
        ], exclude: [], limit: 10)
        XCTAssertEqual(ranked.count, 1)
    }

    // MARK: - Seed weighting

    func testFinishedAndRatedBeatsWatchingBeatsWant() {
        let finished = LibraryStore.seedWeight(item(state: .finished, rating: 5))
        let watching = LibraryStore.seedWeight(item(state: .watching))
        let want = LibraryStore.seedWeight(item(state: .wantToWatch))
        XCTAssertGreaterThan(finished, watching)
        XCTAssertGreaterThan(watching, want)
    }

    func testDroppedIsNeverAPositiveSignal() {
        XCTAssertLessThan(LibraryStore.seedWeight(item(state: .dropped, rating: 5)), 0)
    }

    // MARK: - Anime season math

    private func date(month: Int, day: Int = 15, year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testCurrentSeasonBoundaries() {
        XCTAssertEqual(KitsuProvider.currentSeason(now: date(month: 1)).season, "winter")
        XCTAssertEqual(KitsuProvider.currentSeason(now: date(month: 3)).season, "winter")
        XCTAssertEqual(KitsuProvider.currentSeason(now: date(month: 4)).season, "spring")
        XCTAssertEqual(KitsuProvider.currentSeason(now: date(month: 7)).season, "summer")
        XCTAssertEqual(KitsuProvider.currentSeason(now: date(month: 10)).season, "fall")
        XCTAssertEqual(KitsuProvider.currentSeason(now: date(month: 12)).season, "fall")
        XCTAssertEqual(KitsuProvider.currentSeason(now: date(month: 12)).year, 2026)
    }

    // MARK: - Episode checklist watermark math

    func testEpisodeIsWatchedAcrossSeasons() {
        // Watermark at S2 E3:
        XCTAssertTrue(EpisodeProgress.isWatched(season: 1, episode: 10, currentSeason: 2, currentEpisode: 3))
        XCTAssertTrue(EpisodeProgress.isWatched(season: 2, episode: 3, currentSeason: 2, currentEpisode: 3))
        XCTAssertFalse(EpisodeProgress.isWatched(season: 2, episode: 4, currentSeason: 2, currentEpisode: 3))
        XCTAssertFalse(EpisodeProgress.isWatched(season: 3, episode: 1, currentSeason: 2, currentEpisode: 3))
    }

    func testTapMovesWatermarkToTappedEpisode() {
        let forward = EpisodeProgress.watermarkAfterTap(season: 2, episode: 5,
                                                        currentSeason: 2, currentEpisode: 3, seasons: [])
        XCTAssertEqual(forward.season, 2)
        XCTAssertEqual(forward.episode, 5)

        let backward = EpisodeProgress.watermarkAfterTap(season: 1, episode: 2,
                                                         currentSeason: 2, currentEpisode: 3, seasons: [])
        XCTAssertEqual(backward.season, 1)
        XCTAssertEqual(backward.episode, 2)
    }

    func testTapWatermarkRewindsOneEpisode() {
        let result = EpisodeProgress.watermarkAfterTap(season: 2, episode: 3,
                                                       currentSeason: 2, currentEpisode: 3, seasons: [])
        XCTAssertEqual(result.season, 2)
        XCTAssertEqual(result.episode, 2)
    }

    func testTapSeasonPremiereRewindsIntoPreviousSeason() {
        let seasons = [SeasonInfo(number: 1, name: "Season 1", episodeCount: 8),
                       SeasonInfo(number: 2, name: "Season 2", episodeCount: 10)]
        let result = EpisodeProgress.watermarkAfterTap(season: 2, episode: 1,
                                                       currentSeason: 2, currentEpisode: 1, seasons: seasons)
        XCTAssertEqual(result.season, 1)
        XCTAssertEqual(result.episode, 8)
    }

    func testTapVeryFirstEpisodeClearsProgress() {
        let result = EpisodeProgress.watermarkAfterTap(season: 1, episode: 1,
                                                       currentSeason: 1, currentEpisode: 1, seasons: [])
        XCTAssertEqual(result.season, 1)
        XCTAssertEqual(result.episode, 0)
    }

    // MARK: - Episode paging

    func testPagedSlicesFallbackEpisodeLists() {
        let eps = (1...250).map { EpisodeInfo(number: $0, title: nil, airDate: nil) }
        let pageOne = MetadataService.paged(eps, page: 1)
        XCTAssertEqual(pageOne.lastPage, 3)
        XCTAssertEqual(pageOne.episodes.count, 100)
        XCTAssertEqual(pageOne.episodes.first?.number, 1)

        let pageThree = MetadataService.paged(eps, page: 3)
        XCTAssertEqual(pageThree.episodes.count, 50)
        XCTAssertEqual(pageThree.episodes.first?.number, 201)

        // Out-of-range pages clamp instead of crashing.
        XCTAssertEqual(MetadataService.paged(eps, page: 99).episodes.first?.number, 201)
        XCTAssertEqual(MetadataService.paged([], page: 1).lastPage, 1)
    }

    // MARK: - State round-trips

    func testWatchStateRawValuesAreStable() {
        // These raw values live in Firestore documents — changing them breaks existing data.
        XCTAssertEqual(WatchState.wantToWatch.rawValue, "wantToWatch")
        XCTAssertEqual(WatchState.watching.rawValue, "watching")
        XCTAssertEqual(WatchState.finished.rawValue, "finished")
        XCTAssertEqual(WatchState.dropped.rawValue, "dropped")
        XCTAssertEqual(MediaType.anime.rawValue, "anime")
    }
}
