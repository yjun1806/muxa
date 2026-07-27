import Foundation
import Testing
@testable import muxa

/// 탭별 IDE 포트 기억의 순수 판정 — 저장 파일이 깨져도 **기억을 잃을 뿐 동작은 계속돼야** 하고,
/// 이상한 포트로는 절대 바인딩을 시도하지 않아야 한다(YJ-3).
struct IdePortStoreTests {
    /// 키는 탭 id가 아니라 **tmux 세션 이름**이다 — 탭 id는 재시작 때 새로 생기지만 세션 이름은
    /// 저장돼 살아남는다(YJ-3 조사에서 확인).
    private let tab = "muxa__F2AF1DD9-90D0-45BA-B24B-C9D8DDC5F657__term__4E78113E-C6CA-4C36-BFBE-E3C881D98A11"

    // MARK: 다시 쓸 포트 고르기

    @Test func 기억한_포트를_그대로_돌려준다() {
        #expect(IdePortStore.preferredPort([tab: 63437], for: tab) == 63437)
    }

    @Test func 모르는_탭은_nil이다() {
        #expect(IdePortStore.preferredPort([tab: 63437], for: "다른세션") == nil)
    }

    @Test func 특권_포트와_0은_무시한다() {
        // 저장 파일이 손상됐거나 옛 형식일 때 엉뚱한 곳에 바인딩하지 않게 하는 방어선.
        #expect(IdePortStore.preferredPort([tab: 0], for: tab) == nil)
        #expect(IdePortStore.preferredPort([tab: 80], for: tab) == nil)
        #expect(IdePortStore.preferredPort([tab: 1023], for: tab) == nil)
        #expect(IdePortStore.preferredPort([tab: 1024], for: tab) == 1024)
    }

    // MARK: 저장 파일 해석

    @Test func 정상_파일을_읽는다() throws {
        let data = try #require(#"{"\#(tab)":63437}"#.data(using: .utf8))
        #expect(IdePortStore.decode(data) == [tab: 63437])
    }

    @Test func 깨진_파일은_빈_맵이다() throws {
        // 기억만 잃고 랜덤 포트로 계속 동작한다 — 크래시도, 예외도 아니다.
        let garbage = try #require("이건 JSON이 아니다".data(using: .utf8))
        #expect(IdePortStore.decode(garbage).isEmpty)
        let wrongShape = try #require(#"{"tab":"63437"}"#.data(using: .utf8))
        #expect(IdePortStore.decode(wrongShape).isEmpty)
    }

    @Test func 범위를_벗어난_항목만_버리고_나머지는_살린다() throws {
        let data = try #require(#"{"a":63437,"b":0,"c":70000,"d":443}"#.data(using: .utf8))
        #expect(IdePortStore.decode(data) == ["a": 63437])
    }
}
