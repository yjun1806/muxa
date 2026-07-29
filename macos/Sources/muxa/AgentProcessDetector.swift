import Darwin

/// 패인(pty)에서 특정 에이전트 프로세스가 돌고 있는지 감지한다 — 제로설정 세션 재개의 "탐지" 단계. (cmux식)
///
/// pty의 현재 foreground pid에서 **부모 방향으로 셸(rootPid)까지** 거슬러 오르며 comm을 검사한다.
/// claude가 전면이면 그 자신이, claude가 띄운 자식(툴 실행 등)이 전면이면 부모 사슬에서 claude가 잡힌다.
/// 전 프로세스 순회 없이 pid별 조회(`proc_pidinfo`)만 하므로, 저장(snapshot)이 잦아도 비용이 거의 없다.
enum AgentProcessDetector {
    /// `startPid`에서 부모로 올라가며(최대 `maxHops`) comm이 `commNames`에 있는 프로세스를 찾으면 true.
    /// `rootPid`(셸)에 닿거나 pid가 1 이하가 되면 멈춘다 — 셸 위(muxa 자신)는 보지 않는다.
    static func agentRunning(
        commNames: Set<String>,
        from startPid: pid_t,
        upTo rootPid: pid_t,
        maxHops: Int = 32
    ) -> Bool {
        var pid = startPid
        var hops = 0
        while pid > 1, hops < maxHops {
            guard let info = bsdInfo(pid) else { return false }
            if commNames.contains(comm(info)) { return true }
            if pid == rootPid { return false } // 셸 도달 — 그 위는 우리 프로세스
            let parent = pid_t(bitPattern: info.pbi_ppid)
            if parent == pid { return false } // 자기참조 방어(루프 차단)
            pid = parent
            hops += 1
        }
        return false
    }

    /// `root`의 **모든 자손** 프로세스 이름(자기 자신 포함). 트리를 아래로 훑는다.
    ///
    /// 부모 방향 훑기(`agentRunning`)와 달리 여기서는 "이 pty 안에서 뭐가 돌고 있나"를 묻는다.
    /// TTY의 포그라운드 그룹만 보면 부족하다 — 셸 래퍼가 자체 pty를 만들어 실제 셸을 그 안에서
    /// 돌리면 진짜 작업이 그 아래 숨는다(실측). 전 프로세스 목록을 한 번 읽어 트리를 세운다.
    static func descendantNames(of root: pid_t, maxDepth: Int = 8) -> [String] {
        var childrenOf: [pid_t: [pid_t]] = [:]
        var nameOf: [pid_t: String] = [:]
        for proc in allProcesses() {
            // **argv[0]을 먼저 본다.** comm은 실행 바이너리 이름이라, node 스크립트인 `claude`가
            // `node`로 잡힌다 — 목록에 "node"가 뜨면 뭐가 도는지 알 수 없다. 못 읽으면 comm으로 폴백.
            nameOf[proc.pid] = argv0(proc.pid) ?? proc.comm
            childrenOf[proc.ppid, default: []].append(proc.pid)
        }

        var names: [String] = []
        var frontier = [root]
        var depth = 0
        while !frontier.isEmpty, depth < maxDepth {
            var next: [pid_t] = []
            for pid in frontier {
                if let name = nameOf[pid] { names.append(name) }
                next.append(contentsOf: childrenOf[pid] ?? [])
            }
            frontier = next
            depth += 1
        }
        return names
    }

    /// 이 머신의 **모든** 프로세스(pid·ppid·이름) — `ps`와 같은 방법(`sysctl KERN_PROC_ALL`).
    ///
    /// **`proc_listallpids` + `proc_pidinfo` 조합을 쓰지 않는다.** 둘 다 조용히 트리를 자른다:
    ///
    ///  1. `proc_listallpids`의 반환값은 **pid 개수**다(헤더 주석은 "number of bytes"라고 한다).
    ///     문서를 믿고 나누면 프로세스의 1/4만 본다 — 실측에서 1071개 중 268개였다.
    ///  2. `proc_pidinfo(PROC_PIDTBSDINFO)`는 **root 소유 프로세스에서 실패한다.** `/usr/bin/login`이
    ///     그렇고, muxa 탭의 조상 체인(`tmux → sh → login → muxa`)이 정확히 거기서 끊긴다.
    ///
    /// 증상은 같다: 트리가 잘려 **pane 안에서 도는 작업을 못 본다.** 그러면
    /// `TerminalSession.shouldDetach`가 "셸뿐"이라 판정해 30분 돌던 빌드가 있는 탭을 ⌘W에 죽인다 —
    /// 이 파일이 막으려던 바로 그 사고다. sysctl은 한 번의 호출로 전부 준다(실측 7.2ms, 1103개).
    static func allProcesses() -> [(pid: pid_t, ppid: pid_t, comm: String)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        // 묻는 사이에 새로 뜬 프로세스 몫으로 여유를 둔다(부족하면 sysctl이 ENOMEM으로 실패한다).
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = buffer.count * stride
        guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [] }
        return buffer.prefix(size / stride).map { proc in
            let comm = withUnsafeBytes(of: proc.kp_proc.p_comm) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            return (proc.kp_proc.p_pid, proc.kp_eproc.e_ppid, comm)
        }
    }

    /// pid가 실행 중인 **바이너리 이름**(comm). 죽었거나 접근 불가면 nil.
    ///
    /// `descendantNames`와 달리 argv[0]을 보지 않는다. 그건 node 스크립트(`claude`)를 구별하려는
    /// 장치인데, 그 대가로 `KERN_PROCARGS2` sysctl을 두 번 돌리고 수십 KB를 할당한다.
    /// **바이너리를 이름으로 묻는 자리**(tmux가 붙어 있나)에는 comm이 더 싸고 더 안정적이다 —
    /// `proc_pidinfo` 한 번이면 끝나고, 폴링으로 반복 호출된다.
    static func command(of pid: pid_t) -> String? {
        guard let info = bsdInfo(pid) else { return nil }
        return comm(info)
    }

    /// pid가 **스스로를 부르는 이름**(argv[0]). 실패하면 nil.
    ///
    /// `comm`(실행 바이너리 이름)으로는 부족하다. `claude`는 node 스크립트라 comm이 `node`로 잡히고,
    /// 그러면 목록에 "node"가 떠서 **뭐가 도는지 알 수 없다**(실측). `ps`가 보여주는 `claude`는 argv[0]다.
    ///
    /// KERN_PROCARGS2 레이아웃: `[argc: Int32][exec_path\0][정렬 패딩\0…][argv0\0][argv1\0]…`
    static func argv0(_ pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        let header = MemoryLayout<Int32>.size
        // exec_path를 건너뛰고(첫 NUL까지), 이어지는 정렬 패딩(연속 NUL)도 건너뛰면 argv[0]이 나온다.
        var i = header
        while i < size, buffer[i] != 0 { i += 1 }
        while i < size, buffer[i] == 0 { i += 1 }
        guard i < size else { return nil }

        var end = i
        while end < size, buffer[end] != 0 { end += 1 }
        guard end > i else { return nil }
        return String(decoding: buffer[i..<end], as: UTF8.self)
    }

    /// pid의 BSD 프로세스 정보(ppid·comm 포함). 죽었거나 접근 불가면 nil.
    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return ret == size ? info : nil
    }

    /// 고정 크기 C char 배열(pbi_comm, MAXCOMLEN)을 Swift 문자열로. 종단 null이 없을 수도 있어(정확히 꽉 찬 이름)
    /// 버퍼 크기를 넘겨 읽지 않도록 첫 null 전까지만 UTF-8로 해석한다.
    private static func comm(_ info: proc_bsdinfo) -> String {
        withUnsafeBytes(of: info.pbi_comm) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
