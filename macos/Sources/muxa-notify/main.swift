import Foundation

// muxa notify — 훅에서 부르는 작은 CLI. 셸 env에 muxa가 심어둔 MUXA_SOCK/MUXA_TAB_ID를 읽어
// 앱의 Unix 소켓에 한 줄(`<tabId>\t<state>\t<title>\t<body>`)을 쓰고 종료한다.
//
// 사용: muxa notify --state waiting --title "승인 대기" --body "..."
// (실행 파일명이 muxa-notify라 맨 앞의 "notify" 토큰은 있어도 없어도 된다.)

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
var title = ""
var body = ""
var i = 0
while i < args.count {
    switch args[i] {
    case "--state": i += 1; if i < args.count { state = args[i] }
    case "--title": i += 1; if i < args.count { title = args[i] }
    case "--body":  i += 1; if i < args.count { body = args[i] }
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

let line = "\(tabId)\t\(state)\t\(sanitize(title))\t\(sanitize(body))\n"

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
