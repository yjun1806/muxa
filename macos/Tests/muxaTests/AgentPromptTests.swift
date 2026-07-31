import Bonsplit
import Foundation
import Testing

@testable import muxa

/// 마지막 입력 프롬프트 순수층 — 파싱(이미지 마커·클램프)·훅 전달·행 제목 승격.
struct AgentPromptTests {
    // MARK: 파싱

    @Test func parseKeepsPlainText() {
        let p = AgentPrompt.parse("사이드바에 마지막 프롬프트를 노출해줘")
        #expect(p?.text == "사이드바에 마지막 프롬프트를 노출해줘")
        #expect(p?.imageCount == 0)
        #expect(p?.truncated == false)
    }

    @Test func parseNilAndBlankReturnNil() {
        #expect(AgentPrompt.parse(nil) == nil)
        #expect(AgentPrompt.parse("") == nil)
        #expect(AgentPrompt.parse("  \n ") == nil)
    }

    /// 붙여넣은 이미지는 프롬프트에 "[Image #N]" 마커로 들어온다 — 개수로 세고 본문에선 뺀다.
    @Test func parseCountsAndStripsImageMarkers() {
        let p = AgentPrompt.parse("[Image #1] 이 스크린샷의 간격 틀어진 것 고쳐줘 [Image #2]")
        #expect(p?.imageCount == 2)
        #expect(p?.text == "이 스크린샷의 간격 틀어진 것 고쳐줘")
    }

    /// 이미지만 던진 턴 — 본문은 비어도 프롬프트는 있다(행이 "이미지 N장"으로 말한다).
    @Test func parseImageOnlyPromptSurvives() {
        let p = AgentPrompt.parse("[Image #1]")
        #expect(p != nil)
        #expect(p?.text == "")
        #expect(p?.imageCount == 1)
    }

    /// 긴 프롬프트는 저장 시점에 자른다 — hover 팝오버도 전문 무한정은 아니다(메모리·표시 모두).
    @Test func parseClampsLongText() {
        let long = String(repeating: "가", count: AgentPrompt.textMax + 100)
        let p = AgentPrompt.parse(long)
        #expect(p?.text.count == AgentPrompt.textMax + 1) // +1 = 말줄임표
        #expect(p?.text.hasSuffix("…") == true)
        #expect(p?.truncated == true)
    }

    /// 행 제목은 한 줄 — 개행은 공백으로 평탄화한다.
    @Test func oneLineFlattensNewlines() {
        let p = AgentPrompt.parse("첫 줄이다\n둘째 줄이다\n\n셋째")
        #expect(p?.oneLine == "첫 줄이다 둘째 줄이다 셋째")
    }

    // MARK: 훅 전달 — UserPromptSubmit payload의 prompt가 outcome에 실린다

    private func interpret(_ json: String) -> HookOutcome {
        guard let payload = ClaudeHookPayload.parse(Data(json.utf8)) else {
            Issue.record("payload 파싱 실패: \(json)")
            return HookOutcome()
        }
        return ClaudeHookInterpreter.interpret(
            event: .userPromptSubmit, payload: payload, state: HookSessionState()
        ).outcome
    }

    @Test func userPromptSubmitCarriesPrompt() {
        let outcome = interpret(#"{"prompt": "make test 돌리고 실패 원인 고쳐줘"}"#)
        #expect(outcome.prompt?.text == "make test 돌리고 실패 원인 고쳐줘")
        #expect(outcome.state == .working)
    }

    @Test func userPromptSubmitWithoutPromptFieldIsNil() {
        #expect(interpret("{}").prompt == nil)
    }

    /// 다른 이벤트(Stop 등)는 prompt를 건드리지 않는다 — "변화 없음"과 "지우기"가 안 섞이게.
    @Test func stopDoesNotCarryPrompt() {
        guard let payload = ClaudeHookPayload.parse(Data(#"{"prompt": "이건 무시"}"#.utf8)) else {
            Issue.record("payload 파싱 실패")
            return
        }
        let outcome = ClaudeHookInterpreter.interpret(
            event: .stop, payload: payload, state: HookSessionState()
        ).outcome
        #expect(outcome.prompt == nil)
    }

    // MARK: 행 제목 승격 — 프롬프트가 곧 행의 이름(B+C)

    private func row(prompt: AgentPrompt?, viewerKind: String? = nil, isAgent: Bool = true) -> AgentRow {
        AgentRow(tabId: TabID(), title: "claude", state: .working, detail: "실행 중: swift",
                 waitingSeconds: nil, isAgent: isAgent, typeIcon: "terminal",
                 viewerKind: viewerKind, prompt: prompt)
    }

    @Test func promptBecomesRowTitle() {
        let r = row(prompt: AgentPrompt.parse("사이드바 고쳐줘"))
        #expect(r.promptTitle == "사이드바 고쳐줘")
    }

    /// 프롬프트가 없으면(비에이전트·훅 이전 세션) 현행 한 줄 표시로 폴백 — 승격 없음.
    @Test func noPromptMeansNoPromotedTitle() {
        #expect(row(prompt: nil).promptTitle == nil)
    }

    /// 이미지만 던진 턴은 "이미지 N장"이 제목이 된다(빈 제목 금지).
    @Test func imageOnlyPromptTitleSaysImageCount() {
        let r = row(prompt: AgentPrompt.parse("[Image #2][Image #1]"))
        #expect(r.promptTitle == "이미지 2장")
    }

    /// 뷰어(문서·코드…) 행은 종류가 이름이다 — 프롬프트가 있어도 승격하지 않는다.
    @Test func viewerRowsKeepKindAsTitle() {
        let r = row(prompt: AgentPrompt.parse("무관한 프롬프트"), viewerKind: "문서")
        #expect(r.promptTitle == nil)
    }
}
