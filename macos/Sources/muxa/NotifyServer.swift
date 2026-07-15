import Foundation

/// 훅(Claude Code Notification/Stop 등)이 `muxa notify`로 보낸 결정론적 신호.
/// 프로토콜은 탭 구분 한 줄: `<tabId>\t<state>\t<title>\t<body>\t<category>\t<resumeCommand>\t<agentLabel>\n`
/// (뒤쪽 필드는 전부 선택 — 옛 훅/CLI는 안 보낸다. category 없으면 state에서 파생,
///  resumeCommand 없으면 바인딩 등록 없음. resumeCommand 단독이면 state 필드가 비어 상태 신호는 없다).
enum NotifyState: String {
    case waiting // 에이전트가 승인/입력 대기 — 세션 내내 OSC 133이 안 오는 그 순간을 명시 신호로.
    case done    // 작업 완료.
    case working // 작업 재개 — 주의 해소(배지 클리어).

    /// category 미지정 시 state에서 파생하는 기본 배달 카테고리(하위호환).
    /// waiting=입력/권한 대기(긴급), done=턴 완료, working=알림 없음(배지 클리어라 nil).
    var defaultCategory: NotifyCategory? {
        switch self {
        case .waiting: return .needsPermission
        case .done: return .turnComplete
        case .working: return nil
        }
    }
}

/// 훅에서 온 알림 한 줄을 파싱한 값. category는 선택 — 결정론 배달 게이트(NotificationGate) 입력.
/// state는 선택 — resumeCommand 단독(바인딩만 등록) 메시지는 상태 신호가 없어 nil이다.
/// resume는 선택 — 훅이 재개 명령을 실었을 때만 채워진다(tabId에 묶어 영속·복원).
struct NotifyMessage {
    let tabId: String
    let state: NotifyState?
    let title: String
    let body: String
    let category: NotifyCategory?
    let resume: ResumeBinding?
}

/// 훅이 payload를 **해석하지 않고 그대로** 넘긴 원본 신호(`muxa-notify hook --event <E>`).
///
/// 와이어: 첫 줄 `hook\t<tabId>\t<event>` + 개행 이후 EOF까지 전부 원본 JSON.
/// 줄 단위 프로토콜(NotifyMessage)과 달리 body에 개행·탭이 들어가도 안전하다(길이로 자르지 않고
/// 첫 개행 하나만 경계로 쓴다). 파싱·분류는 앱이 한다 — 훅 스크립트에 로직을 넣으면 사용자 디스크에
/// 박혀서 앱 업데이트로 못 고친다.
struct HookMessage {
    let tabId: String
    let event: ClaudeHookEvent
    let payload: ClaudeHookPayload
}

/// Unix 도메인 소켓 리스너 — `muxa notify` CLI가 보낸 한 줄을 받아 콜백으로 넘긴다.
///
/// 부작용(소켓·fd·DispatchSource)을 이 경계 타입에 격리한다(순수 라우팅은 AppState). 소켓
/// 처리는 백그라운드 큐에서 돌고, 콜백(onMessage)만 메인 큐로 넘긴다 — UI 갱신은 상위가 한다.
final class NotifyServer {
    /// **이 인스턴스 전용** 소켓 경로 — `…/<instance>/sockets/notify.sock` (재시작해도 **같은 경로**).
    ///
    /// 인스턴스를 가르는 건 pid가 아니라 **지원 디렉터리**다 — release는 `muxa`, 개발 빌드는
    /// `muxa-dev-<slug>`로 이미 격리돼 있다(여러 창이 각각 자기 소켓을 갖는다는 목표는 그것이 달성한다).
    /// 그래서 디렉터리 **안에서는 고정 이름**이면 충분하다.
    ///
    /// **pid를 넣으면 안 된다**(예전 방식): 소켓 경로가 재시작마다 바뀌는데, tmux 영속 세션의 셸 env
    /// (`MUXA_SOCK`)는 세션 생성 시 한 번만 박히므로 — 재시작을 넘긴 영속 세션이 **죽은 소켓**을 가리켜
    /// 훅 신호가 전멸했다(`resolveTab`은 stale TAB_ID만 고치지 SOCK은 못 고친다). 고정 경로면 재시작해도
    /// 같은 소켓이라 영속 세션이 살아남는다. sun_path 길이 제한(104B) 안에 드는 짧은 경로다.
    ///
    /// 같은 인스턴스가 동시에 두 번 뜨는 비정상 상황에선 나중 프로세스가 `setup()`에서 unlink 후 재바인드해
    /// 소켓을 가져간다(단일 인스턴스 앱이라 정상 경로에선 일어나지 않는다).
    static let socketPath: String = {
        let dir = MuxaSupportDir.subdirectory("sockets")
        return dir.appendingPathComponent("notify.sock").path
    }()

    /// sockaddr_un.sun_path 용량(macOS).
    private static let sunPathCapacity = 104
    /// 한 연결에서 받아들일 최대 바이트(악의/폭주 방지). PostToolUse payload(tool_response 포함)가
    /// 커질 수 있어 넉넉히 둔다 — 넘으면 자르지 않고 폐기한다.
    private static let maxMessageBytes = 1024 * 1024
    /// 연결 하나의 읽기 상한(초) — 죽은 클라이언트가 리스너 자원을 붙잡지 못하게.
    private static let readTimeoutSeconds = 2

    private let queue = DispatchQueue(label: "com.muxa.notify-server")
    /// 연결 읽기 전용 동시 큐 — accept 루프와 분리해 느린 연결이 배달을 막지 않게 한다.
    private let readQueue = DispatchQueue(label: "com.muxa.notify-read", attributes: .concurrent)
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    /// 메시지 수신 콜백 — 메인 큐에서 호출된다. 라우팅·UI 갱신은 상위(AppState)가 한다.
    var onMessage: ((NotifyMessage) -> Void)?

    /// 훅 원본 payload 수신 콜백 — 메인 큐. 해석(ClaudeHookInterpreter)은 소유 store가 한다.
    var onHook: ((HookMessage) -> Void)?

    /// 리스너 시작(백그라운드). 시작 전에 죽은 인스턴스가 남긴 소켓 파일을 청소한다.
    func start() {
        queue.async { [weak self] in
            Self.reapStaleSockets()
            self?.setup()
        }
    }

    /// 죽은 인스턴스의 소켓 파일을 지운다 — 크래시·강제종료하면 `stop()`이 안 돌아 파일이 남는다.
    /// 파일명의 pid가 살아있지 않으면(`kill(pid, 0)` → ESRCH) 그 소켓은 주인 없는 찌꺼기다.
    private static func reapStaleSockets() {
        let dir = MuxaSupportDir.subdirectory("sockets")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names {
            guard name.hasPrefix("muxa-"), name.hasSuffix(".sock"),
                  let pid = Int32(name.dropFirst(5).dropLast(5)) else { continue }
            guard pid != getpid() else { continue }
            // kill(pid, 0)은 시그널을 보내지 않고 존재만 확인한다. ESRCH = 그런 프로세스 없음.
            if kill(pid, 0) != 0, errno == ESRCH {
                unlink(dir.appendingPathComponent(name).path)
            }
        }
    }

    /// 리스너 종료 — 소스 취소(내부에서 fd close) + 소켓 파일 제거.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.source?.cancel()
            self.source = nil
            unlink(Self.socketPath)
        }
    }

    private func setup() {
        let path = Self.socketPath
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            NSLog("muxa NotifyServer: socket() 실패 errno=\(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { rawPtr in
                rawPtr.withMemoryRebound(to: CChar.self, capacity: Self.sunPathCapacity) { dst in
                    strlcpy(dst, src, Self.sunPathCapacity)
                }
            }
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard bound == 0 else {
            NSLog("muxa NotifyServer: bind() 실패 errno=\(errno) path=\(path)")
            close(fd)
            return
        }
        guard listen(fd, 16) == 0 else {
            NSLog("muxa NotifyServer: listen() 실패 errno=\(errno)")
            close(fd)
            return
        }

        listenFD = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptConnection() }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func acceptConnection() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        // 연결을 읽는 동안 accept 큐를 막지 않는다 — 직렬 큐에서 블로킹 read를 돌면 연결 하나만
        // 붙잡고 안 닫아도(`nc -U`) 모든 탭의 훅 배달이 영구 정지한다.
        readQueue.async { [weak self] in self?.handleConnection(client) }
    }

    /// 연결 하나에서 EOF까지 읽어 줄 단위로 파싱한다. CLI는 한 줄 쓰고 닫으므로 짧다.
    private func handleConnection(_ clientFD: Int32) {
        defer { close(clientFD) }
        // 죽은/느린 클라이언트가 이 연결을 영원히 잡고 있지 못하게 상한을 건다.
        var timeout = timeval(tv_sec: Self.readTimeoutSeconds, tv_usec: 0)
        _ = setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(clientFD, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            // 상한을 넘으면 **잘라서 쓰지 않고 통째로 버린다** — 반쪽 JSON은 필드가 사라진 payload가 되어
            // "배경 작업 없음"으로 오독되고, 그게 곧 가짜 완료 알림이다. 없는 게 틀린 것보다 낫다.
            if data.count > Self.maxMessageBytes {
                NSLog("muxa NotifyServer: 메시지가 상한(\(Self.maxMessageBytes)B)을 넘어 폐기")
                return
            }
        }
        // 손실 허용 디코딩 — UTF-8 경계에서 잘려도 nil로 프레임 전체를 잃지 않는다(그러면 Stop이 증발한다).
        let text = String(decoding: data, as: UTF8.self)
        // 훅 프레임(첫 줄이 hook 헤더)은 나머지 전체가 원본 JSON이라 줄 분해를 하면 안 된다.
        if let hook = Self.parseHook(text) {
            let callback = onHook
            DispatchQueue.main.async { callback?(hook) }
            return
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let msg = Self.parse(String(line)) else { continue }
            let callback = onMessage
            DispatchQueue.main.async { callback?(msg) }
        }
    }

    /// `hook\t<tabId>\t<event>\n<원본 JSON…>` 프레임 파싱. 헤더가 아니면 nil(줄 단위 경로로 폴백).
    /// payload가 없거나 깨졌으면 빈 payload로 통과시킨다 — 이벤트 이름만으로도 상태 전이는 유효하다.
    static func parseHook(_ text: String) -> HookMessage? {
        guard text.hasPrefix(hookFramePrefix) else { return nil }
        let split = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let header = split[0].components(separatedBy: "\t")
        guard header.count >= 3, !header[1].isEmpty,
              let event = ClaudeHookEvent(rawValue: header[2]) else { return nil }
        let json = split.count > 1 ? Data(split[1].utf8) : Data()
        let payload = ClaudeHookPayload.parse(json) ?? ClaudeHookPayload.empty
        return HookMessage(tabId: header[1], event: event, payload: payload)
    }

    /// 훅 프레임 식별 접두 — CLI(muxa-notify)와 공유하는 와이어 상수.
    static let hookFramePrefix = "hook\t"

    /// `<tabId>\t<state>\t<title>\t<body>\t<category>\t<resumeCommand>\t<agentLabel>` 파싱. 부족한
    /// 필드는 관대하게 채운다(title/body는 빈 문자열, category는 미지정·미인식이면 nil → deliverNotify가
    /// state에서 파생). state가 비었거나 미인식이면 nil(바인딩 단독 메시지) — state·resume 둘 다 없으면 폐기한다.
    static func parse(_ line: String) -> NotifyMessage? {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 2 else { return nil }
        let tabId = parts[0]
        guard !tabId.isEmpty else { return nil }
        let state = NotifyState(rawValue: parts[1]) // 빈/미인식이면 nil — resume 단독 메시지
        let title = parts.count > 2 ? parts[2] : ""
        let body = parts.count > 3 ? parts[3] : ""
        let category = parts.count > 4 ? NotifyCategory(rawValue: parts[4]) : nil
        let resumeCommand = parts.count > 5 ? parts[5] : ""
        let agentLabel = parts.count > 6 ? parts[6] : ""
        // 줄 프로토콜 명령은 외부 입력이다 — muxa가 만드는 고정 꼴일 때만 신뢰(.hook), 아니면 배너 확인(.scan).
        let resume = resumeCommand.isEmpty ? nil
            : ResumeBinding(command: resumeCommand, agentLabel: agentLabel.isEmpty ? nil : agentLabel,
                            source: ResumeBinding.hookSource(forExternalCommand: resumeCommand))
        // 유효 신호가 아무것도 없으면(상태도, 바인딩도) 폐기 — 구 동작(미인식 state 폐기)과 동일.
        guard state != nil || resume != nil else { return nil }
        return NotifyMessage(tabId: tabId, state: state, title: title, body: body,
                             category: category, resume: resume)
    }
}
