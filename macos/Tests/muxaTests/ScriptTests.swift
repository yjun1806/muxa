import Foundation
import Testing
@testable import muxa

/// 스크립트 순수 기반 — Script 모델 왕복·하위호환, 소속 순회(collect*).
/// 실행 전이(merge)는 ScriptRunTests, 세션명 규약은 ScriptSessionTests가 맡는다.
struct ScriptTests {
    // MARK: Script 모델 — Codable 왕복·Project.scripts 하위호환

    @Test("Script는 Codable 왕복에서 그대로 돌아온다 — cwd 지정 포함")
    func 스크립트왕복() throws {
        let s = Script(id: "s1", name: "build", command: "make build", cwd: "/repo/apps/admin")
        let back = try JSONDecoder().decode(Script.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test("scripts 필드가 없는 구 Project JSON은 nil로 디코드된다")
    func 구프로젝트하위호환() throws {
        // scripts는 물론 services·detached도 없던 옛 저장분 — 하위호환의 최저선.
        let json = Data(#"{"id":"p","name":"메인"}"#.utf8)
        let back = try JSONDecoder().decode(Project.self, from: json)
        #expect(back.scripts == nil)
    }

    @Test("Project.scripts는 왕복에서 그대로 돌아온다")
    func 프로젝트왕복() throws {
        let p = Project(id: "p", name: "메인",
                        scripts: [Script(id: "s1", name: "build", command: "make build")])
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(back.scripts == p.scripts)
    }

    // MARK: 소속 순회 — 모니터 폴링·도크 목록·GC 입력이 전부 이 하나를 쓴다

    @Test("collectAllScripts는 모든 워크스페이스를 훑고 소속·cwd(프로젝트 경로 우선)를 단다")
    func 전체수집() {
        let ws1 = Workspace(id: "w1", path: "/ws1", name: "메인",
                            projects: [Project(id: "p1", name: "웹",
                                               scripts: [Script(id: "s1", name: "build", command: "make")])],
                            activeProjectId: "p1")
        let ws2 = Workspace(id: "w2", path: "/ws2", name: "실험",
                            projects: [Project(id: "p2", name: "api", path: "/wt/api",
                                               scripts: [Script(id: "s2", name: "test", command: "pnpm test")])],
                            activeProjectId: "p2")
        let all = collectAllScripts(in: [ws1, ws2])
        #expect(all.map(\.id) == ["s1", "s2"])
        #expect(all[0].cwd == "/ws1") // 프로젝트 경로가 없으면 워크스페이스 경로 상속
        #expect(all[1].cwd == "/wt/api") // 프로젝트 자체 경로(워크트리)가 우선
        #expect(all[1].workspaceName == "실험")
        #expect(all[1].projectId == "p2")
    }

    @Test("스크립트 자체 cwd가 있으면 프로젝트 경로보다 우선한다 — 서비스와 같은 해석 사슬")
    func cwd지정우선() {
        let ws = Workspace(id: "w", path: "/repo", name: "repo",
                           projects: [Project(id: "p", name: "메인",
                                              scripts: [Script(id: "s", name: "build", command: "make",
                                                               cwd: "/repo/apps/admin")])],
                           activeProjectId: "p")
        #expect(collectAllScripts(in: [ws]).first?.cwd == "/repo/apps/admin")
    }

    @Test("collectLiveScriptIds는 모든 워크스페이스의 등록 id를 모은다 — GC 판정의 보존 입력")
    func 등록id수집() {
        let ws1 = Workspace(id: "w1", path: nil, name: "a", projects: [
            Project(id: "p1", name: "x", scripts: [Script(id: "s1", name: "b", command: "c")]),
        ], activeProjectId: "p1")
        let ws2 = Workspace(id: "w2", path: nil, name: "b", projects: [
            Project(id: "p2", name: "y", scripts: [Script(id: "s2", name: "b", command: "c")]),
            Project(id: "p3", name: "z"), // scripts nil — 크래시 없이 건너뛴다
        ], activeProjectId: "p2")
        #expect(collectLiveScriptIds(in: [ws1, ws2]) == ["s1", "s2"])
    }
}
