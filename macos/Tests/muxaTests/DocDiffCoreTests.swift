import Foundation
import Testing
import JavaScriptCore
@testable import muxa

/// JS 하네스를 못 띄웠을 때 던진다. XCTest의 `XCTSkip` 자리인데 — swift-testing에는 런타임
/// 건너뛰기가 없어서 **건너뛰기가 아니라 실패로 잡힌다.** 리소스는 소스 트리에서 직접 읽으므로
/// 못 읽는 건 실제로 고쳐야 할 문제다(관대하게 넘기면 검증을 안 한 채 초록불이 뜬다).
private struct JSHarnessUnavailable: Error, CustomStringConvertible {
    let description: String
}

/// 문서 diff **JS 코어**를 JavaScriptCore에서 직접 돌려 검증한다.
///
/// core.js는 DOM을 안 만지므로 WKWebView 없이 순수 함수처럼 테스트된다 — muxa의
/// "순수 로직은 테스트로 못 박는다"를 JS까지 늘린 장치다. 비동기도 플레이키도 없다.
///
/// **`.serialized`가 필수다.** JSContext를 `sharedCtx`로 공유하고 입력을 `__old`/`__new`
/// 전역에 넣은 뒤 평가하므로, 병렬로 돌면 테스트끼리 서로의 입력을 덮어쓴다(XCTest는 순차라
/// 드러나지 않았다). 컨텍스트를 매번 새로 만들면 병렬이 가능하지만 번들 로딩이 비싸다.
@Suite(.serialized) struct DocDiffCoreTests {

    private static var sharedCtx: JSContext?

    /// markdown-it + dmp + core.js를 얹은 컨텍스트. 번들 로딩이 비싸 한 번만 만든다.
    private func ctx() throws -> JSContext {
        if let c = Self.sharedCtx { return c }
        let c = JSContext()!
        var jsError: String?
        c.exceptionHandler = { _, e in jsError = e?.toString() }

        let res = Self.resourcesDir()
        // paint.js도 얹는다 — DOM은 함수 **안**에서만 만지므로 로드 자체는 JSC에서 안전하고,
        // 오프셋 보정(`_shiftPastDeletions`)은 순수 함수라 DOM 없이 그대로 검증된다.
        for path in ["mdviewer/markdown-it.min.js", "diffdoc/diff-match-patch.js", "diffdoc/core.js",
                     "diffdoc/paint.js"] {
            let url = res.appendingPathComponent(path)
            let src = try String(contentsOf: url, encoding: .utf8)
            c.evaluateScript(src)
            if let e = jsError { throw JSHarnessUnavailable(description: "JS 로드 실패 \(path): \(e)") }
        }
        // core는 렌더러와 **같은 파서 인스턴스**를 쓴다(파서가 둘이면 좌표가 어긋난다).
        c.evaluateScript("globalThis.__diffdocMarkdownIt = markdownit({ html: true, linkify: true });")
        if let e = jsError { throw JSHarnessUnavailable(description: "markdown-it 초기화 실패: \(e)") }
        Self.sharedCtx = c
        return c
    }

    /// 번들 경로 — SPM 리소스 번들이 아니라 소스 트리에서 직접 읽는다(테스트 전용).
    private static func resourcesDir() -> URL {
        URL(fileURLWithPath: #filePath)              // .../Tests/muxaTests/DocDiffCoreTests.swift
            .deletingLastPathComponent()              // muxaTests
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // macos
            .appendingPathComponent("Sources/muxa/Resources")
    }

    /// core를 호출하고 JSON으로 받는다.
    private func diff(_ old: String, _ new: String) throws -> [String: Any] {
        let c = try ctx()
        c.setObject(old, forKeyedSubscript: "__old" as NSString)
        c.setObject(new, forKeyedSubscript: "__new" as NSString)
        guard let v = c.evaluateScript("JSON.stringify(DiffDocCore.computeDocDiff(__old, __new))"),
              let s = v.toString(), let d = s.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            throw JSHarnessUnavailable(description: "core 호출 실패")
        }
        return obj
    }

    private func blocks(_ r: [String: Any]) -> [[String: Any]] { r["blocks"] as? [[String: Any]] ?? [] }
    private func stats(_ r: [String: Any]) -> [String: Int] {
        (r["stats"] as? [String: Any])?.mapValues { ($0 as? Int) ?? 0 } ?? [:]
    }

    // MARK: 환경 — 이게 깨지면 나머지가 다 무의미하다

    @Test func testJSCEnvironmentIsUsable() throws {
        let c = try ctx()
        #expect(c.evaluateScript("typeof markdownit")?.toString() == "function")
        #expect(c.evaluateScript("typeof diff_match_patch")?.toString() == "function")
        #expect(c.evaluateScript("typeof DiffDocCore.computeDocDiff")?.toString() == "function")
        #expect(c.evaluateScript("typeof Intl.Segmenter")?.toString() == "function", "어절 분절이 없으면 2층이 폴백으로 떨어진다")
    }

    // MARK: 1층 — 블록 매칭

    @Test func testIdenticalDocumentHasNoChanges() throws {
        let src = "# 제목\n\n첫 문단입니다.\n\n둘째 문단입니다.\n"
        let s = stats(try diff(src, src))
        #expect(s["inserted"] == 0)
        #expect(s["deleted"] == 0)
        #expect(s["modified"] == 0)
    }

    @Test func testInsertedParagraphIsDetected() throws {
        let r = try diff("# 제목\n\n첫 문단.\n", "# 제목\n\n첫 문단.\n\n새 문단.\n")
        #expect(stats(r)["inserted"] == 1)
        #expect(stats(r)["deleted"] == 0)
    }

    @Test func testDeletedParagraphKeepsItsPlace() throws {
        let r = try diff("# 제목\n\nA 문단.\n\nB 문단.\n", "# 제목\n\nB 문단.\n")
        #expect(stats(r)["deleted"] == 1)
        let kinds = blocks(r).map { $0["kind"] as? String ?? "" }
        // 삭제 블록이 사라지지 않고 목록 안에 남아야 "여기서 뭐가 없어졌다"를 말할 수 있다.
        #expect(kinds.contains("deleted"), "삭제 블록이 목록에서 빠졌다: \(kinds)")
    }

    /// **소스 노이즈 흡수** — 소프트랩만 바뀌면 렌더 결과가 같으므로 무변경이어야 한다.
    @Test func testSoftWrapChangeIsNotAChange() throws {
        let a = "이 문단은 한 줄로 되어 있습니다.\n"
        let b = "이 문단은\n한 줄로\n되어 있습니다.\n"
        let s = stats(try diff(a, b))
        #expect(s["modified"] == 0, "소프트랩 변경이 수정으로 새어나왔다")
        #expect(s["inserted"] == 0)
        #expect(s["deleted"] == 0)
    }

    /// 리스트 마커 교체(`-`↔`*`)도 렌더 결과가 같다.
    @Test func testListMarkerChangeIsNotAChange() throws {
        let s = stats(try diff("- 하나\n- 둘\n", "* 하나\n* 둘\n"))
        #expect(s["modified"] == 0)
        #expect(s["inserted"] == 0)
        #expect(s["deleted"] == 0)
    }

    /// **리스트 항목 추가가 리스트 전체 교체로 보이면 안 된다.**
    @Test func testListItemAdditionOnlyMarksThatItem() throws {
        let r = try diff("- 하나\n- 둘\n", "- 하나\n- 하나 반\n- 둘\n")
        #expect(stats(r)["inserted"] == 1)
        #expect(stats(r)["deleted"] == 0)
        #expect(stats(r)["modified"] == 0)
    }

    // MARK: 2·3층 — 한국어

    /// **핵심** — 조사만 바뀌면 조사만 강조돼야 한다("문단을" 통째가 아니라 "을"만).
    @Test func testKoreanParticleChangeHighlightsOnlyParticle() throws {
        let r = try diff("이 문단을 수정합니다.\n", "이 문단이 수정합니다.\n")
        let mod = blocks(r).first { $0["kind"] as? String == "modified" }
        #expect(mod != nil, "수정으로 안 잡혔다")
        let text = mod?["text"] as? String ?? ""
        let ins = mod?["ins"] as? [[String: Any]] ?? []
        #expect(!(ins.isEmpty), "삽입 스팬이 없다")
        let covered = ins.reduce(0) { $0 + (($1["end"] as? Int ?? 0) - ($1["start"] as? Int ?? 0)) }
        #expect(covered <= 2, "조사 하나(1자)만 강조돼야 하는데 \(covered)자가 칠해졌다 — text=\(text)")
    }

    /// 어미 변화도 공통부는 남아야 한다("수정" + "습니다"는 공통).
    @Test func testKoreanEndingChangeKeepsCommonParts() throws {
        let r = try diff("문서를 수정했습니다.\n", "문서를 수정되었습니다.\n")
        let mod = blocks(r).first { $0["kind"] as? String == "modified" }
        let ins = mod?["ins"] as? [[String: Any]] ?? []
        let covered = ins.reduce(0) { $0 + (($1["end"] as? Int ?? 0) - ($1["start"] as? Int ?? 0)) }
        #expect(covered < 8, "어미만 바뀌었는데 \(covered)자가 칠해졌다")
    }

    /// **과분절 방지** — 완전히 다른 단어는 통째 교체여야 한다(조각조각 나면 안 읽힌다).
    @Test func testUnrelatedWordIsWholeReplacement() throws {
        let c = try ctx()
        let v = c.evaluateScript("DiffDocCore._similarity('고양이','강아지')")
        #expect(v?.toDouble() ?? 1 < 0.5, "닮지 않은 단어가 문자 세분 임계를 넘었다")
    }

    @Test func testSimilarityThresholdsSeparateCases() throws {
        let c = try ctx()
        let particle = c.evaluateScript("DiffDocCore._similarity('문단을','문단이')")?.toDouble() ?? 0
        let ending = c.evaluateScript("DiffDocCore._similarity('수정했습니다','수정되었습니다')")?.toDouble() ?? 0
        #expect(particle >= 0.5, "조사 교체가 임계 아래로 떨어졌다")
        #expect(ending >= 0.5, "어미 변화가 임계 아래로 떨어졌다")
    }

    /// 어절 분절이 한국어에서 기대대로 동작하는지(2층의 전제).
    @Test func testKoreanSegmentation() throws {
        let c = try ctx()
        let v = c.evaluateScript("JSON.stringify(DiffDocCore._segmentsOf('문단을 수정했습니다'))")
        #expect(v?.toString() == "[\"문단을\",\" \",\"수정했습니다\"]")
    }

    // MARK: 과분절 방어 — "단어 수프" 방지

    /// 긴 문단이 사실상 다시 쓰였으면 인라인 강조를 포기하고 **통째 교체**로 보여준다.
    /// 삭제·삽입이 단어마다 뒤엉킨 화면은 diff가 아니라 소음이다(실제로 그런 화면이 나왔다).
    @Test func testHeavilyRewrittenParagraphBecomesWholeReplacement() throws {
        let a = "저장은 recruit_until 컬럼에 기록하고 closed_at 타임스탬프로 수동 마감 시각을 남기며 처리 창 배제 판정에 쓴다. 별도 reason 컬럼은 두지 않는다.\n"
        let b = "기록은 완전히 다른 방식으로 바뀌었다. 유일한 마감은 존재하지 않으며 capacity 또는 manual 중 하나를 골라 필요할 때만 별도로 남긴다.\n"
        let r = try diff(a, b)
        let kinds = blocks(r).map { $0["kind"] as? String ?? "" }
        #expect(!(kinds.contains("modified")), "다시 쓴 문단이 인라인 강조로 남았다 — 단어 수프가 된다: \(kinds)")
        #expect(kinds.contains("deleted") && kinds.contains("inserted"), "통째 교체(삭제+삽입)로 강등되지 않았다: \(kinds)")
    }

    /// **짧은 문장은 강등하지 않는다.** 단어 하나만 바꿔도 비율이 쉽게 50%를 넘는데
    /// 그건 전혀 안 읽히는 화면이 아니다 — 비율 기준은 긴 문단에서만 적용한다.
    @Test func testShortSentenceKeepsInlineHighlight() throws {
        let r = try diff("안녕 반가워\n", "안녕 반갑다\n")
        let kinds = blocks(r).map { $0["kind"] as? String ?? "" }
        #expect(kinds.contains("modified"), "짧은 문장이 통째 교체로 강등됐다: \(kinds)")
    }

    /// 긴 문단에서 한 군데만 고친 건 당연히 인라인으로 남는다.
    @Test func testLongParagraphWithSmallEditStaysInline() throws {
        let base = String(repeating: "이 문장은 충분히 길어서 비율 판정이 적용됩니다. ", count: 4)
        let r = try diff(base + "끝맺음을 수정합니다.\n", base + "끝맺음을 수정했습니다.\n")
        let kinds = blocks(r).map { $0["kind"] as? String ?? "" }
        #expect(kinds.contains("modified"), "작은 수정이 통째 교체로 강등됐다: \(kinds)")
    }

    // MARK: 원자 블록

    /// 코드블록은 **어절** diff 대상이 아니다 — 코드에 워드 하이라이트를 치면 읽히지 않는다.
    /// 대신 **줄** 단위로 짚는다(어느 줄이 바뀌었는지는 알려줘야 한다).
    @Test func testCodeBlockIsLineDiffedNotWordDiffed() throws {
        let a = "```swift\nlet x = 1\n```\n"
        let b = "```swift\nlet x = 2\n```\n"
        let r = try diff(a, b)
        let mod = blocks(r).first { $0["kind"] as? String == "modified" }
        #expect(mod != nil)
        #expect(mod?["codeLines"] as? Bool == true, "줄 단위 diff가 아니다")
        // 어절 세분의 흔적(문자 단위 조각)이 있으면 안 된다 — 줄 경계로만 나뉜다.
        let ins = mod?["ins"] as? [[String: Any]] ?? []
        #expect(!(ins.isEmpty), "바뀐 줄이 안 잡혔다")
    }

    /// 코드블록은 **줄 단위**로 어디가 바뀌었는지 짚는다 — 통짜 "코드 변경됨"으로 넘기지 않는다.
    @Test func testCodeBlockMarksChangedLines() throws {
        let a = "```swift\nlet x = 1\nlet y = 2\nprint(x)\n```\n"
        let b = "```swift\nlet x = 1\nlet y = 99\nprint(x)\n```\n"
        let r = try diff(a, b)
        let code = blocks(r).first { ($0["type"] as? String) == "code" }
        #expect(code?["kind"] as? String == "modified")
        #expect(code?["codeLines"] as? Bool == true, "줄 단위 diff가 아니다")
        #expect(code?["wholeCode"] as? Bool != true, "통짜 변경으로 물러섰다")
        let ins = code?["ins"] as? [[String: Any]] ?? []
        #expect(!(ins.isEmpty), "바뀐 줄이 안 잡혔다")
        // 바뀐 줄 하나만 — 블록 전체가 아니다.
        let covered = ins.reduce(0) { $0 + (($1["end"] as? Int ?? 0) - ($1["start"] as? Int ?? 0)) }
        let total = (code?["text"] as? String ?? "").utf16.count
        #expect(covered < total, "코드블록 전체가 칠해졌다")
    }

    /// 표는 **칸 단위**로 짚는다. 바뀐 칸만 좌표와 함께 나와야 한다.
    @Test func testTableMarksChangedCell() throws {
        let a = "| 항목 | 값 |\n|---|---|\n| 하나 | 1 |\n| 둘 | 2 |\n"
        let b = "| 항목 | 값 |\n|---|---|\n| 하나 | 1 |\n| 둘 | 22 |\n"
        let r = try diff(a, b)
        let table = blocks(r).first { ($0["type"] as? String) == "table" }
        let cells = table?["cells"] as? [[String: Any]] ?? []
        #expect(cells.count == 1, "바뀐 칸이 하나여야 한다: \(cells)")
        #expect(cells.first?["row"] as? Int == 2, "헤더가 0행이면 바뀐 칸은 2행")
        #expect(cells.first?["col"] as? Int == 1)
    }

    /// **행·열 구조가 바뀌면 칸 좌표가 어긋난다** — 어느 칸인지 지어내지 말고 통짜로 물러선다.
    @Test func testTableStructureChangeFallsBackToWhole() throws {
        let a = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        let b = "| A | B | C |\n|---|---|---|\n| 1 | 2 | 3 |\n"
        let r = try diff(a, b)
        let table = blocks(r).first { ($0["type"] as? String) == "table" }
        if table?["kind"] as? String == "modified" {
            #expect(table?["wholeCode"] as? Bool == true, "구조가 바뀌었는데 칸을 지어냈다")
            #expect(table?["cells"] as? [[String: Any]] == nil)
        }
    }

    /// **`html_block`은 인라인 스팬을 지어내지 않는다.** 원본 HTML은 태그를 포함해 렌더된
    /// 텍스트와 좌표계가 다르고(`<div>안녕</div>` 16자 vs 렌더 2자), 태그를 정규식으로 걷어내는 건
    /// 속성값 속 `>`·주석에서 깨진다. 틀린 오프셋은 **조용히 엉뚱한 글자를 칠하므로** 통짜로 물러선다.
    @Test func testHtmlBlockFallsBackToWholeChange() throws {
        let r = try diff("<div class=\"box\">안녕하세요 여기</div>\n",
                         "<div class=\"box\">안녕하세요 저기</div>\n")
        let html = blocks(r).first { ($0["type"] as? String) == "html" }
        #expect(html != nil, "html_block으로 안 잡혔다: \(blocks(r).map { $0["type"] as? String ?? "" })")
        #expect(html?["kind"] as? String == "modified")
        #expect(html?["wholeCode"] as? Bool == true, "HTML에 인라인 스팬을 지어냈다")
        #expect((html?["ins"] as? [[String: Any]] ?? []).isEmpty, "통짜로 물러섰는데 스팬이 남았다 — 렌더 텍스트를 넘어 아무것도 안 칠해진다")
    }

    /// 코드펜스 언어 태그가 바뀌면 같은 블록이 아니다(info가 매칭 키에 들어간다).
    /// 렌더된 결과에는 언어가 클래스로만 남아 눈에 안 띄므로, 최소한 "무변경"으로 삼키면 안 된다.
    @Test func testCodeFenceLanguageIsPartOfIdentity() throws {
        let r = try diff("```js\nx\n```\n", "```ts\nx\n```\n")
        let kinds = blocks(r).map { $0["kind"] as? String ?? "" }
        #expect(!(kinds.allSatisfy { $0 == "same" }), "언어 태그 변경이 무변경으로 삼켜졌다: \(kinds)")
    }

    /// **리스트 소속 정보가 실려야 한다.** 없으면 페인트가 항목마다 `<ul>`을 새로 만들어
    /// 리스트가 쪼개지고, 순서 리스트는 번호가 전부 1로 초기화된다(실제로 한 번 그랬다).
    @Test func testListItemsCarryListIdentity() throws {
        let r = try diff("- 하나\n- 둘\n", "- 하나\n- 하나 반\n- 둘\n")
        let items = blocks(r).filter { ($0["listId"] as? String) != nil }
        #expect(items.count == 3, "리스트 항목에 listId가 안 실렸다")
        let ids = Set(items.compactMap { $0["listId"] as? String })
        #expect(ids.count == 1, "같은 리스트인데 id가 갈렸다: \(ids)")
        #expect(items.allSatisfy { ($0["listTag"] as? String) == "ul" })
    }

    @Test func testOrderedListCarriesOlTag() throws {
        let r = try diff("1. 하나\n2. 둘\n", "1. 하나\n2. 하나 반\n3. 둘\n")
        let items = blocks(r).filter { ($0["listId"] as? String) != nil }
        #expect(!(items.isEmpty))
        #expect(items.allSatisfy { ($0["listTag"] as? String) == "ol" }, "순서 리스트가 ul로 잡혔다")
    }

    /// 서로 다른 리스트는 id가 갈려야 한다 — 안 그러면 문단 건너뛴 두 리스트가 하나로 붙는다.
    @Test func testSeparateListsGetDistinctIds() throws {
        let src = "- A\n\n문단.\n\n- B\n"
        let r = try diff(src, src)
        let ids = Set(blocks(r).compactMap { $0["listId"] as? String })
        #expect(ids.count == 2, "떨어진 두 리스트가 같은 id를 받았다: \(ids)")
    }

    /// 인용 안 문단도 안쪽이 원자다 — 바깥까지 세면 같은 내용이 두 번 잡힌다.
    @Test func testBlockquoteCountsInnerParagraphOnce() throws {
        let r = try diff("> 인용 문단.\n", "> 인용 문단 수정.\n")
        #expect(stats(r)["modified"] == 1)
        #expect(stats(r)["inserted"] == 0)
        #expect(stats(r)["deleted"] == 0)
    }

    /// **표는 통째로 원자다.** 행 단위로 자르면 `| 하나 | 1 |`이 헤더·구분선 없이 남아
    /// 다시 렌더할 때 생 파이프 텍스트가 된다(실측으로 확인한 회귀).
    @Test func testTableIsOneAtomicBlock() throws {
        let a = "| 항목 | 값 |\n|---|---|\n| 하나 | 1 |\n| 둘 | 2 |\n"
        let b = "| 항목 | 값 |\n|---|---|\n| 하나 | 1 |\n| 둘 | 22 |\n"
        let r = try diff(a, b)
        let tables = blocks(r).filter { ($0["type"] as? String) == "table" }
        #expect(tables.count == 1, "표가 여러 블록으로 쪼개졌다: \(blocks(r).map { $0["type"] as? String ?? "" })")
        #expect(tables.first?["kind"] as? String == "modified")
        // 표 **전체** 텍스트 오프셋으로는 칠하지 않는다 — 셀 경계를 넘어 엉뚱한 칸이 칠해진다.
        // 대신 칸 좌표로 짚는다(어느 칸이 바뀌었는지는 알려줘야 한다).
        // #expect는 옵셔널 체이닝·as?·??·!가 겹친 식을 분해하다 평가를 놓친다 — 중간 변수로 뽑는다.
        let spans = tables.first?["ins"] as? [[String: Any]] ?? []
        let cells = tables.first?["cells"] as? [[String: Any]] ?? []
        #expect(spans.isEmpty, "표 전체 오프셋 스팬이 생겼다")
        #expect(!cells.isEmpty, "바뀐 칸 좌표가 없다")
    }

    /// 표 행이 추가돼도 표는 여전히 블록 하나다.
    @Test func testTableRowAdditionKeepsSingleBlock() throws {
        let a = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        let b = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n"
        let r = try diff(a, b)
        #expect(blocks(r).filter { ($0["type"] as? String) == "table" }.count == 1)
    }

    // MARK: 빈 문서 (생성·삭제)

    @Test func testCreationIsAllInserted() throws {
        let r = try diff("", "# 새 문서\n\n내용.\n")
        #expect(stats(r)["deleted"] == 0)
        #expect(stats(r)["inserted"] ?? 0 > 0)
    }

    @Test func testDeletionIsAllDeleted() throws {
        let r = try diff("# 옛 문서\n\n내용.\n", "")
        #expect(stats(r)["inserted"] == 0)
        #expect(stats(r)["deleted"] ?? 0 > 0)
    }

    @Test func testEmptyToEmptyIsNoop() throws {
        let s = stats(try diff("", ""))
        #expect(s["inserted"] == 0)
        #expect(s["deleted"] == 0)
        #expect(s["modified"] == 0)
    }

    // MARK: 오프셋 좌표계 — 모델의 오프셋은 **렌더된 DOM** 기준이어야 한다

    /// 블록 `text`를 이어붙인 것이 렌더된 텍스트와 같아야 한다(프로젝션 불변식).
    ///
    /// markdown-it inline 토큰의 `.content`는 렌더 결과가 아니라 **원본 마크다운 소스**다.
    /// 그걸 그대로 쓰면 굵게·인라인코드·링크가 있는 문단에서 하이라이트가 마크업 기호 길이만큼
    /// 밀리고, 밀린 양이 텍스트 길이를 넘으면 아무것도 안 칠해진다(실측으로 확인한 회귀).
    @Test func testProjectionMatchesRenderedText() throws {
        let c = try ctx()
        c.evaluateScript("""
        globalThis.__proj = function (src) {
          var md = globalThis.__diffdocMarkdownIt;
          var proj = DiffDocCore._toBlocks(md, src).map(function (b) { return b.text; }).join('');
          var rendered = md.render(src).replace(/<[^>]*>/g, '')
            .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
            .replace(/&quot;/g, '"').replace(/&#39;/g, "'");
          return JSON.stringify([proj.trim(), rendered.trim()]);
        };
        """)
        // 마크업 종류마다 — 기호가 텍스트로 새면 여기서 갈린다.
        for src in ["이 **문단이** 수정합니다.",
                    "값은 `bravo` 입니다.",
                    "[설명](https://example.com/very/long/path) 참고하세요.",
                    "![그림](a.png) 뒤 텍스트.",
                    "*기울임*과 ~~취소~~ 섞임.",
                    "# **굵은** 제목"] {
            c.setObject(src, forKeyedSubscript: "__src" as NSString)
            let v = c.evaluateScript("__proj(__src)")?.toString() ?? ""
            let pair = (try? JSONSerialization.jsonObject(with: Data(v.utf8))) as? [String] ?? []
            #expect(pair.count == 2, "프로젝션 검사 실패: \(src)")
            #expect(pair.first == pair.last, "프로젝션이 렌더 텍스트와 다르다 — 하이라이트가 밀린다: \(src)")
        }
    }

    /// 스팬은 **프로젝션** 텍스트 안에 들어와야 한다. 소스 오프셋이 새면 길이를 넘어버린다.
    @Test func testSpansStayInsideProjectedText() throws {
        let r = try diff("[아주아주긴링크텍스트](https://example.com/a/b/c) 뒤 문단을 고칩니다.\n",
                         "[아주아주긴링크텍스트](https://example.com/a/b/c) 뒤 문단이 고칩니다.\n")
        let mod = blocks(r).first { $0["kind"] as? String == "modified" }
        #expect(mod != nil, "링크가 있는 문단이 수정으로 안 잡혔다")
        let text = (mod?["text"] as? String) ?? ""
        let ins = mod?["ins"] as? [[String: Any]] ?? []
        #expect(!(ins.isEmpty), "삽입 스팬이 없다")
        for span in ins {
            #expect(span["end"] as? Int ?? 0 <= text.utf16.count, "스팬이 프로젝션 길이를 넘었다 — 아무것도 안 칠해진다")
        }
        // 링크 URL이 프로젝션에 새어 들어오면 안 된다.
        #expect(!(text.contains("example.com")), "링크 URL이 텍스트 프로젝션에 남았다: \(text)")
    }

    /// **`norm`은 원본 소스 기준으로 남긴다.** 프로젝션으로 정규화하면 `굵게`→`**굵게**` 같은
    /// 서식만의 변경이 무변경으로 삼켜진다(렌더 텍스트는 같기 때문).
    @Test func testFormattingOnlyChangeIsNotSwallowed() throws {
        let kinds = blocks(try diff("굵게 강조합니다.\n", "**굵게** 강조합니다.\n"))
            .map { $0["kind"] as? String ?? "" }
        #expect(!(kinds.allSatisfy { $0 == "same" }), "서식만의 변경이 무변경으로 삼켜졌다: \(kinds)")
    }

    /// 표 **칸**도 같은 좌표계다 — 칸 오프셋은 셀 DOM 위에서 쓰인다.
    @Test func testTableCellSpansUseProjectedOffsets() throws {
        let a = "| 항목 | 값 |\n|---|---|\n| 하나 | **굵은값** 뒤 |\n"
        let b = "| 항목 | 값 |\n|---|---|\n| 하나 | **굵은값** 앞 |\n"
        let table = blocks(try diff(a, b)).first { ($0["type"] as? String) == "table" }
        let cells = table?["cells"] as? [[String: Any]] ?? []
        #expect(cells.count == 1, "바뀐 칸이 하나여야 한다: \(cells)")
        // 렌더된 셀 텍스트는 "굵은값 앞"(6자) — 소스 오프셋이면 여기를 넘어간다.
        for span in (cells.first?["ins"] as? [[String: Any]] ?? []) {
            #expect(span["end"] as? Int ?? 0 <= 6, "칸 스팬이 렌더된 셀 텍스트 길이를 넘었다")
        }
    }

    /// 칸 정체성은 **raw**로 본다 — 프로젝션으로 보면 칸 안의 서식만 바뀐 변경이 삼켜진다.
    @Test func testTableCellFormattingOnlyChangeIsNotSwallowed() throws {
        let a = "| 항목 | 값 |\n|---|---|\n| 하나 | 강조 |\n"
        let b = "| 항목 | 값 |\n|---|---|\n| 하나 | **강조** |\n"
        let kinds = blocks(try diff(a, b)).map { $0["kind"] as? String ?? "" }
        #expect(!(kinds.allSatisfy { $0 == "same" }), "칸 안의 서식 변경이 무변경으로 삼켜졌다: \(kinds)")
    }

    // MARK: 페인트 좌표 보정 — 삭제 텍스트를 되살린 뒤의 오프셋

    /// `insertDeletions`가 `<del>`을 끼워 넣어 텍스트 총량이 늘어난 만큼 스팬을 민다.
    /// 안 밀면 새 글자 대신 **방금 되살린 삭제 글자**가 칠해진다("문단이"의 "이" 대신 "을").
    @Test func testShiftPastDeletionsMovesSpanPastRestoredText() throws {
        let c = try ctx()
        let v = c.evaluateScript("""
        JSON.stringify(DiffDocPaint._shiftPastDeletions(
          [{start: 4, end: 5}], [{at: 4, text: '을'}]))
        """)
        #expect(v?.toString() == "[{\"start\":5,\"end\":6}]", "삭제 삽입분만큼 안 밀렸다 — 삭제된 글자가 칠해진다")
    }

    /// **경계는 비대칭이다.** 스팬 끝에 붙은 삭제는 밀지 않는다 —
    /// 밀면 삽입 하이라이트가 삭제 텍스트까지 삼킨다.
    @Test func testShiftPastDeletionsDoesNotSwallowTrailingDeletion() throws {
        let c = try ctx()
        let v = c.evaluateScript("""
        JSON.stringify(DiffDocPaint._shiftPastDeletions(
          [{start: 0, end: 4}], [{at: 4, text: 'X'}]))
        """)
        #expect(v?.toString() == "[{\"start\":0,\"end\":4}]", "스팬 끝의 삭제까지 하이라이트에 삼켜졌다")
    }

    /// 여러 삭제가 앞에 있으면 **합계**만큼 민다.
    @Test func testShiftPastDeletionsAccumulates() throws {
        let c = try ctx()
        let v = c.evaluateScript("""
        JSON.stringify(DiffDocPaint._shiftPastDeletions(
          [{start: 10, end: 12}], [{at: 2, text: '가나'}, {at: 6, text: '다'}]))
        """)
        #expect(v?.toString() == "[{\"start\":13,\"end\":15}]", "삭제 길이 합계가 안 맞다")
    }

    /// **모델을 제자리에서 고치면 안 된다** — `setDensity`가 같은 모델로 다시 그리므로
    /// 두 번째 페인트에서 스팬이 또 밀린다(밀도를 토글할수록 하이라이트가 흘러간다).
    @Test func testShiftPastDeletionsDoesNotMutateInput() throws {
        let c = try ctx()
        let v = c.evaluateScript("""
        (function () {
          var spans = [{start: 4, end: 5}], dels = [{at: 4, text: '을'}];
          DiffDocPaint._shiftPastDeletions(spans, dels);
          DiffDocPaint._shiftPastDeletions(spans, dels);
          return JSON.stringify(spans);
        })()
        """)
        #expect(v?.toString() == "[{\"start\":4,\"end\":5}]", "입력 스팬이 변형됐다 — 밀도 전환 때마다 하이라이트가 밀린다")
    }

    // MARK: 유니코드 안전성 (오프셋 불변식의 전제)

    /// 이모지는 UTF-16 서로게이트 쌍이다 — 오프셋 계산이 어긋나면 하이라이트가 밀린다.
    @Test func testEmojiDoesNotBreakOffsets() throws {
        let r = try diff("안녕 🎉 반가워\n", "안녕 🎉 반갑다\n")
        let mod = blocks(r).first { $0["kind"] as? String == "modified" }
        #expect(mod != nil, "이모지가 있는 문단이 수정으로 안 잡혔다")
        let text = (mod?["text"] as? String) ?? ""
        let ins = mod?["ins"] as? [[String: Any]] ?? []
        for span in ins {
            let end = span["end"] as? Int ?? 0
            #expect(end <= text.utf16.count, "스팬이 텍스트 길이를 넘었다")
        }
    }
}
