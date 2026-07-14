import Testing
@testable import muxa

/// 인박스 라우팅의 갈림길(순수) — **이 id는 탭인가 서비스인가.**
///
/// 서비스가 죽으면 인박스 항목의 `tabId` 자리에 **서비스 id**가 들어간다. 서비스는 탭 트리 밖에 살아
/// (D19) 그 id로는 어떤 탭도 못 찾는데, 그걸 모르고 진행하면 프로젝트만 이동하고 Git 패널이 열려
/// 정작 죽은 서버의 로그는 안 뜬다. 그 분기를 여기서 못 박는다.
struct ServiceRevealTests {
    private func workspace(_ id: String, projects: [Project]) -> Workspace {
        Workspace(id: id, path: nil, name: "front", projects: projects,
                  activeProjectId: projects.first?.id ?? "")
    }

    private func project(_ id: String, services: [Service]) -> Project {
        Project(id: id, name: "웹", path: nil, services: services)
    }

    @Test("등록된 서비스 id면 소속(워크스페이스·프로젝트)과 함께 찾는다")
    func 서비스id를찾는다() {
        let ws = [workspace("W1", projects: [project("P1", services: [])]),
                  workspace("W2", projects: [project("P2", services: [
                      Service(id: "S1", name: "web", command: "pnpm dev")
                  ])])]
        let found = locateService("S1", in: ws)
        #expect(found?.service.name == "web")
        #expect(found?.workspaceId == "W2")
        #expect(found?.projectId == "P2")
    }

    @Test("탭 id(서비스가 아닌 id)면 nil — 탭 동선으로 흘려보낸다")
    func 탭id면nil() {
        let ws = [workspace("W1", projects: [project("P1", services: [
            Service(id: "S1", name: "web", command: "pnpm dev")
        ])])]
        #expect(locateService("3F2504E0-4F89-11D3-9A0C-0305E82C3301", in: ws) == nil)
    }

    @Test("서비스가 하나도 없으면 nil")
    func 서비스없음() {
        #expect(locateService("S1", in: [workspace("W1", projects: [project("P1", services: [])])]) == nil)
    }
}
