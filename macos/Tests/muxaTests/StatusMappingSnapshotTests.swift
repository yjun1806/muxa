import Testing
@testable import muxa

/// 상태 표시 매핑의 **현행 스냅샷**(통일 작업 0단계 회귀 앵커).
///
/// 지금 상태값은 여러 스타일 함수에 흩어져 있다(`ProjectStatusStyle`·`ServiceStatusStyle`·
/// `AgentActivity.borderColor`). 이 표를 못 박아 두면, 이후 통일 단계(StatusTone/StatusStyle)에서
/// 의도한 변경만 diff로 드러나고 **의도치 않은 시각 변화는 곧 실패**로 잡힌다.
/// 각 단계가 이 테스트를 **함께 고쳐야** = "무엇을 바꿨는지" 명시적 기록이 남는다.
struct StatusMappingSnapshotTests {
    // MARK: 프로젝트 상태(사이드바 롤업 아이콘·점)

    @Test func 프로젝트_상태_글리프() {
        #expect(ProjectStatusStyle.glyph(.idle) == "circle")
        #expect(ProjectStatusStyle.glyph(.working) == "circle.fill")
        #expect(ProjectStatusStyle.glyph(.attention) == "ellipsis.circle.fill") // 느낌표는 failure로 옮김(에러 오독 방지)
    }

    @Test func 프로젝트_상태_점크기는_유휴만_작다() {
        #expect(ProjectStatusStyle.dotSize(.idle) == IconSize.dotSmall)
        #expect(ProjectStatusStyle.dotSize(.working) == IconSize.dot)
        #expect(ProjectStatusStyle.dotSize(.attention) == IconSize.dot)
    }

    // MARK: 서비스 상태(도크·칩·사이드바 요약)

    @Test func 서비스_상태_글리프() {
        #expect(ServiceStatusStyle.glyph(.running) == "circle.fill")
        #expect(ServiceStatusStyle.glyph(.exited(code: 0)) == "stop.circle")
        #expect(ServiceStatusStyle.glyph(.exited(code: 3)) == "exclamationmark.triangle.fill")
        #expect(ServiceStatusStyle.glyph(.missing) == "circle.dotted")
    }

    @Test func 서비스_상태_라벨() {
        #expect(ServiceStatusStyle.label(.running) == "실행 중")
        #expect(ServiceStatusStyle.label(.exited(code: 0)) == "종료됨")
        #expect(ServiceStatusStyle.label(.exited(code: 3)) == "비정상 종료 (exit 3)")
        #expect(ServiceStatusStyle.label(.missing) == "실행 전")
    }

    // MARK: 에이전트 활동(탭 층)

    @Test func 에이전트_활동_라벨() {
        #expect(AgentActivity.idle.label == "대기 없음")
        #expect(AgentActivity.working.label == "작업 중")
        #expect(AgentActivity.waiting.label == "입력 대기")
        #expect(AgentActivity.done.label == "완료")
    }

    @Test func 에이전트_테두리색은_대기와_완료에만_있다() {
        // 상시 테두리는 "사람을 기다린다/끝났다"만 — working·idle은 조용(nil).
        #expect(AgentActivity.waiting.borderColor != nil)
        #expect(AgentActivity.done.borderColor != nil)
        #expect(AgentActivity.working.borderColor == nil)
        #expect(AgentActivity.idle.borderColor == nil)
    }

    // MARK: 통일 대상의 핵심 증거 — 같은 글리프가 서로 다른 의미에 쓰인다

    @Test func 글리프_충돌_현황_에이전트작업중과_서비스실행중이_같은_원() {
        // 한 사이드바 행에 동시에 뜨는데 둘 다 `circle.fill`(색만 틸/초록으로 다름).
        // **이 등식이 깨지면**(글리프 분리) 통일 4단계가 진전된 것 — 그때 이 테스트를 갱신한다.
        #expect(ProjectStatusStyle.glyph(.working) == ServiceStatusStyle.glyph(.running))
    }
}
