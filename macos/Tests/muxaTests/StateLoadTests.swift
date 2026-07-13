import Testing
@testable import muxa

/// 상태 파일 2단 폴백 판정(순수) — primary → backup → 빈 상태.
/// 파일 I/O와 분리해 두어야 "손상되면 정말 백업을 쓰는가"를 앱을 띄우지 않고 검증할 수 있다.
struct StateLoadTests {
    @Test func primary가_정상이면_primary를_쓰고_백업을_갱신한다() {
        let r = StateLoad.choose(primary: .valid, backup: .valid)
        #expect(r.source == .primary)
        #expect(r.refreshBackup) // 정상 로드분을 백업으로 남긴다(세션당 1회)
        #expect(r.warnings.isEmpty)
    }

    @Test func primary가_손상이면_백업으로_폴백하고_경고한다() {
        let r = StateLoad.choose(primary: .corrupt, backup: .valid)
        #expect(r.source == .backup)
        #expect(!r.refreshBackup) // 백업은 유일한 복구 경로 — 절대 덮지 않는다
        #expect(r.warnings.count == 1)
    }

    @Test func primary가_없고_백업만_있으면_백업을_쓴다() {
        // 저장 도중 크래시로 primary만 날아간 경우.
        let r = StateLoad.choose(primary: .missing, backup: .valid)
        #expect(r.source == .backup)
        #expect(!r.refreshBackup)
        #expect(r.warnings.count == 1)
    }

    @Test func 둘_다_손상이면_빈_상태로_시작하고_경고한다() {
        let r = StateLoad.choose(primary: .corrupt, backup: .corrupt)
        #expect(r.source == .none)
        #expect(r.warnings.count == 1)
    }

    @Test func 최초_실행은_경고하지_않는다() {
        // 파일이 아예 없는 것은 유실이 아니다 — 첫 실행에 경고를 띄우면 안 된다.
        let r = StateLoad.choose(primary: .missing, backup: .missing)
        #expect(r.source == .none)
        #expect(r.warnings.isEmpty)
        #expect(!r.refreshBackup)
    }

    @Test func primary가_손상이고_백업이_없으면_경고한다() {
        let r = StateLoad.choose(primary: .corrupt, backup: .missing)
        #expect(r.source == .none)
        #expect(r.warnings.count == 1)
    }
}
