import Testing
@testable import DynamicNotch

// MARK: - Helpers

private func highlight(_ id: String) -> WhatsNewHighlight {
    WhatsNewHighlight(id: id, icon: "star", title: "Title \(id)", body: "Body \(id)")
}

private func release(_ version: String, _ highlightIDs: String...) -> WhatsNewRelease {
    WhatsNewRelease(version: version, highlights: highlightIDs.map(highlight))
}

// MARK: - Tests

@Suite("WhatsNewCatalog page selection")
struct WhatsNewCatalogTests {

    @Test("A single version bump returns that release's pages")
    func versionBumpReturnsNewRelease() {
        let releases = [release("27.2", "a"), release("27.3", "b")]
        let pages = WhatsNewCatalog.pages(lastSeenVersion: "27.2", currentVersion: "27.3", releases: releases)
        #expect(pages.map(\.highlight.id) == ["b"])
    }

    @Test("Equal lastSeen and current versions return no pages")
    func equalVersionsReturnEmpty() {
        let releases = [release("27.2", "a"), release("27.3", "b")]
        let pages = WhatsNewCatalog.pages(lastSeenVersion: "27.3", currentVersion: "27.3", releases: releases)
        #expect(pages.isEmpty)
    }

    @Test("Empty lastSeenVersion returns only the current version's pages, not the whole history")
    func emptyLastSeenReturnsOnlyCurrent() {
        let releases = [release("27.1", "a"), release("27.2", "b"), release("27.3", "c")]
        let pages = WhatsNewCatalog.pages(lastSeenVersion: "", currentVersion: "27.3", releases: releases)
        #expect(pages.map(\.highlight.id) == ["c"])
    }

    @Test("A catalog entry newer than currentVersion is excluded")
    func futureEntryIsExcluded() {
        let releases = [release("27.2", "a"), release("27.3", "b"), release("27.4", "c")]
        let pages = WhatsNewCatalog.pages(lastSeenVersion: "27.1", currentVersion: "27.3", releases: releases)
        #expect(pages.map(\.highlight.id) == ["a", "b"])
    }

    @Test("Pages across two skipped releases are returned in ascending version order")
    func orderingIsAscendingAcrossSkippedReleases() {
        let releases = [release("27.1", "a"), release("27.2", "b"), release("27.3", "c")]
        let pages = WhatsNewCatalog.pages(lastSeenVersion: "27.0", currentVersion: "27.3", releases: releases)
        #expect(pages.map(\.highlight.id) == ["a", "b", "c"])
    }

    @Test(".numeric comparison treats version segments numerically, not lexically")
    func numericComparisonEdgeCases() {
        #expect(WhatsNewCatalog.isVersion("27.10", newerThan: "27.9"))
        #expect(!WhatsNewCatalog.isVersion("27.9", newerThan: "27.10"))
        #expect(WhatsNewCatalog.isVersion("27.2.1", newerThan: "27.2"))
        #expect(!WhatsNewCatalog.isVersion("27.2", newerThan: "27.2.1"))
    }
}
