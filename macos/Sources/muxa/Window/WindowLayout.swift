/// 창 배치의 순수 모델 — 어느 프로젝트가 어느 창에 속하는가.
///
/// **AppKit을 임포트하지 않는다.** 실물 `NSWindow`와의 정합은 경계(WindowHost)가 맡고,
/// 여기서는 값만 다룬다.
///
/// 배치의 원자는 **프로젝트**이고, 메인 창은 **여집합**이다(ARCHITECTURE D28) —
/// 분리 창 목록만 저장하고 "어느 창에도 없는 프로젝트 = 메인 소유"로 정의한다.
/// 그래서 `owner(of:in:)`가 총함수가 되고, 유실·dangling·중복 소유가 타입상 표현 불가능해진다.

/// 창 신원. 메인은 고정 id 하나, 분리 창은 UUID.
struct WindowID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    static let main = WindowID(rawValue: "main")
    var isMain: Bool { self == .main }

    // RawRepresentable + Codable을 함께 선언하면 무엇이 합성되는지가 모호하다 —
    // 저장 포맷(문자열 하나)을 코드로 못 박는다.
    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 분리 창 하나. **메인 창은 여기 없다**(여집합 — D28).
struct ProjectWindow: Codable, Equatable, Identifiable {
    let id: WindowID
    /// 순서 = 프로젝트 스트립 표시 순서. 비면 창이 사라진다(I5).
    var projectIds: [String]
    /// `projectIds` 밖이면 normalize/move가 첫 항목으로 clamp한다.
    var activeProjectId: String?
    /// nil = 기본 크기 + cascade.
    var frame: FrameSnapshot?
    /// 크롬 토글은 창 지역 상태다(메인 것은 AppState의 기존 필드 그대로 — 명세 §6).
    var showExplorer: Bool = false
    var showGitPanel: Bool = false
    var explorerWidth: Double?
    var gitPanelWidth: Double?

    init(id: WindowID,
         projectIds: [String],
         activeProjectId: String? = nil,
         frame: FrameSnapshot? = nil,
         showExplorer: Bool = false,
         showGitPanel: Bool = false,
         explorerWidth: Double? = nil,
         gitPanelWidth: Double? = nil) {
        self.id = id
        self.projectIds = projectIds
        self.activeProjectId = activeProjectId
        self.frame = frame
        self.showExplorer = showExplorer
        self.showGitPanel = showGitPanel
        self.explorerWidth = explorerWidth
        self.gitPanelWidth = gitPanelWidth
    }
}

struct FrameSnapshot: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum WindowLayout {
    /// 총함수 — 어느 분리 창에도 없으면 메인이 가진다(I1). 유실될 수 없다.
    static func owner(of projectId: String, in windows: [ProjectWindow]) -> WindowID {
        windows.first { $0.projectIds.contains(projectId) }?.id ?? .main
    }

    /// **먼저 모든 창에서 제거한 뒤** 대상에 삽입한다 → 두 창이 같은 프로젝트를 가질 수 없다(I2).
    ///
    /// 창을 만들지는 않는다 — 대상 창이 목록에 없으면 그 프로젝트는 여집합(메인)으로 떨어진다.
    /// 새 창 생성은 호출자(AppState.moveProjects)가 `ProjectWindow`를 append한 뒤 다시 부른다.
    static func move(_ projectIds: [String], to target: WindowID,
                     in windows: [ProjectWindow]) -> [ProjectWindow] {
        let ids = dedup(projectIds)
        let moving = Set(ids)
        let stripped = windows.map { window -> ProjectWindow in
            var next = window
            next.projectIds = window.projectIds.filter { !moving.contains($0) }
            return next
        }
        guard !target.isMain else { return compact(stripped) }
        let inserted = stripped.map { window -> ProjectWindow in
            guard window.id == target else { return window }
            var next = window
            next.projectIds += ids
            return next
        }
        return compact(inserted)
    }

    /// 저장분을 신뢰 가능한 모양으로 되돌린다. **멱등**(I8).
    ///
    /// 파괴는 좁게, 보존은 넓게 — 프로젝트를 창에서 빼도 여집합이라 메인이 받는다(유실 없음).
    static func normalize(_ windows: [ProjectWindow]?, projectIds: [String]) -> [ProjectWindow] {
        guard let windows else { return [] }
        let known = Set(projectIds)
        var seenWindows: Set<WindowID> = []
        var seenProjects: Set<String> = []
        var result: [ProjectWindow] = []

        for window in windows {
            // 메인은 여집합이라 목록에 있을 수 없다 — 있으면 표현 오류이므로 버린다(프로젝트는 메인이 갖는다).
            guard !window.id.isMain else { continue }
            guard seenWindows.insert(window.id).inserted else { continue } // 중복 창 id: 앞선 것 승

            var next = window
            next.projectIds = window.projectIds.filter { id in
                known.contains(id) && seenProjects.insert(id).inserted   // 중복 프로젝트: 앞선 창 승
            }
            guard !next.projectIds.isEmpty else { continue }              // 빈 창 없음(I5)
            result.append(clampActive(next))
        }
        return result
    }

    /// 지금 **어느 창에서든 눈에 들어와 있는** 활성 프로젝트들 — 메인의 활성 프로젝트 + 각 분리 창의 것.
    /// 배지 판정("보고 있는 프로젝트엔 배지를 달지 않는다")의 입력이다. 메인의 활성 프로젝트가 분리돼
    /// 나갔으면 메인은 플레이스홀더를 그리고 있으므로 보이는 것이 아니다.
    static func visibleActiveProjects(mainActive: String?, in windows: [ProjectWindow]) -> Set<String> {
        var result = Set(windows.compactMap(\.activeProjectId))
        if let mainActive, owner(of: mainActive, in: windows).isMain { result.insert(mainActive) }
        return result
    }

    /// 메인 창의 프로젝트 순환(⌘⇧[ / ⌘⇧])이 갈 다음 프로젝트.
    /// **분리된 프로젝트는 건너뛴다** — 다른 창이 그리고 있어, 넘어가 봐야 플레이스홀더만 보인다.
    /// 돌 곳이 없으면 nil(무동작).
    static func nextMainProject(from current: String, in projectIds: [String], forward: Bool,
                                windows: [ProjectWindow]) -> String? {
        guard let idx = projectIds.firstIndex(of: current), projectIds.count > 1 else { return nil }
        let count = projectIds.count
        for step in 1..<count {
            let candidate = projectIds[(idx + (forward ? step : count - step)) % count]
            if owner(of: candidate, in: windows).isMain { return candidate }
        }
        return nil
    }

    /// 빈 창 제거 + activeProjectId clamp — move/normalize의 공통 마무리.
    private static func compact(_ windows: [ProjectWindow]) -> [ProjectWindow] {
        windows.filter { !$0.projectIds.isEmpty }.map(clampActive)
    }

    private static func clampActive(_ window: ProjectWindow) -> ProjectWindow {
        if let active = window.activeProjectId, window.projectIds.contains(active) { return window }
        var next = window
        next.activeProjectId = window.projectIds.first
        return next
    }

    private static func dedup(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }
}
