import Darwin
import Foundation

/// 세션이 지금 **어느 GUI에 보이고 있는가**.
///
/// tmux의 `session_attached`(0/1)만으로는 부족하다. muxa 세션은 인스턴스가 여럿이고(릴리스 + 워크트리별
/// 개발빌드) 사용자가 터미널에서 직접 붙을 수도 있다. "누가 보고 있나"를 갈라야 무엇을 죽여도 되는지 안다.
enum SessionAttachment: Equatable {
    /// **붙을 탭조차 없다** — 이 창이 찾아야 할 상태. 되찾으려면 새로 열어야 한다.
    case detached
    /// **탭은 있는데 지금 붙어 있지 않다** — 앱을 막 켰거나 사용자가 detach한 경우.
    /// 그 탭으로 가면 다시 붙는다. `detached`와 구분해야 한다: 이쪽은 잃어버린 세션이 아니다.
    case idleTab
    /// 이 앱의 탭으로 보이고 있다.
    case thisApp
    /// 다른 muxa 인스턴스가 보고 있다. **pid를 함께 들고 다닌다** — 그 앱을 앞으로 가져오는 데 쓴다.
    /// 조상 추적이 어차피 찾아낸 값이라 버릴 이유가 없다.
    case otherApp(name: String, pid: pid_t)
    /// muxa가 아닌 터미널에서 직접 붙었다.
    case external

    var text: String {
        switch self {
        case .detached: return "분리됨"
        case .idleTab: return "미연결"
        case .thisApp: return "이 앱"
        case .otherApp(let name, _): return name
        case .external: return "외부 터미널"
        }
    }

    /// 되찾을 자리가 있는가 — 탭이 있으면(붙어 있든 아니든) 잃어버린 세션이 아니다.
    var hasHome: Bool { self != .detached }
}

/// "이 세션은 누구 것인가"의 판정(순수).
enum SessionOwnership {
    // MARK: 소켓 → 그 인스턴스의 지원 폴더

    /// 소켓의 짝이 되는 지원 폴더 이름. 규약 밖 소켓이면 nil.
    ///
    /// 소켓과 지원 폴더는 같은 `AppInfo.devKey`에서 파생돼 **1:1로 대응한다**(실측 검증):
    ///
    ///     muxa-services                  ↔ muxa
    ///     muxa-services-muxa-2b410b      ↔ muxa-dev-muxa-2b410b
    ///
    /// 이 대응이 필요한 이유: 고아 판정을 **소켓별로** 해야 한다. 자기 인스턴스의 등록으로 남의 소켓
    /// 세션을 재면 전부 미등록이 된다 — 실측에서 41개 중 40개가 그렇게 잘못 고아로 표시됐다.
    /// 짝을 못 찾으면 **판정하지 않는다**(nil). 지어낸 기준으로 "지워도 된다"고 말하는 것이 최악이다.
    static func supportFolder(for socket: String) -> String? {
        if socket == TmuxSocketScanner.releaseSocket { return "muxa" }
        let prefix = TmuxSocketScanner.releaseSocket + "-"
        guard socket.hasPrefix(prefix) else { return nil }
        let folder = "muxa-dev-" + socket.dropFirst(prefix.count)
        return isSafePathComponent(folder) ? folder : nil
    }

    /// 경로 성분으로 안전한가 — 이 값은 **디렉터리 목록에서 온 파일 이름**이라 신뢰 경계 밖이다.
    /// `..`나 `/`가 섞이면 지원 폴더 밖의 파일을 읽게 된다. `/tmp/tmux-<uid>`가 0700이라 실제
    /// 위험은 낮지만, 파일명을 경로에 붙이는 자리에는 검증이 있어야 한다
    /// (`ServiceSession.isValidId`가 같은 이유로 존재한다).
    private static func isSafePathComponent(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("..")
    }

    /// 그 인스턴스가 등록한 **projectId → 워크스페이스 이름**. 읽을 수 없으면 nil(= 판정 불가).
    ///
    /// 키는 **`Project.id`다 — `Workspace.id`가 아니다.** 세션명 `muxa__<projectId>__…`의 그 값이고
    /// GC(`ServiceSession.orphans`)도 같은 값을 쓴다(`collectKnownProjectIds`).
    ///
    /// 값(워크스페이스 이름)은 표를 묶는 데 쓴다 — 세션이 41개쯤 되면 폴더명만으로는 어느 작업
    /// 묶음의 것인지 한눈에 안 들어온다.
    static func projectWorkspaces(inSupportFolder folder: String) -> [String: String]? {
        let path = NSHomeDirectory() + "/Library/Application Support/\(folder)/state.v4.json"
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let workspaces = root["workspaces"] as? [[String: Any]] else { return nil }
        var byProject: [String: String] = [:]
        for workspace in workspaces {
            let name = workspace["name"] as? String ?? ""
            for project in workspace["projects"] as? [[String: Any]] ?? [] {
                if let id = project["id"] as? String { byProject[id] = name }
            }
        }
        return byProject
    }

    // MARK: 연결 상태 — 어느 GUI가 보고 있나

    /// `list-clients -F '#{client_session}|#{client_pid}'` → 세션별 클라이언트 pid(순수).
    static func parseClients(_ raw: String) -> [String: [pid_t]] {
        var bySession: [String: [pid_t]] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.components(separatedBy: "|")
            guard fields.count >= 2, !fields[0].isEmpty, let pid = pid_t(fields[1]) else { continue }
            bySession[fields[0], default: []].append(pid)
        }
        return bySession
    }

    /// 붙어 있는 클라이언트들의 조상을 거슬러 **누가 보고 있는지** 가린다(순수).
    ///
    /// 클라이언트 프로세스의 부모 체인에 앱이 있다: `tmux → zsh → login → muxa`(실측).
    /// **내 앱이 우선이다** — 여럿이 붙어 있으면 "내가 보고 있다"가 가장 중요한 사실이다.
    /// - Parameter hasOwnTab: 이 앱의 **탭이 이 세션을 참조하는가**. 클라이언트가 없어도 탭이 있으면
    ///   `.idleTab`이다 — 앱을 막 켰거나 사용자가 detach한 경우로, 그 탭으로 가면 다시 붙는다.
    ///   "붙을 탭조차 없는" 진짜 분리와는 되찾을 수 있느냐가 다르다.
    static func attachment(clientPids: [pid_t], snapshot: ProcessSnapshot,
                           ownAppPid: pid_t, hasOwnTab: Bool = false) -> SessionAttachment {
        // **클라이언트가 하나라도 있으면 분리가 아니다.** 조상 추적이 실패해도(방금 죽은 pid, 표본 누락)
        // 최소 `.external`로 둔다 — 붙어 있는 걸 "분리됨"이라 말하면 사람이 남의 화면을 죽인다.
        // 반대 실수(안 붙은 걸 붙었다고 하는 것)는 안 죽이고 넘어가는 것뿐이라 훨씬 싸다.
        guard !clientPids.isEmpty else { return hasOwnTab ? .idleTab : .detached }
        var best: SessionAttachment = .external
        for pid in clientPids {
            switch owner(of: pid, in: snapshot, ownAppPid: ownAppPid) {
            case .thisApp: return .thisApp // 더 볼 것 없다
            case .otherApp(let name, let appPid): best = .otherApp(name: name, pid: appPid)
            // `owner`는 이 셋을 내놓지 않는다(추적 결과는 앱이거나 아니거나다).
            case .external, .detached, .idleTab: continue
            }
        }
        return best
    }

    /// 한 클라이언트의 조상에서 앱을 찾는다. 표본에 없으면 `.detached`
    /// (호출부가 그걸 `.external`로 승격한다 — 위 주석).
    private static func owner(of clientPid: pid_t, in snapshot: ProcessSnapshot,
                              ownAppPid: pid_t) -> SessionAttachment {
        var pid = clientPid
        var hops = 0
        guard snapshot.samples[pid] != nil else { return .detached }
        while pid > 1, hops < maxHops {
            guard let sample = snapshot.samples[pid] else { break }
            if sample.pid == ownAppPid { return .thisApp }
            if isMuxaApp(sample.name) { return .otherApp(name: sample.name, pid: sample.pid) }
            if sample.ppid == sample.pid { break } // 자기참조 방어
            pid = sample.ppid
            hops += 1
        }
        return .external
    }

    /// muxa 앱 프로세스인가 — 릴리스는 `muxa`, 개발빌드는 `muxa-dev-<슬러그>`(`scripts/app-identity.sh`).
    /// 훅 CLI(`muxa-notify`)는 앱이 아니므로 뺀다.
    private static func isMuxaApp(_ name: String) -> Bool {
        name == "muxa" || (name.hasPrefix("muxa-dev") && name != "muxa-notify")
    }

    /// 조상 추적 상한 — 체인은 실측에서 4단계다. 순환이 있어도 여기서 멈춘다.
    private static let maxHops = 32
}
