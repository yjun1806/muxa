import Bonsplit
import XCTest

@testable import muxa

/// 마지막 입력 프롬프트 순수층 — 파싱(이미지 마커·클램프)·훅 전달·행 제목 승격.
final class AgentPromptTests: XCTestCase {
    // MARK: 파싱

    func testParseKeepsPlainText() {
        let p = AgentPrompt.parse("사이드바에 마지막 프롬프트를 노출해줘")
        XCTAssertEqual(p?.text, "사이드바에 마지막 프롬프트를 노출해줘")
        XCTAssertEqual(p?.imageCount, 0)
        XCTAssertEqual(p?.truncated, false)
    }

    func testParseNilAndBlankReturnNil() {
        XCTAssertNil(AgentPrompt.parse(nil))
        XCTAssertNil(AgentPrompt.parse(""))
        XCTAssertNil(AgentPrompt.parse("  \n "))
    }

    /// 붙여넣은 이미지는 프롬프트에 "[Image #N]" 마커로 들어온다 — 개수로 세고 본문에선 뺀다.
    func testParseCountsAndStripsImageMarkers() {
        let p = AgentPrompt.parse("[Image #1] 이 스크린샷의 간격 틀어진 것 고쳐줘 [Image #2]")
        XCTAssertEqual(p?.imageCount, 2)
        XCTAssertEqual(p?.text, "이 스크린샷의 간격 틀어진 것 고쳐줘")
    }

    /// 이미지만 던진 턴 — 본문은 비어도 프롬프트는 있다(행이 "이미지 N장"으로 말한다).
    func testParseImageOnlyPromptSurvives() {
        let p = AgentPrompt.parse("[Image #1]")
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.text, "")
        XCTAssertEqual(p?.imageCount, 1)
    }

    /// 긴 프롬프트는 저장 시점에 자른다 — hover 팝오버도 전문 무한정은 아니다(메모리·표시 모두).
    func testParseClampsLongText() {
        let long = String(repeating: "가", count: AgentPrompt.textMax + 100)
        let p = AgentPrompt.parse(long)
        XCTAssertEqual(p?.text.count, AgentPrompt.textMax + 1) // +1 = 말줄임표
        XCTAssertEqual(p?.text.hasSuffix("…"), true)
        XCTAssertEqual(p?.truncated, true)
    }

    /// 행 제목은 한 줄 — 개행은 공백으로 평탄화한다.
    func testOneLineFlattensNewlines() {
        let p = AgentPrompt.parse("첫 줄이다\n둘째 줄이다\n\n셋째")
        XCTAssertEqual(p?.oneLine, "첫 줄이다 둘째 줄이다 셋째")
    }

    // MARK: 훅 전달 — UserPromptSubmit payload의 prompt가 outcome에 실린다

    private func interpret(_ json: String) -> HookOutcome {
        guard let payload = ClaudeHookPayload.parse(Data(json.utf8)) else {
            XCTFail("payload 파싱 실패: \(json)")
            return HookOutcome()
        }
        return ClaudeHookInterpreter.interpret(
            event: .userPromptSubmit, payload: payload, state: HookSessionState()
        ).outcome
    }

    func testUserPromptSubmitCarriesPrompt() {
        let outcome = interpret(#"{"prompt": "make test 돌리고 실패 원인 고쳐줘"}"#)
        XCTAssertEqual(outcome.prompt?.text, "make test 돌리고 실패 원인 고쳐줘")
        XCTAssertEqual(outcome.state, .working)
    }

    func testUserPromptSubmitWithoutPromptFieldIsNil() {
        XCTAssertNil(interpret("{}").prompt)
    }

    /// 다른 이벤트(Stop 등)는 prompt를 건드리지 않는다 — "변화 없음"과 "지우기"가 안 섞이게.
    func testStopDoesNotCarryPrompt() {
        guard let payload = ClaudeHookPayload.parse(Data(#"{"prompt": "이건 무시"}"#.utf8)) else {
            return XCTFail("payload 파싱 실패")
        }
        let outcome = ClaudeHookInterpreter.interpret(
            event: .stop, payload: payload, state: HookSessionState()
        ).outcome
        XCTAssertNil(outcome.prompt)
    }

    // MARK: 행 제목 승격 — 프롬프트가 곧 행의 이름(B+C)

    private func row(prompt: AgentPrompt?, viewerKind: String? = nil, isAgent: Bool = true) -> AgentRow {
        AgentRow(tabId: TabID(), title: "claude", state: .working, detail: "실행 중: swift",
                 waitingSeconds: nil, isAgent: isAgent, typeIcon: "terminal",
                 viewerKind: viewerKind, prompt: prompt)
    }

    func testPromptBecomesRowTitle() {
        let r = row(prompt: AgentPrompt.parse("사이드바 고쳐줘"))
        XCTAssertEqual(r.promptTitle, "사이드바 고쳐줘")
    }

    /// 프롬프트가 없으면(비에이전트·훅 이전 세션) 현행 한 줄 표시로 폴백 — 승격 없음.
    func testNoPromptMeansNoPromotedTitle() {
        XCTAssertNil(row(prompt: nil).promptTitle)
    }

    /// 이미지만 던진 턴은 "이미지 N장"이 제목이 된다(빈 제목 금지).
    func testImageOnlyPromptTitleSaysImageCount() {
        let r = row(prompt: AgentPrompt.parse("[Image #2][Image #1]"))
        XCTAssertEqual(r.promptTitle, "이미지 2장")
    }

    /// 뷰어(문서·코드…) 행은 종류가 이름이다 — 프롬프트가 있어도 승격하지 않는다.
    func testViewerRowsKeepKindAsTitle() {
        let r = row(prompt: AgentPrompt.parse("무관한 프롬프트"), viewerKind: "문서")
        XCTAssertNil(r.promptTitle)
    }
}
