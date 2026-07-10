import Bonsplit
import Foundation

/// 빠른 전환기(⌘K) 항목의 계층 종류 — 아이콘·라벨·타이브레이크에 쓴다.
/// 계층 5단(워크스페이스›프로젝트›칸/탭›서브탭)의 탐색 대상 표현.
enum QuickSwitchKind {
    case workspace
    case project
    case tab      // 칸 안의 탭(터미널 또는 문서/변경 그룹). 대기(배지) 신호가 실린다.
    case subtab   // 그룹 탭의 서브탭(개별 문서·diff)

    var label: String {
        switch self {
        case .workspace: return "워크스페이스"
        case .project: return "프로젝트"
        case .tab: return "탭"
        case .subtab: return "서브탭"
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

/// 빠른 전환기의 단일 탐색 항목(값 타입) — 표시 정보 + 점프 라우팅 좌표.
/// AppState가 워크스페이스·프로젝트·스토어를 순회해 만들고, 엔터 시 좌표로 점프한다.
struct QuickSwitchItem: Identifiable {
    let id: String
    let kind: QuickSwitchKind
    let title: String
    let subtitle: String      // 위치 브레드크럼(워크스페이스 · 프로젝트 …)
    let icon: String          // SF Symbol
    let waiting: Bool         // 대기(배지) — 최상단 정렬
    // 점프 좌표
    let workspaceId: String
    let projectId: String?
    let tabId: TabID?
    let subItemId: String?
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
