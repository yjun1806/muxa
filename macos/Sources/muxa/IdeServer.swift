import Foundation
import Network
import os

/// IDE 서버 관측 로그 — 사용자가 "연결 안 됨"을 보고할 때 진단할 수 있게 연결/거절/해제만 남긴다.
private let ideLog = Logger(subsystem: "com.muxa.ide", category: "server")

/// muxa를 **IDE**로 노출하는 로컬 ws 서버 — muxa 터미널에서 실행된 `claude` CLI가 붙어 선택·활성파일·
/// 진단을 받아간다(VS Code 확장과 같은 역할). 부작용(소켓·락파일)을 이 경계에 격리한다. 순수 로직
/// (핸드셰이크·프레임·JSON-RPC·MCP 응답 조립)은 IdeWs*/IdeJsonRpc/IdeProtocol에 있고 테스트로 못 박혔다.
///
/// **CC 칸마다 하나**(IdeServerRegistry가 탭별로 소유) — 각 claude 세션이 자기 포트/락파일에 붙어
/// 선택이 그 세션에만 간다(VS Code가 창마다 엔드포인트를 갖는 격리). getCurrentSelection은 이 세션에
/// 마지막으로 라우팅된 선택을 준다.
final class IdeServer {
    /// 관측한 컨텍스트 스냅샷(플레인 값) — 네트워크 큐에서 락으로 읽는다(메인 홉 없이 안전).
    struct Context {
        var workspaceFolders: [String] = []
        var selection: IdeSelection?
    }

    private let queue = DispatchQueue(label: "com.muxa.ide-server")
    private let lock = NSLock()
    private var context = Context()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: Conn] = [:]
    private(set) var port: UInt16?
    private let authToken = IdeLockfile.newAuthToken()
    private let version: String
    /// 락파일 ideName — 인스턴스 구분(릴리스="muxa", 개발="Muxa Dev · slug")으로 고아 정리가 서로를 안 건드린다.
    private let ideName: String

    init(version: String, ideName: String) {
        self.version = version
        self.ideName = ideName
    }

    /// 터미널에 심을 IDE 통합 env — 서버가 떠 있을 때만 값이 있다.
    var terminalEnv: [String: String] {
        guard let port else { return [:] }
        return ["CLAUDE_CODE_SSE_PORT": String(port),
                "ENABLE_IDE_INTEGRATION": "true",
                "FORCE_CODE_TERMINAL": "true"]
    }

    /// 지금 claude가 이 서버에 붙어 있나(업그레이드된 연결이 하나라도) — 라우팅 대상 판정에 쓴다.
    var isConnected: Bool { queue.sync { connections.values.contains { $0.upgraded } } }

    // MARK: 수명

    /// 루프백(랜덤 포트)에 바인딩하고 락파일을 쓴다. **ready까지 짧게 동기 대기**해 `port`를 확정한다 —
    /// 터미널 생성 시점(term(for:))에 env로 포트를 심어야 하므로 반환 전에 포트가 있어야 한다. 실패는 조용히 무시.
    func start(workspaceFolders: [String]) {
        context.workspaceFolders = workspaceFolders
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback // 127.0.0.1 only
        guard let listener = try? NWListener(using: params, on: .any) else { return }
        self.listener = listener
        let sem = DispatchSemaphore(value: 0)
        var settled = false
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let p = listener.port?.rawValue {
                    self.port = p
                    IdeLockfile.write(port: p, content: IdeLockfile.content(
                        pid: ProcessInfo.processInfo.processIdentifier,
                        workspaceFolders: self.context.workspaceFolders,
                        ideName: self.ideName, authToken: self.authToken))
                }
                if !settled { settled = true; sem.signal() }
            case .failed:
                if !settled { settled = true; sem.signal() }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
        _ = sem.wait(timeout: .now() + 1.0) // 포트 확정까지 최대 1초(터미널 생성 전 보장)
    }

    func stop() {
        if let port { IdeLockfile.remove(port: port) }
        queue.async {
            self.connections.values.forEach { $0.conn.cancel() }
            self.connections.removeAll()
        }
        listener?.cancel()
        listener = nil
        port = nil
    }

    // MARK: 컨텍스트 갱신 (메인에서 호출) + 선택 푸시

    func updateContext(_ mutate: (inout Context) -> Void) {
        lock.lock(); mutate(&context); let snapshot = context; lock.unlock()
        // 선택 변화는 붙어 있는 모든 CLI에 알린다.
        if let sel = snapshot.selection { broadcastSelection(sel) }
    }

    /// 공유 중인 컨텍스트를 **명시적으로 지운다**(우클릭 "Claude 컨텍스트 지우기"). 선택 해제와 달리 파일
    /// 참조까지 비운 selection_changed를 즉시 푸시하고 getCurrentSelection도 no-editor가 되게 한다.
    func clearSelection() {
        lock.lock(); context.selection = nil; lock.unlock()
        let cleared = IdeSelection(filePath: "", text: "", startLine: 0, startCharacter: 0, endLine: 0, endCharacter: 0)
        broadcastSelection(cleared)
    }

    private func snapshot() -> Context { lock.lock(); defer { lock.unlock() }; return context }

    private func broadcastSelection(_ sel: IdeSelection) {
        guard let data = IdeJsonRpc.notificationData(method: "selection_changed",
                                                     params: IdeProtocol.selectionParams(sel)) else { return }
        queue.async { self.connections.values.forEach { $0.upgraded ? self.send(data, on: $0) : () } }
    }

    // MARK: 연결

    private final class Conn {
        let conn: NWConnection
        var buffer = Data()
        var upgraded = false
        init(_ c: NWConnection) { conn = c }
    }

    private func accept(_ nwConn: NWConnection) {
        let c = Conn(nwConn)
        connections[ObjectIdentifier(nwConn)] = c
        nwConn.stateUpdateHandler = { [weak self] state in
            if case .failed(let e) = state { ideLog.error("IDE conn failed: \(e.localizedDescription, privacy: .public)") }
            switch state {
            case .cancelled, .failed:
                self?.queue.async { self?.connections[ObjectIdentifier(nwConn)] = nil }
            default: break
            }
        }
        nwConn.start(queue: queue)
        receive(c)
    }

    private func receive(_ c: Conn) {
        c.conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { c.buffer.append(data); self.process(c) }
            if isComplete || error != nil { c.conn.cancel(); return }
            self.receive(c)
        }
    }

    /// 버퍼를 소진: 업그레이드 전이면 HTTP 핸드셰이크, 후면 ws 프레임들.
    private func process(_ c: Conn) {
        if !c.upgraded { processHandshake(c); return }
        processFrames(c)
    }

    private func processHandshake(_ c: Conn) {
        guard let range = c.buffer.range(of: Data("\r\n\r\n".utf8)) else { return } // 헤더 끝까지 대기
        let headerData = c.buffer.subdata(in: c.buffer.startIndex..<range.upperBound)
        c.buffer.removeSubrange(c.buffer.startIndex..<range.upperBound)
        guard let req = IdeWsHandshake.parse(String(decoding: headerData, as: UTF8.self)),
              let key = req.headers["sec-websocket-key"] else {
            send(Data(IdeWsHandshake.errorResponse(reason: "Malformed request").utf8), on: c, thenClose: true)
            return
        }
        if let reason = IdeWsHandshake.rejectReason(req, expectedToken: authToken) {
            ideLog.error("handshake rejected: \(reason, privacy: .public)")
            send(Data(IdeWsHandshake.errorResponse(reason: reason).utf8), on: c, thenClose: true)
            return
        }
        let sub = IdeWsHandshake.negotiateSubprotocol(req.headers["sec-websocket-protocol"])
        ideLog.notice("IDE connected (subprotocol=\(sub ?? "none", privacy: .public))")
        send(Data(IdeWsHandshake.successResponse(secWebSocketKey: key, subprotocol: sub).utf8), on: c)
        c.upgraded = true
        if !c.buffer.isEmpty { processFrames(c) } // 업그레이드 뒤 붙어온 프레임 처리
    }

    private func processFrames(_ c: Conn) {
        while true {
            switch IdeWsFrame.decode(c.buffer) {
            case .incomplete: return
            case .error: c.conn.cancel(); return
            case let .frame(frame, consumed):
                c.buffer.removeSubrange(c.buffer.startIndex..<(c.buffer.startIndex + consumed))
                handleFrame(frame, c)
            }
        }
    }

    private func handleFrame(_ frame: IdeWsFrame.Frame, _ c: Conn) {
        switch IdeWsFrame.Opcode(rawValue: frame.opcode) {
        case .text:
            guard let req = IdeJsonRpc.parse(String(decoding: frame.payload, as: UTF8.self)) else { return }
            dispatch(req, c)
        case .ping: send(IdeWsFrame.encodePong(frame.payload), on: c, framed: false)
        case .close: send(IdeWsFrame.encodeClose(), on: c, framed: false, thenClose: true)
        default: break
        }
    }

    // MARK: JSON-RPC 디스패치

    private func dispatch(_ req: IdeRequest, _ c: Conn) {
        switch req.method {
        case "initialize":
            reply(req.id, result: IdeProtocol.initializeResult(version: version), c)
        case "notifications/initialized":
            break // no-op
        case "prompts/list":
            reply(req.id, result: IdeProtocol.promptsListResult, c)
        case "tools/list":
            reply(req.id, result: IdeProtocol.toolsListResult, c)
        case "tools/call":
            let name = req.params["name"] as? String ?? ""
            let args = req.params["arguments"] as? [String: Any] ?? [:]
            reply(req.id, result: IdeProtocol.toolResult(text: handleTool(name, args)), c)
        default:
            if !req.isNotification,
               let data = IdeJsonRpc.errorData(id: req.id, code: -32601, message: "Method not found: \(req.method)") {
                send(data, on: c)
            }
        }
    }

    private func reply(_ id: Any?, result: [String: Any], _ c: Conn) {
        guard let data = IdeJsonRpc.responseData(id: id, result: result) else { return }
        send(data, on: c)
    }

    /// 툴 호출 → 결과 text(평문 또는 JSON문자열). M1: 선택·워크스페이스는 실제 값, 나머지는 최소 대응.
    private func handleTool(_ name: String, _ args: [String: Any]) -> String {
        let ctx = snapshot()
        switch name {
        case "getCurrentSelection", "getLatestSelection":
            return IdeProtocol.selectionText(ctx.selection)
        case "getOpenEditors":
            return IdeProtocol.toolText(["tabs": [Any]()]) // M2에서 채운다
        case "getWorkspaceFolders":
            let folders = ctx.workspaceFolders.map { path -> [String: Any] in
                ["name": (path as NSString).lastPathComponent,
                 "uri": URL(fileURLWithPath: path).absoluteString, "path": path]
            }
            return IdeProtocol.toolText(["success": true, "folders": folders,
                                         "rootPath": ctx.workspaceFolders.first ?? ""])
        case "getDiagnostics":
            return IdeProtocol.toolText(array: []) // LSP 없음 — 빈 배열(M3에서 재검토)
        case "checkDocumentDirty":
            let path = args["filePath"] as? String ?? ""
            return IdeProtocol.toolText(["success": true, "filePath": path, "isDirty": false, "isUntitled": false])
        case "saveDocument":
            let path = args["filePath"] as? String ?? ""
            return IdeProtocol.toolText(["success": true, "filePath": path, "saved": true,
                                         "message": "Document saved successfully"])
        case "openFile":
            return "Opened file: \(args["filePath"] as? String ?? "")" // M3에서 실제 뷰어 오픈
        case "openDiff":
            return "DIFF_REJECTED" // M3에서 muxa DocDiff 뷰어 연동
        case "closeAllDiffTabs":
            return "CLOSED_0_DIFF_TABS"
        default:
            return IdeProtocol.toolText(["success": false, "message": "Tool not found: \(name)"])
        }
    }

    // MARK: 송신

    private func send(_ data: Data, on c: Conn, framed: Bool = true, thenClose: Bool = false) {
        // framed=false는 이미 프레임/HTTP 바이트(핸드셰이크·pong·close). text 응답은 framed=true로 감싼다.
        let out = framed && c.upgraded ? IdeWsFrame.encode(opcode: .text, payload: data) : data
        c.conn.send(content: out, completion: .contentProcessed { _ in
            if thenClose { c.conn.cancel() }
        })
    }
}
