import Foundation
import Observation

/// 탭 그룹 종류 — 문서(md)·HTML·코드·변경(diff)을 각각 묶는다. 터미널은 그룹이 아니라 개별 탭.
enum TabGroupKind: Equatable {
    case documents // 마크다운
    case html
    case code
    case media // 이미지·영상
    case diffs
    case browser // 인앱 웹 브라우저

    var title: String {
        switch self {
        case .documents: return "문서"
        case .html: return "HTML"
        case .code: return "코드"
        case .media: return "미디어"
        case .diffs: return "변경"
        case .browser: return "웹"
        }
    }

    var icon: String {
        switch self {
        case .documents: return "doc.richtext"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .code: return "curlybraces"
        case .media: return "photo"
        case .diffs: return "plusminus"
        case .browser: return "globe"
        }
    }

    /// 영속용 문자열 키(PaneSnapshot).
    var raw: String {
        switch self {
        case .documents: return "documents"
        case .html: return "html"
        case .code: return "code"
        case .media: return "media"
        case .diffs: return "diffs"
        case .browser: return "browser"
        }
    }

    init?(raw: String) {
        switch raw {
        case "documents": self = .documents
        case "html": self = .html
        case "code": self = .code
        case "media": self = .media
        case "diffs": self = .diffs
        case "browser": self = .browser
        default: return nil
        }
    }
}

/// 그룹 안의 한 서브탭 내용 — 파일 뷰어이거나 diff. id로 dedup·선택한다.
enum GroupItemContent: Identifiable {
    case file(FileViewTarget)
    case diff(GitDiffTarget)
    case web(BrowserTab)

    var id: String {
        switch self {
        case .file(let t): return t.id
        case .diff(let t): return "diff:\(t.id)"
        case .web(let t): return t.id
        }
    }

    var title: String {
        switch self {
        case .file(let t): return t.tabTitle
        case .diff(let t): return t.tabTitle
        // 서브탭 라벨은 nonisolated 컨텍스트라 불변 initialURL(let)로만 잡는다(페이지 제목 실시간 반영은 안 함).
        case .web(let t): return t.initialURL.host ?? t.initialURL.absoluteString
        }
    }

    var icon: String {
        switch self {
        case .file(let t): return t.tabIcon
        case .diff(let t): return t.tabIcon
        case .web: return "globe"
        }
    }

    var kind: TabGroupKind {
        switch self {
        case .file(let t):
            switch t.kind {
            case .markdown: return .documents
            case .html: return .html
            case .code: return .code
            case .image, .video: return .media
            }
        case .diff: return .diffs
        case .web: return .browser
        }
    }

    /// 이 서브탭이 가리키는 실제 파일 경로 — 파일 뷰어는 절대 경로, 파일 diff는 `dir`(리포 루트) 기준.
    /// 커밋·전체 diff·웹은 특정 파일이 없다(nil). 서브탭 메뉴(경로 복사·Finder)·드래그 게이트의 단일 출처.
    func filePath(dir: String) -> String? {
        switch self {
        case .file(let target): return target.path
        case .diff(.file(let change)): return dir.isEmpty ? nil : (dir as NSString).appendingPathComponent(change.path)
        case .diff, .web: return nil
        }
    }
}

/// 그룹 탭 하나의 서브탭 상태 — 항목 순서 + 선택. 뷰가 controlled로 관측한다.
@MainActor
@Observable
final class TabGroupState {
    let kind: TabGroupKind
    var items: [GroupItemContent]
    var selectedId: String

    init(first: GroupItemContent) {
        self.kind = first.kind
        self.items = [first]
        self.selectedId = first.id
    }

    var selected: GroupItemContent? { items.first { $0.id == selectedId } }

    var contains: (String) -> Bool { { [items] id in items.contains { $0.id == id } } }

    /// 항목 추가(있으면 선택만) 후 그 항목을 선택 상태로.
    func add(_ item: GroupItemContent) {
        if !items.contains(where: { $0.id == item.id }) { items.append(item) }
        selectedId = item.id
    }

    /// 서브탭 닫기 → 인접 항목 선택. 그룹이 비면 true(그룹 탭 자체를 닫아야 함).
    func remove(_ id: String) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return items.isEmpty }
        items.remove(at: idx)
        if items.isEmpty { return true }
        if selectedId == id { selectedId = items[min(idx, items.count - 1)].id }
        return false
    }
}
