import Foundation

/// 서비스 도크의 세 탭 — **실행하는 것들**의 세 축을 가른다(축 어휘는 DESIGN §2).
///
///  - `.services` = 끝없는 프로세스(dev 서버). 등록·반복·자동기동. 원형 글리프 축.
///  - `.scripts`  = 끝있는 명령(build·test). 등록·반복. 사각형 글리프 축.
///  - `.oneoff`   = 즉석 명령(`brew install`·`pnpm install`). 등록 안 함·한 번. 사각형 축을
///                  **재사용**(끝있는 명령이라)하되, 입력창 유무·탭 위치로 스크립트와 갈린다.
///
/// 탭은 순간 내비게이션이라 **비영속**(세션 내 기억)이다 — 재시작 복원 대상이 아니다.
enum DockTab: String, CaseIterable, Identifiable {
    case services
    case scripts
    case oneoff

    var id: String { rawValue }

    /// 탭 라벨 — 넓을 때 글리프 옆에 붙고, 좁으면 접혀 VoiceOver 라벨로만 남는다.
    var title: String {
        switch self {
        case .services: return "서비스"
        case .scripts: return "스크립트"
        case .oneoff: return "일회용"
        }
    }

    /// 탭의 **축 글리프**(카테고리 마커 — 상태가 아니라 종류를 말한다, 그래서 `.fill`·상태색 안 씀).
    /// 서비스=원형·스크립트=사각형 축은 DESIGN §2의 목록 행 글리프와 이어진다.
    /// `terminal`은 "명령을 친다"는 일회용 축 — 한 곳에서 바꾸도록 여기 SSOT로 둔다.
    var icon: String {
        switch self {
        case .services: return "play.circle"
        case .scripts: return "play.square"
        case .oneoff: return "terminal"
        }
    }
}
