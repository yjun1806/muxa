import XCTest
@testable import muxa

/// 사용량 서비스의 상태 규칙 검증 — 캐시 TTL·실패 백오프·실패 시 이전 값 유지.
/// (조회와 시각을 주입해 네트워크·키체인 없이 돌린다.)
@MainActor
final class ClaudeUsageServiceTests: XCTestCase {
    private let sample = [UsageLimit(kind: "session", label: "5h", percent: 9, resetsAt: nil,
                                     severity: "normal", isModelScoped: false)]

    /// 시각을 마음대로 흘릴 수 있는 시계 + 호출 횟수를 세는 가짜 조회.
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000_000)
        var calls = 0
    }

    /// 인메모리 공유 저장소 — 파일 없이 좌표 로직을 검증한다(한 서비스당 하나).
    private final class MemoryStore: UsageStore, @unchecked Sendable {
        private var snapshot: UsageSnapshot?
        func load() -> UsageSnapshot? { snapshot }
        func save(_ s: UsageSnapshot) { snapshot = s }
    }

    private func makeService(_ clock: Clock,
                             results: [UsageFetch],
                             store: UsageStore = MemoryStore()) -> ClaudeUsageService {
        ClaudeUsageService(
            fetcher: { [clock] in
                let index = min(clock.calls, results.count - 1)
                clock.calls += 1
                return results[index]
            },
            now: { [clock] in clock.now },
            store: store
        )
    }

    func testSuccessPopulatesLimits() async {
        let clock = Clock()
        let service = makeService(clock, results: [.ok(sample)])
        await service.refresh()
        XCTAssertEqual(service.limits, sample)
        XCTAssertEqual(service.state, .ok)
        XCTAssertFalse(service.failed)
        XCTAssertEqual(service.lastSuccess, clock.now)
    }

    /// 성공 뒤 5분 안에는 다시 안 때린다 — 사용량 API를 자주 호출하면 계정에 이상 신호가 될 수 있다.
    func testSuccessIsCachedForFiveMinutes() async {
        let clock = Clock()
        let service = makeService(clock, results: [.ok(sample)])
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 1)

        clock.now.addTimeInterval(299)
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 1, "5분 전엔 재조회하지 않아야 한다")

        clock.now.addTimeInterval(2)
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 2, "5분이 지나면 재조회한다")
    }

    /// 실패는 성공과 같은 5분을 기다리면 안 된다 — 순단 한 번이 5분간의 "—"로 굳는다.
    func testFailureRetriesSoonerThanSuccess() async {
        let clock = Clock()
        let service = makeService(clock, results: [.failure, .ok(sample)])
        await service.refreshIfStale()
        XCTAssertEqual(service.state, .failed)

        clock.now.addTimeInterval(44)
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 1, "45초 전엔 재시도하지 않는다")

        clock.now.addTimeInterval(2)
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 2, "45초가 지나면 재시도한다")
        XCTAssertEqual(service.state, .ok)
        XCTAssertEqual(service.limits, sample)
    }

    /// 실패해도 이전 값은 남는다 — 일시적 오류로 화면이 비면 오히려 불안하다.
    func testFailureKeepsPreviousLimits() async {
        let clock = Clock()
        let service = makeService(clock, results: [.ok(sample), .failure])
        await service.refresh()
        clock.now.addTimeInterval(600)
        await service.refresh()

        XCTAssertEqual(service.state, .failed)
        XCTAssertEqual(service.limits, sample, "이전 조회 결과가 유지돼야 한다")
        XCTAssertEqual(service.lastSuccess, Date(timeIntervalSince1970: 1_000_000), "성공 시각은 실패로 갱신되지 않는다")
    }

    /// 429는 서버가 "기다려라"고 말한 것 — retry-after를 존중한다. 45초 재시도로 두드리면
    /// 리밋 창이 계속 연장돼 스스로 벗어나지 못한다(실측: retry-after 3068초를 무시하고 두드렸다).
    func testRateLimitHonorsRetryAfter() async {
        let clock = Clock()
        let service = makeService(clock, results: [.rateLimited(retryAfter: 3068), .ok(sample)])
        await service.refreshIfStale()
        XCTAssertEqual(service.state, .rateLimited)

        clock.now.addTimeInterval(46)
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 1, "실패 백오프(45초)로 재시도하면 안 된다 — 리밋이 연장된다")

        clock.now.addTimeInterval(3000)
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 1, "retry-after(3068초) 전엔 재시도하지 않는다")

        clock.now.addTimeInterval(30)
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 2, "retry-after가 지나면 재시도한다")
        XCTAssertEqual(service.state, .ok)
    }

    /// retry-after 헤더가 없으면 기본 15분을 기다린다(45초 루프보다 훨씬 보수적으로).
    func testRateLimitWithoutHeaderWaitsDefault() async {
        let clock = Clock()
        let service = makeService(clock, results: [.rateLimited(retryAfter: nil), .ok(sample)])
        await service.refreshIfStale()

        clock.now.addTimeInterval(899)
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 1, "기본 대기(15분) 전엔 재시도하지 않는다")

        clock.now.addTimeInterval(2)
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 2)
    }

    /// 서버가 터무니없는 retry-after를 줘도 1시간 상한 — "영영 안 물어봄"으로 굳지 않게.
    func testRateLimitWaitIsCappedAtOneHour() async {
        let clock = Clock()
        let service = makeService(clock, results: [.rateLimited(retryAfter: 90_000), .ok(sample)])
        await service.refreshIfStale()

        clock.now.addTimeInterval(3601)
        await service.refreshIfStale()
        XCTAssertEqual(clock.calls, 2, "1시간이 지나면 상한에 걸려 재시도한다")
    }

    /// 레이트리밋도 이전 값은 유지한다(실패와 동일) — 화면이 비면 오히려 불안하다.
    func testRateLimitKeepsPreviousLimits() async {
        let clock = Clock()
        let service = makeService(clock, results: [.ok(sample), .rateLimited(retryAfter: 60)])
        await service.refresh()
        clock.now.addTimeInterval(600)
        await service.refresh()

        XCTAssertEqual(service.state, .rateLimited)
        XCTAssertEqual(service.limits, sample, "이전 조회 결과가 유지돼야 한다")
    }

    /// 수동 새로고침(refresh)은 백오프를 무시한다 — 사용자가 눌렀으면 지금 물어본다.
    func testManualRefreshBypassesRateLimitBackoff() async {
        let clock = Clock()
        let service = makeService(clock, results: [.rateLimited(retryAfter: 3068), .ok(sample)])
        await service.refreshIfStale()
        XCTAssertEqual(service.state, .rateLimited)

        clock.now.addTimeInterval(10)
        await service.refresh()
        XCTAssertEqual(clock.calls, 2)
        XCTAssertEqual(service.state, .ok)
    }

    /// 200인데 항목이 0개(스키마 변경 의심)는 실패와 구분된다 — 원인 진단이 가능해야 한다.
    func testEmptyResponseIsNotFailure() async {
        let clock = Clock()
        let service = makeService(clock, results: [.empty])
        await service.refresh()

        XCTAssertEqual(service.state, .empty)
        XCTAssertFalse(service.failed, "서버는 정상 응답했다 — 네트워크 실패와 같게 취급하면 진단이 막힌다")
        XCTAssertTrue(service.limits.isEmpty)
    }

    // MARK: 인스턴스 간 공유 — 한 저장소를 두 서비스가 함께 본다

    /// 인스턴스 A가 성공하면, B는 프로브 없이 공유 캐시에서 값을 읽는다 — 전체 요청률이 한 인스턴스분으로 준다.
    func testSharedCacheServedToOtherInstance() async {
        let store = MemoryStore()
        let clockA = Clock()
        let serviceA = makeService(clockA, results: [.ok(sample)], store: store)
        await serviceA.refreshIfStale()
        XCTAssertEqual(clockA.calls, 1)

        let clockB = Clock() // 같은 시각(t0)에서 출발
        let serviceB = makeService(clockB, results: [.ok(sample)], store: store)
        await serviceB.refreshIfStale()
        XCTAssertEqual(clockB.calls, 0, "A의 신선한 캐시가 있으면 B는 네트워크를 건드리지 않는다")
        XCTAssertEqual(serviceB.state, .ok)
        XCTAssertEqual(serviceB.limits, sample, "B는 공유 캐시 값을 그대로 보여준다")
    }

    /// 인스턴스 A가 429를 받으면, B는 같은 백오프 창을 존중한다 — 서로 리밋을 연장시키지 않는다(핵심 목적).
    func testRateLimitBackoffSharedAcrossInstances() async {
        let store = MemoryStore()
        let clockA = Clock()
        let serviceA = makeService(clockA, results: [.rateLimited(retryAfter: 1800)], store: store)
        await serviceA.refreshIfStale()
        XCTAssertEqual(serviceA.state, .rateLimited)

        let clockB = Clock() // t0 — A의 백오프 창(1800초) 한참 안쪽
        let serviceB = makeService(clockB, results: [.ok(sample)], store: store)
        await serviceB.refreshIfStale()
        XCTAssertEqual(clockB.calls, 0, "A가 429 백오프 중이면 B는 프로브하지 않는다 — 이게 리밋 연장을 막는다")
        XCTAssertEqual(serviceB.state, .rateLimited, "B도 제한 상태로 표시(로그인 문제가 아니다)")
    }

    /// 429 백오프 중인 인스턴스가 갓 떠도(idle) 공유 캐시의 이전 값을 화면에 보여준다 — "—"로 비지 않게.
    func testFreshInstanceShowsCachedLimitsWhileRateLimited() async {
        let store = MemoryStore()
        let seed = Clock()
        // 먼저 한 번 성공시켜 공유 캐시에 값을 심는다.
        await makeService(seed, results: [.ok(sample)], store: store).refreshIfStale()

        // 캐시가 만료된 뒤(5분+) 새 인스턴스가 프로브했다가 429를 받는다.
        let late = Clock()
        late.now.addTimeInterval(400)
        let service = makeService(late, results: [.rateLimited(retryAfter: 600)], store: store)
        await service.refreshIfStale()

        XCTAssertEqual(service.state, .rateLimited)
        XCTAssertEqual(service.limits, sample, "제한 중에도 공유 캐시의 이전 값을 보여준다")
    }
}
