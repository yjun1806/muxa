import Testing
import Foundation
@testable import muxa

/// 프로젝트별 격리 디코드 — 스냅샷 하나가 깨져도 나머지 프로젝트는 살아남아야 한다.
/// (기존 `try?` 통짜 디코드는 하나가 깨지면 전 프로젝트 레이아웃을 조용히 날렸다.)
struct LayoutDecodeTests {
    /// 터미널 탭 하나짜리 최소 leaf 스냅샷의 JSON.
    private static let validLeaf = """
    {"leaf":{"tabs":[{"items":[],"selectedItem":0}],"selected":0,"focused":true}}
    """

    private func decode(_ json: String) throws -> LenientLayouts {
        try JSONDecoder().decode(LenientLayouts.self, from: Data(json.utf8))
    }

    @Test func 정상_스냅샷_전부_디코드() throws {
        let result = try decode("""
        {"p1": \(Self.validLeaf), "p2": \(Self.validLeaf)}
        """)
        #expect(result.layouts.count == 2)
        #expect(result.dropped.isEmpty)
    }

    @Test func 손상된_프로젝트만_버리고_나머지는_보존() throws {
        // p2는 leaf/split 어느 쪽도 아닌 쓰레기 — 이것 때문에 p1까지 잃으면 안 된다.
        let result = try decode("""
        {"p1": \(Self.validLeaf), "p2": {"garbage": 1}}
        """)
        #expect(result.layouts.keys.sorted() == ["p1"])
        #expect(result.dropped == ["p2"])
    }

    @Test func 전부_손상이면_빈_레이아웃과_전체_dropped() throws {
        let result = try decode("""
        {"p1": {"garbage": 1}, "p2": "not-an-object"}
        """)
        #expect(result.layouts.isEmpty)
        #expect(result.dropped.sorted() == ["p1", "p2"])
    }

    @Test func 빈_객체는_빈_결과() throws {
        let result = try decode("{}")
        #expect(result.layouts.isEmpty)
        #expect(result.dropped.isEmpty)
    }

    /// 인코딩 왕복 — 격리 디코더가 정상 데이터를 원형 그대로 복구하는지.
    @Test func 왕복_보존() throws {
        let original: [String: PaneSnapshot] = [
            "p1": .leaf(tabs: [TabSnapshot(group: nil, items: [], selectedItem: 0)], selected: 0, focused: true)
        ]
        let data = try JSONEncoder().encode(original)
        let result = try JSONDecoder().decode(LenientLayouts.self, from: data)
        #expect(result.dropped.isEmpty)
        guard case .leaf(let tabs, _, let focused)? = result.layouts["p1"] else {
            Issue.record("leaf로 복구되지 않음"); return
        }
        #expect(tabs.count == 1)
        #expect(focused)
    }

    /// 탭 개수 집계 — 분할 트리 전체의 최상위 탭 합(사이드바 개수 배지의 lazy 프로젝트 출처).
    @Test func 탭_개수는_분할_양쪽을_합산() {
        let term = TabSnapshot(group: nil, items: [], selectedItem: 0)
        let viewer = TabSnapshot(group: "documents", items: [], selectedItem: 0)
        let snap = PaneSnapshot.split(
            vertical: false, divider: 0.5,
            first: .leaf(tabs: [term, viewer], selected: 0, focused: true),
            second: .leaf(tabs: [term], selected: 0, focused: false)
        )
        #expect(snap.tabCount() == 3) // 터미널+뷰어 구분 없이 최상위 탭 전부
    }
}
