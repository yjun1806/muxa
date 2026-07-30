import Foundation
import Testing
@testable import muxa

/// 한 탭이 만진 파일·참고한 것의 축적(순수). 신호는 `PreToolUse` 훅 하나에서 오고,
/// 그건 도구가 **실행되기 전**의 신호다 — 그래서 이 타입은 "무엇을 시도했나"를 모을 뿐
/// "무엇이 바뀌었나"를 단정하지 않는다(그 판정은 git·mtime과 교차하는 표시 단계의 몫).
struct AgentChangeSetTests {
    private let cwd = "/Users/me/repo"
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    // MARK: 수집 대상 판정

    @Test func 편집_도구만_경로를_낸다() {
        for tool in ["Edit", "Write", "MultiEdit"] {
            #expect(AgentChangeSet.touchedPath(toolName: tool,
                                               input: ["file_path": "/a/b.swift"],
                                               cwd: cwd) == "/a/b.swift",
                    "\(tool)은 수집 대상이다")
        }
    }

    /// 읽기·검색·셸은 **변경이 아니다** — 변경 목록에 섞이면 바꾼 것이 파묻힌다.
    @Test func 비편집_도구는_경로를_내지_않는다() {
        for tool in ["Read", "Bash", "Grep", "Glob", "WebFetch", "WebSearch", "Task"] {
            #expect(AgentChangeSet.touchedPath(toolName: tool,
                                               input: ["file_path": "/a/b.swift",
                                                       "command": "sed -i s/a/b/ x",
                                                       "pattern": "foo"],
                                               cwd: cwd) == nil,
                    "\(tool)은 변경이 아니다")
        }
        #expect(AgentChangeSet.touchedPath(toolName: nil, input: [:], cwd: cwd) == nil)
        #expect(AgentChangeSet.touchedPath(toolName: "Edit", input: [:], cwd: cwd) == nil)
    }

    /// NotebookEdit은 `file_path`가 아니라 `notebook_path`로 온다.
    @Test func 노트북은_다른_키를_쓴다() {
        #expect(AgentChangeSet.touchedPath(toolName: "NotebookEdit",
                                           input: ["notebook_path": "/a/n.ipynb"],
                                           cwd: cwd) == "/a/n.ipynb")
    }

    // MARK: 경로 정규화 — 키가 어긋나면 같은 파일이 두 항목이 된다

    @Test func 상대경로는_cwd로_절대화한다() {
        #expect(AgentChangeSet.touchedPath(toolName: "Edit",
                                           input: ["file_path": "src/a.swift"],
                                           cwd: cwd) == "/Users/me/repo/src/a.swift")
    }

    @Test func 상위참조를_정리한다() {
        #expect(AgentChangeSet.touchedPath(toolName: "Edit",
                                           input: ["file_path": "/Users/me/repo/src/../a.swift"],
                                           cwd: cwd) == "/Users/me/repo/a.swift")
    }

    @Test func 물결표는_홈으로_펼친다() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(AgentChangeSet.touchedPath(toolName: "Write",
                                           input: ["file_path": "~/notes.md"],
                                           cwd: cwd) == "\(home)/notes.md")
    }

    /// cwd 없이 상대경로가 오면 **버린다** — 어디를 가리키는지 지어낼 수 없다.
    @Test func cwd가_없으면_상대경로를_버린다() {
        #expect(AgentChangeSet.touchedPath(toolName: "Edit",
                                           input: ["file_path": "src/a.swift"],
                                           cwd: nil) == nil)
        // 절대경로는 cwd가 없어도 살아남는다.
        #expect(AgentChangeSet.touchedPath(toolName: "Edit",
                                           input: ["file_path": "/abs/a.swift"],
                                           cwd: nil) == "/abs/a.swift")
    }

    // MARK: upsert

    @Test func 첫_기록은_시각과_횟수를_세운다() {
        var set = AgentChangeSet()
        set.record(path: "/a.swift", sessionId: "S1", prompt: "로그인 버그 수정", at: t0)

        let e = set.entries["/a.swift"]
        #expect(e?.firstTouchedAt == t0)
        #expect(e?.lastTouchedAt == t0)
        #expect(e?.touchCount == 1)
        #expect(e?.lastSessionId == "S1")
        #expect(e?.seenAt == nil, "새 항목은 안 본 상태다")
    }

    @Test func 같은_경로를_다시_만지면_항목이_늘지_않는다() {
        var set = AgentChangeSet()
        set.record(path: "/a.swift", sessionId: "S1", prompt: "첫 지시", at: t0)
        set.record(path: "/a.swift", sessionId: "S2", prompt: "나중 지시", at: t1)

        #expect(set.entries.count == 1)
        let e = set.entries["/a.swift"]
        #expect(e?.firstTouchedAt == t0, "처음 만진 시각은 안 바뀐다")
        #expect(e?.lastTouchedAt == t1)
        #expect(e?.touchCount == 2)
        #expect(e?.lastSessionId == "S2", "세션 라벨은 최신을 따른다")
    }

    // MARK: originPrompt — 제목은 얼려야 거짓이 안 된다

    /// 마지막 프롬프트를 제목으로 쓰면 20턴 전에 만진 파일이 지금 프롬프트 아래 놓인다.
    /// 그래서 **첫 수집 턴의 프롬프트**를 얼린다.
    @Test func 첫_프롬프트만_얼리고_이후엔_덮이지_않는다() {
        var set = AgentChangeSet()
        set.record(path: "/a.swift", sessionId: nil, prompt: "diff 뷰어 연결 설계", at: t0)
        set.record(path: "/b.swift", sessionId: nil, prompt: "초록 벽 걷어내줘", at: t1)

        #expect(set.originPrompt == "diff 뷰어 연결 설계")
    }

    /// 첫 수집 때 프롬프트가 없었으면(훅 이전 세션 등) 다음 기회에 채운다 — 빈 제목을 고수하지 않는다.
    @Test func 첫_기록에_프롬프트가_없었으면_다음_것을_받는다() {
        var set = AgentChangeSet()
        set.record(path: "/a.swift", sessionId: nil, prompt: nil, at: t0)
        set.record(path: "/b.swift", sessionId: nil, prompt: "나중에 알게 된 지시", at: t1)

        #expect(set.originPrompt == "나중에 알게 된 지시")
    }

    // MARK: 참고 항목 — 변경과 섞이지 않는다

    @Test func 읽기와_웹조회만_참고로_잡힌다() {
        let read = AgentChangeSet.reference(toolName: "Read",
                                            input: ["file_path": "docs/DESIGN.md"],
                                            cwd: cwd, at: t0)
        #expect(read?.kind == .file)
        #expect(read?.value == "/Users/me/repo/docs/DESIGN.md", "참고 파일도 절대화한다")

        let web = AgentChangeSet.reference(toolName: "WebFetch",
                                           input: ["url": "https://docs.example.com/a/b?x=1"],
                                           cwd: cwd, at: t0)
        #expect(web?.kind == .web)
        #expect(web?.value == "https://docs.example.com/a/b?x=1",
                "여는 데 쓰므로 호스트가 아니라 URL 전문을 남긴다")
    }

    /// 열 수 있는 대상이 아닌 것은 넣지 않는다 — 눌러도 안 되는 행을 만들지 않는다.
    @Test func 검색어와_명령은_참고가_아니다() {
        for tool in ["Grep", "Glob", "WebSearch", "Bash", "Task", "Edit", "Write"] {
            #expect(AgentChangeSet.reference(toolName: tool,
                                             input: ["pattern": "foo", "query": "bar",
                                                     "command": "ls", "file_path": "/a.swift",
                                                     "url": "https://x.test/"],
                                             cwd: cwd, at: t0) == nil,
                    "\(tool)은 참고 목록에 들어가지 않는다")
        }
    }

    @Test func http가_아닌_주소는_버린다() {
        #expect(AgentChangeSet.reference(toolName: "WebFetch",
                                         input: ["url": "javascript:alert(1)"],
                                         cwd: cwd, at: t0) == nil)
    }

    @Test func 참고는_중복없이_쌓이고_변경과_분리된다() {
        var set = AgentChangeSet()
        let ref = AgentChangeSet.reference(toolName: "Read",
                                          input: ["file_path": "/a/DESIGN.md"], cwd: cwd, at: t0)!
        set.record(reference: ref, at: t0)
        set.record(reference: ref, at: t1)

        #expect(set.references.count == 1)
        #expect(set.references.values.first?.lastSeenAt == t1)
        #expect(set.entries.isEmpty, "참고가 변경 목록을 오염시키지 않는다")
    }

    // MARK: 천장 — 조용히 지우지 않는다

    /// oldest-touched 축출은 이 기능이 막으려던 "안 본 변경이 남는다"의 재생산이다.
    /// 천장에 닿으면 **지우는 대신 센다**.
    @Test func 천장에_닿으면_지우지_않고_센다() {
        var set = AgentChangeSet()
        set.record(path: "/a.swift", sessionId: nil, prompt: nil, at: t0, ceiling: 2)
        set.record(path: "/b.swift", sessionId: nil, prompt: nil, at: t0, ceiling: 2)
        set.record(path: "/c.swift", sessionId: nil, prompt: nil, at: t0, ceiling: 2)

        #expect(set.entries.count == 2)
        #expect(set.entries["/a.swift"] != nil, "먼저 온 것을 지우지 않는다")
        #expect(set.entries["/c.swift"] == nil)
        #expect(set.truncatedCount == 1, "잘린 사실을 말할 수 있어야 한다")
    }

    /// 천장에 닿았어도 **이미 있는 경로의 갱신은 계속**돼야 한다 — 안 그러면 최신 활동을 잃는다.
    @Test func 천장에_닿아도_기존_항목은_갱신된다() {
        var set = AgentChangeSet()
        set.record(path: "/a.swift", sessionId: nil, prompt: nil, at: t0, ceiling: 1)
        set.record(path: "/b.swift", sessionId: nil, prompt: nil, at: t0, ceiling: 1)
        set.record(path: "/a.swift", sessionId: nil, prompt: nil, at: t1, ceiling: 1)

        #expect(set.entries["/a.swift"]?.lastTouchedAt == t1)
        #expect(set.entries["/a.swift"]?.touchCount == 2)
        #expect(set.truncatedCount == 1, "b만 잘렸다")
    }

    // MARK: 봤음

    @Test func 봤음은_그_항목만_찍는다() {
        var set = AgentChangeSet()
        set.record(path: "/a.swift", sessionId: nil, prompt: nil, at: t0)
        set.record(path: "/b.swift", sessionId: nil, prompt: nil, at: t0)
        set.markSeen(path: "/a.swift", at: t1)

        #expect(set.entries["/a.swift"]?.seenAt == t1)
        #expect(set.entries["/b.swift"]?.seenAt == nil)
    }

    @Test func 모르는_경로를_봤다고_해도_항목이_생기지_않는다() {
        var set = AgentChangeSet()
        set.markSeen(path: "/ghost.swift", at: t1)
        #expect(set.entries.isEmpty)
    }

    // MARK: 영속

    @Test func 왕복해도_같다() throws {
        var set = AgentChangeSet()
        set.baselineHead = "a3f21c9"
        set.record(path: "/a.swift", sessionId: "S1", prompt: "지시", at: t0)
        set.markSeen(path: "/a.swift", at: t1)
        set.record(reference: AgentChangeSet.reference(toolName: "WebFetch",
                                                      input: ["url": "https://x.test/a"],
                                                      cwd: nil, at: t0)!, at: t0)

        let data = try JSONEncoder().encode(set)
        #expect(try JSONDecoder().decode(AgentChangeSet.self, from: data) == set)
    }
}
