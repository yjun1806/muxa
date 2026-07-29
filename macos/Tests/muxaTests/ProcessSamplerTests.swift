import Foundation
import Testing
@testable import muxa

/// 세션 무게 계산의 판정(순수) — 프로세스 트리 표본 → CPU%·메모리·프로세스 수·작업 이름.
///
/// **이 숫자가 "죽여도 되나"의 1차 근거다**(YJ-6). 실측에서 빈 셸(10~19MB·2개)과 실제 작업
/// (164~986MB·15~24개)이 10배 이상 갈렸고, 그 분리가 고아 표시보다 신뢰할 만했다.
/// 틀린 무게는 사람이 986MB짜리 빌드를 "비어 보인다"며 죽이게 만든다.
struct ProcessSamplerTests {
    /// pid → (ppid, 이름, 누적 CPU 나노초, footprint 바이트)로 표본을 짓는다.
    private func snapshot(_ entries: [(pid_t, pid_t, String, UInt64, UInt64)],
                          uptime: TimeInterval) -> ProcessSnapshot {
        ProcessSnapshot(samples: entries.reduce(into: [:]) { acc, e in
            acc[e.0] = ProcessSample(pid: e.0, ppid: e.1, name: e.2, cpuNanos: e.3, footprintBytes: e.4)
        }, uptime: uptime)
    }

    /// 손자까지 합산한다 — tmux pane의 셸 밑에 claude가 있고 그 밑에 MCP 서버들이 산다.
    /// 자식만 세면 실제 작업의 대부분을 놓친다.
    @Test func sumsWholeTree() {
        let snap = snapshot([
            (100, 1, "zsh", 0, 10),
            (200, 100, "claude", 0, 100),
            (300, 200, "node", 0, 1000),
            (900, 1, "무관", 0, 99999),  // 다른 트리 — 섞이면 안 된다
        ], uptime: 0)
        let weight = ProcessSampler.weight(of: 100, current: snap, previous: nil)
        #expect(weight.processCount == 3)
        #expect(weight.footprintBytes == 1110)
    }

    /// 없는 pid(죽은 pane)는 0 — 표에서 빈 칸이 아니라 0으로 보여야 "안에 아무것도 없다"가 읽힌다.
    @Test func missingRootIsZero() {
        #expect(ProcessSampler.weight(of: 404, current: snapshot([], uptime: 0), previous: nil) == .zero)
        #expect(ProcessSampler.weight(of: nil, current: snapshot([], uptime: 0), previous: nil) == .zero)
    }

    /// CPU%는 **두 표본의 델타**다. 1초 동안 0.5초를 썼으면 50%.
    @Test func cpuPercentFromDelta() {
        let before = snapshot([(100, 1, "node", 1_000_000_000, 0)], uptime: 10)
        let after = snapshot([(100, 1, "node", 1_500_000_000, 0)], uptime: 11)
        let weight = ProcessSampler.weight(of: 100, current: after, previous: before)
        #expect(abs(weight.cpuPercent - 50) < 0.001)
    }

    /// 코어가 여럿이면 100%를 넘을 수 있다 — 활성 상태 보기와 같은 규약이라 자르지 않는다.
    @Test func cpuPercentMayExceedHundred() {
        let before = snapshot([(100, 1, "node", 0, 0)], uptime: 0)
        let after = snapshot([(100, 1, "node", 3_000_000_000, 0)], uptime: 1)
        #expect(ProcessSampler.weight(of: 100, current: after, previous: before).cpuPercent > 100)
    }

    /// **첫 표본에서는 CPU를 모른다 — 0으로 둔다.**
    /// 누적 시간을 프로세스 수명으로 나누면(ps의 %cpu가 그렇다) "지금 도는 중"이 아니라
    /// "평생 평균"이 나온다. 30분 전에 바빴던 유휴 프로세스가 바쁜 것처럼 보인다.
    @Test func firstSampleReportsZeroCPU() {
        let snap = snapshot([(100, 1, "node", 9_999_999_999, 500)], uptime: 10)
        let weight = ProcessSampler.weight(of: 100, current: snap, previous: nil)
        #expect(weight.cpuPercent == 0)
        #expect(weight.footprintBytes == 500) // 메모리는 한 표본으로 알 수 있다
    }

    /// 직전 표본에 없던 프로세스는 CPU에 기여하지 않는다 — 방금 태어난 것의 누적 시간을
    /// 통째로 이번 구간에 실으면 스파이크가 튄다.
    @Test func newProcessContributesNoCPU() {
        let before = snapshot([(100, 1, "zsh", 0, 0)], uptime: 0)
        let after = snapshot([(100, 1, "zsh", 0, 0), (200, 100, "node", 5_000_000_000, 0)], uptime: 1)
        #expect(ProcessSampler.weight(of: 100, current: after, previous: before).cpuPercent == 0)
    }

    /// 경과가 0이거나 뒤로 간 표본은 나누지 않는다(0으로 나누기 방어).
    @Test func nonPositiveElapsedYieldsZeroCPU() {
        let before = snapshot([(100, 1, "node", 0, 0)], uptime: 5)
        let after = snapshot([(100, 1, "node", 1_000_000_000, 0)], uptime: 5)
        #expect(ProcessSampler.weight(of: 100, current: after, previous: before).cpuPercent == 0)
    }

    /// 누적 시간이 줄어드는 표본(pid 재사용)은 음수 CPU를 만들지 않는다.
    @Test func pidReuseDoesNotYieldNegativeCPU() {
        let before = snapshot([(100, 1, "node", 9_000_000_000, 0)], uptime: 0)
        let after = snapshot([(100, 1, "node", 1_000_000_000, 0)], uptime: 1)
        #expect(ProcessSampler.weight(of: 100, current: after, previous: before).cpuPercent == 0)
    }

    /// 부모를 자기 자신으로 가리키는 표본에서도 멈춘다(무한 루프 방어).
    @Test func selfParentDoesNotLoop() {
        let snap = snapshot([(100, 100, "zsh", 0, 1)], uptime: 0)
        #expect(ProcessSampler.weight(of: 100, current: snap, previous: nil).processCount == 1)
    }

    /// 작업 이름은 셸을 걷어낸다 — `TerminalSession.workLabels`가 규약의 SSOT다.
    /// 셸만 있는 세션은 라벨이 비고, 그게 곧 "되찾을 것이 없다"는 뜻이다.
    @Test func labelsSkipShells() {
        let snap = snapshot([
            (100, 1, "zsh", 0, 0),
            (200, 100, "claude", 0, 0),
            (300, 200, "node", 0, 0),
        ], uptime: 0)
        let weight = ProcessSampler.weight(of: 100, current: snap, previous: nil)
        #expect(weight.labels == ["claude", "node"])

        let empty = snapshot([(100, 1, "zsh", 0, 0)], uptime: 0)
        #expect(ProcessSampler.weight(of: 100, current: empty, previous: nil).labels.isEmpty)
    }

    /// 같은 이름이 여럿이면 접는다 — 실측 세션엔 node가 여러 개다. 안 접으면 요약이 반복으로 찬다.
    @Test func labelsFoldDuplicates() {
        let snap = snapshot([
            (100, 1, "zsh", 0, 0),
            (200, 100, "node", 0, 0),
            (300, 100, "node", 0, 0),
            (400, 100, "esbuild", 0, 0),
        ], uptime: 0)
        #expect(ProcessSampler.weight(of: 100, current: snap, previous: nil).labels == ["node", "esbuild"])
    }

    /// 라벨은 개수를 제한한다 — 표의 한 칸에 24개를 쏟으면 아무것도 안 읽힌다.
    @Test func labelsRespectLimit() {
        let snap = snapshot([
            (100, 1, "zsh", 0, 0), (200, 100, "a", 0, 0), (300, 100, "b", 0, 0), (400, 100, "c", 0, 0),
        ], uptime: 0)
        #expect(ProcessSampler.weight(of: 100, current: snap, previous: nil, labelLimit: 2).labels == ["a", "b"])
    }
}
