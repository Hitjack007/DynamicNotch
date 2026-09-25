import Testing
@testable import DynamicNotch

// MARK: - Helpers

private let defaultOrder: [AmbientActivity] = [.music, .download, .face, .aiUsage]

private func availability(
    musicPlaying: Bool = false,
    musicEnabled: Bool = true,
    hasActiveDownloads: Bool = false,
    downloadEnabled: Bool = true,
    faceEnabled: Bool = false,
    aiUsageAvailable: Bool = false,
    aiUsagePromoted: Bool = false
) -> AmbientActivityResolver.Availability {
    .init(
        musicPlaying: musicPlaying,
        musicEnabled: musicEnabled,
        hasActiveDownloads: hasActiveDownloads,
        downloadEnabled: downloadEnabled,
        faceEnabled: faceEnabled,
        aiUsageAvailable: aiUsageAvailable,
        aiUsagePromoted: aiUsagePromoted
    )
}

// MARK: - Tests

@Suite("Ambient activity resolution")
struct AmbientActivityResolverTests {

    @Test("Default order reproduces today's behavior: music wins while playing")
    func defaultOrderMusicWins() {
        let winner = AmbientActivityResolver.resolve(
            order: defaultOrder,
            availability: availability(musicPlaying: true, hasActiveDownloads: true, faceEnabled: true, aiUsageAvailable: true)
        )
        #expect(winner == .music)
    }

    @Test("Default order falls through to the next active entry when music isn't playing")
    func defaultOrderFallsThrough() {
        let winner = AmbientActivityResolver.resolve(
            order: defaultOrder,
            availability: availability(hasActiveDownloads: true, faceEnabled: true, aiUsageAvailable: true)
        )
        #expect(winner == .download, "Download should win once music stops, even though Face and AI Usage are also available")
    }

    @Test("Reordering actually flips the winner")
    func reorderingFlipsWinner() {
        let order: [AmbientActivity] = [.aiUsage, .music, .download, .face]
        let winner = AmbientActivityResolver.resolve(
            order: order,
            availability: availability(musicPlaying: true, aiUsageAvailable: true)
        )
        #expect(winner == .aiUsage, "AI Usage ranked above Music should win even while music plays")
    }

    @Test("Promotion moves AI Usage to the front regardless of its stored position")
    func promotionOverridesPosition() {
        let winner = AmbientActivityResolver.resolve(
            order: defaultOrder,
            availability: availability(musicPlaying: true, aiUsageAvailable: true, aiUsagePromoted: true)
        )
        #expect(winner == .aiUsage, "Promoted AI Usage should beat Music even though Music is ranked first")
    }

    @Test("Promotion never overrides AI Usage being unavailable")
    func promotionDoesNotBypassAvailability() {
        let winner = AmbientActivityResolver.resolve(
            order: defaultOrder,
            availability: availability(musicPlaying: true, aiUsageAvailable: false, aiUsagePromoted: true)
        )
        #expect(winner == .music, "A promotion flag with no live reading behind it must not force AI Usage to show")
    }

    @Test("Unavailable activities are skipped, not treated as a block")
    func unavailableActivitiesAreSkipped() {
        let order: [AmbientActivity] = [.music, .download, .face, .aiUsage]
        let winner = AmbientActivityResolver.resolve(
            order: order,
            availability: availability(musicEnabled: false, aiUsageAvailable: true)
        )
        #expect(winner == .aiUsage, "Music being ranked first but disabled should not block AI Usage from winning")
    }

    @Test("Nothing active resolves to nil")
    func nothingActiveResolvesToNil() {
        let winner = AmbientActivityResolver.resolve(order: defaultOrder, availability: availability())
        #expect(winner == nil)
    }

    @Test("Normalize drops unknown entries and appends missing cases")
    func normalizeRepairsStoredOrder() {
        // Simulates a corrupted or stale stored order missing an entry, with
        // duplicates collapsed to their first occurrence.
        let stale: [AmbientActivity] = [.download, .download, .music]
        let repaired = AmbientActivityResolver.normalize(stale)
        #expect(repaired == [.download, .music, .face, .aiUsage])
    }

    @Test("Normalize recovers an empty stored order to the full case list")
    func normalizeRecoversEmptyOrder() {
        let repaired = AmbientActivityResolver.normalize([])
        #expect(repaired == AmbientActivity.allCases)
    }
}
