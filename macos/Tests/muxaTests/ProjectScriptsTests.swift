import Testing
import XCTest
@testable import muxa

/// 프로젝트 스크립트 탐지 순수 로직 — package.json 파싱 · 패키지 매니저 판별 · 실행 명령 조립.
/// 파일 읽기(부작용)는 ProjectScripts.discover 경계에 있고, 여기서는 순수 함수만 검증한다.
final class ProjectScriptsTests: XCTestCase {
    // MARK: 패키지 매니저 판별 — **추측하지 않는다**. lock 파일이 진실이다.

    func testDetectsPnpmFromLockfile() {
        XCTAssertEqual(PackageManager.detect(files: ["package.json", "pnpm-lock.yaml"]), .pnpm)
    }

    func testDetectsYarnFromLockfile() {
        XCTAssertEqual(PackageManager.detect(files: ["yarn.lock"]), .yarn)
    }

    func testDetectsBunFromLockfile() {
        XCTAssertEqual(PackageManager.detect(files: ["bun.lockb"]), .bun)
        XCTAssertEqual(PackageManager.detect(files: ["bun.lock"]), .bun)
    }

    func testDetectsNpmFromLockfile() {
        XCTAssertEqual(PackageManager.detect(files: ["package-lock.json"]), .npm)
    }

    /// lock 파일이 없으면 npm으로 **가정하지 않는다** — 모르면 nil이고, UI는 사용자가 고르게 한다.
    /// (pnpm 프로젝트에 `npm run`을 넣으면 lock이 깨지거나 엉뚱한 의존성이 깔린다.)
    func testNoLockfileMeansUnknown() {
        XCTAssertNil(PackageManager.detect(files: ["package.json", "README.md"]))
        XCTAssertNil(PackageManager.detect(files: []))
    }

    /// lock 파일이 여러 개면(모노레포 이관 중 등) 우선순위가 높은 하나를 고른다 — 흔들리지 않게 고정한다.
    func testMultipleLockfilesUsePriority() {
        XCTAssertEqual(PackageManager.detect(files: ["package-lock.json", "pnpm-lock.yaml"]), .pnpm)
    }

    // MARK: 실행 명령 조립

    func testRunCommand() {
        XCTAssertEqual(PackageManager.pnpm.runCommand("dev"), "pnpm run dev")
        XCTAssertEqual(PackageManager.npm.runCommand("dev"), "npm run dev")
        XCTAssertEqual(PackageManager.yarn.runCommand("dev"), "yarn run dev")
        XCTAssertEqual(PackageManager.bun.runCommand("dev"), "bun run dev")
    }

    // MARK: package.json scripts 파싱

    func testParsesScripts() {
        let json = """
        {"name":"app","scripts":{"dev":"vite","build":"vite build","test":"vitest"}}
        """
        let scripts = ProjectScripts.parsePackageScripts(json)
        XCTAssertEqual(scripts.count, 3)
        // 목록 순서는 안정적이어야 한다(JSON 딕셔너리는 순서가 없으므로 이름순으로 고정).
        XCTAssertEqual(scripts.map(\.name), ["build", "dev", "test"])
        XCTAssertEqual(scripts.first { $0.name == "dev" }?.body, "vite")
    }

    func testParsesEmptyOrMissingScripts() {
        XCTAssertTrue(ProjectScripts.parsePackageScripts(#"{"name":"app"}"#).isEmpty)
        XCTAssertTrue(ProjectScripts.parsePackageScripts(#"{"scripts":{}}"#).isEmpty)
    }

    /// 깨진 JSON에 죽지 않는다 — 스크립트가 없는 것으로 본다(추측하지 않는다).
    func testParseBrokenJSONIsEmpty() {
        XCTAssertTrue(ProjectScripts.parsePackageScripts("{not json").isEmpty)
        XCTAssertTrue(ProjectScripts.parsePackageScripts("").isEmpty)
    }

    /// scripts 값이 문자열이 아닌 이상한 형태면 그 항목만 버린다.
    func testParseIgnoresNonStringValues() {
        let json = #"{"scripts":{"dev":"vite","weird":{"nested":true}}}"#
        let scripts = ProjectScripts.parsePackageScripts(json)
        XCTAssertEqual(scripts.map(\.name), ["dev"])
    }

    // MARK: 설명(주석) — package.json은 JSON이라 진짜 주석이 없다. 실제로 쓰이는 두 관례를 읽는다.

    /// npm은 `//`로 시작하는 키를 무시하므로, `"//dev"`를 주석으로 쓰는 관례가 있다.
    func testReadsSlashSlashCommentKeys() {
        let json = """
        {"scripts":{"//dev":"개발 서버(HMR)","dev":"vite","build":"vite build"}}
        """
        let scripts = ProjectScripts.parsePackageScripts(json)
        // 주석 키 자체는 스크립트 목록에 넣지 않는다.
        XCTAssertEqual(scripts.map(\.name), ["build", "dev"])
        XCTAssertEqual(scripts.first { $0.name == "dev" }?.note, "개발 서버(HMR)")
        XCTAssertNil(scripts.first { $0.name == "build" }?.note)
    }

    /// 공백을 넣은 `"// dev"` 형태도 흔하다.
    func testReadsSpacedCommentKeys() {
        let json = #"{"scripts":{"// dev":"개발 서버","dev":"vite"}}"#
        XCTAssertEqual(ProjectScripts.parsePackageScripts(json).first?.note, "개발 서버")
    }

    /// npm-scripts-info 관례 — 최상위 `scripts-info` 필드.
    func testReadsScriptsInfoField() {
        let json = """
        {"scripts":{"dev":"vite"},"scripts-info":{"dev":"개발 서버를 띄웁니다"}}
        """
        XCTAssertEqual(ProjectScripts.parsePackageScripts(json).first?.note, "개발 서버를 띄웁니다")
    }

    /// 둘 다 있으면 `scripts-info`가 이긴다(명시적으로 설명하려고 만든 필드다).
    func testScriptsInfoWinsOverCommentKey() {
        let json = """
        {"scripts":{"//dev":"주석","dev":"vite"},"scripts-info":{"dev":"명시적 설명"}}
        """
        XCTAssertEqual(ProjectScripts.parsePackageScripts(json).first?.note, "명시적 설명")
    }

    // MARK: Makefile — package.json이 없는 생태계(Go·Rust·C)의 사실상 표준

    /// self-documenting makefile 관례: `target: ## 설명`. 설명이 있는 타깃을 먼저 보여준다.
    func testParsesMakefileTargets() {
        let make = """
        .PHONY: dev build

        dev: ## 개발 서버 (:8080)
        \tgo run ./cmd/server

        build:
        \tgo build -o bin/app ./cmd/server

        # 이건 주석일 뿐 타깃이 아니다
        """
        let targets = ProjectScripts.parseMakefile(make)
        XCTAssertEqual(targets.map(\.name), ["build", "dev"])
        XCTAssertEqual(targets.first { $0.name == "dev" }?.note, "개발 서버 (:8080)")
        XCTAssertEqual(targets.first { $0.name == "dev" }?.body, "make dev")
        XCTAssertNil(targets.first { $0.name == "build" }?.note)
    }

    /// `.PHONY`·변수 대입·패턴 규칙은 타깃이 아니다.
    func testMakefileIgnoresNonTargets() {
        let make = """
        .PHONY: all
        CC = gcc
        CFLAGS := -O2
        %.o: %.c
        \t$(CC) -c $<
        run: ## 실행
        \t./app
        """
        XCTAssertEqual(ProjectScripts.parseMakefile(make).map(\.name), ["run"])
    }

    func testMakefileEmpty() {
        XCTAssertTrue(ProjectScripts.parseMakefile("").isEmpty)
        XCTAssertTrue(ProjectScripts.parseMakefile("# 주석만 있다").isEmpty)
    }

    // MARK: 셸 스크립트 — 상단 주석을 설명으로 읽는다

    func testShellScriptDescription() {
        let sh = """
        #!/usr/bin/env bash
        # 개발 서버를 띄운다 (포트 3000)
        set -euo pipefail
        exec node server.js
        """
        XCTAssertEqual(ProjectScripts.shellScriptNote(sh), "개발 서버를 띄운다 (포트 3000)")
    }

    /// shebang 뒤 첫 주석만 설명으로 본다 — `set -e` 이후의 주석은 코드 설명이지 스크립트 설명이 아니다.
    func testShellScriptNoteStopsAtFirstCode() {
        let sh = """
        #!/bin/sh
        set -e
        # 이건 내부 로직 주석
        echo hi
        """
        XCTAssertNil(ProjectScripts.shellScriptNote(sh))
    }

    func testShellScriptNoteAbsent() {
        XCTAssertNil(ProjectScripts.shellScriptNote("#!/bin/sh\necho hi"))
        XCTAssertNil(ProjectScripts.shellScriptNote(""))
    }

    // MARK: discover — 실제 디렉터리를 읽는 경계

    func testDiscoverReadsRealDirectory() throws {
        let dir = NSTemporaryDirectory() + "muxa-scripts-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try #"""
        {"scripts":{"//dev":"개발 서버","dev":"vite","build":"vite build"}}
        """#.write(toFile: dir + "/package.json", atomically: true, encoding: .utf8)
        try "".write(toFile: dir + "/pnpm-lock.yaml", atomically: true, encoding: .utf8)

        let found = ProjectScripts.discover(in: dir)
        XCTAssertEqual(found.manager, .pnpm)
        XCTAssertEqual(found.scripts.map(\.name), ["build", "dev"])
        XCTAssertEqual(found.scripts.first { $0.name == "dev" }?.note, "개발 서버")
        XCTAssertEqual(found.manager?.runCommand("dev"), "pnpm run dev")
    }

    /// package.json이 없는 프로젝트(Swift·Go 등)에서도 죽지 않는다 — 빈 목록이고 UI는 직접 입력만 보여준다.
    func testDiscoverWithoutPackageJSON() throws {
        let dir = NSTemporaryDirectory() + "muxa-noscripts-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let found = ProjectScripts.discover(in: dir)
        XCTAssertTrue(found.scripts.isEmpty)
        XCTAssertNil(found.manager)
    }

    func testDiscoverNilDirectory() {
        let found = ProjectScripts.discover(in: nil)
        XCTAssertTrue(found.scripts.isEmpty)
        XCTAssertNil(found.manager)
    }

    // MARK: dogfooding — 우리 리포에서 실제로 동작하는가

    /// **muxa 자신을 읽는다.** 합성 픽스처만으로는 "현실의 파일에서 되는가"를 증명하지 못한다.
    /// muxa는 package.json이 없는 프로젝트(Swift/SPM)라 Makefile·scripts/ 경로를 검증한다.
    func testDiscoverFindsOurOwnMakefileAndScripts() {
        // .../macos/Tests/muxaTests/ProjectScriptsTests.swift → 리포 루트
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // muxaTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // (리포 루트)
        let found = ProjectScripts.discover(in: repo.path)

        // Makefile 타깃 — 설명(## 주석)까지 읽힌다
        let make = found.scripts.filter { $0.source == .makefile }
        XCTAssertTrue(make.contains { $0.name == "test" && $0.body == "make test" },
                      "Makefile의 test 타깃을 못 찾았다: \(make.map(\.name))")
        XCTAssertNotNil(make.first { $0.name == "app" }?.note, "## 설명을 못 읽었다")

        // scripts/*.sh — 실행 가능한 셸 스크립트
        let shell = found.scripts.filter { $0.source == .shell }
        XCTAssertTrue(shell.contains { $0.name == "bootstrap" && $0.body == "./scripts/bootstrap.sh" },
                      "scripts/bootstrap.sh를 못 찾았다: \(shell.map(\.name))")

        // package.json이 없는 프로젝트다 — 매니저는 nil이어야 한다(추측하지 않는다)
        XCTAssertNil(found.manager)
        XCTAssertTrue(found.scripts.filter { $0.source == .packageJSON }.isEmpty)
    }
}

/// Makefile 타깃 판정의 경계 — **대입은 타깃이 아니고, 이중 콜론 규칙은 타깃이다.**
/// 콜론 하나만 보고 자르면 `X ::= y`(POSIX 즉시 대입)가 타깃 목록에 섞여 들어와 목록이 거짓말을 한다.
struct MakefileTargetTests {
    @Test("POSIX 즉시 대입(::=)은 타깃이 아니다")
    func 즉시대입은타깃이아니다() {
        let make = """
        FOO::=bar
        BAZ ::= qux
        dev: ## 개발 서버
        \tgo run .
        """
        #expect(ProjectScripts.parseMakefile(make).map(\.name) == ["dev"])
    }

    @Test("이중 콜론 규칙(foo::)은 진짜 타깃이라 남는다")
    func 이중콜론규칙은타깃이다() {
        let make = """
        clean::
        \trm -rf bin
        """
        let targets = ProjectScripts.parseMakefile(make)
        #expect(targets.map(\.name) == ["clean"])
        #expect(targets.first?.body == "make clean")
    }
}
