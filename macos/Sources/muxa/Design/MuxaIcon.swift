import AppKit
import SwiftUI

/// 아이콘 이름 → 글리프. **SF Symbol과 muxa 커스텀 심볼을 한 이름 공간에서 다룬다.**
///
/// 왜 필요한가: 아이콘을 **문자열로 넘기는 API**가 여럿이다(`EmptyState(icon:)`·`MuxaMenuItem(icon:)`·
/// `InspectorTab.icon`·`QuickSwitchItem.icon`). 이들이 전부 `Image(systemName:)`을 직접 부르면
/// SF Symbols에 없는 글리프는 영영 못 쓴다. 통로를 하나 만들어 커스텀 이름만 가로챈다.
///
/// **크기를 명시로 받는 이유**: SF Symbol은 글자라 `.font()`로 크기가 정해지지만, 커스텀 SVG는
/// 이미지라 `.font()`에 반응하지 않는다. 호출부가 이미 알고 있는 크기를 넘겨 둘을 같은 규격으로 맞춘다.
/// 색은 둘 다 `.foregroundStyle`을 따른다(커스텀은 템플릿 이미지로 로드한다).
enum MuxaSymbol {
    /// git 브랜치 — 저장소·브랜치·워크트리 표시의 공통 글리프.
    ///
    /// SF Symbols의 `arrow.triangle.branch`/`arrow.triangle.merge` 두 개를 섞어 쓰다가 하나로 모았다.
    /// 둘을 나눠 두면 "Git 섹션"과 "브랜치 표시"가 다른 것처럼 보이는데, 사용자에게는 둘 다 git이다.
    /// 모양은 Octicons(MIT)의 `git-branch` — 개발자에게 가장 익숙한 브랜치 글리프다.
    static let gitBranch = "muxa.git.branch"

    /// 커스텀 이름이면 번들 SVG를, 아니면 nil(= SF Symbol로 처리).
    /// 번들에서 1회 로드해 재사용한다(뷰가 그려질 때마다 디스크를 읽지 않게 — ClaudeMark와 같은 경로).
    static func image(_ name: String) -> NSImage? {
        guard name == gitBranch else { return nil }
        return gitBranchImage
    }

    private static let gitBranchImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "git-branch", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        // 템플릿이라야 `.foregroundStyle`이 먹는다 — 로고인 ClaudeMark와 달리 이건 UI 글리프다.
        image.isTemplate = true
        return image
    }()
}

/// SF Symbol 또는 muxa 커스텀 심볼을 그린다 — 문자열 아이콘 이름을 받는 곳의 **유일한 통로**.
struct MuxaIcon: View {
    let name: String
    let size: CGFloat

    /// 타이포 스케일로 크기를 고르는 기본 경로 — 크롬 글리프는 글자와 같은 계단을 쓴다.
    init(name: String, size: TypeScale = .body) {
        self.name = name
        self.size = size.rawValue
    }

    /// 스케일 밖의 크기(빈 상태의 큰 글리프 등)를 직접 줄 때.
    init(name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    var body: some View {
        if let custom = MuxaSymbol.image(name) {
            Image(nsImage: custom)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: name).font(.system(size: size))
        }
    }
}
