import SwiftUI

/// 앱 크롬의 치수·모션 토큰 — 색(`Palette.swift`)과 함께 디자인 SSOT를 이룬다.
/// 새 UI를 짤 때 숫자를 직접 쓰지 않고 여기서 고른다(하드코딩 금지, DESIGN 5절).
///
/// 값은 새로 발명하지 않고 **기존 화면에서 실제로 쓰던 값에 스냅**했다.
/// (3·5·7처럼 한 픽셀씩 어긋나던 값들만 가장 가까운 단계로 흡수 — 시각 변화는 미미하고 일관성만 생긴다.)

/// 간격 — HStack/VStack spacing, padding.
///
/// **이 스케일 밖의 값이 필요하면 산술(`xl - xs`)로 만들지 말고 단계를 추가한다.**
/// 뺄셈으로 만든 값은 읽는 사람이 암산해야 하고, `xl`을 바꾸면 무관한 곳이 함께 움직인다.
enum Space {
    /// 아이콘과 라벨을 밀착시킬 때(배지 내부).
    static let tight: CGFloat = 2
    static let xs: CGFloat = 4
    /// 기본 가로 배치 간격 — 대부분의 HStack이 이것.
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    /// 패널 좌우 인셋 — 사이드바·git 패널·도구줄의 가로 여백 기준선.
    static let panelInset: CGFloat = 10
    /// 블록 사이 여백(버튼 가로 패딩·빈 상태 요소 간격).
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
}

/// 모서리 반경.
enum Radius {
    static let sm: CGFloat = 4
    /// 탭·버튼처럼 작은 면.
    static let md: CGFloat = 6
    /// 콘텐츠 카드처럼 큰 면. 터미널이 사는 창이라 과하게 둥글리지 않는다.
    static let lg: CGFloat = 8
}

/// 행·바 높이 — 목록 밀도의 단일 출처. 터미널 앱이라 compact를 기준으로 잡는다.
enum RowHeight {
    /// 섹션 헤더처럼 아주 얕은 줄.
    static let tight: CGFloat = 22
    /// 목록 한 행(파일·커밋 등).
    static let row: CGFloat = 24
    /// 도구줄(버튼이 있는 줄).
    static let toolbar: CGFloat = 28
    /// 보조 바(리뷰 코멘트 바 등).
    static let bar: CGFloat = 30
    /// 패널 헤더.
    static let header: CGFloat = 34
    /// 창 상단바 — 프로젝트 탭이 카드로 앉는 줄.
    /// 표준 타이틀바(28pt)보다 높으므로 **신호등을 이 높이의 중앙으로 내려야** 한다
    /// (`TrafficLights.align` — 안 하면 신호등만 위로 붙는다).
    static let topBar: CGFloat = 38
    /// 상단바 안에 앉는 프로젝트 탭의 높이.
    static let tab: CGFloat = 28
    /// 경계선 두께(1px 구분선).
    static let hairline: CGFloat = 1
}

/// 전환 — 종류를 늘리지 않는다. 크롬의 미세 전환은 전부 `fast`.
enum Motion {
    /// hover·포커스 같은 즉각 피드백.
    static let fast = Animation.easeOut(duration: 0.12)
    /// 패널 열림처럼 조금 더 보이는 전환.
    static let medium = Animation.easeOut(duration: 0.18)
}
