import Foundation

/// 훅(Claude Code Notification/Stop 등)이 `muxa notify`로 보낸 결정론적 신호.
/// 프로토콜은 탭 구분 한 줄: `<tabId>\t<state>\t<title>\t<body>\n`.
enum NotifyState: String {
    case waiting // 에이전트가 승인/입력 대기 — 세션 내내 OSC 133이 안 오는 그 순간을 명시 신호로.
    case done    // 작업 완료.
    case working // 작업 재개 — 주의 해소(배지 클리어).
}

/// 훅에서 온 알림 한 줄을 파싱한 값.
struct NotifyMessage {
    let tabId: String
    let state: NotifyState
    let title: String
    let body: String
}

/// Unix 도메인 소켓 리스너 — `muxa notify` CLI가 보낸 한 줄을 받아 콜백으로 넘긴다.
///
/// 부작용(소켓·fd·DispatchSource)을 이 경계 타입에 격리한다(순수 라우팅은 AppState). 소켓
/// 처리는 백그라운드 큐에서 돌고, 콜백(onMessage)만 메인 큐로 넘긴다 — UI 갱신은 상위가 한다.
final class NotifyServer {
    /// 소켓 경로 — applicationSupport/muxa/muxa.sock (AppState.fileURL과 같은 디렉토리).
    /// sun_path 길이 제한(104B) 안에 드는 짧은 경로다.
    static let socketPath: String = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("muxa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("muxa.sock").path
    }()

    /// sockaddr_un.sun_path 용량(macOS).
    private static let sunPathCapacity = 104
    /// 한 연결에서 받아들일 최대 바이트(악의/폭주 방지).
    private static let maxMessageBytes = 64 * 1024

    private let queue = DispatchQueue(label: "com.muxa.notify-server")
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    /// 메시지 수신 콜백 — 메인 큐에서 호출된다. 라우팅·UI 갱신은 상위(AppState)가 한다.
    var onMessage: ((NotifyMessage) -> Void)?

    /// 리스너 시작(백그라운드). 이미 있던 소켓 파일은 unlink 후 재바인드한다.
    func start() {
        queue.async { [weak self] in self?.setup() }
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
        handleConnection(client)
    }

    /// 연결 하나에서 EOF까지 읽어 줄 단위로 파싱한다. CLI는 한 줄 쓰고 닫으므로 짧다.
    private func handleConnection(_ clientFD: Int32) {
        defer { close(clientFD) }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(clientFD, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            if data.count > Self.maxMessageBytes { break }
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let msg = Self.parse(String(line)) else { continue }
            let callback = onMessage
            DispatchQueue.main.async { callback?(msg) }
        }
    }

    /// `<tabId>\t<state>\t<title>\t<body>` 파싱. tab이 부족한 필드는 빈 문자열로 관대하게 채운다.
    static func parse(_ line: String) -> NotifyMessage? {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 2 else { return nil }
        let tabId = parts[0]
        guard !tabId.isEmpty, let state = NotifyState(rawValue: parts[1]) else { return nil }
        let title = parts.count > 2 ? parts[2] : ""
        let body = parts.count > 3 ? parts[3] : ""
        return NotifyMessage(tabId: tabId, state: state, title: title, body: body)
    }
}
