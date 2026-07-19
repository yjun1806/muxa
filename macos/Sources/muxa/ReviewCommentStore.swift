import Foundation
import CryptoKit
import Observation

/// 리포별 리뷰 코멘트 영속 스토어(경계 타입). 순수 앵커링 로직은 ReviewCommentAnchor에 있고,
/// 여기는 메모리 상태 + 디스크 JSON 입출력만 맡는다. `.shared` 싱글턴 — GitService·MuxaSupportDir처럼
/// 뷰가 직접 접근하는 영속 경계다(값 자체는 immutable 교체로 갱신해 SwiftUI @Observable이 관측한다).
///
/// 파일: `<App Support>/muxa/review-comments/<sha256(repoRoot)>.json`. 키는 canonical repo 루트 절대경로.
@MainActor
@Observable
final class ReviewCommentStore {
    static let shared = ReviewCommentStore()

    /// repo 루트 → 코멘트 목록. 뷰가 이걸 읽어 관측한다(개수 배지·카드 표시).
    private(set) var byRepo: [String: [ReviewComment]] = [:]
    /// 이미 디스크에서 로드한 repo(중복 로드 방지). 관측 대상 아님.
    @ObservationIgnored private var loaded: Set<String> = []
    /// repo별 다음 seq(생성 순서). 관측 대상 아님.
    @ObservationIgnored private var nextSeq: [String: Int] = [:]

    private static let dirName = "review-comments"

    /// repo 루트 → 저장 파일 URL(SHA256로 경로 안전한 파일명).
    private func fileURL(forRepo root: String) -> URL {
        let digest = SHA256.hash(data: Data(root.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return MuxaSupportDir.subdirectory(Self.dirName).appendingPathComponent("\(name).json")
    }

    /// 최초 접근 시 디스크에서 로드(1회). 이후는 메모리에서 즉시 반환.
    private func ensureLoaded(_ root: String) {
        guard !loaded.contains(root) else { return }
        loaded.insert(root)
        guard let data = try? Data(contentsOf: fileURL(forRepo: root)),
              let comments = try? JSONDecoder().decode([ReviewComment].self, from: data) else {
            nextSeq[root] = 0
            return
        }
        byRepo[root] = comments
        nextSeq[root] = (comments.map(\.seq).max() ?? -1) + 1
    }

    private func persist(_ root: String) {
        let comments = byRepo[root] ?? []
        do {
            if comments.isEmpty {
                try? FileManager.default.removeItem(at: fileURL(forRepo: root))
            } else {
                let data = try JSONEncoder().encode(comments)
                try data.write(to: fileURL(forRepo: root), options: .atomic)
            }
        } catch {
            NSLog("[muxa] review comment persist 실패: \(error)")
        }
    }

    /// 이 리포의 코멘트(생성 순). 뷰 body에서 호출하면 관측이 걸린다.
    func comments(inRepo root: String) -> [ReviewComment] {
        ensureLoaded(root)
        return (byRepo[root] ?? []).sorted { $0.seq < $1.seq }
    }

    /// **한 스코프**의 코멘트만 — 커밋 diff엔 그 커밋 것만, 워크트리 diff엔 커밋 없는 것만.
    /// 화면에 뿌릴 땐 반드시 이쪽을 쓴다(`comments(inRepo:)`는 제출·개수 집계용 전체 목록이다).
    /// 스코프를 안 가르면 같은 파일·같은 줄이라는 이유로 남의 맥락 코멘트가 떠오른다.
    func comments(inRepo root: String, commit: String?) -> [ReviewComment] {
        comments(inRepo: root).filter { $0.commit == commit }
    }

    /// 코멘트 추가(seq 자동 부여) → 새 객체를 담고 즉시 영속.
    /// `commit`이 nil이면 워크트리 코멘트, 있으면 그 커밋에 묶인다.
    func add(file: String, side: DiffSide, line: Int, lineText: String, body: String,
             inRepo root: String, commit: String? = nil) {
        ensureLoaded(root)
        let seq = nextSeq[root] ?? 0
        nextSeq[root] = seq + 1
        let comment = ReviewComment(file: file, side: side, line: line, lineText: lineText,
                                    body: body, seq: seq, commit: commit)
        byRepo[root] = (byRepo[root] ?? []) + [comment] // immutable 교체
        persist(root)
    }

    /// id로 코멘트 제거.
    func delete(id: String, inRepo root: String) {
        ensureLoaded(root)
        guard let list = byRepo[root] else { return }
        byRepo[root] = list.filter { $0.id != id }
        persist(root)
    }

    /// 미제출 코멘트를 모두 반환하고 스토어에서 비운다(제출 후 consumed). 생성 순 정렬로 반환.
    func consumeAll(inRepo root: String) -> [ReviewComment] {
        ensureLoaded(root)
        let taken = (byRepo[root] ?? []).sorted { $0.seq < $1.seq }
        byRepo[root] = []
        persist(root)
        return taken
    }
}
