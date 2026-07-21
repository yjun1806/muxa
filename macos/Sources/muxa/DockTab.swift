import Foundation

/// 서비스 도크의 두 탭 — **실행하는 것들**의 두 축을 가른다(축 어휘는 DESIGN §2).
///
///  - `.services` = 끝없는 프로세스(dev 서버). 등록·반복·자동기동. 원형 글리프 축.
///  - `.commands` = 끝있는 명령(build·test·`brew install`). 등록 여부는 축이 아니라 **저장 위치**다 —
///                  등록(`Project.scripts`)이든 즉석(입력창)이든 한 탭에서 다룬다. 입력창으로 즉석 실행하고,
///                  등록된 건 위 섹션, 실행한 건 아래 히스토리(`Project.commandHistory`, lastRun)로 남는다.
///
/// (구 3탭 `[서비스|스크립트|일회용]`에서 스크립트+일회용을 하나로 합쳤다 — 둘은 끝있는 명령으로 같고
///  차이는 등록 여부뿐이었다.) 탭은 순간 내비게이션이라 **비영속**(세션 내 기억)이다.
enum DockTab: String, CaseIterable, Identifiable {
    case services
    case commands

    var id: String { rawValue }

    /// 탭 라벨 — 넓을 때 글리프 옆에 붙고, 좁으면 접혀 VoiceOver 라벨로만 남는다.
    var title: String {
        switch self {
        case .services: return "서비스"
        case .commands: return "명령"
        }
    }

    /// 탭의 **축 글리프**(카테고리 마커 — 상태가 아니라 종류를 말한다, 그래서 `.fill`·상태색 안 씀).
    /// 서비스=원형·명령=사각형 축은 DESIGN §2의 목록 행 글리프와 이어진다(끝없음 vs 끝있음).
    var icon: String {
        switch self {
        case .services: return "play.circle"
        case .commands: return "play.square"
        }
    }
}
