import Foundation
import CryptoKit

/// IDE 통합 ws의 **HTTP→WebSocket 업그레이드**(RFC 6455) 순수 처리. 소켓 IO는 IdeServer가,
/// 요청 파싱·검증·accept-key·응답 조립만 여기서 한다(전부 테스트로 못 박는다).
///
/// 인증(`x-claude-code-ide-authorization`)을 이 단계에서 상수시간 비교로 검증한다 — NWProtocolWebSocket이
/// 업그레이드 헤더를 안 내주기 때문에 프레이밍을 직접 구현하는 이유가 바로 이 검증이다.
enum IdeWsHandshake {
    /// RFC 6455 고정 GUID.
    static let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    struct Request {
        let requestLine: String
        /// 헤더 — 키는 소문자로 정규화(HTTP 헤더는 대소문자 무시).
        let headers: [String: String]
    }

    /// 헤더 블록(`\r\n\r\n` 이전)까지의 문자열을 요청으로 파싱. 첫 줄 없으면 nil.
    static func parse(_ raw: String) -> Request? {
        let lines = raw.components(separatedBy: "\r\n")
        guard let first = lines.first, !first.isEmpty else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return Request(requestLine: first, headers: headers)
    }

    /// `Sec-WebSocket-Accept` 값 = base64(sha1(key + GUID)).
    static func acceptKey(for secWebSocketKey: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data((secWebSocketKey + guid).utf8))
        return Data(digest).base64EncodedString()
    }

    /// 업그레이드 검증 — 통과면 nil, 실패면 거절 사유(문자열). `expectedToken`이 nil이면 인증 생략.
    static func rejectReason(_ req: Request, expectedToken: String?) -> String? {
        // RFC 6455 필수 헤더.
        guard (req.headers["upgrade"]?.lowercased().contains("websocket")) == true else {
            return "Missing or invalid Upgrade header"
        }
        guard (req.headers["connection"]?.lowercased().contains("upgrade")) == true else {
            return "Missing or invalid Connection header"
        }
        guard req.headers["sec-websocket-version"] == "13" else {
            return "Unsupported Sec-WebSocket-Version"
        }
        guard let key = req.headers["sec-websocket-key"], key.count == 24 else {
            return "Missing or malformed Sec-WebSocket-Key"
        }
        // 인증 토큰(레퍼런스와 동일 규칙: 10~500자, 상수시간 비교).
        if let expectedToken {
            guard let auth = req.headers["x-claude-code-ide-authorization"] else {
                return "Missing authentication header: x-claude-code-ide-authorization"
            }
            guard auth.count >= 10, auth.count <= 500 else { return "Authentication token length invalid" }
            guard constantTimeEqual(auth, expectedToken) else { return "Invalid authentication token" }
        }
        return nil
    }

    /// 101 응답(성공) — key로 accept를 계산해 붙인다. 클라가 요청한 서브프로토콜(있으면)을 **반드시 echo**한다:
    /// claude(2.1.218)는 `Sec-WebSocket-Protocol: mcp`를 요청하고, 응답에 echo가 없으면 업그레이드 직후
    /// 연결을 끊는다(ws 라이브러리 규칙). 압축 확장(permessage-deflate)은 echo하지 않아 비압축으로 협상된다.
    static func successResponse(secWebSocketKey: String, subprotocol: String? = nil) -> String {
        var r = "HTTP/1.1 101 Switching Protocols\r\n"
            + "Upgrade: websocket\r\n"
            + "Connection: Upgrade\r\n"
            + "Sec-WebSocket-Accept: \(acceptKey(for: secWebSocketKey))\r\n"
        if let subprotocol { r += "Sec-WebSocket-Protocol: \(subprotocol)\r\n" }
        return r + "\r\n"
    }

    /// 클라가 제안한 서브프로토콜 중 우리가 지원하는 것("mcp")을 고른다. 없으면 nil(echo 안 함).
    static func negotiateSubprotocol(_ header: String?) -> String? {
        guard let header else { return nil }
        let offered = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return offered.contains("mcp") ? "mcp" : nil
    }

    /// 400 응답(거절) — 레퍼런스와 같은 본문 형식.
    static func errorResponse(reason: String) -> String {
        let body = "Bad WebSocket upgrade request: \(reason)"
        return "HTTP/1.1 400 Bad Request\r\n"
            + "Content-Type: text/plain\r\n"
            + "Content-Length: \(body.utf8.count)\r\n\r\n"
            + body
    }

    /// 길이·내용 유출을 줄이는 상수시간 비교(레퍼런스 constant_time_compare 대응).
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
