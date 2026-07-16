import Bonsplit
import Foundation

/// 사이드바 프로젝트 행을 펼쳤을 때 나오는 **에이전트 목록**의 한 행 = 탭 하나의 표시 스냅샷.
///
/// 순수 값이다 — 정렬·본문 문자열만 알고, 수확(하비스트)은 `TerminalStore.agentRows`, 표현은 뷰가 맡는다.
/// 라이브 도구 한 줄(`detail`)·대기 경과(`waitingSeconds`)는 스토어가 채워 넣는다(뷰는 계산하지 않는다).
struct AgentRow: Equatable, Identifiable {
    let tabId: TabID
    /// 탭 제목(claude/codex/… 또는 셸). 비면 폴백 라벨을 뷰가 대신 쓴다.
    let title: String
    let state: AgentActivity
    /// working일 때 라이브 도구 한 줄("실행 중: swift"). 없으면 nil → 상태 라벨로 폴백.
    let detail: String?
    /// waiting 경과(초, 단조시간 기준). 상태 한정 시간("입력 대기 19m째")에만 쓴다.
    /// working/done/idle은 시간을 붙이지 않아(무게·시계 혼선 회피) nil.
    let waitingSeconds: TimeInterval?
    /// 이 탭이 **확정 Claude 세션**인가(muxa 훅을 보낸 탭). 참이면 행에 Claude 마크를 단다 —
    /// "진짜 에이전트"와 "로그만 흐르는 터미널"을 가른다(훅 미설정 Claude는 놓칠 수 있음).
    let isAgent: Bool
    /// 탭 종류 아이콘(SF Symbol) — 터미널="terminal", 뷰어=그 종류(doc.richtext·curlybraces·plusminus·photo·…).
    /// **isAgent면 이 아이콘 대신 ClaudeMark(정체성)를 단다** — "누구(WHO)"와 "무슨 상태(WHAT)"를 가른다(Orca 원칙).
    let typeIcon: String
    /// 뷰어(문서·코드·diff…) 탭이면 그 종류 라벨("문서"·"코드"·"변경"…), 아니면 nil.
    /// 뷰어는 에이전트 상태가 없어(유휴) 부제로 종류를 말하고, **유휴여도 목록에 남긴다**("파일탭은 파일로").
    let viewerKind: String?

    var id: TabID { tabId }

    /// 행 본문 — 뷰어는 종류를, 나머지는 상태 인지형. 대기=경과 시간, 작업=라이브 도구(없으면 라벨), 완료=완료, 유휴=라벨.
    /// done에 상대시간을 붙이지 않는다 — 벽시계 완료시각을 저장하지 않아 신뢰할 수 없다(계획 #4).
    var subtitle: String {
        if let kind = viewerKind { return kind } // 뷰어는 상태 대신 종류를 부제로("· 문서")
        switch state {
        case .waiting: return waitingSeconds.map(RelativeTime.waitingLabel) ?? state.label
        case .working: return detail ?? state.label
        case .done, .idle: return state.label
        }
    }
}

extension AgentRow {
    /// 표시 정렬 — **긴급도 그룹**(대기 > 작업중 > 완료 > 유휴), 그룹 내부는 **입력 순서 고정**.
    ///
    /// 그룹 내 원래(탭) 순서를 유지하는 게 핵심이다: 안정 정렬이 아니면 working 하나가 끝나 done 그룹으로
    /// 내려가는 순간 목록이 통째로 재배치돼 **클릭하려던 행이 포인터 밑에서 사라진다**(Orca가 시간순을
    /// 고수하는 이유). 그룹 경계 이동은 어쩔 수 없지만, 그룹 내 흔들림은 없앤다.
    static func ordered(_ rows: [AgentRow]) -> [AgentRow] {
        rows.enumerated()
            .sorted { a, b in
                let pa = priority(a.element.state), pb = priority(b.element.state)
                return pa != pb ? pa < pb : a.offset < b.offset
            }
            .map(\.element)
    }

    private static func priority(_ s: AgentActivity) -> Int {
        switch s {
        case .waiting: return 0
        case .working: return 1
        case .done: return 2
        case .idle: return 3
        }
    }
}

/// 경과 시간을 사람이 읽는 짧은 문자열로 바꾸는 순수 함수.
enum RelativeTime {
    /// 대기 상태 전용 라벨 — "입력 대기 19m째"(내가 지금 얼마나 붙잡고 있나).
    static func waitingLabel(seconds: TimeInterval) -> String {
        "입력 대기 \(compact(seconds))째"
    }

    /// 단위 하나로 압축("45s"·"19m"·"3h"·"2d"). 분 미만은 초, 그 위는 가장 큰 단위 한 개.
    static func compact(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        switch s {
        case ..<60: return "\(s)s"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h"
        default: return "\(s / 86400)d"
        }
    }
}
