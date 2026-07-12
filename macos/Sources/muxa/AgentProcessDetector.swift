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
