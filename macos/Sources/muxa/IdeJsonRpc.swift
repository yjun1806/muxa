import Foundation

/// IDE 통합 와이어의 JSON-RPC 2.0 한 메시지(순수 파싱·조립). 프레이밍(ws)·소켓은 IdeServer(경계)가,
/// 메시지의 해석/조립만 여기서 한다. `id`는 숫자/문자열 무엇이든 **그대로 되돌려야** 하므로 원본 값을 보존한다.
struct IdeRequest {
    /// 응답에 그대로 echo할 원본 id(Int 또는 String). nil이면 알림(notification) — 응답 없음.
    let id: Any?
    let method: String
    let params: [String: Any]

    var isNotification: Bool { id == nil }
}

enum IdeJsonRpc {
    /// 텍스트 프레임 하나를 요청/알림으로 파싱. jsonrpc=="2.0"이 아니거나 method가 없으면 nil.
    static func parse(_ text: String) -> IdeRequest? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["jsonrpc"] as? String) == "2.0",
              let method = obj["method"] as? String else { return nil }
        let params = (obj["params"] as? [String: Any]) ?? [:]
        return IdeRequest(id: normalizeId(obj["id"]), method: method, params: params)
    }

    /// 성공 응답 바이트. `result`는 이미 조립된 객체(툴 결과면 `{content:[…]}`).
    static func responseData(id: Any?, result: [String: Any]) -> Data? {
        serialize(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    /// 에러 응답 바이트(JSON-RPC error 객체). 코드: -32601(method/tool 없음) 등.
    static func errorData(id: Any?, code: Int, message: String) -> Data? {
        serialize(["jsonrpc": "2.0", "id": id ?? NSNull(),
                   "error": ["code": code, "message": message]])
    }

    /// 서버→클라 알림 바이트(id 없음) — selection_changed·at_mentioned. 빈 params는 `{}`로 나간다.
    static func notificationData(method: String, params: [String: Any]) -> Data? {
        serialize(["jsonrpc": "2.0", "method": method, "params": params])
    }

    // MARK: 내부

    /// JSON id는 숫자면 NSNumber로 온다 — 정수는 Int로 좁혀 되돌릴 때 `1.0`이 아니라 `1`로 나가게 한다.
    private static func normalizeId(_ raw: Any?) -> Any? {
        switch raw {
        case let n as NSNumber: return n.intValue
        case let s as String: return s
        default: return nil
        }
    }

    private static func serialize(_ obj: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: obj)
    }
}
