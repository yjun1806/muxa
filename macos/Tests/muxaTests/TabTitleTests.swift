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
}
