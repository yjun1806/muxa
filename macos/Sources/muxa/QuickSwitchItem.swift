import Bonsplit
import Foundation

/// 빠른 전환기(⌘K) 항목의 계층 종류 — 아이콘·라벨·타이브레이크에 쓴다.
/// 계층 5단(워크스페이스›프로젝트›칸/탭›서브탭)의 탐색 대상 표현.
enum QuickSwitchKind {
    case workspace
    case project
    case tab      // 칸 안의 탭(터미널 또는 문서/변경 그룹). 대기(배지) 신호가 실린다.
    case subtab   // 그룹 탭의 서브탭(개별 문서·diff)
    case command  // 실행 명령(새 터미널·분할·탭 닫기 등) — 점프가 아니라 KeymapAction을 실행한다.

    var label: String {
        switch self {
        case .workspace: return "워크스페이스"
        case .project: return "프로젝트"
        case .tab: return "탭"
        case .subtab: return "서브탭"
        case .command: return "명령"
        }
    }
}

/// TerminalStore가 넘기는 탭 열거의 가벼운 값 — 뷰 상태를 노출하지 않고 전환기 항목만 만든다.
struct QuickTab {
    let tabId: TabID
    let title: String
    let icon: String?
    let badged: Bool          // 배지(대기 중) → 최상단 정렬 대상
    let subItems: [QuickSubTab]
}

/// 그룹 탭의 서브탭 열거값(문서·diff).
struct QuickSubTab {
    let id: String
    let title: String
    let icon: String
}

/// 빠른 전환기의 단일 항목(값 타입) — 표시 정보 + (점프 좌표 | 실행 명령).
/// AppState가 워크스페이스·프로젝트·스토어를 순회해 점프 항목을, 카탈로그가 명령 항목을 만든다.
/// 엔터 시 `action`이 있으면 그 KeymapAction을 실행하고(키맵과 같은 경로), 없으면 좌표로 점프한다.
struct QuickSwitchItem: Identifiable {
    let id: String
    let kind: QuickSwitchKind
    let title: String
    let subtitle: String      // 위치 브레드크럼(워크스페이스 · 프로젝트 …) 또는 명령 설명
    let icon: String          // SF Symbol
    let waiting: Bool         // 대기(배지) — 최상단 정렬
    // 점프 좌표(점프 항목)
    let workspaceId: String
    let projectId: String?
    let tabId: TabID?
    let subItemId: String?
    // 실행 명령(명령 항목) — 있으면 엔터 시 이 동작을 실행하고 팔레트를 닫는다.
    let action: KeymapAction?
    let shortcutHint: String? // 명령 항목의 단축키 힌트(예: "⌘T") — 행 우측에 표시.

    init(id: String, kind: QuickSwitchKind, title: String, subtitle: String, icon: String,
         waiting: Bool, workspaceId: String, projectId: String?, tabId: TabID?, subItemId: String?,
         action: KeymapAction? = nil, shortcutHint: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.subtitle = subtitle
        self.icon = icon; self.waiting = waiting
        self.workspaceId = workspaceId; self.projectId = projectId
        self.tabId = tabId; self.subItemId = subItemId
        self.action = action; self.shortcutHint = shortcutHint
    }

    /// 명령 항목 팩토리 — KeymapAction을 실은 항목(점프 좌표는 비운다). 카탈로그가 쓴다.
    /// 기본 단축키가 없는 명령은 힌트를 비운다(nil → 행에 칩이 안 그려진다).
    static func command(_ action: KeymapAction, id: String, title: String, subtitle: String,
                        icon: String, shortcutHint: String? = nil) -> QuickSwitchItem {
        QuickSwitchItem(id: id, kind: .command, title: title, subtitle: subtitle, icon: icon,
                        waiting: false, workspaceId: "", projectId: nil, tabId: nil, subItemId: nil,
                        action: action, shortcutHint: shortcutHint)
    }
}

/// 팔레트에 섞이는 실행 명령 카탈로그(순수 데이터) — KeymapAction을 재사용하고, 실행은 AppState.perform이 맡는다.
/// 여기가 명령 목록의 단일 진실 원천. 단축키는 KeymapResolver 기본 테이블과 짝을 맞춰 힌트로만 표시한다.
enum QuickCommandCatalog {
    static let items: [QuickSwitchItem] = [
        .command(.newTerminal, id: "cmd:new-terminal", title: "새 터미널",
                 subtitle: "활성 칸에 새 터미널 탭", icon: "plus.square", shortcutHint: "⌘T"),
        .command(.split(vertical: false), id: "cmd:split-h", title: "수평 분할",
                 subtitle: "활성 칸 분할", icon: "rectangle.split.2x1", shortcutHint: "⌘D"),
        .command(.split(vertical: true), id: "cmd:split-v", title: "수직 분할",
                 subtitle: "활성 칸 분할", icon: "rectangle.split.1x2", shortcutHint: "⌘⇧D"),
        .command(.closeTab, id: "cmd:close-tab", title: "탭 닫기",
                 subtitle: "활성 탭 닫기", icon: "xmark.square", shortcutHint: "⌘W"),
        .command(.toggleExplorer, id: "cmd:toggle-explorer", title: "익스플로러 토글",
                 subtitle: "파일 탐색 패널", icon: "sidebar.left", shortcutHint: "⌘⇧E"),
        .command(.toggleGitPanel, id: "cmd:toggle-git", title: "Git 패널 토글",
                 subtitle: "변경사항·브랜치·워크트리", icon: "arrow.triangle.merge", shortcutHint: "⌘⇧G"),
        .command(.jumpToNextWaiting, id: "cmd:next-waiting", title: "다음 대기 세션",
                 subtitle: "배지된 다음 세션으로 점프", icon: "bell.badge", shortcutHint: "⌘⇧A"),
        .command(.separateProject, id: "cmd:separate-project", title: "새 창으로 분리",
                 subtitle: "활성 프로젝트를 새 창으로", icon: "macwindow"),
        // 첫 스크립트의 상시 진입점 — 푸터 칩은 등록 0개면 숨어서 스스로는 0→1을 못 만든다.
        .command(.addScript, id: "cmd:add-script", title: "스크립트 추가",
                 subtitle: "활성 프로젝트에 1회 실행 명령 등록", icon: "play.square"),
        // 일회용 명령 — 등록 없이 즉석 1회(brew install·pnpm install). 도크 일회용 탭 입력창을 연다.
        .command(.runOneOff, id: "cmd:run-one-off", title: "일회용 명령 실행",
                 subtitle: "brew install·pnpm install처럼 한 번만 돌릴 명령", icon: "terminal"),
    ]
}

/// 항목 필터·정렬(순수). 대기 항목을 최상단, 그 안에서 쿼리 퍼지 점수순.
/// 쿼리가 비면 전부 유지하고 대기 우선 + 원래(계층) 순서를 지킨다.
enum QuickSwitchRanker {
    static func rank(_ items: [QuickSwitchItem], query: String) -> [QuickSwitchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        struct Scored { let item: QuickSwitchItem; let score: Int; let order: Int }
        var scored: [Scored] = []
        for (i, item) in items.enumerated() {
            if trimmed.isEmpty {
                scored.append(Scored(item: item, score: 0, order: i))
            } else if let s = matchScore(trimmed, item) {
                scored.append(Scored(item: item, score: s, order: i))
            }
        }

        return scored.sorted { a, b in
            if a.item.waiting != b.item.waiting { return a.item.waiting } // 대기 우선
            if trimmed.isEmpty { return a.order < b.order }               // 계층 순
            if a.score != b.score { return a.score > b.score }            // 점수순
            return a.order < b.order                                      // 안정 정렬
        }.map(\.item)
    }

    /// 제목 우선 매칭, 없으면 부제목(위치)로 폴백하되 감점. 둘 다 아니면 nil(제외).
    private static func matchScore(_ query: String, _ item: QuickSwitchItem) -> Int? {
        if let s = FuzzyMatch.score(query: query, in: item.title) { return s }
        if let s = FuzzyMatch.score(query: query, in: item.subtitle) { return s - 100 }
        return nil
    }
}
