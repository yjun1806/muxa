import Foundation
import Testing
@testable import muxa

/// 탭별 수집 파일의 영속과 GC.
///
/// 키가 **탭 id가 아니라 tmux 세션명**인 경우가 있다 — `reattach`는 백그라운드 세션을 되찾을 때
/// 새 `TabID`에 기존 세션 이름을 물려주므로, 탭 id로 파일을 잡으면 기록이 유실된다
/// (`IdeSessionLedger`가 같은 지점에서 받은 리뷰 지적 I-1).
///
/// 삭제 판정은 `ScrollbackStore.orphans`와 **같은 3중 보존**을 쓴다 — 의심되면 안 지운다.
struct AgentChangeStoreTests {
    private let now = Date(timeIntervalSince1970: 10_000)
    private let hour: TimeInterval = 3600

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-changes-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: 키 검증 — 외부에서 온 문자열이 파일 경로가 된다

    @Test func 실제로_쓰는_키들은_통과한다() {
        #expect(AgentChangeStore.isSafeKey("muxa__F2AF1DD9__term__4E78113E"))  // tmux 세션명
        #expect(AgentChangeStore.isSafeKey(UUID().uuidString))                 // TabID
        #expect(AgentChangeStore.isSafeKey("a.b-c_1"))
    }

    /// 키는 파일명이 된다 — 경로 구분자·상위참조가 통과하면 지정 폴더 밖에 쓰게 된다.
    /// 형식을 아는 값은 **블랙리스트가 아니라 화이트리스트**로 검증한다(`ClaudeSessionIndex.isSafeSessionId` 태도).
    @Test func 경로가_될_수_있는_키는_거부한다() {
        for bad in ["", ".", "..", "../evil", "a/b", "/abs", "a b", "a\nb", "키", "a:b", "~"] {
            #expect(!AgentChangeStore.isSafeKey(bad), "거부해야 한다: \(bad.debugDescription)")
        }
    }

    @Test func 위험한_키로는_파일을_만들지_않는다() {
        let dir = tempDir()
        var set = AgentChangeSet()
        set.record(path: "/a.swift", sessionId: nil, prompt: nil, at: now)

        AgentChangeStore.write(set, key: "../escaped", in: dir)

        let siblings = try? FileManager.default.contentsOfDirectory(
            at: dir.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        #expect(siblings?.contains { $0.lastPathComponent.contains("escaped") } != true)
        #expect(AgentChangeStore.load(key: "../escaped", in: dir) == nil)
    }

    // MARK: 왕복 — Codable 실패는 사용자 기록의 조용한 유실이다

    @Test func 쓰고_읽으면_그대로다() {
        let dir = tempDir()
        let key = UUID().uuidString
        var set = AgentChangeSet()
        set.baselineHead = "a3f21c9"
        set.record(path: "/a.swift", sessionId: "S1", prompt: "지시", at: now)
        set.markSeen(path: "/a.swift", at: now)
        set.record(reference: AgentReference(kind: .web, value: "https://x.test/a", lastSeenAt: now),
                   at: now)

        AgentChangeStore.write(set, key: key, in: dir)
        #expect(AgentChangeStore.load(key: key, in: dir) == set)
    }

    @Test func 없는_키는_nil이고_터지지_않는다() {
        #expect(AgentChangeStore.load(key: UUID().uuidString, in: tempDir()) == nil)
    }

    @Test func 깨진_파일은_nil로_삼킨다() throws {
        let dir = tempDir()
        let key = UUID().uuidString
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("\(key).json"))
        // 파싱 실패로 앱이 죽지 않는다 — 기록 하나를 잃을 뿐이다.
        #expect(AgentChangeStore.load(key: key, in: dir) == nil)
    }

    @Test func 지우면_사라진다() {
        let dir = tempDir()
        let key = UUID().uuidString
        AgentChangeStore.write(AgentChangeSet(), key: key, in: dir)
        #expect(AgentChangeStore.load(key: key, in: dir) != nil)

        AgentChangeStore.delete(key: key, in: dir)
        #expect(AgentChangeStore.load(key: key, in: dir) == nil)
    }

    // MARK: GC 판정 (순수) — 보존 조건 셋

    private func file(_ key: String, ago: TimeInterval) -> AgentChangeStore.ChangeFile {
        AgentChangeStore.ChangeFile(path: "/dir/\(key).json", key: key,
                                   modified: now.addingTimeInterval(-ago))
    }

    @Test func 살아있는_키는_남긴다() {
        let f = file("live", ago: 10 * hour)
        #expect(AgentChangeStore.orphans(in: [f], liveKeys: ["live"], referencedPaths: [],
                                         now: now, graceInterval: hour).isEmpty)
    }

    /// 아직 안 연 lazy 프로젝트의 기록 — 살아있는 탭은 없지만 스냅샷이 가리킨다.
    @Test func 스냅샷이_가리키면_남긴다() {
        let f = file("lazy", ago: 10 * hour)
        #expect(AgentChangeStore.orphans(in: [f], liveKeys: [], referencedPaths: [f.path],
                                         now: now, graceInterval: hour).isEmpty)
    }

    /// 방금 쓰였는데 아직 어디에도 안 실린 파일 방어 — 의심되면 안 지운다.
    @Test func 유예_안쪽에_수정된_것은_남긴다() {
        let f = file("fresh", ago: 60)
        #expect(AgentChangeStore.orphans(in: [f], liveKeys: [], referencedPaths: [],
                                         now: now, graceInterval: hour).isEmpty)
    }

    @Test func 셋_다_아니면_고아다() {
        let f = file("gone", ago: 10 * hour)
        #expect(AgentChangeStore.orphans(in: [f], liveKeys: [], referencedPaths: [],
                                         now: now, graceInterval: hour) == [f.path])
    }

    /// mtime을 못 읽었을 때 경계가 넣는 값 — 항상 유예 안쪽이라 삭제 대상이 되지 않는다.
    @Test func 수정시각을_모르면_지우지_않는다() {
        let f = AgentChangeStore.ChangeFile(path: "/dir/x.json", key: "x", modified: .distantFuture)
        #expect(AgentChangeStore.orphans(in: [f], liveKeys: [], referencedPaths: [],
                                         now: now, graceInterval: hour).isEmpty)
    }

    // MARK: GC 실행 — 고아만 지운다

    @Test func 수집실행은_고아만_지운다() throws {
        let dir = tempDir()
        let live = UUID().uuidString, orphan = UUID().uuidString
        AgentChangeStore.write(AgentChangeSet(), key: live, in: dir)
        AgentChangeStore.write(AgentChangeSet(), key: orphan, in: dir)

        // 유예를 0으로 둬 방금 쓴 파일도 판정 대상이 되게 한다.
        AgentChangeStore.collectGarbage(liveKeys: [live], referencedPaths: [],
                                        now: Date(), graceInterval: 0, in: dir)

        #expect(AgentChangeStore.load(key: live, in: dir) != nil)
        #expect(AgentChangeStore.load(key: orphan, in: dir) == nil)
    }

    /// 스캔이 안 되면(폴더 없음) 아무것도 안 지운다 — 판정 못 하면 손대지 않는다.
    @Test func 폴더가_없으면_아무것도_하지_않는다() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString)", isDirectory: true)
        AgentChangeStore.collectGarbage(liveKeys: [], referencedPaths: [],
                                        now: now, graceInterval: 0, in: missing)
        // 터지지 않으면 통과.
    }
}
