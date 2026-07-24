import Foundation
import Testing
@testable import muxa

/// 업데이트 확인·설치의 상태 전이 — 조회·설치를 주입해 네트워크 없이 검증한다.
@MainActor
struct UpdateCheckerTests {
    /// 격리된 UserDefaults(테스트 간 오염 방지) — suite 이름으로 만든다.
    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "muxa.update.tests")!
        d.removePersistentDomain(forName: "muxa.update.tests")
        return d
    }

    private func checker(current: String = "0.3.0",
                         isDev: Bool = false,
                         sourceRoot: String? = "/tmp/muxa-src",
                         tags: [String]? = ["v0.4.0", "v0.3.0"],
                         install: @escaping @Sendable (String) async -> Result<Void, UpdateInstaller.Failure>
                            = { _ in .success(()) }) -> UpdateChecker {
        UpdateChecker(current: current, isDev: isDev, sourceRoot: sourceRoot,
                      fetchTags: { tags }, install: install, defaults: defaults())
    }

    @Test("원격이 더 높으면 available")
    func 업데이트감지() async {
        let c = checker()
        await c.checkNow()
        #expect(c.phase == .available(SemVer(parsing: "0.4.0")!))
    }

    @Test("이미 최신이면 idle")
    func 최신이면idle() async {
        let c = checker(current: "0.4.0")
        await c.checkNow()
        #expect(c.phase == .idle)
    }

    @Test("조회 실패(nil)는 무음 — phase 유지")
    func 조회실패무음() async {
        // 먼저 available로 만든 뒤, 다음 조회가 실패하면 그대로 유지되는지.
        let c = checker()
        await c.checkNow()
        #expect(c.phase == .available(SemVer(parsing: "0.4.0")!))
        // 실패를 흉내내려면 새 checker가 필요 — fetch가 고정이라, 별도 인스턴스로 nil 검증.
        let fail = UpdateChecker(current: "0.3.0", isDev: false, sourceRoot: "/tmp",
                                 fetchTags: { nil }, install: { _ in .success(()) }, defaults: defaults())
        await fail.checkNow()
        #expect(fail.phase == .idle)  // 조회 실패 시 초기 idle 유지(덮지 않음)
    }

    @Test("dev 빌드는 확인하지 않는다")
    func dev스킵() async {
        let c = checker(isDev: true)
        await c.checkNow()
        #expect(c.phase == .idle)
    }

    @Test("자동확인 끄면 확인 안 하고, 켜져 있던 배지도 지운다")
    func optOut() async {
        let c = checker()
        await c.checkNow()
        #expect(c.phase == .available(SemVer(parsing: "0.4.0")!))
        c.autoCheckEnabled = false
        #expect(c.phase == .idle)           // 끄면 배지 제거
        await c.checkNow()
        #expect(c.phase == .idle)           // 꺼진 동안 재확인 안 함
    }

    @Test("업데이트 성공 → updated")
    func 설치성공() async {
        let c = checker(install: { _ in .success(()) })
        await c.checkNow()
        await c.startUpdate()
        #expect(c.phase == .updated(SemVer(parsing: "0.4.0")!))
    }

    @Test("업데이트 실패 → failed(메시지·로그)")
    func 설치실패() async {
        let c = checker(install: { _ in .failure(.init(message: "재빌드 실패", logPath: "/tmp/u.log")) })
        await c.checkNow()
        await c.startUpdate()
        #expect(c.phase == .failed(SemVer(parsing: "0.4.0")!, message: "재빌드 실패", logPath: "/tmp/u.log"))
    }

    @Test("소스 저장소 없으면 failed — 재설치 안내")
    func 소스없음() async {
        let c = checker(sourceRoot: nil)
        await c.checkNow()
        await c.startUpdate()
        guard case .failed(_, let message, let log) = c.phase else {
            Issue.record("failed 상태가 아님: \(c.phase)"); return
        }
        #expect(message.contains("curl"))
        #expect(log == nil)
    }

    @Test("available 아닐 때 startUpdate는 무동작")
    func idle에서설치무동작() async {
        let c = checker(current: "0.4.0")  // 최신 → idle
        await c.checkNow()
        await c.startUpdate()
        #expect(c.phase == .idle)
    }

    // MARK: - 수동 확인(checkManually)

    @Test("수동 확인 — 업데이트 있으면 .available 반환 + 레일 배지(phase) 등장")
    func 수동_업데이트있음() async {
        let c = checker()  // current 0.3.0, tags [v0.4.0]
        let r = await c.checkManually()
        #expect(r == .available(SemVer(parsing: "0.4.0")!))
        #expect(c.phase == .available(SemVer(parsing: "0.4.0")!))  // 배지 뜨는 계약
    }

    @Test("수동 확인 — 최신이면 .upToDate, 배지 없음")
    func 수동_최신() async {
        let c = checker(current: "0.4.0")
        let r = await c.checkManually()
        #expect(r == .upToDate)
        #expect(c.phase == .idle)
    }

    @Test("수동 확인 — 조회 실패는 .failed")
    func 수동_조회실패() async {
        let c = checker(tags: nil)
        let r = await c.checkManually()
        #expect(r == .failed)
    }

    @Test("수동 확인 — 자동확인을 꺼도 동작한다(명시적 요청)")
    func 수동_자동확인꺼져도동작() async {
        let c = checker()
        c.autoCheckEnabled = false
        let r = await c.checkManually()
        #expect(r == .available(SemVer(parsing: "0.4.0")!))
        #expect(c.phase == .available(SemVer(parsing: "0.4.0")!))
    }

    @Test("수동 확인 — dev 빌드는 .devBuild (오탐 방지)")
    func 수동_dev빌드() async {
        let c = checker(isDev: true)
        let r = await c.checkManually()
        #expect(r == .devBuild)
        #expect(c.phase == .idle)  // dev는 phase도 안 건드림
    }

    @Test("수동 확인 — 설치 흐름 중이면 .busy (덮지 않음)")
    func 수동_설치중이면busy() async {
        let c = checker(install: { _ in .success(()) })
        await c.checkNow()
        await c.startUpdate()
        #expect(c.phase == .updated(SemVer(parsing: "0.4.0")!))
        let r = await c.checkManually()
        #expect(r == .busy)
        #expect(c.phase == .updated(SemVer(parsing: "0.4.0")!))  // 안 덮음
    }

    @Test("수동 확인 — 최신이 되면 이전 배지를 정리한다")
    func 수동_이전배지정리() async {
        let feed = TagFeed(["v0.4.0"])
        let c = UpdateChecker(current: "0.3.0", isDev: false, sourceRoot: "/tmp",
                              fetchTags: { feed.tags }, install: { _ in .success(()) }, defaults: defaults())
        _ = await c.checkManually()
        #expect(c.phase == .available(SemVer(parsing: "0.4.0")!))  // 배지 있음
        feed.tags = ["v0.3.0"]                                     // 원격이 현재와 같아짐(최신)
        let r = await c.checkManually()
        #expect(r == .upToDate)
        #expect(c.phase == .idle)                                  // 이전 배지 정리됨
    }
}

/// 호출 간 태그를 바꿀 수 있는 테스트용 피드(단일 스레드 테스트라 @unchecked Sendable로 충분).
private final class TagFeed: @unchecked Sendable {
    var tags: [String]
    init(_ tags: [String]) { self.tags = tags }
}
