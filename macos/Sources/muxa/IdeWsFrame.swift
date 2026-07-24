import Foundation

/// IDE 통합 ws의 **프레임 코덱**(RFC 6455) 순수 구현. 클라→서버 프레임은 마스킹돼 오므로 언마스크하고,
/// 서버→클라 프레임은 마스크 없이 인코딩한다. 버퍼 경계(TCP는 조각나 온다)는 IdeServer가, 조립/해체는 여기.
enum IdeWsFrame {
    /// 오피코드(하위 4비트).
    enum Opcode: UInt8 {
        case continuation = 0x0, text = 0x1, binary = 0x2, close = 0x8, ping = 0x9, pong = 0xA
    }

    struct Frame {
        let opcode: UInt8
        let fin: Bool
        let payload: Data
    }

    enum Decoded {
        case frame(Frame, consumed: Int)   // 완결 프레임 하나 + 소비한 바이트 수
        case incomplete                    // 아직 프레임이 덜 왔다
        case error                         // 규격 위반(비정상 종료)
    }

    // MARK: 인코딩 (서버→클라, 마스크 없음)

    static func encodeText(_ s: String) -> Data { encode(opcode: .text, payload: Data(s.utf8)) }
    static func encodePong(_ payload: Data) -> Data { encode(opcode: .pong, payload: payload) }
    /// 정상 종료 프레임(1000).
    static func encodeClose() -> Data { encode(opcode: .close, payload: Data([0x03, 0xE8])) }

    static func encode(opcode: Opcode, payload: Data) -> Data {
        var out = Data([0x80 | opcode.rawValue]) // FIN=1
        let n = payload.count
        if n <= 125 {
            out.append(UInt8(n))
        } else if n <= 0xFFFF {
            out.append(126)
            out.append(UInt8((n >> 8) & 0xFF)); out.append(UInt8(n & 0xFF))
        } else {
            out.append(127)
            for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8((n >> shift) & 0xFF)) }
        }
        out.append(payload)
        return out
    }

    // MARK: 디코딩 (클라→서버, 마스크 해제)

    /// 버퍼 앞쪽에서 프레임 하나를 떼어낸다. 덜 왔으면 .incomplete.
    static func decode(_ buf: Data) -> Decoded {
        let b = [UInt8](buf)
        guard b.count >= 2 else { return .incomplete }
        let fin = (b[0] & 0x80) != 0
        let opcode = b[0] & 0x0F
        let masked = (b[1] & 0x80) != 0
        var len = Int(b[1] & 0x7F)
        var offset = 2
        if len == 126 {
            guard b.count >= offset + 2 else { return .incomplete }
            len = (Int(b[offset]) << 8) | Int(b[offset + 1]); offset += 2
        } else if len == 127 {
            guard b.count >= offset + 8 else { return .incomplete }
            var v = 0
            for i in 0..<8 { v = (v << 8) | Int(b[offset + i]) }
            len = v; offset += 8
        }
        var maskKey: [UInt8] = []
        if masked {
            guard b.count >= offset + 4 else { return .incomplete }
            maskKey = Array(b[offset..<offset + 4]); offset += 4
        }
        guard len >= 0, b.count >= offset + len else { return .incomplete }
        var payload = Array(b[offset..<offset + len])
        if masked {
            for i in payload.indices { payload[i] ^= maskKey[i % 4] }
        }
        return .frame(Frame(opcode: opcode, fin: fin, payload: Data(payload)), consumed: offset + len)
    }
}
