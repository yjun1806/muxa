import Foundation

/// 행의 상태 표식 — git 축(`GitStatusStyle`)을 그대로 쓰거나, git이 조용한 경우를 따로 말한다.
enum AgentChangeMark: Equatable {
    /// git이 아는 상태(`A`/`M`/`D`/`?`/…) — 글리프·색은 `GitStatusStyle`이 정한다.
    case git(Character)
    /// 기준선 이후 바뀌었는데 지금 워킹트리는 깨끗하다 = **커밋됐다**.
    /// 목록에서 사라지면 "내가 본 그 변경이 어디 갔지"가 되므로 남기고 꼬리표만 바꾼다.
    case committed
}

/// 패널이 그리는 한 줄 — 수집 기록 × git 상태 × 디스크를 교차한 파생(순수 값).
struct AgentChangeRow: Equatable, Identifiable {
    let path: String
    let mark: AgentChangeMark
    /// 안 봤음 — 굵게 그린다. 봤어도 그 뒤 바뀌면 다시 참이 된다.
    let isUnread: Bool
    /// 마지막 변경 시각(꼬리표 "3m"). 모르면 침묵한다.
    let mtime: Date?

    var id: String { path }
}

/// 한 세션(탭)의 그룹.
struct AgentChangeGroup: Equatable {
    /// 그룹 제목 — **첫 수집 턴의 프롬프트**(얼린 값). 없으면 호출측이 탭 이름으로 폴백한다.
    let title: String?
    let rows: [AgentChangeRow]
    /// 안 본 개수 — 접힌 그룹의 롤업 배지. 0이면 배지를 그리지 않는다.
    let unreadCount: Int
    /// 표시 상한을 넘겨 접힌 행 수("그 외 N개").
    let hiddenCount: Int
    /// 천장에 닿아 **애초에 기록하지 못한** 수. 접힌 것과 다른 사건이라 따로 말한다.
    let truncatedCount: Int
    /// 이 그룹의 diff 기준 리비전(얼린 HEAD). 아직 못 읽었으면 nil — 여는 쪽이 HEAD로 떨어진다.
    let baseline: String?
}

/// 수집 기록을 표시용으로 접는 판정 — 전부 순수 함수라 테스트로 못 박는다.
///
/// `PreToolUse`는 실행 **전** 신호라 거부·실패한 편집도 수집된다. 그 오탐을 여기서 강등하되,
/// **완전 제거는 불가능하다** — 같은 파일을 성공 1회 + 거부 1회 만지면 그 둘은 구분되지 않는다.
enum AgentChangeDisplay {
    /// 그룹당 표시할 최대 행 수. 넘치면 지우지 않고 접는다("그 외 N개").
    static let rowLimit = 50

    /// 안 봤는가 — `max(마지막 만진 시각, mtime) > 봤은 시각`.
    ///
    /// mtime을 함께 보는 게 핵심이다. 훅은 `Bash`(`sed`·스크립트)로 한 변경을 못 보는데,
    /// 그것만 믿으면 **실제로 바뀐 파일이 "봤음"으로 남는다** — 이 기능에서 가장 나쁜 실패다.
    /// mtime은 `GitFileTime`이 이미 읽고 있어 셸아웃이 늘지 않는다.
    static func isUnread(entry: AgentChangeEntry, mtime: Date?) -> Bool {
        guard let seenAt = entry.seenAt else { return true } // 한 번도 안 열었다
        return max(entry.lastTouchedAt, mtime ?? .distantPast) > seenAt
    }

    /// 표시를 억제하는가 — 편집을 **시도**했으나 git·디스크 어디에도 흔적이 없다(거부·no-op).
    ///
    /// 변경 리뷰 창구에 "안 바뀐 파일"을 띄우면 "muxa가 헛것을 보여준다"가 된다.
    /// 판정은 남기고 표시만 하지 않는다 — 나중에 켜고 싶어질 수 있고, 켜는 판단은 UI의 몫이다.
    static func isSuppressed(entry: AgentChangeEntry, status: Character?, mtime: Date?) -> Bool {
        if status != nil { return false }                 // git이 변화를 안다
        guard let mtime else { return true }              // 파일이 없다 = 만든 적도 없다
        return mtime < entry.firstTouchedAt               // 우리가 만지기 전 그대로다
    }

    /// 표식 판정. git이 조용한데 디스크는 바뀐 파일은 **커밋된 것**이다.
    static func mark(status: Character?, entry: AgentChangeEntry, mtime: Date?) -> AgentChangeMark {
        if let status { return .git(status) }
        return .committed
    }

    /// 한 세션의 그룹을 만든다. 정렬은 **최근 만진 순** — "방금 만진 게 뭐지"가 리뷰의 첫 질문이다.
    static func group(from set: AgentChangeSet,
                      status: [String: Character],
                      mtimes: [String: Date],
                      limit: Int = rowLimit) -> AgentChangeGroup {
        let visible = set.entries.values
            .filter { !isSuppressed(entry: $0, status: status[$0.path], mtime: mtimes[$0.path]) }
            .sorted { lhs, rhs in
                // 시각이 같으면 경로로 갈라 순서를 결정적으로 만든다(딕셔너리 순회는 불안정하다).
                lhs.lastTouchedAt == rhs.lastTouchedAt
                    ? lhs.path < rhs.path
                    : lhs.lastTouchedAt > rhs.lastTouchedAt
            }

        let shown = visible.prefix(limit).map { entry in
            AgentChangeRow(path: entry.path,
                           mark: mark(status: status[entry.path], entry: entry,
                                      mtime: mtimes[entry.path]),
                           isUnread: isUnread(entry: entry, mtime: mtimes[entry.path]),
                           mtime: mtimes[entry.path])
        }
        // 안 본 개수는 **보이는 것 전부**를 센다 — 접힌 행에 안 본 게 있는데 배지가 침묵하면 안 된다.
        let unread = visible.filter { isUnread(entry: $0, mtime: mtimes[$0.path]) }.count

        return AgentChangeGroup(title: set.originPrompt,
                                rows: Array(shown),
                                unreadCount: unread,
                                hiddenCount: max(0, visible.count - shown.count),
                                truncatedCount: set.truncatedCount,
                                baseline: set.baselineHead)
    }

    /// 참고 목록 — 종류별로 갈라 최근 본 순. 탭에서 "뭘 봤나"만 답하므로 통계는 붙이지 않는다.
    static func references(from set: AgentChangeSet, kind: AgentReference.Kind) -> [AgentReference] {
        set.references.values
            .filter { $0.kind == kind }
            .sorted { lhs, rhs in
                lhs.lastSeenAt == rhs.lastSeenAt ? lhs.value < rhs.value : lhs.lastSeenAt > rhs.lastSeenAt
            }
    }
}
