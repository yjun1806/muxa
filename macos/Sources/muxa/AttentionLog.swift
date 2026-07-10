import AppKit
import Foundation
import Observation

/// 주의 신호의 종류 — 배지가 붙은 이유. 인박스에서 아이콘·색·라벨로 구분한다.
/// (완료=OSC 133 명령 완료, 벨=터미널 벨, 알림=OSC 9/777·훅 데스크톱 알림)
enum AttentionKind: String, Codable {
    case done
    case bell
    case notify
    /// 시스템 경고 — 탭 활동이 아니라 앱 자체가 알리는 항목(키맵 재정의 진단·크래시 복원 등).
    /// 특정 칸에 묶이지 않는 전역 항목이라 클릭 점프 대상이 없다(빈 컨텍스트로 기록 → reveal 무동작).
    case system

    var label: String {
        switch self {
        case .done: return "완료"
        case .bell: return "벨"
        case .notify: return "알림"
        case .system: return "시스템"
        }
    }

    var icon: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .bell: return "bell.fill"
        case .notify: return "message.fill"
        case .system: return "exclamationmark.triangle.fill"
        }
    }

    /// 종류색 — 팔레트 재사용(신규 색 없음). 완료=초록, 벨=주황, 알림=청록, 시스템=주황빨강(경고).
    var color: NSColor {
        switch self {
        case .done: return Palette.gitAdded
        case .bell: return Palette.borderActivity
        case .notify: return Palette.borderFocus
        case .system: return Palette.gitConflict
        }
    }
}

/// 놓친 주의 이력 한 건(값 타입). 배지가 생긴 순간을 기록한다 — 배지는 "지금 상태",
/// 이 엔트리는 "자리 비웠다 돌아왔을 때의 복구 동선". 시각(date)은 표시용,
/// 정렬·읽음 판정은 단조 증가 시퀀스(seq)로 한다(같은 밀리초에 여러 건이 와도 안정 정렬).
struct AttentionEntry: Identifiable, Equatable {
    var id: Int { seq }
    let workspaceId: String
    let projectId: String
    let tabId: String
    let kind: AttentionKind
    let title: String
    let seq: Int
    let date: Date
}

/// 주의 이력 큐(@Observable) — AppState가 소유하고, 인박스 패널이 관측해 렌더한다.
/// 배지 발생 경로(markBadge)에서만 append된다(보이는 칸은 테두리 플래시라 이력에 안 남는다).
/// 상한을 두고 오래된 것부터 버린다(무한 성장 방지). 영속하지 않음 — 배지처럼 세션 한정.
@MainActor
@Observable
final class AttentionLog {
    /// 최근 항목 우선이 아니라 발생 순(오래된→최신)으로 보관한다. 뷰가 역순으로 그린다.
    private(set) var entries: [AttentionEntry] = []
    /// 여기까지 읽음(이 seq 이하 항목은 읽음). markAllRead가 최신 seq로 올린다.
    private(set) var lastReadSeq: Int = 0

    /// 다음 엔트리에 부여할 단조 시퀀스. 관측 대상 아님(엔트리 seq로 이미 노출).
    @ObservationIgnored private var seqCounter: Int = 0

    /// 이력 상한 — 넘으면 오래된 것부터 버린다.
    private static let cap = 200

    /// 안 읽은 항목 수 — 벨 배지에 표시.
    var unreadCount: Int {
        entries.reduce(0) { $0 + ($1.seq > lastReadSeq ? 1 : 0) }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// 배지 발생 시 이력을 한 건 추가한다(immutable — 새 배열로 교체). 상한 초과분은 앞에서 버린다.
    ///
    /// 병합(coalescing): 직전(최신) 항목이 같은 탭·같은 종류면 새 항목을 쌓지 않고 **교체**한다(last-write-wins).
    /// auto-approve 연타로 같은 신호가 반복돼도 인박스가 부풀지 않고, 상한(cap)을 중복이 잡아먹지 않는다.
    /// 교체 시에도 seq를 올려 최신·안 읽음으로 되살린다(반복 활동도 새 주의로 환기). 시각도 갱신.
    func record(workspaceId: String, projectId: String, tabId: String, kind: AttentionKind, title: String) {
        seqCounter += 1
        let entry = AttentionEntry(workspaceId: workspaceId, projectId: projectId, tabId: tabId,
                                   kind: kind, title: title, seq: seqCounter, date: Date())
        var next = entries
        if let last = next.last, last.tabId == tabId, last.kind == kind {
            next[next.count - 1] = entry // 직전 동일 신호 교체 — 중복 누적 방지
        } else {
            next.append(entry)
            if next.count > Self.cap { next.removeFirst(next.count - Self.cap) }
        }
        entries = next
    }

    /// 시스템 경고(키맵 진단·크래시 복원 등)를 한 건 기록한다 — 탭에 안 묶이는 전역 항목이라 컨텍스트는 비운다
    /// (클릭 점프 대상이 없어 revealAttention이 안전하게 무동작). 배지 신호가 아니라 seqCounter만 올려 안 읽음으로 뜬다.
    ///
    /// 같은 메시지가 이미 있으면 다시 쌓지 않는다(제목 기준 dedup) — 라이브 리로드로 동일 진단이 재검출되거나
    /// 시작 시 같은 경고가 반복돼도 인박스가 부풀지 않게 한다. tabId 기반 병합(record)과 달리 전 이력을 훑는다
    /// (시스템 항목 수가 적어 충분). 사용자가 "모두 지우기"로 비우면 다시 뜰 수 있다(현재 문제 재알림).
    func recordSystem(title: String) {
        guard !entries.contains(where: { $0.kind == .system && $0.title == title }) else { return }
        seqCounter += 1
        let entry = AttentionEntry(workspaceId: "", projectId: "", tabId: "",
                                   kind: .system, title: title, seq: seqCounter, date: Date())
        var next = entries
        next.append(entry)
        if next.count > Self.cap { next.removeFirst(next.count - Self.cap) }
        entries = next
    }

    /// 인박스를 열어 다 봤음 — 현재까지를 전부 읽음 처리(벨 배지 0으로).
    func markAllRead() { lastReadSeq = seqCounter }

    /// 이력 비우기(읽음 기준선도 최신으로).
    func clear() {
        entries = []
        lastReadSeq = seqCounter
    }
}
