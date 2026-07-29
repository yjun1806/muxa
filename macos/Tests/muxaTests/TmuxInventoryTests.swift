import Foundation
import Testing
@testable import muxa

/// 세션 인벤토리의 판정(순수) — `list-panes` 출력 → 표의 행.
///
/// 이 판정이 틀리면 사람이 **잘못된 근거로 세션을 죽인다**. 특히 고아 표시는 "지워도 된다"로 읽히므로
/// 모호할 때는 고아라고 말하지 않는 쪽으로 기운다(GC의 보수성과 같은 방향).
struct TmuxInventoryTests {
    // 실측 세션명(2026-07-29 `muxa-services` 소켓).
    private let term = "muxa__93903E7D-BFBA-489E-AB2E-FA1F680C43C4__term__F927EF89-0050-4687-A70F-16B897D38C14"
    private let script = "muxa__5FF2728E-EF5E-4762-9AF7-1289B08F08DE__script__D125F850-1C77-484B-9545-6E6AC040A62F"
    private let service = "muxa__93903E7D-BFBA-489E-AB2E-FA1F680C43C4__S1"

    /// 세 네임스페이스가 각자의 파서로 갈린다. 규약은 `TerminalSession`·`ScriptSession`·
    /// `ServiceSession`이 소유하고 여기서는 **되묻기만** 한다(규약을 두 번 쓰면 갈라진다).
    @Test func classifiesEachNamespace() {
        #expect(TmuxInventory.classify(term).kind == .terminal)
        #expect(TmuxInventory.classify(script).kind == .script)
        #expect(TmuxInventory.classify(service).kind == .service)
        #expect(TmuxInventory.classify(term).projectId == "93903E7D-BFBA-489E-AB2E-FA1F680C43C4")
    }

    /// muxa 규약 밖 세션은 `foreign` — 소켓 이름이 `muxa*`여도 세션까지 우리 것이란 보장은 없다
    /// (출처 미상인 `muxa_test_*` 소켓이 실제로 있다).
    @Test func classifiesForeignSessions() {
        #expect(TmuxInventory.classify("scratch").kind == .foreign)
        #expect(TmuxInventory.classify("muxa__onlytwo").kind == .foreign)
        #expect(TmuxInventory.classify("scratch").projectId == nil)
    }

    @Test func parsesRowFields() {
        let raw = "\(term)|1753776593|1|0|0|4242|/Users/yj/Documents/private/muxa"
        let rows = TmuxInventory.parse(raw, socket: "muxa-services")
        #expect(rows.count == 1)
        let row = try! #require(rows.first)
        #expect(row.socket == "muxa-services")
        #expect(row.name == term)
        #expect(row.kind == .terminal)
        #expect(row.isAttached)
        #expect(!row.isDead)
        #expect(row.panePid == 4242)
        #expect(row.path == "/Users/yj/Documents/private/muxa")
        #expect(row.createdAt == Date(timeIntervalSince1970: 1_753_776_593))
    }

    /// **경로는 마지막 필드고, 나머지를 통째로 잇는다.** 경로에 `|`가 들어가는 건 드물지만 가능하고,
    /// 그때 앞 필드가 밀리면 pid·dead가 통째로 어긋난다(엉뚱한 세션을 죽이는 길).
    @Test func pathMayContainSeparator() {
        let raw = "\(term)|1753776593|0|0|0|1|/Users/yj/a|b"
        let row = try! #require(TmuxInventory.parse(raw, socket: "s").first)
        #expect(row.path == "/Users/yj/a|b")
        #expect(row.panePid == 1)
    }

    /// **최소 인덱스 pane이 그 세션의 상태다.** 사용자가 attach해 화면을 나누면 더 높은 인덱스의
    /// 셸 pane이 붙는데, 그걸 집으면 죽은 서비스가 살아있는 것으로 보인다
    /// (`ServiceSession.parsePanes`가 같은 이유로 같은 규칙을 쓴다 — pane 0을 하드코딩하지 않는다).
    @Test func lowestPaneIndexWins() {
        let raw = """
        \(script)|100|0|1|0|900|/live
        \(script)|100|0|0|1|800|/dead
        """
        let rows = TmuxInventory.parse(raw, socket: "s")
        #expect(rows.count == 1)
        #expect(rows.first?.isDead == true)
        #expect(rows.first?.panePid == 800)
    }

    /// 형식이 어긋난 줄은 조용히 버린다 — 상태를 지어내지 않는다.
    @Test func dropsMalformedLines() {
        let raw = """
        쓰레기
        \(term)|100|0|0|0|1|/ok
        너무|적은|필드
        """
        #expect(TmuxInventory.parse(raw, socket: "s").count == 1)
    }

    /// 죽은 pane은 pid가 없을 수 있다(프로세스가 사라졌다) — 0/빈 값은 nil로 다룬다.
    @Test func deadPaneHasNoPid() {
        let raw = "\(script)|100|0|0|1|0|"
        let row = try! #require(TmuxInventory.parse(raw, socket: "s").first)
        #expect(row.isDead)
        #expect(row.panePid == nil)
        #expect(row.path.isEmpty)
    }

    /// 등록된 프로젝트의 세션은 고아가 아니다.
    @Test func knownProjectIsNotOrphan() {
        let rows = TmuxInventory.parse("\(term)|100|0|0|0|1|/x", socket: "s")
        let marked = TmuxInventory.markOrphans(rows, knownProjectIds: ["93903E7D-BFBA-489E-AB2E-FA1F680C43C4"])
        #expect(marked.first?.isOrphan == false)
    }

    /// 등록에 없는 프로젝트의 세션 = 고아(추정). 실측에서 29/29가 여기 걸렸다.
    @Test func unknownProjectIsOrphan() {
        let rows = TmuxInventory.parse("\(term)|100|0|0|0|1|/x", socket: "s")
        #expect(TmuxInventory.markOrphans(rows, knownProjectIds: ["다른-id"]).first?.isOrphan == true)
    }

    /// **아는 프로젝트가 하나도 없으면 아무것도 고아라 하지 않는다.**
    /// 빈 집합은 "고아뿐"이 아니라 "아직 모른다"는 뜻이다(앱 기동 직후·state 로드 실패).
    /// 이걸 고아로 칠하면 표 전체가 빨개져 사람이 그걸 근거로 멀쩡한 세션을 죽인다.
    /// GC(`ServiceSession.orphans`)가 같은 상황에서 아무것도 안 지우는 것과 같은 보수성이다.
    @Test func emptyKnownSetMarksNothing() {
        let rows = TmuxInventory.parse("\(term)|100|0|0|0|1|/x", socket: "s")
        #expect(TmuxInventory.markOrphans(rows, knownProjectIds: []).first?.isOrphan == false)
    }

    /// 남의 세션은 고아 판정 대상이 아니다 — 우리 규약 밖이라 등록 여부를 물을 근거가 없다.
    @Test func foreignSessionIsNeverOrphan() {
        let rows = TmuxInventory.parse("scratch|100|0|0|0|1|/x", socket: "s")
        #expect(TmuxInventory.markOrphans(rows, knownProjectIds: ["아무거나"]).first?.isOrphan == false)
    }

    /// 같은 이름의 세션이 **소켓마다 따로 존재**할 수 있다(dev 빌드가 같은 프로젝트를 열면 그렇다).
    /// id가 이름만이면 표에서 둘이 하나로 합쳐져 엉뚱한 쪽을 죽인다.
    @Test func identityIncludesSocket() {
        let a = TmuxInventory.parse("\(term)|100|0|0|0|1|/x", socket: "muxa-services").first
        let b = TmuxInventory.parse("\(term)|100|0|0|0|1|/x", socket: "muxa-services-dev-1").first
        #expect(a?.id != b?.id)
    }
}
