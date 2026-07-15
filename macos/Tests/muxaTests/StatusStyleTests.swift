import Testing
@testable import muxa

/// 상태 톤 SSOT(`StatusTone`/`StatusStyle`)의 순수 판정 — 통일 1단계.
struct StatusStyleTests {
    /// **색맹 안전의 핵심 계약**: 색을 빼도 톤이 구분돼야 한다 = 톤마다 글리프가 유일하다.
    @Test func 글리프는_톤마다_다르다() {
        let glyphs = StatusTone.allCases.map(StatusStyle.glyph)
        #expect(Set(glyphs).count == StatusTone.allCases.count)
    }

    /// 무채는 조용/미실행에만 — 나머지는 의미색(크롬 무채·색은 신호일 때만).
    @Test func 점크기는_조용한_톤만_작다() {
        #expect(StatusStyle.dotSize(.quiet) == IconSize.dotSmall)
        #expect(StatusStyle.dotSize(.inert) == IconSize.dotSmall)
        #expect(StatusStyle.dotSize(.active) == IconSize.dot)
        #expect(StatusStyle.dotSize(.attention) == IconSize.dot)
        #expect(StatusStyle.dotSize(.success) == IconSize.dot)
        #expect(StatusStyle.dotSize(.failure) == IconSize.dot)
    }

    /// 프로젝트 롤업 상태 → 톤 매핑(어댑터가 이걸 거쳐 StatusStyle을 부른다).
    @Test func 프로젝트상태_톤_매핑() {
        #expect(SidebarTree.ProjectStatus.idle.tone == .quiet)
        #expect(SidebarTree.ProjectStatus.working.tone == .active)
        #expect(SidebarTree.ProjectStatus.attention.tone == .attention)
    }

    /// 어댑터(ProjectStatusStyle)가 StatusStyle과 **정확히 같은 값**을 낸다 = 위임이 시각 무변임을 증명.
    /// (StatusMappingSnapshotTests가 "그 값이 통일 이전과 같다"를 별도로 못 박는다.)
    @Test func 어댑터는_SSOT를_그대로_위임한다() {
        for status in [SidebarTree.ProjectStatus.idle, .working, .attention] {
            #expect(ProjectStatusStyle.glyph(status) == StatusStyle.glyph(status.tone))
            #expect(ProjectStatusStyle.dotSize(status) == StatusStyle.dotSize(status.tone))
        }
    }
}
