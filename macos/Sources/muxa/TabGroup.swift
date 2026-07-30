import Bonsplit
import Foundation
import Observation

/// 탭 그룹 종류 — 문서(md)·HTML·코드·변경(diff)을 각각 묶는다. 터미널은 그룹이 아니라 개별 탭.
enum TabGroupKind: Equatable {
    case documents // 마크다운
    case html
    case code
    case media // 이미지·영상
    case diffs
    /// **에이전트 변경**(YJ-7) — 에이전트 패널이 연 기준선 diff. `.diffs`와 갈라 두는 이유:
    /// 비교 기준이 다르다(탭 기준선 ↔ HEAD). 한 그룹에 섞으면 같은 파일의 서브탭 두 개가
    /// **라벨이 똑같은데 내용이 다른** 상태가 된다 — 어느 쪽이 무엇인지 알 방법이 없어진다.
    /// **에이전트**(YJ-7) — 그 세션이 만진 파일의 기준선 diff와 참고 목록을 함께 담는다.
    /// `.diffs`와 갈라 두는 이유: 비교 기준이 다르다(탭 기준선 ↔ HEAD). 한 그룹에 섞으면
    /// 같은 파일의 서브탭 두 개가 라벨이 똑같은데 내용이 다른 상태가 된다.
    /// 세션 하나. **세션마다 그룹이 따로 뜬다** — 한 그룹에 몰면 어느 세션의 변경인지 사라진다.
    case agent(TabID)
    case browser // 인앱 웹 브라우저

    var title: String {
        switch self {
        case .documents: return "문서"
        case .html: return "HTML"
        case .code: return "코드"
        case .media: return "미디어"
        case .diffs: return "변경"
        case .agent: return "에이전트"  // 실제 탭 라벨은 세션 제목으로 덮는다(openInGroup)
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
        // 래스터화 실패 시에만 쓰이는 폴백 — 평소엔 `iconImageData`(ClaudeMark)가 이긴다.
        case .agent: return "sparkle"
        case .browser: return "globe"
        }
    }

    /// 탭 아이콘 **이미지**(있으면 SF Symbol보다 우선). 정체성 마크는 원본색을 지켜야 해서
    /// 템플릿 심볼로 그릴 수 없다 — Bonsplit `createTab(iconImageData:)`에 넘긴다.
    /// 나중에 Codex 같은 다른 에이전트가 붙으면 여기서 갈린다.
    var iconImageData: Data? {
        switch self {
        case .agent: return ClaudeMark.pngData()
        default: return nil
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
        case .agent: return "agent"
        case .browser: return "browser"
        }
    }

    /// 복원 — **에이전트 그룹은 되살리지 않는다.** 담긴 항목(기준선 diff·상세)이 전부
    /// 세션 종속이라 복원 대상이 아니고, 껍데기만 되살리면 빈 그룹이 남는다.
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
    /// 참고 목록(YJ-7) — 그 탭이 읽은 것들. 내용을 복사해 담지 않고 **탭을 가리킨다**
    /// (스토어가 SSOT라 에이전트가 더 읽으면 화면이 따라간다).
    case references(AgentDetailTarget)

    var id: String {
        switch self {
        case .file(let t): return t.id
        case .diff(let t): return "diff:\(t.id)"
        case .web(let t): return t.id
        case .references(let t): return t.id
        }
    }

    var title: String {
        switch self {
        case .file(let t): return t.tabTitle
        case .diff(let t): return t.tabTitle
        // 서브탭 라벨은 nonisolated 컨텍스트라 불변 initialURL(let)로만 잡는다(페이지 제목 실시간 반영은 안 함).
        case .web(let t): return t.initialURL.host ?? t.initialURL.absoluteString
        // 서브탭 라벨은 **짧게** — 세션 제목(첫 프롬프트 전문)을 여기 쓰면 스트립을 통째로 먹는다.
        // 어느 세션인지는 패널 안 헤더가 말한다.
        case .references: return "상세"
        }
    }

    var icon: String {
        switch self {
        case .file(let t): return t.tabIcon
        case .diff(let t): return t.tabIcon
        case .web: return "globe"
        case .references: return "book"
        }
    }

    /// 서브탭 스트립에서 **앞자리를 가지는가** — 참고 목록은 개별 diff와 맥락이 달라
    /// 있을 때 항상 맨 앞에 선다. (상시 고정이 아니라 **정렬**이다 — 0건이면 아예 없다.)
    var pinsFirst: Bool {
        if case .references = self { return true }
        return false
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
        case .diff(.baselineFile(_, _, let session)): return .agent(session)
        case .diff: return .diffs
        case .web: return .browser
        case .references(let t): return .agent(t.tabId)
        }
    }

    /// 이 서브탭이 가리키는 실제 파일 경로 — 파일 뷰어는 절대 경로, 파일 diff는 `dir`(리포 루트) 기준.
    /// 커밋·전체 diff·웹은 특정 파일이 없다(nil). 서브탭 메뉴(경로 복사·Finder)·드래그 게이트의 단일 출처.
    func filePath(dir: String) -> String? {
        switch self {
        case .file(let target): return target.path
        case .diff(.file(let change)): return dir.isEmpty ? nil : (dir as NSString).appendingPathComponent(change.path)
        case .diff(.baselineFile(_, let path, _)): return dir.isEmpty ? nil : (dir as NSString).appendingPathComponent(path)
        case .diff, .web, .references: return nil
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
