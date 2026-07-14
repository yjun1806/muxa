import Bonsplit
import Foundation

/// 스크롤백 텍스트 정제 — 순수 로직(부작용 없음). libghostty read_text가 이미 평문(SGR 없음)을
/// 주지만 방어적으로 잔여 제어/OSC 시퀀스를 걷어내고 용량 상한(줄·바이트)을 적용한다.
/// 최신 내용이 가장 쓸모 있으므로 상한 초과 시 앞을 버리고 꼬리(가장 최근)를 남긴다.
enum ScrollbackText {
    /// 저장 상한 — 스크롤백은 커질 수 있어 파일·메모리를 제한한다.
    static let maxLines = 4000
    static let maxBytes = 400_000

    /// **원본 읽기 상한** — 정제 전에 파일 꼬리만 올린다. 상한(maxBytes)이 어차피 꼬리를 남기므로
    /// 8MB짜리 덤프를 통째로 문자열로 올릴 이유가 없다(strip은 원본 전체를 스칼라 배열로 복사하고
    /// capLines는 원본 전체를 split한다 — ⌘Q 종료가 메인 스레드에서 터미널당 수백 ms를 먹었다).
    /// 여유(2배)는 strip으로 사라질 몫(테마 OSC)과 줄 경계 절단분을 감안한 것.
    static let captureBytes = 2 * maxBytes

    /// 색/제어 스트립 → 줄 상한(꼬리) → 바이트 상한(UTF-8 안전, 꼬리). 셋 다 적용한 문자열.
    static func sanitize(_ raw: String, maxLines: Int = maxLines, maxBytes: Int = maxBytes) -> String {
        capBytes(capLines(strip(raw), maxLines: maxLines), maxBytes: maxBytes)
    }

    // MARK: VT 경로 — 색을 살린 채 저장한다

    /// VT 덤프(`write_screen_file:copy,vt`) 위생 처리. 평문 경로(`sanitize`)와 달리 **SGR·OSC 8을 보존**한다.
    ///
    /// 걷어내는 것은 **캡처 당시 테마가 구워진 색상 정의**(OSC 4/5/10~19/104/105/110~119)뿐이다.
    /// 이걸 그대로 재주입하면 라이트→다크로 테마를 바꾼 뒤 복원할 때 배경과 글자가 같은 색이 된다
    /// (cmux 이슈 #5165). 앞뒤를 reset으로 감싸 잔여 속성이 새 프롬프트로 새지 않게 한다.
    static func sanitizeVT(_ raw: String, maxLines: Int = maxLines, maxBytes: Int = maxBytes) -> String {
        let stripped = stripThemeOSC(raw)
        let capped = capBytesVT(capLines(stripped, maxLines: maxLines), maxBytes: maxBytes)
        let body = capped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "" }
        return "\u{1B}[0m" + capped + "\u{1B}[0m"
    }

    /// 색상 정의 OSC만 제거한다. SGR(`ESC[…m`)·OSC 8(하이퍼링크)·본문은 그대로 통과시킨다.
    static func stripThemeOSC(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        out.reserveCapacity(scalars.count)
        var i = 0
        let n = scalars.count
        while i < n {
            // ESC ] <숫자> … (BEL | ST) 형태만 들여다본다.
            guard scalars[i].value == 0x1B, i + 1 < n, scalars[i + 1].value == 0x5D else {
                out.append(scalars[i]); i += 1; continue
            }
            // OSC 코드(숫자) 파싱
            var j = i + 2
            var code = 0
            var hasDigit = false
            while j < n, let d = scalars[j].properties.numericValue, scalars[j].value < 0x80 {
                code = code * 10 + Int(d); hasDigit = true; j += 1
            }
            // 종결자(BEL 또는 ESC \)까지의 끝을 찾는다.
            var end = j
            while end < n {
                if scalars[end].value == 0x07 { end += 1; break }
                if scalars[end].value == 0x1B, end + 1 < n, scalars[end + 1].value == 0x5C { end += 2; break }
                end += 1
            }
            if hasDigit, isThemeOSC(code) {
                i = end // 색상 정의 — 통째로 버린다
            } else {
                out.append(contentsOf: scalars[i..<end]) // OSC 8 등은 원형 보존
                i = end
            }
        }
        return String(out)
    }

    /// 테마를 굽는 OSC 코드인가 — 팔레트·전경/배경·커서색 정의와 그 리셋들.
    private static func isThemeOSC(_ code: Int) -> Bool {
        code == 4 || code == 5
            || (code >= 10 && code <= 19)
            || code == 104 || code == 105
            || (code >= 110 && code <= 119)
    }

    /// 바이트 상한(꼬리 보존) — 자르고 나서 **깨진 첫 줄을 통째로 버린다**.
    /// 문자 단위로 자르면 이스케이프 시퀀스 중간이 끊겨 "31m" 같은 잔해가 본문으로 출력된다.
    static func capBytesVT(_ s: String, maxBytes: Int) -> String {
        guard s.utf8.count > maxBytes else { return s }
        return dropPartialFirstLine(capBytes(s, maxBytes: maxBytes))
    }

    /// 꼬리를 잘라낸 텍스트의 **첫 줄을 버린다** — 절단면은 이스케이프 시퀀스 중간일 수 있다.
    /// 개행이 없으면(한 줄뿐) 통째로 버린다. 파일 꼬리 읽기(ScrollbackStore.readTail)와 공유하는 규칙.
    static func dropPartialFirstLine(_ s: String) -> String {
        guard let nl = s.firstIndex(of: "\n") else { return "" }
        return String(s[s.index(after: nl)...])
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

    /// 파일 **꼬리**에서 최대 maxBytes만 읽는다(원본 전체를 메모리에 올리지 않는다 — TranscriptTail과 같은 패턴).
    /// 잘렸으면 깨진 첫 줄을 버린다(순수 판정은 ScrollbackText.dropPartialFirstLine).
    static func readTail(path: String, maxBytes: Int = ScrollbackText.captureBytes) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let truncated = size > UInt64(maxBytes)
        let offset = truncated ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty
        else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        return truncated ? ScrollbackText.dropPartialFirstLine(text) : text
    }

    /// 탭이 닫힐 때 해당 스크롤백 파일 정리.
    static func delete(for tabId: TabID) {
        try? FileManager.default.removeItem(at: fileURL(for: tabId))
    }

    // MARK: 고아 파일 GC — 복원 시 새 tabId 발급으로 남는 이전 파일 정리 (디스크 누수 방지)
    //
    // 복원은 controller.createTab이 새 UUID를 발급하므로 이전 tabId 이름의 스크롤백 파일이 고아가 된다.
    // "삭제 대상 판정"은 순수 함수(orphans)로 뽑아 테스트하고, 스캔·삭제(부작용)만 경계(collectGarbage)에 둔다.

    /// GC의 mtime 유예(초) — 참조 집합이 곧 진실이지만, 방금 쓰였는데 아직 어디에도 안 실린
    /// 파일을 실수로 지우지 않게 유예 안쪽(최근)에 수정된 파일은 무조건 보존한다(활성 파일 방어, 안전 최우선).
    static let orphanGraceInterval: TimeInterval = 3600 // 1시간

    /// 스크롤백 파일 하나의 GC 판정 입력(순수) — 경로·tabId키(파일명에서 .txt 제거)·수정시각.
    struct ScrollbackFile: Equatable {
        let path: String
        let tabIdKey: String
        let modified: Date
    }

    /// 삭제해도 안전한 '고아' 파일 경로를 고른다(순수, 부작용 없음).
    /// 보존(=삭제 안 함) 조건 — 하나라도 참이면 남긴다:
    ///  1) 살아있는 탭의 파일(tabIdKey ∈ liveTabIds)
    ///  2) 스냅샷이 아직 참조하는 파일(path ∈ referencedPaths) — 아직 안 연 lazy 프로젝트의 스크롤백 보존
    ///  3) 최근(now-modified < grace) 수정 — 방금 쓰였는데 아직 참조에 안 실린 파일 방어(의심되면 안 지움)
    static func orphans(in files: [ScrollbackFile], liveTabIds: Set<String>,
                        referencedPaths: Set<String>, now: Date,
                        graceInterval: TimeInterval) -> [String] {
        files.filter { file in
            if liveTabIds.contains(file.tabIdKey) { return false }
            if referencedPaths.contains(file.path) { return false }
            if now.timeIntervalSince(file.modified) < graceInterval { return false }
            return true
        }.map(\.path)
    }

    /// 세션 복원이 끝난 뒤 호출 — 살아있는 탭·스냅샷 참조 어디에도 없고 유예를 넘긴 고아 파일을 지운다.
    /// 스캔·삭제(부작용)만 여기, 판정은 orphans(순수)에 위임한다. 판정 못 하면(스캔 실패) 아무것도 안 지운다.
    static func collectGarbage(liveTabIds: Set<String>, referencedPaths: Set<String>,
                               now: Date = Date(), graceInterval: TimeInterval = orphanGraceInterval) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let files: [ScrollbackFile] = entries.compactMap { url in
            guard url.pathExtension == "txt" else { return nil }
            // mtime을 못 읽으면 distantFuture로 둬(=항상 유예 안쪽) 절대 삭제 대상이 안 되게 한다(안전).
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? Date.distantFuture
            return ScrollbackFile(path: url.path,
                                  tabIdKey: url.deletingPathExtension().lastPathComponent,
                                  modified: modified)
        }
        for path in orphans(in: files, liveTabIds: liveTabIds, referencedPaths: referencedPaths,
                            now: now, graceInterval: graceInterval) {
            try? fm.removeItem(at: URL(fileURLWithPath: path))
        }
    }
}
