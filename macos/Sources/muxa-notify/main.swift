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

/// connect 대기 상한(ms). 앱 미실행·소켓 지연이어도 에이전트 흐름을 막지 않게 짧게 끊는다.
let connectTimeoutMillis: Int32 = 200
/// 전송 상한(초). 앱이 느려도 훅이 에이전트를 오래 막지 않게 한다.
let writeTimeoutSeconds = 2

/// 훅으로 쓰이므로 어떤 실패도 에이전트 흐름을 막지 않는다 — 진단은 stderr 한 줄, 종료코드는 항상 0.
/// (에이전트 stdout 오염 금지. exit 0 = fire-and-forget.)
func bail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("muxa notify: \(message)\n".utf8))
    exit(0)
}

/// 구분자(탭·개행)를 공백으로 바꿔 프로토콜이 깨지지 않게 한다.
func sanitize(_ s: String) -> String {
    s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
}

// 인자 파싱 — 맨 앞 "notify" 서브커맨드는 선택. 외부 의존성 없이 수동 파싱.
var args = Array(CommandLine.arguments.dropFirst())
if args.first == "notify" { args.removeFirst() }

// hook 모드 — Claude Code 훅이 stdin으로 주는 JSON을 **해석하지 않고 그대로** 앱에 넘긴다.
// 분류·게이팅은 전부 앱이 한다: 훅 명령줄은 사용자의 settings.json에 박혀 있어서, 여기에 로직을 넣으면
// 그 로직을 앱 업데이트로 못 고친다. CLI는 배관일 뿐이다.
var hookEvent: String?
if args.first == "hook" {
    args.removeFirst()
    var j = 0
    while j < args.count {
        if args[j] == "--event", j + 1 < args.count { hookEvent = args[j + 1] }
        j += 1
    }
    guard let event = hookEvent, !event.isEmpty else { bail("hook: --event 누락") }
    hookEvent = event
}

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

// muxa 밖에서 돌면(일반 터미널·IDE의 claude 세션) 보낼 곳이 없다. 이건 **에러가 아니라 정상**이다 —
// 훅은 전역 settings.json에 등록되므로 muxa 밖 세션에서도 매 도구 호출마다 불린다.
// stderr에 한 줄이라도 쓰면 Claude Code가 그걸 "hook error"로 표시해 매 턴 시끄러워진다. 조용히 빠진다.
let env = ProcessInfo.processInfo.environment
guard let sock = env["MUXA_SOCK"], !sock.isEmpty,
      let tabId = env["MUXA_TAB_ID"], !tabId.isEmpty else {
    exit(0)
}

/// 소켓에 실을 바이트. hook 모드면 `hook\t<tabId>\t<event>\n<원본 JSON>`, 아니면 기존 줄 프로토콜.
/// hook 프레임은 payload를 손대지 않는다(개행·탭이 들어 있어도 첫 개행 하나만 경계로 쓴다).
let line: String = {
    guard let event = hookEvent else {
        // --resume-command 단독(명시적 --state 없음)이면 상태 필드를 비운다 — 바인딩만 등록하고 상태 신호는 안 보낸다.
        // (resume-command가 없으면 종전대로 기본 waiting이 실린다 — 하위호환.)
        let stateField = (!resumeCommand.isEmpty && !stateExplicit) ? "" : state
        // 필드 순서 고정: category(5)·resumeCommand(6)·agentLabel(7). 빈 문자열이면 서버가 nil로 파싱 — 하위호환.
        return "\(tabId)\t\(stateField)\t\(sanitize(title))\t\(sanitize(body))\t\(sanitize(category))\t\(sanitize(resumeCommand))\t\(sanitize(agent))\n"
    }
    // stdin이 비어도(훅이 payload를 안 줘도) 이벤트 이름만으로 상태 전이는 유효하다 — 프레임은 보낸다.
    let payload = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    return "hook\t\(tabId)\t\(sanitize(event))\n\(payload)"
}()

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { bail("socket() 실패 errno=\(errno)") }
defer { close(fd) }

// 논블로킹 connect + poll 타임아웃 — 앱이 붙지 않아도 connectTimeoutMillis에서 조용히 끊는다.
let flags = fcntl(fd, F_GETFL, 0)
if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }

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
let rc = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
}
if rc != 0 {
    // 즉시 실패가 아니라 진행 중(EINPROGRESS)이면 쓰기 가능해질 때까지 짧게 기다린다.
    guard errno == EINPROGRESS else { bail("connect() 실패 errno=\(errno) — muxa가 실행 중인지 확인") }
    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
    let ready = poll(&pfd, 1, connectTimeoutMillis)
    guard ready > 0 else { bail("connect 타임아웃 — muxa 미응답") }
    // connect 결과 확정 — SO_ERROR가 0이어야 성공.
    var soErr: Int32 = 0
    var soLen = socklen_t(MemoryLayout<Int32>.size)
    let got = getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &soLen)
    guard got == 0, soErr == 0 else { bail("connect 실패 errno=\(soErr) — muxa가 실행 중인지 확인") }
}

// connect가 끝났으니 블로킹으로 되돌린다 — 논블로킹인 채로 쓰면 커널 송신 버퍼(macOS 기본 8KB)를
// 넘는 순간 부분 전송되고 나머지가 조용히 사라진다. PostToolUse payload는 tool_response를 포함해
// 8KB를 우습게 넘으므로, 이 한 줄이 없으면 프레임이 잘려 앱에서 JSON 파싱이 실패한다.
if flags >= 0 { _ = fcntl(fd, F_SETFL, flags) }
// 앱이 먼저 소켓을 닫으면 write가 SIGPIPE를 쏘고 프로세스가 즉사한다 — exit 0 보장이 깨져
// Claude가 "hook error"를 띄운다. 시그널 대신 EPIPE로 받게 한다(fire-and-forget 유지).
var noSigPipe: Int32 = 1
_ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
// 앱이 느리면(연결 폭주 등) 여기서 무한정 막힐 수 있다 — 훅은 에이전트 흐름을 막지 않아야 하므로 상한을 건다.
var sendTimeout = timeval(tv_sec: writeTimeoutSeconds, tv_usec: 0)
_ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))

// fire-and-forget: 전량 쓰고 종료. 부분 쓰기를 오프셋으로 밀어가며 끝까지 보낸다(쓰기 실패해도 exit 0).
let payload = Array(line.utf8)
payload.withUnsafeBytes { buffer in
    var sent = 0
    while sent < buffer.count {
        let n = write(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
        if n > 0 { sent += n; continue }
        if n < 0 && errno == EINTR { continue } // 시그널로 끊겼을 뿐 — 재시도
        break // EPIPE·타임아웃 등: 조용히 포기한다(에이전트를 막지 않는 게 우선)
    }
}
exit(0)
