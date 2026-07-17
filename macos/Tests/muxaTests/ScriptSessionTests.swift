import Foundation
import Testing
@testable import muxa

/// 스크립트 tmux 세션 규약 — 이름·파싱·고아 판정(순수).
///
/// 세 네임스페이스(서비스 3조각 · 터미널 4조각 `term` · 스크립트 4조각 `script`)가 **서로의
/// 파서·GC에 안 걸리는 것**이 급소다 — 걸리면 남의 GC가 내 세션을 죽인다(파괴적 동작).
struct ScriptSessionTests {
    // MARK: 이름 — 규약과 화이트리스트

    @Test("세션명 규약: muxa__<projectId>__script__<scriptId>")
    func 세션명() {
        #expect(ScriptSession.name(projectId: "p1", scriptId: "s1") == "muxa__p1__script__s1")
    }

    @Test("id가 화이트리스트를 벗어나면 이름을 만들지 않는다 — 좀비보다 실패가 낫다")
    func 이름검증() {
        #expect(ScriptSession.name(projectId: "p'1", scriptId: "s1") == nil) // 인용 탈출
        #expect(ScriptSession.name(projectId: "p1", scriptId: "s__1") == nil) // 구분자 충돌
        #expect(ScriptSession.name(projectId: "", scriptId: "s1") == nil)
    }

    // MARK: 파싱 — 내 것만 분해한다

    @Test("스크립트 세션만 분해한다 — 서비스·터미널·남의 세션은 nil")
    func 파싱경계() {
        #expect(ScriptSession.parse("muxa__p1__script__s1")?.projectId == "p1")
        #expect(ScriptSession.parse("muxa__p1__script__s1")?.scriptId == "s1")
        #expect(ScriptSession.parse("muxa__p1__s1") == nil) // 서비스(3조각)
        #expect(ScriptSession.parse("muxa__p1__term__t1") == nil) // 터미널(marker 다름)
        #expect(ScriptSession.parse("main") == nil) // 남의 tmux 세션
        #expect(ScriptSession.parse("muxa__p1__script__") == nil) // 빈 id
    }

    @Test("역방향 — 스크립트 세션은 서비스·터미널 파서에 안 걸린다(남의 GC에 안 죽는다)")
    func 타파서불가침() {
        let session = ScriptSession.name(projectId: "p1", scriptId: "s1")!
        #expect(ServiceSession.parse(session) == nil)
        #expect(TerminalSession.parse(session) == nil)
    }

    // MARK: 고아 판정 — 좁게 죽이고 넓게 보존한다

    @Test("고아 = 아는 프로젝트의 스크립트 세션인데 등록이 사라진 것만")
    func 고아판정() {
        let sessions = ["muxa__p1__script__dead", // 등록 사라짐 → 고아
                        "muxa__p1__script__live", // 등록 있음 → 보존(종료 로그도 여기 산다)
                        "muxa__p9__script__x", // 모르는 프로젝트 → 남의 인스턴스, 보존
                        "muxa__p1__svc", // 서비스 → 판정 대상 아님
                        "muxa__p1__term__t1", // 터미널 → 판정 대상 아님
                        "main"] // 남의 세션 → 불가침
        let orphans = ScriptSession.orphans(sessions: sessions,
                                            liveScriptIds: ["live"],
                                            knownProjectIds: ["p1"])
        #expect(orphans == ["muxa__p1__script__dead"])
    }

    @Test("아는 프로젝트가 없으면 아무것도 안 지운다 — state 없이 뜬 인스턴스가 몰살하지 않게")
    func 빈프로젝트보존() {
        #expect(ScriptSession.orphans(sessions: ["muxa__p1__script__s1"],
                                      liveScriptIds: [], knownProjectIds: []).isEmpty)
    }
}
