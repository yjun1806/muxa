import Foundation

/// 공유 사용량 스냅샷의 읽기·쓰기 경계 — 부작용(파일 IO)을 여기 한 곳에 가둔다.
/// 테스트는 인메모리 구현을 주입해 파일 없이 좌표 로직을 검증한다.
protocol UsageStore: Sendable {
    func load() -> UsageSnapshot?
    func save(_ snapshot: UsageSnapshot)
}

/// 파일 기반 공유 저장소 — 모든 빌드가 `MuxaSupportDir.sharedURL`의 한 파일을 공유한다.
/// 원자적 쓰기(`.atomic` = temp 파일 → rename)라 여러 인스턴스가 동시에 읽어도 torn read가 없다.
struct UsageFileStore: UsageStore {
    let url: URL

    static let `default` = UsageFileStore(
        url: MuxaSupportDir.sharedURL.appendingPathComponent("usage-cache.json"))

    func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    func save(_ snapshot: UsageSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
