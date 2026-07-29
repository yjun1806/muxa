import Foundation

/// 세션 관리자가 다루는 세션 하나 — 표의 한 행.
///
/// 무게(CPU·RSS·프로세스 수)는 여기 없다. 그건 tmux가 아니라 커널에서 오고 갱신 주기도 달라서
/// `ProcessSampler`가 따로 재고 뷰가 `panePid`로 이어 붙인다.
struct TmuxSessionRow: Identifiable, Equatable {
    /// **소켓까지 넣어야 유일하다.** 같은 프로젝트를 릴리스와 dev 빌드가 동시에 열면 세션 이름이
    /// 같고 소켓만 다르다 — 이름만으로 식별하면 표에서 둘이 하나로 합쳐져 엉뚱한 쪽을 죽인다.
    var id: String { "\(socket)/\(name)" }

    let socket: String
    let name: String
    let kind: Kind
    /// muxa 규약 세션이면 소속 프로젝트 id. `foreign`이면 nil.
    let projectId: String?
    let isDead: Bool
    /// tmux가 보고하는 원시 연결 여부. **표시는 `attachment`를 쓴다** — 이 값은 "누가" 보고 있는지
    /// 말해주지 않아 내 탭과 남의 인스턴스와 완전 분리가 한 칸에 뭉개진다.
    let isAttached: Bool
    let createdAt: Date?
    let path: String
    /// 첫 pane의 프로세스. 죽은 pane엔 없다(프로세스가 사라졌다).
    let panePid: pid_t?
    /// 등록된 프로젝트에 속하지 않는다 — **추정이다**(`TmuxInventory.markOrphans` 주석).
    var isOrphan: Bool = false
    /// 지금 **누가 보고 있나** — 이 앱 / 다른 인스턴스 / 외부 터미널 / 아무도(분리됨).
    /// 수집 시 `SessionOwnership.attachment`가 채운다.
    var attachment: SessionAttachment = .detached
    /// 이 세션이 속한 워크스페이스 이름. 등록을 못 찾으면 빈 문자열(고아이거나 남의 소켓이다).
    var workspace: String = ""

    /// 세션이 어느 네임스페이스에 사는가. 규약의 SSOT는 `TerminalSession`·`ScriptSession`·
    /// `ServiceSession`이고 여기서는 그 결과를 담기만 한다.
    enum Kind: Equatable {
        case terminal
        case script
        case service
        /// muxa 규약 밖 — 소켓 이름이 `muxa*`여도 세션까지 우리 것이란 보장은 없다.
        case foreign
    }
}

/// `list-panes` 출력 → 표의 행(순수). 부작용은 전부 `TmuxService` 경계에 있다.
enum TmuxInventory {
    /// 수집에 쓰는 tmux 포맷 — **경로가 마지막이어야 한다**(`parse`의 필드 합치기 규칙과 한 쌍).
    static let paneFormat =
        "#{session_name}|#{session_created}|#{session_attached}|#{pane_index}|#{pane_dead}|#{pane_pid}|#{pane_current_path}"

    /// 세션과 클라이언트를 **한 번의 프로세스로** 읽는 tmux 인자.
    ///
    /// **프로세스 spawn이 폴링 비용의 거의 전부다** — 실측에서 소켓 하나당 ~43ms고, 16개 소켓에
    /// 두 명령을 따로 부르니 32회 spawn = 1390ms였다(폴링 주기 2000ms의 70%). tmux는 `;`로 명령을
    /// 이으므로 한 프로세스가 둘 다 처리한다. 출력이 이어 붙으니 줄 접두사로 가른다(`split`).
    static let observeArgs: [String] = [
        "list-panes", "-a", "-F", paneMarker + paneFormat,
        ";", "list-clients", "-F", clientMarker + "#{client_session}|#{client_pid}",
    ]

    static let paneMarker = "P|"
    static let clientMarker = "C|"

    /// 합친 출력을 두 갈래로 가른다(순수). 접두사가 없는 줄은 버린다(tmux 경고 등).
    static func split(_ raw: String) -> (panes: String, clients: String) {
        var panes: [Substring] = []
        var clients: [Substring] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix(paneMarker) { panes.append(line.dropFirst(paneMarker.count)) }
            else if line.hasPrefix(clientMarker) { clients.append(line.dropFirst(clientMarker.count)) }
        }
        return (panes.joined(separator: "\n"), clients.joined(separator: "\n"))
    }

    /// 고정 필드 수(경로 앞까지). 이보다 적은 줄은 버린다.
    private static let fixedFieldCount = 6

    /// 세션명 → 네임스페이스와 소속 프로젝트(순수).
    ///
    /// 규약을 여기서 다시 쓰지 않고 각 타입의 파서에 **되묻는다**. 규약이 두 곳에 살면 한쪽만
    /// 고쳐졌을 때 관리자가 보는 종류와 GC가 판정하는 종류가 갈린다.
    static func classify(_ sessionName: String) -> (kind: TmuxSessionRow.Kind, projectId: String?) {
        if let parsed = TerminalSession.parse(sessionName) { return (.terminal, parsed.projectId) }
        if let parsed = ScriptSession.parse(sessionName) { return (.script, parsed.projectId) }
        if let parsed = ServiceSession.parse(sessionName) { return (.service, parsed.projectId) }
        return (.foreign, nil)
    }

    /// 한 소켓의 `list-panes -a -F paneFormat` 출력을 행으로 만든다.
    ///
    /// **세션의 첫(최소 인덱스) pane이 그 세션의 상태다.** 사용자가 attach해 화면을 나누면 더 높은
    /// 인덱스의 셸 pane이 붙는데, 그걸 집으면 죽은 스크립트가 살아있는 것으로 보인다. pane 0을
    /// 하드코딩하지 않는 이유도 같다 — `~/.tmux.conf`의 `pane-base-index 1`이면 첫 pane이 1이다
    /// (`ServiceSession.parsePanes`가 같은 함정에서 배운 규칙).
    static func parse(_ raw: String, socket: String) -> [TmuxSessionRow] {
        var best: [String: (index: Int, row: TmuxSessionRow)] = [:]
        var order: [String] = []

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.components(separatedBy: "|")
            guard fields.count > fixedFieldCount, !fields[0].isEmpty,
                  let index = Int(fields[3]) else { continue }

            let name = fields[0]
            if let existing = best[name], existing.index <= index { continue }
            if best[name] == nil { order.append(name) }

            let classified = classify(name)
            best[name] = (index, TmuxSessionRow(
                socket: socket,
                name: name,
                kind: classified.kind,
                projectId: classified.projectId,
                isDead: fields[4] == "1",
                isAttached: fields[2] == "1",
                createdAt: TimeInterval(fields[1]).map(Date.init(timeIntervalSince1970:)),
                // 경로에 `|`가 들어갈 수 있다 — 앞 필드는 개수가 고정이므로 나머지를 도로 잇는다.
                // 밀린 채로 읽으면 pid·dead가 통째로 어긋나 엉뚱한 세션을 죽이게 된다.
                path: fields[fixedFieldCount...].joined(separator: "|"),
                // 죽은 pane은 pid가 0이거나 비어 있다 — 프로세스가 이미 사라졌다.
                panePid: pid_t(fields[5]).flatMap { $0 > 0 ? $0 : nil }
            ))
        }
        return order.compactMap { best[$0]?.row }
    }

    /// 등록에 없는 프로젝트의 세션에 고아 표시를 단다(순수, 새 배열을 돌려준다).
    ///
    /// **추정이다.** 다른 muxa 인스턴스의 등록은 종료 시점에 저장된 `state.v4.json`으로만 알 수 있어
    /// 실시간이 아니다. 그래서 이 표시는 "지워도 된다"가 아니라 "확인해볼 것"이라는 뜻이고,
    /// 실제 판단은 무게(RSS·프로세스 수)와 사람이 한다.
    ///
    /// **아는 프로젝트가 하나도 없으면 아무것도 표시하지 않는다.** 빈 집합은 "전부 고아"가 아니라
    /// "아직 모른다"는 뜻이다(기동 직후·state 로드 실패). 그걸 고아로 칠하면 표 전체가 빨개지고,
    /// 사람이 그 표시를 근거로 멀쩡한 세션을 죽인다. GC가 같은 상황에서 아무것도 안 지우는 것과
    /// 같은 보수성이다(`ServiceSession.orphans`).
    static func markOrphans(_ rows: [TmuxSessionRow],
                            projectWorkspaces: [String: String]) -> [TmuxSessionRow] {
        guard !projectWorkspaces.isEmpty else { return rows }
        return rows.map { row in
            // 남의 세션은 판정 대상이 아니다 — 우리 규약 밖이라 등록 여부를 물을 근거가 없다.
            guard let projectId = row.projectId else { return row }
            var marked = row
            marked.workspace = projectWorkspaces[projectId] ?? ""
            marked.isOrphan = projectWorkspaces[projectId] == nil
            return marked
        }
    }
}
