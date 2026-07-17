import SwiftUI

/// 스크립트 실행 상태의 표시 규칙 — 색·글리프·라벨·꼬리표의 단일 출처(**스크립트 축 SSOT**).
/// 푸터 칩(`ScriptStrip`)과 팝오버 행(`ScriptRow`)이 같은 규칙을 써야 "✗는 실패"가 흔들리지 않는다.
///
/// **제3의 어휘다 — 에이전트 축(`StatusStyle`)·서비스 축(`ServiceStatusStyle`)과 일부러 다르다.**
/// 서비스는 끝없는 프로세스라 **원형** play/stop 짝(▶/■)이고, 스크립트는 끝있는 명령이라
/// **사각형 가족**이다(탭 아이콘 `play.square`와 한 축): 실행중 ⟳ · 성공 `checkmark.square` ·
/// 실패 `xmark.square`. 성공은 **무채**(pMuted) — 에이전트 완료의 세이지 ✓(`checkmark`)와
/// 색·모양 둘 다 갈라 한 푸터에 나란히 떠도 안 헷갈린다.
enum ScriptStatusStyle {
    /// 스크립트 축의 대표 글리프 — 칩·팝오버·도크 빈 상태가 같은 것을 쓴다.
    /// 서비스(play.circle)·에이전트 활동(bolt)과 글리프 축을 가른다(사각형 가족).
    static let icon = "play.square"

    /// **색만으로 구분하지 않는다**(색맹 안전) — 결과가 갈리면 글리프 자체가 바뀐다.
    /// `nil` state = 등록만 되고 실행 이력이 없는 스크립트(팝오버 목록의 평시 행).
    /// code nil(결과 미상 — ⌘W·프레임 유실)은 **✓를 지어내지 않고** 물음표로 남긴다.
    static func glyph(_ state: ScriptRun.RunState?) -> String {
        switch state {
        case .none: return "square.dashed"
        case .running: return "arrow.triangle.2.circlepath"
        case .finished(let code, _):
            guard let code else { return "questionmark.square" }
            return code == 0 ? "checkmark.square" : "xmark.square"
        }
    }

    /// 실행중은 서비스 실행중과 같은 파랑(pServiceRunning)을 **재사용**한다 — "돌고 있다"는 의미가
    /// 같고 글리프(⟳ vs ▶)가 이미 축을 가른다. 성공·미상은 무채, 실패만 빨강.
    static func color(_ state: ScriptRun.RunState?) -> Color {
        switch state {
        case .none: return .pMuted
        case .running: return .pServiceRunning
        case .finished(let code, _):
            guard let code, code != 0 else { return .pMuted }
            return .pServiceExited
        }
    }

    /// 스크린리더용 상태 이름 — 색도 글리프도 VoiceOver에는 존재하지 않는다(DESIGN §2 규칙).
    static func label(_ state: ScriptRun.RunState?) -> String {
        switch state {
        case .none: return "실행 전"
        case .running: return "실행 중"
        case .finished(let code, _):
            guard let code else { return "결과 미상" }
            return code == 0 ? "성공" : "실패 (exit \(code))"
        }
    }

    /// 꼬리표 — 실행중은 경과("12s"), 성공·미상은 걸린 시간("8s"), 실패는 exit code("exit 2").
    /// 실행 이력이 없거나 **시각을 모르면**(재시작 후 채택 — startedAt·duration nil) 아무것도
    /// 안 붙인다(지어내지 않는다).
    static func tail(_ run: ScriptRun?, now: Date) -> String? {
        guard let run else { return nil }
        switch run.state {
        case .running:
            return run.startedAt.map { RelativeTime.compact(now.timeIntervalSince($0)) }
        case .finished(let code, let duration):
            if let code, code != 0 { return "exit \(code)" }
            return duration.map(RelativeTime.compact)
        }
    }
}

/// 푸터 스크립트 칩이 지금 어떤 모습이어야 하나 — 순수 판정(칩 뷰는 이 결과를 그리기만 한다).
enum ScriptChipMode: Equatable {
    /// 등록 0개 — **그래도 그린다**(플레이스홀더). 서비스 칩과 같은 철학으로 바뀌었다:
    /// 이 칩이 스크립트 기능의 상시 발견 지점이다(숨기면 있는지도 모른다).
    case empty
    /// 등록 ≥1, 실행 0, 잔류 0 — 개수만 말하는 조용한 칩(클릭 = 팝오버).
    case idle(count: Int)
    /// 실행 ≥1 — 최신 시작 순(시작 시각 미상 = 재시작 후 채택은 뒤로). 잔류가 있어도 실행이
    /// 우선이다("지금 도는 것"이 헤드라인).
    case running([ScriptRun])
    /// 실행 0, 완료 잔류 ≥1 — 하나만 고른다: **실패 최우선**(ServiceStatusStyle.summarize와
    /// 같은 원칙 — 성공 다수에 실패가 묻히면 안 된다), 같은 급이면 최신.
    /// 확인된(acknowledged) 잔류는 세지 않는다 — 클릭·새 실행으로 이미 내려간 칩이다.
    case lingering(ScriptRun)

    static func judge(scriptCount: Int, runs: [ScriptRun]) -> ScriptChipMode {
        guard scriptCount > 0 else { return .empty }
        let running = runs.filter(\.isRunning)
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        if !running.isEmpty { return .running(running) }
        // code nil(결과 미상)은 실패로 세지 않는다 — ✗를 지어내지 않는 것과 같은 원칙.
        let linger = runs.filter { !$0.isRunning && !$0.acknowledged }.max { a, b in
            if a.isFailure != b.isFailure { return b.isFailure }
            return (a.startedAt ?? .distantPast) < (b.startedAt ?? .distantPast)
        }
        if let linger { return .lingering(linger) }
        return .idle(count: scriptCount)
    }
}
