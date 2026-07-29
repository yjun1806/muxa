import Foundation

/// 표의 한 행이 실제로 보여주는 값 — 세션(tmux)과 무게(커널)를 합친 표시용 모델(순수).
///
/// 정렬·필터·검색이 전부 여기서 파생된다. `Table`의 정렬은 `Comparable` 값을 요구하는데
/// 무게는 세션 자체에 없으므로(출처도 갱신 주기도 다르다) 여기서 한 번 합쳐 놓는다.
struct SessionListItem: Identifiable, Equatable {
    let row: TmuxSessionRow
    let weight: SessionWeight

    var id: String { row.id }

    /// **폴더명이 이름이다.** 세션명은 UUID 두 개(`muxa__<projectId>__term__<tabId>`)라 사람이 못 읽고,
    /// 실측에서 세션을 구분해준 것은 `citadel-admin`·`gitNote` 같은 폴더명이었다.
    var title: String {
        let folder = row.path.split(separator: "/").last.map(String.init)
        // 죽은 pane엔 경로가 없다 — 그래도 빈 칸을 두지 않는다(무엇을 지우는지는 알아야 한다).
        return folder ?? "(경로 없음)"
    }

    var kindText: String {
        switch row.kind {
        case .terminal: return "터미널"
        case .script: return "스크립트"
        case .service: return "서비스"
        case .foreign: return "외부"
        }
    }

    /// 죽음이 먼저다 — 죽은 pane에 클라이언트가 붙어 있는 경우가 있어서, 연결을 앞세우면
    /// 종료된 세션이 "이 앱"으로 보인다.
    ///
    /// 살아 있으면 **누가 보고 있는지**를 말한다. tmux의 0/1로는 내 탭·남의 인스턴스·완전 분리가
    /// 한 칸에 뭉개져, 정작 찾아야 할 "어느 화면에도 없는 세션"이 안 보인다.
    var statusText: String {
        row.isDead ? "종료됨" : row.attachment.text
    }

    /// 어느 화면에도 없이 살아 있다 — 이 창이 찾아야 할 것.
    var isHidden: Bool { !row.isDead && row.attachment == .detached }

    var socketText: String { TmuxSocketScanner.label(for: row.socket) }

    /// 안에 도는 것 — 셸을 걷어낸 이름들. 셸뿐이면 빈 문자열이고, 그게 "되찾을 것이 없다"는 뜻이다.
    var labelsText: String { weight.labels.joined(separator: ", ") }

    var memoryText: String { Self.memoryFormatter.string(fromByteCount: Int64(weight.footprintBytes)) }

    /// 소수 한 자리. **첫 훑기의 0도 그대로 보여준다** — "모른다"고 빈 칸을 두면 진짜 0과 구분이 안 된다.
    var cpuText: String { String(format: "%.1f", weight.cpuPercent) }

    /// 이름·경로·안에 도는 것을 함께 훑는다 — "esbuild가 어디서 돌지"로 찾을 수 있어야 한다.
    func matches(search: String) -> Bool {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return title.lowercased().contains(needle)
            || row.path.lowercased().contains(needle)
            || labelsText.lowercased().contains(needle)
    }

    /// 활성 상태 보기와 같은 단위 규약(`.memory`) — 두 창을 나란히 놓고 비교할 수 있어야 한다.
    private static let memoryFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        // 기본값은 0을 "Zero KB"로 쓴다 — 죽은 pane이 한 열에서만 말로 표기되면 정렬된 숫자 사이에서
        // 튀고, 다른 행과 눈으로 비교되지 않는다.
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}

/// 표 상단의 세그먼트 — 무엇을 볼 것인가.
enum SessionFilter: String, CaseIterable, Identifiable {
    case all, terminal, task, hidden, orphan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "전체"
        case .terminal: return "터미널"
        case .task: return "스크립트·서비스"
        case .hidden: return "숨은 것"
        case .orphan: return "고아"
        }
    }

    /// 스크립트와 서비스를 한 칸에 묶는 이유: 둘 다 "돌리고 끝나는 것"이고, 사용자에게는
    /// 터미널이냐 아니냐가 더 큰 구분이다(도크가 이미 둘을 한 목록에 두는 것과 같은 판단).
    func matches(_ item: SessionListItem) -> Bool {
        switch self {
        case .all: return true
        case .terminal: return item.row.kind == .terminal
        case .task: return item.row.kind == .script || item.row.kind == .service
        // 어느 화면에도 없이 살아 있는 것 — "뒤에 숨은 tmux"가 정확히 이것이다(YJ-6의 출발점).
        case .hidden: return item.isHidden
        case .orphan: return item.row.isOrphan
        }
    }
}

/// 하단 요약 — 세 숫자만 말한다.
struct SessionSummary: Equatable {
    let total: Int
    let dead: Int
    let orphan: Int

    init(items: [SessionListItem]) {
        total = items.count
        dead = items.filter(\.row.isDead).count
        orphan = items.filter(\.row.isOrphan).count
    }

    var text: String {
        var parts = ["세션 \(total)개"]
        if dead > 0 { parts.append("종료됨 \(dead)개") }
        if orphan > 0 { parts.append("고아 \(orphan)개") }
        return parts.joined(separator: " · ")
    }
}
