import Testing
@testable import muxa

/// 서비스 팝오버의 묶기·정렬(순수) — **현재 프로젝트가 반드시 맨 앞**이어야 한다.
///
/// 원래 `sorted { a, _ in a == current }`였는데, 이건 엄격 약순서가 아니라 정렬 결과가 비교자 호출
/// 순서에 좌우된다(현재 프로젝트가 가운데 박히는 배치가 나온다). 분할로 바꾸고 여기서 못 박는다.
struct ServiceGroupTests {
    private func located(_ serviceId: String, project: String, projectName: String? = nil,
                         workspace: String = "W", workspaceName: String = "front") -> LocatedService {
        LocatedService(service: Service(id: serviceId, name: serviceId, command: "pnpm dev"),
                       workspaceId: workspace, workspaceName: workspaceName,
                       projectId: project, projectName: projectName ?? project, cwd: nil)
    }

    @Test("현재 프로젝트가 맨 앞에 온다")
    func 현재프로젝트가맨앞() {
        let items = [located("a", project: "P1"), located("b", project: "P2"), located("c", project: "P3")]
        let groups = groupServices(items, current: "P3", showWorkspace: false)
        #expect(groups.map(\.projectId) == ["P3", "P1", "P2"])
    }

    /// 현재 프로젝트가 **맨 뒤**에 있을 때가 옛 비교자가 가장 잘 틀리던 배치다.
    @Test("현재 프로젝트가 마지막에 선언돼도 맨 앞으로 올라온다")
    func 마지막선언도맨앞() {
        let items = (1...6).map { located("s\($0)", project: "P\($0)") }
        let groups = groupServices(items, current: "P6", showWorkspace: false)
        #expect(groups.first?.projectId == "P6")
        #expect(groups.map(\.projectId) == ["P6", "P1", "P2", "P3", "P4", "P5"])
    }

    @Test("현재 프로젝트를 뺀 나머지는 선언 순서를 지킨다")
    func 나머지는선언순서() {
        let items = [located("a", project: "P1"), located("b", project: "P2"),
                     located("c", project: "P1"), located("d", project: "P3")]
        let groups = groupServices(items, current: "P2", showWorkspace: false)
        #expect(groups.map(\.projectId) == ["P2", "P1", "P3"])
        // 프로젝트 안에서도 선언 순서 유지
        #expect(groups.last(where: { $0.projectId == "P1" })?.services.map(\.id) == ["a", "c"])
    }

    @Test("현재 프로젝트에 서비스가 없으면 그 묶음은 생기지 않는다")
    func 현재프로젝트가비면묶음없음() {
        let groups = groupServices([located("a", project: "P1")], current: "P9", showWorkspace: false)
        #expect(groups.map(\.projectId) == ["P1"])
    }

    @Test("한 프로젝트의 서비스는 한 묶음으로 합쳐진다")
    func 같은프로젝트는한묶음() {
        let items = [located("web", project: "P1"), located("api", project: "P1")]
        let groups = groupServices(items, current: "P1", showWorkspace: false)
        #expect(groups.count == 1)
        #expect(groups[0].services.map(\.id) == ["web", "api"])
    }

    /// 워크스페이스가 여럿이면 어느 워크스페이스인지 밝힌다 — 아니면 프로젝트 이름만(같은 말 반복 금지).
    @Test("워크스페이스가 여럿이면 제목에 워크스페이스를 붙인다")
    func 제목에워크스페이스() {
        let items = [located("web", project: "P1", projectName: "웹", workspaceName: "front")]
        #expect(groupServices(items, current: "P1", showWorkspace: true).first?.title == "front › 웹")
        #expect(groupServices(items, current: "P1", showWorkspace: false).first?.title == "웹")
    }

    @Test("서비스가 없으면 빈 목록")
    func 빈입력() {
        #expect(groupServices([], current: "P1", showWorkspace: true).isEmpty)
    }
}
