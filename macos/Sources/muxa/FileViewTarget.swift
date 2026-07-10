import Foundation

/// 뷰어 탭이 여는 파일 — 확장자로 렌더 종류를 해석한다. (GitDiffTarget 대응)
/// 확장자→종류 매핑을 여기 한 곳에 캡슐화해, openFile·렌더 분기가 각각 하나로 재사용된다.
struct FileViewTarget: Identifiable, Equatable {
    let path: String

    /// 탭 dedup·복원 키. 제목이 아니라 전체 경로로 식별(동명 파일 충돌 방지).
    var id: String { "file:\(path)" }

    enum Kind { case markdown, code }

    var kind: Kind {
        switch (path as NSString).pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd", "mkdn": return .markdown
        default: return .code
        }
    }

    /// 탭 라벨(짧게) — basename.
    var tabTitle: String { basename(path) }

    var tabIcon: String {
        switch kind {
        case .markdown: return "doc.richtext"
        case .code: return "doc.text"
        }
    }
}
