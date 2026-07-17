import XCTest
@testable import muxa

/// 탭 제목 축약 — 셸이 보내는 긴 제목이 탭 폭을 넘겨 잘리는 걸 막는다.
final class TabTitleTests: XCTestCase {
    func testShellDefaultTitleKeepsOnlyLastFolder() {
        XCTAssertEqual(TabTitle.shorten("yj@youngjunui-MacBookPro:~/Documents/private/muxa"), "muxa")
        XCTAssertEqual(TabTitle.shorten("root@server:/var/log"), "log")
    }

    /// 홈·루트는 폴더 이름을 못 뽑으니 그 자체를 이름으로 쓴다.
    func testHomeAndRootStayAsIs() {
        XCTAssertEqual(TabTitle.shorten("yj@mac:~"), "~")
        XCTAssertEqual(TabTitle.shorten("yj@mac:/"), "/")
    }

    /// 에이전트가 도는 중이면 셸이 명령명을 제목으로 보낸다 — 그건 손대지 않는다(그게 알고 싶은 정보다).
    func testNonShellTitlesUntouched() {
        XCTAssertEqual(TabTitle.shorten("claude"), "claude")
        XCTAssertEqual(TabTitle.shorten("vim README.md"), "vim README.md")
        XCTAssertEqual(TabTitle.shorten("build: 3 warnings"), "build: 3 warnings") // 콜론은 있지만 @가 없다
        // @와 콜론이 다 있어도 명령 제목이면 건드리지 않는다 — 콜론 앞이 공백 없는 한 덩어리여야 한다.
        XCTAssertEqual(TabTitle.shorten("vim user@host:config"), "vim user@host:config")
        XCTAssertEqual(TabTitle.shorten("ssh me@box: connecting"), "ssh me@box: connecting")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(TabTitle.shorten("  yj@mac:~/Code/app  "), "app")
    }

    // MARK: decorate — 지속 세션(∞) 접두. 상태 마크가 아이콘 슬롯을 차지해도 제목이 ∞를 말한다.

    /// 지속 탭만 접두가 붙고, 일반 탭은 원형 그대로.
    func testDecoratePrefixesOnlyPersistent() {
        XCTAssertEqual(TabTitle.decorate("muxa", persistent: true), "∞ muxa")
        XCTAssertEqual(TabTitle.decorate("muxa", persistent: false), "muxa")
    }

    /// 멱등 — 엔진 제목 갱신마다 관문(pushTitle)을 다시 지나도 접두가 겹으로 안 붙는다.
    /// 사용자가 손수 "∞ "로 시작하는 이름을 지어도 마찬가지.
    func testDecorateIsIdempotent() {
        XCTAssertEqual(TabTitle.decorate("∞ muxa", persistent: true), "∞ muxa")
        XCTAssertEqual(TabTitle.decorate(TabTitle.decorate("빌드", persistent: true), persistent: true),
                       "∞ 빌드")
    }
}
