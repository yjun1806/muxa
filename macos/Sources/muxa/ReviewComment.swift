import Foundation

/// diff 줄의 어느 쪽에 달린 코멘트인지 — 추가(+)·삭제(-)·문맥(공백). 재앵커링·표시 위치 판정에 쓴다.
enum DiffSide: String, Codable, Equatable {
    case add, del, context
}

/// diff 한 줄에 사람이 남긴 리뷰 코멘트(값 타입·영속). 편집이 아니라 메타데이터라 "에디터 없음" 비목표와 무관.
///
/// 앵커는 `file`+`side`+`line`(저장 시점 줄번호)+`lineText`(저장 시점 줄 내용)로 잡는다.
/// diff가 라이브 리로드로 밀려도 `lineText`로 다시 찾아(재앵커링) 코멘트가 따라가게 한다.
struct ReviewComment: Codable, Identifiable, Equatable {
    let id: String
    /// repo 루트 기준 상대 경로(diff 헤더에서 뽑은 b/ 경로).
    let file: String
    let side: DiffSide
    /// 저장 시점의 줄번호 — add/context는 새 파일 줄, del은 옛 파일 줄.
    let line: Int
    /// 저장 시점의 줄 내용(접두 +/-/공백 제거) — 재앵커링 앵커.
    let lineText: String
    let body: String
    /// 생성 순서(리포 내 단조 증가) — 제출 시 정렬·표시 순서.
    let seq: Int
    let createdAt: Date

    init(id: String = UUID().uuidString, file: String, side: DiffSide, line: Int,
         lineText: String, body: String, seq: Int, createdAt: Date = Date()) {
        self.id = id
        self.file = file
        self.side = side
        self.line = line
        self.lineText = lineText
        self.body = body
        self.seq = seq
        self.createdAt = createdAt
    }
}

/// 재앵커링 결과 상태 — 저장 위치 그대로면 anchored, 같은 텍스트가 유일해 옮겨졌으면 moved, 못 찾으면 outdated.
enum AnchorStatus: String {
    case anchored, moved, outdated
}

/// 코멘트 + 현재 diff에 대한 재앵커링 결과. 표시 계층이 쓰는 파생 값(원본 ReviewComment는 불변).
struct AnchoredComment: Identifiable {
    let comment: ReviewComment
    let status: AnchorStatus
    /// 현재 diff에서 카드를 놓을 줄번호 — anchored=저장 줄, moved=새 줄, outdated=nil(상단 배너).
    let resolvedLine: Int?

    var id: String { comment.id }
}
