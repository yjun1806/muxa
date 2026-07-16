import Bonsplit
import Foundation

/// 스크립트 = 프로젝트에 등록된 **끝이 있는 명령**(`make build`·`pnpm test` 등).
/// 서비스(Service.swift)와 반대 축이다 — 서비스는 끝이 없는 프로세스(tmux·도크·▶),
/// 스크립트는 일반 탭에서 1회 돌고 끝나면 소멸한다:
/// 성공(exit 0) → 프로세스 종료 → close_surface_cb → 탭 자동 닫힘.
/// 실패 → `exec -l $SHELL`로 셸 전환 → 탭 잔류, 에러 로그를 그 자리에서 본다.
///
/// `ProjectScript`(ProjectScripts.swift:42)와 혼동 금지 — 그쪽은 package.json·Makefile·scripts/
/// **디렉터리 스캔 후보**(휘발, 목록 표시용)이고, 사용자가 **등록**하면 이 Script(영속,
/// `Project.scripts`에 실려 저장)로 승격된다.
struct Script: Codable, Identifiable, Equatable {
    let id: String
    var name: String // 표시 이름 ("build")
    var command: String // 실행 명령 ("make build")
}

/// Script → ghostty `command` 필드에 실을 **래퍼 명령 문자열** 조립(순수).
///
/// ghostty의 command는 `exec -l <cmd>`로 태워 **단일 실행 파일**만 받는다 — 복합 명령은
/// `/bin/sh -c '…'`로 감싸야 한다(TerminalSession.execCommand:107-112와 같은 이유·같은 레시피).
/// 래퍼가 지키는 것 세 가지:
///  1. 사용자 명령은 **로그인 셸(-l)**로 실행 — .app은 로그인 PATH를 상속하지 않아(launchd 소속)
///     안 감싸면 `pnpm` 등이 `command not found`로 즉사한다(CLAUDE.md 규약).
///  2. exit code를 muxa-notify(`script-exit --code`)로 앱에 보고 — muxa-notify는 모든 실패가
///     exit 0(fire-and-forget)이라 소켓이 죽어 있어도 래퍼를 죽이지 않는다. 소켓 경로는
///     하드코딩하지 않고 env(`$MUXA_SOCK`, TermView가 주입)로만 해석한다 — 개발빌드는
///     워크트리별로 소켓 경로가 다르다.
///  3. 성공(0)이면 그대로 종료 → 탭 자동 닫힘. 실패면 `exec -l $SHELL` → 탭 잔류.
///     `exec -l`은 POSIX 표준이 아니라 bash/zsh 빌트인이다 — macOS `/bin/sh`가 bash라 동작한다.
enum ScriptRunCommand {
    /// 인용은 전부 `ShellQuote.single` — 사용자 명령(작은따옴표·공백·`$` 포함 가능)과
    /// notify 경로(앱 위치에 공백 가능)를 셸 코드에 안전하게 보간한다.
    static func wrap(command: String, tabId: String, notifyPath: String) -> String {
        // MUXA_TAB_ID는 TermView가 서피스 env로 이미 심지만(TermView.swift:92-101), 프레임의
        // 수신 키이므로 래퍼가 한 번 더 명시한다 — env 상속에 기대지 않아 이 함수 혼자서도
        // 결정론적이고, 테스트가 문자열만으로 배달 키를 검증할 수 있다.
        let script = "\"${SHELL:-/bin/zsh}\" -l -c \(ShellQuote.single(command)); s=$?; "
            + "MUXA_TAB_ID=\(ShellQuote.single(tabId)) \(ShellQuote.single(notifyPath)) "
            + "script-exit --code \"$s\"; "
            + "[ \"$s\" -eq 0 ] || exec -l \"${SHELL:-/bin/zsh}\""
        return "/bin/sh -c \(ShellQuote.single(script))"
    }
}

/// 실행 1회의 상태(순수 값) — 푸터 칩·팝오버가 관측한다.
///
/// 저장 키는 **scriptId**(탭 생존과 분리) — 성공 프레임(script-exit)과 탭 자동 닫힘
/// (close_surface_cb)이 메인 큐에서 경합해도, 탭이 먼저 닫혔다고 결과가 버려지지 않는다.
struct ScriptRun: Equatable {
    enum RunState: Equatable {
        case running
        /// code nil = 프레임 유실 폴백(⌘W·소켓 유실로 exit code를 끝내 못 받음) —
        /// **성공으로 단정하지 않는다**(칩이 ✓를 지어내면 안 된다).
        case finished(code: Int32?, duration: TimeInterval)
    }

    let scriptId: String
    let tabId: TabID
    let name: String
    let startedAt: Date
    var state: RunState
}

// MARK: 전이 규칙(순수) — 프레임 도착과 탭 닫힘이 어느 순서로 와도 결과가 뒤집히지 않는다

extension ScriptRun {
    /// script-exit 프레임 도착 전이. 세 경우를 순서 무관하게 수렴시킨다:
    ///  - .running → .finished(code) — 정상 경로(프레임이 닫힘보다 먼저).
    ///  - .finished(code: nil) → code만 덮어쓴다 — 폴백 선마감(탭이 먼저 닫힘) 후 늦은 프레임.
    ///    duration은 선마감 값을 유지한다(닫힘 시점이 실제 종료에 더 가깝고, 프레임 도착은 큐 지연을 탄다).
    ///  - 이미 code가 확정된 run은 그대로 — 중복 프레임은 첫 판정을 못 뒤집는다.
    func receivingExit(code: Int32, at now: Date) -> ScriptRun {
        var next = self
        switch state {
        case .running:
            next.state = .finished(code: code, duration: now.timeIntervalSince(startedAt))
        case .finished(let existing, let duration):
            guard existing == nil else { return self }
            next.state = .finished(code: code, duration: duration)
        }
        return next
    }

    /// 탭 닫힘 폴백 마감. 프레임 없이 닫히면(⌘W·소켓 유실) code nil로 마감한다 —
    /// **성공으로 단정하지 않는다.** 이미 finished면 무동작(프레임이 먼저 온 정상 경로를 안 덮는다).
    func closingFallback(at now: Date) -> ScriptRun {
        guard case .running = state else { return self }
        var next = self
        next.state = .finished(code: nil, duration: now.timeIntervalSince(startedAt))
        return next
    }
}

// MARK: 표시 판정용 파생값(순수) — 칩(ScriptChipMode)·잔류 해제가 같은 정의를 쓴다

extension ScriptRun {
    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// 실패 **확정**(code 있고 ≠0)만 — code nil(결과 미상)은 실패로 단정하지 않는다
    /// (✓를 안 지어내는 것과 대칭으로, ✗도 안 지어낸다).
    var isFailure: Bool {
        if case .finished(let code, _) = state, let code, code != 0 { return true }
        return false
    }

    /// 새 실행이 시작될 때 레지스트리에서 치울 잔류(finished) 엔트리를 걸러낸다(순수) —
    /// 칩의 완료 잔류(✓/✗)는 "가장 최근 일" 하나만 말하므로, 새 일이 시작되면 옛 결과는 내린다.
    /// running은 남긴다(실행 사실이 사라지면 dedup·프레임 배달이 근거를 잃는다).
    static func clearingFinished(_ runs: [String: ScriptRun]) -> [String: ScriptRun] {
        runs.filter { $0.value.isRunning }
    }
}
