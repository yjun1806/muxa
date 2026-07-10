import Bonsplit
import Foundation

/// 스크롤백 텍스트 정제 — 순수 로직(부작용 없음). libghostty read_text가 이미 평문(SGR 없음)을
/// 주지만 방어적으로 잔여 제어/OSC 시퀀스를 걷어내고 용량 상한(줄·바이트)을 적용한다.
/// 최신 내용이 가장 쓸모 있으므로 상한 초과 시 앞을 버리고 꼬리(가장 최근)를 남긴다.
enum ScrollbackText {
    /// 저장 상한 — 스크롤백은 커질 수 있어 파일·메모리를 제한한다.
    static let maxLines = 4000
    static let maxBytes = 400_000

    /// 색/제어 스트립 → 줄 상한(꼬리) → 바이트 상한(UTF-8 안전, 꼬리). 셋 다 적용한 문자열.
    static func sanitize(_ raw: String, maxLines: Int = maxLines, maxBytes: Int = maxBytes) -> String {
        capBytes(capLines(strip(raw), maxLines: maxLines), maxBytes: maxBytes)
    }

    /// ESC 기반 시퀀스(CSI·OSC·기타 Fe)와 C0 제어문자를 제거. 개행(\n)·탭(\t)만 보존, \r는 버린다.
    static func strip(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        out.reserveCapacity(scalars.count)
        var i = 0
        let n = scalars.count
        while i < n {
            let c = scalars[i]
            if c.value == 0x1B { // ESC
                i += 1
                guard i < n else { break }
                let next = scalars[i]
                switch next.value {
                case 0x5B: // '[' CSI — 종결자 0x40~0x7E까지 소비
                    i += 1
                    while i < n, !(scalars[i].value >= 0x40 && scalars[i].value <= 0x7E) { i += 1 }
                    i += 1 // 종결자 소비
                case 0x5D: // ']' OSC — BEL(0x07) 또는 ST(ESC \)까지 소비
                    i += 1
                    while i < n {
                        if scalars[i].value == 0x07 { i += 1; break }
                        if scalars[i].value == 0x1B, i + 1 < n, scalars[i + 1].value == 0x5C { i += 2; break }
                        i += 1
                    }
                default: // 2문자 Fe 시퀀스 등 — 다음 한 문자만 소비
                    i += 1
                }
                continue
            }
            // C0 제어문자 제거(개행·탭 예외). 0x7F(DEL)도 제거.
            if c.value < 0x20 {
                if c.value == 0x0A || c.value == 0x09 { out.append(c) }
            } else if c.value != 0x7F {
                out.append(c)
            }
            i += 1
        }
        return String(out)
    }

    /// 마지막 maxLines 줄만 남긴다(꼬리 보존).
    static func capLines(_ s: String, maxLines: Int) -> String {
        guard maxLines > 0 else { return "" }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return s }
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    /// UTF-8 바이트 상한 — 문자(grapheme) 경계에서 꼬리를 남겨 안전 절단.
    static func capBytes(_ s: String, maxBytes: Int) -> String {
        guard s.utf8.count > maxBytes else { return s }
        let chars = Array(s)
        var kept = 0
        var idx = chars.count
        while idx > 0 {
            let b = String(chars[idx - 1]).utf8.count
            if kept + b > maxBytes { break }
            kept += b
            idx -= 1
        }
        return String(chars[idx...])
    }
}

/// 스크롤백 파일 저장소 — 경계 타입(파일 IO 부작용 격리). 탭별로 별도 파일에 쓴다
/// (스냅샷 JSON에 큰 텍스트를 넣지 않게). 위치: applicationSupport/muxa/scrollback/<tabId>.txt.
enum ScrollbackStore {
    /// scrollback 디렉터리(없으면 생성). muxa 베이스 아래 하위 디렉터리(단일 경로 소유자 재사용).
    static let directory: URL = MuxaSupportDir.subdirectory("scrollback")

    static func fileURL(for tabId: TabID) -> URL {
        directory.appendingPathComponent("\(tabId.uuid.uuidString).txt")
    }

    /// 정제된 스크롤백을 파일에 쓴다. 빈 문자열이면 저장하지 않고 nil. 성공 시 파일 경로.
    static func write(_ text: String, for tabId: TabID) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = fileURL(for: tabId)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch {
            return nil
        }
    }

    /// 탭이 닫힐 때 해당 스크롤백 파일 정리.
    static func delete(for tabId: TabID) {
        try? FileManager.default.removeItem(at: fileURL(for: tabId))
    }
}
