import XCTest
@testable import muxa

/// 스크롤백 파일 GC 판정(순수) + 스냅샷 참조 경로 수집 검증.
final class ScrollbackGCTests: XCTestCase {
    private let dir = "/tmp/scrollback"
    private func file(_ key: String, ageSeconds: TimeInterval, now: Date) -> ScrollbackStore.ScrollbackFile {
        ScrollbackStore.ScrollbackFile(path: "\(dir)/\(key).txt", tabIdKey: key,
                                       modified: now.addingTimeInterval(-ageSeconds))
    }

    // MARK: orphans — 삭제 대상 판정

    func testLiveTabFileIsKept() {
        let now = Date()
        let f = file("A", ageSeconds: 10_000, now: now) // 오래됐지만 살아있는 탭
        let result = ScrollbackStore.orphans(in: [f], liveTabIds: ["A"], referencedPaths: [],
                                             now: now, graceInterval: 3600)
        XCTAssertTrue(result.isEmpty)
    }

    func testReferencedFileIsKept() {
        let now = Date()
        let f = file("B", ageSeconds: 10_000, now: now) // 스냅샷이 참조하는 경로(미개방 lazy 프로젝트)
        let result = ScrollbackStore.orphans(in: [f], liveTabIds: [], referencedPaths: [f.path],
                                             now: now, graceInterval: 3600)
        XCTAssertTrue(result.isEmpty)
    }

    func testRecentUnreferencedFileIsKept() {
        let now = Date()
        let f = file("C", ageSeconds: 60, now: now) // 유예(3600초) 안쪽 — 방금 쓰인 파일 방어
        let result = ScrollbackStore.orphans(in: [f], liveTabIds: [], referencedPaths: [],
                                             now: now, graceInterval: 3600)
        XCTAssertTrue(result.isEmpty)
    }

    func testOldUnreferencedFileIsOrphan() {
        let now = Date()
        let f = file("D", ageSeconds: 10_000, now: now) // 참조 없음 + 유예 초과 → 고아
        let result = ScrollbackStore.orphans(in: [f], liveTabIds: [], referencedPaths: [],
                                             now: now, graceInterval: 3600)
        XCTAssertEqual(result, [f.path])
    }

    func testMixedSetSelectsOnlyTrueOrphans() {
        let now = Date()
        let live = file("L", ageSeconds: 10_000, now: now)
        let ref = file("R", ageSeconds: 10_000, now: now)
        let recent = file("N", ageSeconds: 10, now: now)
        let orphan1 = file("O1", ageSeconds: 10_000, now: now)
        let orphan2 = file("O2", ageSeconds: 4000, now: now)
        let result = ScrollbackStore.orphans(
            in: [live, ref, recent, orphan1, orphan2],
            liveTabIds: ["L"], referencedPaths: [ref.path], now: now, graceInterval: 3600)
        XCTAssertEqual(Set(result), Set([orphan1.path, orphan2.path]))
    }

    func testExactlyAtGraceIsOrphan() {
        let now = Date()
        let f = file("E", ageSeconds: 3600, now: now) // now-modified == grace → 유예 밖(삭제)
        let result = ScrollbackStore.orphans(in: [f], liveTabIds: [], referencedPaths: [],
                                             now: now, graceInterval: 3600)
        XCTAssertEqual(result, [f.path])
    }

    // MARK: PaneSnapshot.scrollbackPaths — 참조 경로 수집

    func testLeafCollectsScrollbackPaths() {
        let tabs = [
            TabSnapshot(group: nil, items: [], selectedItem: 0, scrollbackFile: "/tmp/scrollback/a.txt"),
            TabSnapshot(group: nil, items: [], selectedItem: 0, scrollbackFile: nil), // 파일 없는 탭
            TabSnapshot(group: nil, items: [], selectedItem: 0, scrollbackFile: "/tmp/scrollback/b.txt"),
        ]
        let snap = PaneSnapshot.leaf(tabs: tabs, selected: 0, focused: true)
        XCTAssertEqual(snap.scrollbackPaths(), ["/tmp/scrollback/a.txt", "/tmp/scrollback/b.txt"])
    }

    func testSplitUnionsBothChildren() {
        let left = PaneSnapshot.leaf(
            tabs: [TabSnapshot(group: nil, items: [], selectedItem: 0, scrollbackFile: "/tmp/scrollback/x.txt")],
            selected: 0, focused: false)
        let right = PaneSnapshot.leaf(
            tabs: [TabSnapshot(group: nil, items: [], selectedItem: 0, scrollbackFile: "/tmp/scrollback/y.txt")],
            selected: 0, focused: false)
        let snap = PaneSnapshot.split(vertical: true, divider: 0.5, first: left, second: right)
        XCTAssertEqual(snap.scrollbackPaths(), ["/tmp/scrollback/x.txt", "/tmp/scrollback/y.txt"])
    }

    func testGroupTabHasNoScrollbackPath() {
        let snap = PaneSnapshot.leaf(
            tabs: [TabSnapshot(group: "diffs", items: [], selectedItem: 0)], selected: 0, focused: false)
        XCTAssertTrue(snap.scrollbackPaths().isEmpty)
    }
}
