import Darwin
import Foundation

/// 한 프로세스의 표본 — 트리를 세우는 데 필요한 것(ppid·이름)과 무게(CPU·메모리).
struct ProcessSample: Equatable {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    /// **누적** CPU 시간(나노초). 이 값 자체는 무의미하고 두 표본의 차이가 CPU%가 된다.
    let cpuNanos: UInt64
    /// 활성 상태 보기의 '메모리' 열과 같은 지표(`phys_footprint`).
    /// `resident_size`가 아니다 — 실측(muxa.app)에서 resident 347MB · footprint 2838MB였고
    /// 활성 상태 보기·top이 보여주는 값은 후자다. 사용자가 두 창을 나란히 놓고 볼 수 있어야 한다.
    let footprintBytes: UInt64
}

/// 한 시점의 프로세스 트리.
struct ProcessSnapshot: Equatable {
    let samples: [pid_t: ProcessSample]
    let childrenOf: [pid_t: [pid_t]]
    /// 단조 증가 시계(초) — CPU 델타를 나눌 분모. 벽시계는 시각 변경·NTP 보정에 흔들린다.
    let uptime: TimeInterval

    init(samples: [pid_t: ProcessSample], uptime: TimeInterval) {
        self.samples = samples
        self.uptime = uptime
        var children: [pid_t: [pid_t]] = [:]
        // 자기 자신을 부모로 가리키는 표본은 잇지 않는다(트리 순회의 무한 루프 방어).
        for sample in samples.values where sample.ppid != sample.pid {
            children[sample.ppid, default: []].append(sample.pid)
        }
        // **pid 순으로 고정한다.** 딕셔너리 순회는 순서가 없어서, 정렬하지 않으면 같은 트리인데도
        // 폴링(2초)마다 "안에 도는 것" 라벨의 순서가 뒤바뀐다.
        childrenOf = children.mapValues { $0.sorted() }
    }
}

/// 세션 하나의 무게 — "죽여도 되나"의 1차 근거(YJ-6).
struct SessionWeight: Equatable {
    var cpuPercent: Double
    var footprintBytes: UInt64
    var processCount: Int
    /// 안에 도는 것들의 이름(셸 제외, 중복 접힘).
    var labels: [String]

    /// 죽은 pane·사라진 프로세스. 빈 칸이 아니라 0으로 보여야 "안에 아무것도 없다"가 읽힌다.
    static let zero = SessionWeight(cpuPercent: 0, footprintBytes: 0, processCount: 0, labels: [])
}

/// 프로세스 트리를 재서 세션의 무게를 낸다.
///
/// `ps` 셸아웃을 쓰지 않는다. 두 가지 이유가 있다:
///  1. `ps`의 `%cpu`는 **프로세스 수명 전체의 평균**이라 "지금 도는 중"을 말해주지 않는다.
///     30분 전에 바빴던 유휴 프로세스가 바쁜 것처럼 보인다.
///  2. 폴링(2초)마다 프로세스를 띄우는 비용이 붙는다. 커널에 직접 묻는 편이 싸고 정확하다
///     (`AgentProcessDetector`가 같은 이유로 같은 API를 쓴다).
enum ProcessSampler {
    /// 트리를 따라 내려갈 최대 깊이. 셸 → claude → MCP 서버 → 그 자식 정도가 실측의 최대치다.
    static let maxDepth = 8

    /// 표에 보여줄 작업 이름 개수 — 한 칸에 24개를 쏟으면 아무것도 안 읽힌다.
    static let defaultLabelLimit = 3

    // MARK: 판정(순수)

    /// `root`와 그 모든 자손(너비 우선). root가 없으면 빈 배열.
    static func descendants(of root: pid_t, in snapshot: ProcessSnapshot,
                            maxDepth: Int = maxDepth) -> [ProcessSample] {
        var visited: Set<pid_t> = []
        var found: [ProcessSample] = []
        var frontier = [root]
        var depth = 0
        while !frontier.isEmpty, depth < maxDepth {
            var next: [pid_t] = []
            for pid in frontier {
                guard visited.insert(pid).inserted, let sample = snapshot.samples[pid] else { continue }
                found.append(sample)
                next.append(contentsOf: snapshot.childrenOf[pid] ?? [])
            }
            frontier = next
            depth += 1
        }
        return found
    }

    /// 세션 pane의 프로세스 트리 무게(순수).
    ///
    /// - Parameter previous: 직전 표본. **없으면 CPU는 0으로 둔다** — 누적 시간을 수명으로 나누면
    ///   `ps`와 같은 "평생 평균"이 나와 유휴 프로세스가 바쁜 것처럼 보인다. 다음 폴링이 채운다.
    static func weight(of root: pid_t?, current: ProcessSnapshot, previous: ProcessSnapshot?,
                       labelLimit: Int = defaultLabelLimit) -> SessionWeight {
        guard let root else { return .zero }
        let tree = descendants(of: root, in: current)
        guard !tree.isEmpty else { return .zero }

        var cpuPercent = 0.0
        if let previous, current.uptime > previous.uptime {
            let elapsedNanos = (current.uptime - previous.uptime) * 1e9
            let delta = tree.reduce(UInt64(0)) { acc, sample in
                // 직전 표본에 없던 프로세스는 기여하지 않는다 — 방금 태어난 것의 누적 시간을
                // 통째로 이번 구간에 실으면 스파이크가 튄다. pid 재사용으로 값이 줄어든 경우도 같다.
                guard let before = previous.samples[sample.pid],
                      sample.cpuNanos > before.cpuNanos else { return acc }
                return acc &+ (sample.cpuNanos - before.cpuNanos)
            }
            cpuPercent = Double(delta) / elapsedNanos * 100
        }

        return SessionWeight(
            cpuPercent: cpuPercent,
            footprintBytes: tree.reduce(UInt64(0)) { $0 &+ $1.footprintBytes },
            processCount: tree.count,
            // 셸·버전 이름을 걷어내는 규약의 SSOT는 `TerminalSession`이다 — 두 벌 쓰면 갈라진다.
            labels: TerminalSession.workLabels(foreground: tree.map(\.name), limit: labelLimit)
        )
    }

    // MARK: 표본 뜨기(부작용)

    /// 지금 이 머신의 프로세스 트리 한 장.
    ///
    /// pid 열거는 `AgentProcessDetector.allPids`가 소유한다 — `proc_listallpids`의 반환값 계약이
    /// 헤더 주석과 다르고(개수 vs 바이트) 그 함정을 두 곳에 적으면 한쪽만 고쳐진다.
    /// 잘린 목록의 증상은 여기서 "세션 대부분이 프로세스 0개·0MB"로 나타난다 — 사람이 그 표를 보고
    /// "비었네" 하며 죽이는 길이다.
    static func snapshot() -> ProcessSnapshot {
        let uptime = ProcessInfo.processInfo.systemUptime
        var samples: [pid_t: ProcessSample] = [:]
        for pid in AgentProcessDetector.allPids() {
            guard let info = bsdInfo(pid) else { continue }
            let usage = rusage(pid)
            samples[pid] = ProcessSample(
                pid: pid,
                ppid: pid_t(bitPattern: info.pbi_ppid),
                name: displayName(pid, comm(info)),
                cpuNanos: usage.map { machToNanos($0.ri_user_time &+ $0.ri_system_time) } ?? 0,
                footprintBytes: usage?.ri_phys_footprint ?? 0
            )
        }
        return ProcessSnapshot(samples: samples, uptime: uptime)
    }

    /// mach absolute time → 나노초.
    ///
    /// **커널이 주는 CPU 시간은 나노초가 아니다.** 실측(Apple Silicon, timebase 125/3)에서 나노초로
    /// 읽으면 0.9%가 나온 프로세스가 변환 후 35.4%였고, 그게 `ps`·`top`과 일치했다.
    static func machToNanos(_ ticks: UInt64) -> UInt64 {
        ticks / UInt64(timebase.denom) * UInt64(timebase.numer)
            + ticks % UInt64(timebase.denom) * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        // 못 읽으면 1:1로 둔다(변환하지 않는 것과 같다) — 0으로 나누지 않는 게 우선이다.
        return info.denom == 0 ? mach_timebase_info_data_t(numer: 1, denom: 1) : info
    }()

    /// 표에 쓸 이름. comm이 **인터프리터**일 때만 argv[0]을 다시 묻는다.
    ///
    /// `claude`는 node 스크립트라 comm이 `node`로 잡히고, 그러면 라벨이 "node"뿐이라 뭐가 도는지
    /// 알 수 없다(`AgentProcessDetector.argv0`가 같은 함정에서 배운 것). 그렇다고 전부에 argv0를
    /// 부르면 sysctl 2회 + 수십 KB 할당이 붙는다 — 실측(프로세스 273개)에서 comm만 0.1ms인데
    /// argv0 전체는 6.2ms로 60배다. 폴링에 상시로 얹기엔 비싸서 **필요할 때만 지불한다.**
    private static func displayName(_ pid: pid_t, _ comm: String) -> String {
        guard interpreters.contains(comm) else { return comm }
        return AgentProcessDetector.argv0(pid) ?? comm
    }

    /// 스크립트를 대신 실행해 자기 이름을 가리는 런타임들.
    private static let interpreters: Set<String> = [
        "node", "deno", "bun", "python", "python3", "ruby", "perl", "java",
    ]

    /// CPU 시간 + phys_footprint. 죽었거나 접근 불가면 nil.
    private static func rusage(_ pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return ok == 0 ? info : nil
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    /// 고정 크기 C 배열(`pbi_comm`)을 첫 null까지만 읽는다 — 이름이 꽉 차면 종단 null이 없다.
    private static func comm(_ info: proc_bsdinfo) -> String {
        withUnsafeBytes(of: info.pbi_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
