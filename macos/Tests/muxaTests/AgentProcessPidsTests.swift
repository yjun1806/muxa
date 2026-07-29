import Darwin
import Foundation
import Testing
@testable import muxa

/// **부작용 경계의 회귀 고정** — 프로세스 열거가 트리를 자르지 않는가.
///
/// 이 계층에 테스트가 없던 탓에 오늘 두 결함이 실기동에서야 드러났다. 둘 다 순수 로직은 멀쩡했고
/// **입력이 잘려 있었다**:
///  1. `proc_listallpids`의 반환값을 바이트로 오해 → 1071개 중 268개만 봄
///  2. `proc_pidinfo`가 root 소유 프로세스에서 실패 → 조상 체인이 `login`에서 끊김
///
/// 실제 머신을 재므로 정확한 수는 고정할 수 없다. 대신 **잘림이 걸리는 불변식**을 건다.
struct AgentProcessPidsTests {
    @Test func seesSelf() {
        #expect(AgentProcessDetector.allProcesses().contains { $0.pid == getpid() })
    }

    /// macOS에서 프로세스가 100개 미만인 경우는 없다. 1/4로 잘려도 넘길 만큼 느슨하지만,
    /// 열거가 통째로 비거나 반환값 해석이 무너지는 회귀는 여기서 걸린다.
    @Test func seesWholeMachine() {
        #expect(AgentProcessDetector.allProcesses().count > 100)
    }

    /// **root 소유 프로세스가 보여야 한다.** `launchd`(pid 1)가 그렇다 — `proc_pidinfo` 기반으로
    /// 되돌아가면 여기서 빠지고, 그 순간 muxa 탭의 조상 체인이 `login`에서 끊긴다.
    @Test func seesRootOwnedProcesses() {
        let all = AgentProcessDetector.allProcesses()
        #expect(all.contains { $0.pid == 1 })
    }

    /// **조상 체인이 root 프로세스를 관통한다.** 내 pid에서 부모를 거슬러 오르면 launchd(1)에 닿아야
    /// 한다 — 중간에 root 소유 프로세스가 있어도 끊기지 않는다는 뜻이다.
    @Test func ancestorChainReachesLaunchd() {
        let byPid = Dictionary(AgentProcessDetector.allProcesses().map { ($0.pid, $0.ppid) },
                               uniquingKeysWith: { a, _ in a })
        var pid = getpid()
        var hops = 0
        while pid > 1, hops < 64, let parent = byPid[pid] {
            pid = parent
            hops += 1
        }
        #expect(pid == 1)
    }

    /// 자기 자신을 뿌리로 삼으면 자기 이름이 나온다 — 트리 순회가 실제로 도는지.
    @Test func descendantsIncludeSelfName() {
        #expect(!AgentProcessDetector.descendantNames(of: getpid()).isEmpty)
    }

    /// 스냅샷도 같은 열거를 쓰므로 같은 불변식을 만족해야 한다 —
    /// 잘리면 세션 대부분이 "프로세스 0개·0MB"로 떠서 사람이 "비었네" 하며 죽인다.
    @Test func snapshotCoversWholeMachine() {
        let snapshot = ProcessSampler.snapshot()
        #expect(snapshot.samples.count > 100)
        #expect(snapshot.samples[1] != nil) // root 소유 launchd
        #expect(snapshot.samples[getpid()] != nil)
    }
}
