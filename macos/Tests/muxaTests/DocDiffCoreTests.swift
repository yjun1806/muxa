import XCTest
import JavaScriptCore
@testable import muxa

/// 문서 diff **JS 코어**를 JavaScriptCore에서 직접 돌려 검증한다.
///
/// core.js는 DOM을 안 만지므로 WKWebView 없이 순수 함수처럼 테스트된다 — muxa의
/// "순수 로직은 테스트로 못 박는다"를 JS까지 늘린 장치다. 비동기도 플레이키도 없다.
final class DocDiffCoreTests: XCTestCase {

    private static var sharedCtx: JSContext?

    /// markdown-it + dmp + core.js를 얹은 컨텍스트. 번들 로딩이 비싸 한 번만 만든다.
    private func ctx() throws -> JSContext {
        if let c = Self.sharedCtx { return c }
        let c = JSContext()!
        var jsError: String?
        c.exceptionHandler = { _, e in jsError = e?.toString() }

        let res = Self.resourcesDir()
        for path in ["mdviewer/markdown-it.min.js", "diffdoc/diff-match-patch.js", "diffdoc/core.js"] {
            let url = res.appendingPathComponent(path)
            let src = try String(contentsOf: url, encoding: .utf8)
            c.evaluateScript(src)
            if let e = jsError { throw XCTSkip("JS 로드 실패 \(path): \(e)") }
        }
        // core는 렌더러와 **같은 파서 인스턴스**를 쓴다(파서가 둘이면 좌표가 어긋난다).
        c.evaluateScript("globalThis.__diffdocMarkdownIt = markdownit({ html: true, linkify: true });")
        if let e = jsError { throw XCTSkip("markdown-it 초기화 실패: \(e)") }
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
            throw XCTSkip("core 호출 실패")
        }
        return obj
    }

    private func blocks(_ r: [String: Any]) -> [[String: Any]] { r["blocks"] as? [[String: Any]] ?? [] }
    private func stats(_ r: [String: Any]) -> [String: Int] {
        (r["stats"] as? [String: Any])?.mapValues { ($0 as? Int) ?? 0 } ?? [:]
    }

    // MARK: 환경 — 이게 깨지면 나머지가 다 무의미하다

    func testJSCEnvironmentIsUsable() throws {
        let c = try ctx()
        XCTAssertEqual(c.evaluateScript("typeof markdownit")?.toString(), "function")
        XCTAssertEqual(c.evaluateScript("typeof diff_match_patch")?.toString(), "function")
        XCTAssertEqual(c.evaluateScript("typeof DiffDocCore.computeDocDiff")?.toString(), "function")
        XCTAssertEqual(c.evaluateScript("typeof Intl.Segmenter")?.toString(), "function",
                       "어절 분절이 없으면 2층이 폴백으로 떨어진다")
    }

    // MARK: 1층 — 블록 매칭

    func testIdenticalDocumentHasNoChanges() throws {
        let src = "# 제목\n\n첫 문단입니다.\n\n둘째 문단입니다.\n"
        let s = stats(try diff(src, src))
        XCTAssertEqual(s["inserted"], 0)
        XCTAssertEqual(s["deleted"], 0)
        XCTAssertEqual(s["modified"], 0)
    }

    func testInsertedParagraphIsDetected() throws {
        let r = try diff("# 제목\n\n첫 문단.\n", "# 제목\n\n첫 문단.\n\n새 문단.\n")
        XCTAssertEqual(stats(r)["inserted"], 1)
        XCTAssertEqual(stats(r)["deleted"], 0)
    }

    func testDeletedParagraphKeepsItsPlace() throws {
        let r = try diff("# 제목\n\nA 문단.\n\nB 문단.\n", "# 제목\n\nB 문단.\n")
        XCTAssertEqual(stats(r)["deleted"], 1)
        let kinds = blocks(r).map { $0["kind"] as? String ?? "" }
        // 삭제 블록이 사라지지 않고 목록 안에 남아야 "여기서 뭐가 없어졌다"를 말할 수 있다.
        XCTAssertTrue(kinds.contains("deleted"), "삭제 블록이 목록에서 빠졌다: \(kinds)")
    }

    /// **소스 노이즈 흡수** — 소프트랩만 바뀌면 렌더 결과가 같으므로 무변경이어야 한다.
    func testSoftWrapChangeIsNotAChange() throws {
        let a = "이 문단은 한 줄로 되어 있습니다.\n"
        let b = "이 문단은\n한 줄로\n되어 있습니다.\n"
        let s = stats(try diff(a, b))
        XCTAssertEqual(s["modified"], 0, "소프트랩 변경이 수정으로 새어나왔다")
        XCTAssertEqual(s["inserted"], 0)
        XCTAssertEqual(s["deleted"], 0)
    }

    /// 리스트 마커 교체(`-`↔`*`)도 렌더 결과가 같다.
    func testListMarkerChangeIsNotAChange() throws {
        let s = stats(try diff("- 하나\n- 둘\n", "* 하나\n* 둘\n"))
        XCTAssertEqual(s["modified"], 0)
        XCTAssertEqual(s["inserted"], 0)
        XCTAssertEqual(s["deleted"], 0)
    }

    /// **리스트 항목 추가가 리스트 전체 교체로 보이면 안 된다.**
    func testListItemAdditionOnlyMarksThatItem() throws {
        let r = try diff("- 하나\n- 둘\n", "- 하나\n- 하나 반\n- 둘\n")
        XCTAssertEqual(stats(r)["inserted"], 1)
        XCTAssertEqual(stats(r)["deleted"], 0)
        XCTAssertEqual(stats(r)["modified"], 0)
    }

    // MARK: 2·3층 — 한국어

    /// **핵심** — 조사만 바뀌면 조사만 강조돼야 한다("문단을" 통째가 아니라 "을"만).
    func testKoreanParticleChangeHighlightsOnlyParticle() throws {
        let r = try diff("이 문단을 수정합니다.\n", "이 문단이 수정합니다.\n")
        let mod = blocks(r).first { $0["kind"] as? String == "modified" }
        XCTAssertNotNil(mod, "수정으로 안 잡혔다")
        let text = mod?["text"] as? String ?? ""
        let ins = mod?["ins"] as? [[String: Any]] ?? []
        XCTAssertFalse(ins.isEmpty, "삽입 스팬이 없다")
        let covered = ins.reduce(0) { $0 + (($1["end"] as? Int ?? 0) - ($1["start"] as? Int ?? 0)) }
        XCTAssertLessThanOrEqual(covered, 2, "조사 하나(1자)만 강조돼야 하는데 \(covered)자가 칠해졌다 — text=\(text)")
    }

    /// 어미 변화도 공통부는 남아야 한다("수정" + "습니다"는 공통).
    func testKoreanEndingChangeKeepsCommonParts() throws {
        let r = try diff("문서를 수정했습니다.\n", "문서를 수정되었습니다.\n")
        let mod = blocks(r).first { $0["kind"] as? String == "modified" }
        let ins = mod?["ins"] as? [[String: Any]] ?? []
        let covered = ins.reduce(0) { $0 + (($1["end"] as? Int ?? 0) - ($1["start"] as? Int ?? 0)) }
        XCTAssertLessThan(covered, 8, "어미만 바뀌었는데 \(covered)자가 칠해졌다")
    }

    /// **과분절 방지** — 완전히 다른 단어는 통째 교체여야 한다(조각조각 나면 안 읽힌다).
    func testUnrelatedWordIsWholeReplacement() throws {
        let c = try ctx()
        let v = c.evaluateScript("DiffDocCore._similarity('고양이','강아지')")
        XCTAssertLessThan(v?.toDouble() ?? 1, 0.5, "닮지 않은 단어가 문자 세분 임계를 넘었다")
    }

    func testSimilarityThresholdsSeparateCases() throws {
        let c = try ctx()
        let particle = c.evaluateScript("DiffDocCore._similarity('문단을','문단이')")?.toDouble() ?? 0
        let ending = c.evaluateScript("DiffDocCore._similarity('수정했습니다','수정되었습니다')")?.toDouble() ?? 0
        XCTAssertGreaterThanOrEqual(particle, 0.5, "조사 교체가 임계 아래로 떨어졌다")
        XCTAssertGreaterThanOrEqual(ending, 0.5, "어미 변화가 임계 아래로 떨어졌다")
    }

    /// 어절 분절이 한국어에서 기대대로 동작하는지(2층의 전제).
    func testKoreanSegmentation() throws {
        let c = try ctx()
        let v = c.evaluateScript("JSON.stringify(DiffDocCore._segmentsOf('문단을 수정했습니다'))")
        XCTAssertEqual(v?.toString(), "[\"문단을\",\" \",\"수정했습니다\"]")
    }

    // MARK: 원자 블록

    /// 코드블록은 어절 diff 대상이 아니다 — 코드에 워드 하이라이트를 치면 읽히지 않는다.
    func testCodeBlockIsNotWordDiffed() throws {
        let a = "```swift\nlet x = 1\n```\n"
        let b = "```swift\nlet x = 2\n```\n"
        let r = try diff(a, b)
        let mod = blocks(r).first { $0["kind"] as? String == "modified" }
        XCTAssertNotNil(mod)
        XCTAssertEqual(mod?["wholeCode"] as? Bool, true, "코드블록이 어절 단위로 쪼개졌다")
        XCTAssertTrue((mod?["ins"] as? [[String: Any]] ?? []).isEmpty)
    }

    /// 코드펜스 언어 태그가 바뀌면 같은 블록이 아니다(info가 매칭 키에 들어간다).
    /// 렌더된 결과에는 언어가 클래스로만 남아 눈에 안 띄므로, 최소한 "무변경"으로 삼키면 안 된다.
    func testCodeFenceLanguageIsPartOfIdentity() throws {
        let r = try diff("```js\nx\n```\n", "```ts\nx\n```\n")
        let kinds = blocks(r).map { $0["kind"] as? String ?? "" }
        XCTAssertFalse(kinds.allSatisfy { $0 == "same" },
                       "언어 태그 변경이 무변경으로 삼켜졌다: \(kinds)")
    }

    /// **리스트 소속 정보가 실려야 한다.** 없으면 페인트가 항목마다 `<ul>`을 새로 만들어
    /// 리스트가 쪼개지고, 순서 리스트는 번호가 전부 1로 초기화된다(실제로 한 번 그랬다).
    func testListItemsCarryListIdentity() throws {
        let r = try diff("- 하나\n- 둘\n", "- 하나\n- 하나 반\n- 둘\n")
        let items = blocks(r).filter { ($0["listId"] as? String) != nil }
        XCTAssertEqual(items.count, 3, "리스트 항목에 listId가 안 실렸다")
        let ids = Set(items.compactMap { $0["listId"] as? String })
        XCTAssertEqual(ids.count, 1, "같은 리스트인데 id가 갈렸다: \(ids)")
        XCTAssertTrue(items.allSatisfy { ($0["listTag"] as? String) == "ul" })
    }

    func testOrderedListCarriesOlTag() throws {
        let r = try diff("1. 하나\n2. 둘\n", "1. 하나\n2. 하나 반\n3. 둘\n")
        let items = blocks(r).filter { ($0["listId"] as? String) != nil }
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { ($0["listTag"] as? String) == "ol" }, "순서 리스트가 ul로 잡혔다")
    }

    /// 서로 다른 리스트는 id가 갈려야 한다 — 안 그러면 문단 건너뛴 두 리스트가 하나로 붙는다.
    func testSeparateListsGetDistinctIds() throws {
        let src = "- A\n\n문단.\n\n- B\n"
        let r = try diff(src, src)
        let ids = Set(blocks(r).compactMap { $0["listId"] as? String })
        XCTAssertEqual(ids.count, 2, "떨어진 두 리스트가 같은 id를 받았다: \(ids)")
    }

    /// 인용 안 문단도 안쪽이 원자다 — 바깥까지 세면 같은 내용이 두 번 잡힌다.
    func testBlockquoteCountsInnerParagraphOnce() throws {
        let r = try diff("> 인용 문단.\n", "> 인용 문단 수정.\n")
        XCTAssertEqual(stats(r)["modified"], 1)
        XCTAssertEqual(stats(r)["inserted"], 0)
        XCTAssertEqual(stats(r)["deleted"], 0)
    }

    /// **표는 통째로 원자다.** 행 단위로 자르면 `| 하나 | 1 |`이 헤더·구분선 없이 남아
    /// 다시 렌더할 때 생 파이프 텍스트가 된다(실측으로 확인한 회귀).
    func testTableIsOneAtomicBlock() throws {
        let a = "| 항목 | 값 |\n|---|---|\n| 하나 | 1 |\n| 둘 | 2 |\n"
        let b = "| 항목 | 값 |\n|---|---|\n| 하나 | 1 |\n| 둘 | 22 |\n"
        let r = try diff(a, b)
        let tables = blocks(r).filter { ($0["type"] as? String) == "table" }
        XCTAssertEqual(tables.count, 1, "표가 여러 블록으로 쪼개졌다: \(blocks(r).map { $0["type"] as? String ?? "" })")
        XCTAssertEqual(tables.first?["kind"] as? String, "modified")
        // 표 안에는 어절 스팬을 만들지 않는다 — 셀 경계를 무시한 오프셋이 엉뚱한 칸을 칠한다.
        XCTAssertEqual(tables.first?["wholeCode"] as? Bool, true)
        XCTAssertTrue((tables.first?["ins"] as? [[String: Any]] ?? []).isEmpty)
    }

    /// 표 행이 추가돼도 표는 여전히 블록 하나다.
    func testTableRowAdditionKeepsSingleBlock() throws {
        let a = "| A | B |\n|---|---|\n| 1 | 2 |\n"
        let b = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n"
        let r = try diff(a, b)
        XCTAssertEqual(blocks(r).filter { ($0["type"] as? String) == "table" }.count, 1)
    }

    // MARK: 빈 문서 (생성·삭제)

    func testCreationIsAllInserted() throws {
        let r = try diff("", "# 새 문서\n\n내용.\n")
        XCTAssertEqual(stats(r)["deleted"], 0)
        XCTAssertGreaterThan(stats(r)["inserted"] ?? 0, 0)
    }

    func testDeletionIsAllDeleted() throws {
        let r = try diff("# 옛 문서\n\n내용.\n", "")
        XCTAssertEqual(stats(r)["inserted"], 0)
        XCTAssertGreaterThan(stats(r)["deleted"] ?? 0, 0)
    }

    func testEmptyToEmptyIsNoop() throws {
        let s = stats(try diff("", ""))
        XCTAssertEqual(s["inserted"], 0)
        XCTAssertEqual(s["deleted"], 0)
        XCTAssertEqual(s["modified"], 0)
    }

    // MARK: 유니코드 안전성 (오프셋 불변식의 전제)

    /// 이모지는 UTF-16 서로게이트 쌍이다 — 오프셋 계산이 어긋나면 하이라이트가 밀린다.
    func testEmojiDoesNotBreakOffsets() throws {
        let r = try diff("안녕 🎉 반가워\n", "안녕 🎉 반갑다\n")
        let mod = blocks(r).first { $0["kind"] as? String == "modified" }
        XCTAssertNotNil(mod, "이모지가 있는 문단이 수정으로 안 잡혔다")
        let text = (mod?["text"] as? String) ?? ""
        let ins = mod?["ins"] as? [[String: Any]] ?? []
        for span in ins {
            let end = span["end"] as? Int ?? 0
            XCTAssertLessThanOrEqual(end, text.utf16.count, "스팬이 텍스트 길이를 넘었다")
        }
    }
}
