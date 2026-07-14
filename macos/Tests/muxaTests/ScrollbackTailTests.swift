import Foundation
import Testing
@testable import muxa

/// 스크롤백 원본을 **꼬리만** 읽는 경로 — 절단면(깨진 첫 줄)을 버려 이스케이프 잔해가 본문에 남지 않게 한다.
struct ScrollbackTailTests {
    @Test("절단된 첫 줄은 통째로 버린다")
    func 깨진첫줄버리기() {
        #expect(ScrollbackText.dropPartialFirstLine("31m깨진잔해\n정상\n마지막") == "정상\n마지막")
    }

    @Test("개행이 없으면 전부 버린다 (한 줄뿐이면 통째로 절단면)")
    func 개행없으면전부버린다() {
        #expect(ScrollbackText.dropPartialFirstLine("잔해뿐") == "")
    }

    @Test("파일 꼬리만 읽고 상한 안이면 원본 그대로")
    func 상한안이면원본그대로() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxa-tail-\(UUID().uuidString).txt")
        try "첫줄\n둘째줄\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ScrollbackStore.readTail(path: url.path) == "첫줄\n둘째줄\n")
    }

    @Test("상한을 넘으면 꼬리만 읽고 깨진 첫 줄을 버린다")
    func 상한넘으면꼬리만() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxa-tail-\(UUID().uuidString).txt")
        let body = (1...200).map { "line\($0)" }.joined(separator: "\n")
        try body.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let tail = try #require(ScrollbackStore.readTail(path: url.path, maxBytes: 40))
        #expect(tail.hasSuffix("line200"))
        #expect(!tail.contains("line1\n")) // 앞부분은 안 실린다
        #expect(!tail.hasPrefix("ine")) // 절단으로 깨진 첫 줄은 버려진다
        #expect(tail.utf8.count <= 40)
    }

    @Test("빈 파일이면 nil")
    func 빈파일() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxa-tail-\(UUID().uuidString).txt")
        try "".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ScrollbackStore.readTail(path: url.path) == nil)
    }
}
