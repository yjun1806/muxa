import Foundation

// muxa notify — 훅에서 부르는 작은 CLI. 셸 env에 muxa가 심어둔 MUXA_SOCK/MUXA_TAB_ID를 읽어
// 앱의 Unix 소켓에 한 줄
// (`<tabId>\t<state>\t<title>\t<body>\t<category>\t<resumeCommand>\t<agentLabel>`)을 쓰고 종료한다.
//
// 사용: muxa notify --state waiting --category needs-permission --title "승인 대기" --body "..."
// (실행 파일명이 muxa-notify라 맨 앞의 "notify" 토큰은 있어도 없어도 된다.)
//
// 인자:
//   --state    waiting | done | working   (기본 waiting — 단 --resume-command 단독이면 상태 신호 없음)
//               waiting=입력/권한 대기, done=턴 완료, working=작업 재개(주의 해소·배지 클리어)
//   --category needs-permission | turn-complete | idle-reminder   (선택)
//               결정론 배달 게이트 입력. 미지정이면 앱이 state에서 파생
//               (waiting→needs-permission, done→turn-complete). 값이 실리면 그 카테고리로 배달을 가른다:
//               needs-permission=안 보이면 항상 알림(긴급), turn-complete=안 보이면 알림,
//               idle-reminder=조용히(배지만, 억제 가능).
//   --resume-command <cmd>  이 탭의 에이전트 재개 명령 전체(예: "claude --resume <sessionId>").
//               지정하면 muxa가 tabId에 묶어 저장·영속하고, 세션 복원 시 다시 그 탭에 되살린다.
//               --state 없이 단독으로 줄 수 있다(그러면 상태 신호 없이 바인딩만 등록). --state와 공존 가능.
//   --agent <label>   재개 명령의 표시용 에이전트 라벨(claude/codex 등, 선택).
//   --title / --body  알림 제목·본문(선택).
//
// Claude Code 훅 프리셋 예시(~/.claude/settings.json hooks):
//   SessionStart(resume 가능)           → muxa notify --resume-command "claude --resume $CLAUDE_SESSION_ID" --agent claude
//   PreToolUse / PostToolUse           → muxa notify --state working
//   PermissionRequest / AskUserQuestion / Notification
//                                      → muxa notify --state waiting --category needs-permission
//   Stop                               → muxa notify --state done --category turn-complete
//   (유휴 리마인더는 별도 타이머/훅에서 muxa notify --state waiting --category idle-reminder)

/// sockaddr_un.sun_path 용량(macOS).
let sunPathCapacity = 104

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("muxa notify: \(message)\n".utf8))
    exit(1)
}

/// 구분자(탭·개행)를 공백으로 바꿔 프로토콜이 깨지지 않게 한다.
func sanitize(_ s: String) -> String {
    s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
}

// 인자 파싱 — 맨 앞 "notify" 서브커맨드는 선택. 외부 의존성 없이 수동 파싱.
var args = Array(CommandLine.arguments.dropFirst())
if args.first == "notify" { args.removeFirst() }

var state = "waiting"
var stateExplicit = false
var category = ""
var title = ""
var body = ""
var resumeCommand = ""
var agent = ""
var i = 0
while i < args.count {
    switch args[i] {
    case "--state":          i += 1; if i < args.count { state = args[i]; stateExplicit = true }
    case "--category":       i += 1; if i < args.count { category = args[i] }
    case "--title":          i += 1; if i < args.count { title = args[i] }
    case "--body":           i += 1; if i < args.count { body = args[i] }
    case "--resume-command": i += 1; if i < args.count { resumeCommand = args[i] }
    case "--agent":          i += 1; if i < args.count { agent = args[i] }
    default: break
    }
    i += 1
}

let env = ProcessInfo.processInfo.environment
guard let sock = env["MUXA_SOCK"], !sock.isEmpty else {
    fail("MUXA_SOCK 미설정 — muxa 안에서 실행해야 한다")
}
guard let tabId = env["MUXA_TAB_ID"], !tabId.isEmpty else {
    fail("MUXA_TAB_ID 미설정 — muxa 안에서 실행해야 한다")
}

// --resume-command 단독(명시적 --state 없음)이면 상태 필드를 비운다 — 바인딩만 등록하고 상태 신호는 안 보낸다.
// (resume-command가 없으면 종전대로 기본 waiting이 실린다 — 하위호환.)
let stateField = (!resumeCommand.isEmpty && !stateExplicit) ? "" : state
// 필드 순서 고정: category(5)·resumeCommand(6)·agentLabel(7). 빈 문자열이면 서버가 nil로 파싱 — 하위호환.
let line = "\(tabId)\t\(stateField)\t\(sanitize(title))\t\(sanitize(body))\t\(sanitize(category))\t\(sanitize(resumeCommand))\t\(sanitize(agent))\n"

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { fail("socket() 실패 errno=\(errno)") }
defer { close(fd) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
_ = sock.withCString { src in
    withUnsafeMutablePointer(to: &addr.sun_path) { rawPtr in
        rawPtr.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { dst in
            strlcpy(dst, src, sunPathCapacity)
        }
    }
}

let len = socklen_t(MemoryLayout<sockaddr_un>.size)
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
}
guard connected == 0 else { fail("connect() 실패 errno=\(errno) — muxa가 실행 중인지 확인") }

let payload = Array(line.utf8)
_ = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
exit(0)
