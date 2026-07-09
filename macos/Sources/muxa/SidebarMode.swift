import Foundation

/// 사이드바 표시 모드 — 상단바 메뉴에서 선택. (src/sidebarMode.ts 이식)
enum SidebarMode: String, Codable, CaseIterable {
    case expanded // 아바타+이름
    case icon // 아바타만
    case slim // 얇은 위치 바
    case hover // 평소 아이콘, 올리면 전체

    var label: String {
        switch self {
        case .expanded: return "펼쳐두기"
        case .icon: return "아이콘"
        case .slim: return "슬림"
        case .hover: return "호버 시 펼침"
        }
    }

    var hint: String {
        switch self {
        case .expanded: return "항상 전체"
        case .icon: return "아바타만"
        case .slim: return "얇은 위치 바"
        case .hover: return "평소 아이콘, 올리면 전체"
        }
    }
}
