import Darwin
import Foundation
import Testing
@testable import muxa

/// **회귀 고정** — `proc_listallpids`의 반환값은 pid 개수다(헤더 주석은 "number of bytes"라고 한다).
///
/// 바이트로 오해해 `sizeof(pid_t)`로 나누면 프로세스의 1/4만 잡힌다(실측: 1071개 중 268개).
/// 그 잘린 목록이 `descendantNames` → `TerminalSession.shouldDetach`로 흘러가 "안에 셸뿐"이라
/// 판정하면, 30분 돌던 빌드가 있는 탭이 ⌘W에 그냥 죽는다.
///
/// 실제 머신을 재므로 정확한 수는 고정할 수 없다. 대신 **잘림을 잡는 하한**을 건다.
struct AgentProcessPidsTests {
    @Test func allPidsIncludesSelf() {
        #expect(AgentProcessDetector.allPids().contains(getpid()))
    }

    /// macOS에서 프로세스가 100개 미만인 경우는 없다. 1/4로 잘려도 넘길 만큼 느슨한 하한이지만,
    /// 버퍼가 통째로 비거나 반환값 해석이 무너지는 회귀는 여기서 걸린다.
    @Test func allPidsSeesWholeMachine() {
        #expect(AgentProcessDetector.allPids().count > 100)
    }

    /// 자기 자신을 뿌리로 삼으면 자기 이름이 나온다 — 트리 순회가 실제로 도는지.
    @Test func descendantsIncludeSelfName() {
        #expect(!AgentProcessDetector.descendantNames(of: getpid()).isEmpty)
    }
}
