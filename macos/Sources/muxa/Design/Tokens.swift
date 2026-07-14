import SwiftUI

/// 앱 크롬의 치수·모션 토큰 — 색(`Palette.swift`)과 함께 디자인 SSOT를 이룬다.
/// 새 UI를 짤 때 숫자를 직접 쓰지 않고 여기서 고른다(하드코딩 금지, DESIGN.md).
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

    /// 2단 트리의 자식(프로젝트) 들여쓰기.
    static let treeIndent: CGFloat = 16
    /// 트리에서 **그룹 사이**를 벌리는 여백 — 위계를 색이 아니라 간격으로 만든다.
    /// (행 간격이 1~3pt로 균일하면 리듬이 없어 목록 전체가 한 덩어리로 뭉갠다.)
    static let groupGap: CGFloat = 10
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
    /// 패널 헤더 = 칸 탭바(Bonsplit `tabBarHeight`)와 같은 높이. 두 줄이 한 선에 이어진다.
    static let header: CGFloat = 34
    /// 도구 패널(탐색기·git) 헤더의 **콘텐츠** 높이 — 아래 구분선(1pt)까지 합쳐야 `header`가 된다.
    /// 탭바엔 구분선이 없으므로, 구분선을 그리는 쪽이 그만큼 콘텐츠를 줄여야 아래 경계가 맞는다.
    static let panelHeader: CGFloat = header - hairline
    /// 창 상단바 — 워드마크·컨트롤·**브레드크럼**(현재 워크스페이스 › 프로젝트)이 앉는 줄.
    /// (프로젝트 탭이 카드로 앉던 줄이었으나, 프로젝트 전환은 사이드바 트리가 유일한 경로가 됐다.)
    /// 표준 타이틀바(28pt)보다 높으므로 **신호등을 이 높이의 중앙으로 내려야** 한다
    /// (`TrafficLights.align` — 안 하면 신호등만 위로 붙는다).
    static let topBar: CGFloat = 38
    /// 경계선 두께(1px 구분선).
    static let hairline: CGFloat = 1
}

/// 아이콘·마크 치수 — 같은 마크가 문맥마다 다른 숫자로 흩어지지 않게 한 출처에 모은다.
/// (인라인과 팝오버는 크기가 다른 게 맞다 — 값을 통일하는 게 아니라 **이름을 붙여** 우발적 불일치를 막는다.)
enum IconSize {
    /// 텍스트와 한 줄에 나란히 앉는 인라인 마크(상단바·푸터 칩).
    static let inlineMark: CGFloat = 13
    /// 팝오버 헤더·메뉴 항목의 마크 슬롯.
    static let mark: CGFloat = 16
    /// 아이콘 버튼·토글의 히트 영역(정사각).
    static let control: CGFloat = 24

    /// 트리 행의 **좌측 정사각 슬롯** — 상태 점·디스클로저·✕가 이 폭을 공유해야
    /// 워크스페이스/프로젝트 두 단의 텍스트가 같은 세로선에서 시작한다(점 크기가 바뀌어도 이름이 안 흔들린다).
    static let statusSlot: CGFloat = 12
    /// 신호 점(작업중·주의).
    static let dot: CGFloat = 6
    /// 조용한 점(유휴·롤업).
    static let dotSmall: CGFloat = 5
    /// 아이콘 캡슐 우상단에 걸치는 롤업 점의 오프셋 — 점의 절반이 캡슐 밖으로 나가 배지처럼 읽힌다.
    static let dotOffset: CGFloat = 3
}

/// 슬림(14pt) 사이드바의 색 막대 — 아이콘이 없어 막대 하나가 상태를 다 말한다.
/// 강조는 **색이 아니라 폭·높이**가 한다(불투명도 곱을 쓰지 않는 이유).
enum SlimBar {
    static let width: CGFloat = 3
    static let widthActive: CGFloat = 4
    static let height: CGFloat = 18
    static let heightActive: CGFloat = 24
    static let radius: CGFloat = 2
}

/// 사이드바의 가로 기하 — **이름 칩이 사이드바 바깥에 떠야 해서** 인셋과 칩 간격이 한 식으로 묶인다.
/// (칩 오프셋을 호출부에서 `sidebarWidth - Space.sm + Space.md`처럼 산술로 만들면, 인셋을 바꾼 사람이
///  칩이 어긋나는 이유를 영영 못 찾는다 — 두 값과 그 식을 여기 한 곳에 둔다.)
enum Sidebar {
    /// 좌우 인셋. 슬림(14pt)은 0 — 인셋을 주면 클릭 영역이 2pt로 쪼그라든다.
    static let hInset: CGFloat = Space.sm
    /// 사이드바 우측 경계 ↔ 이름 칩.
    static let chipGap: CGFloat = Space.md
    /// 항목의 leading 기준, 이름 칩이 사이드바 밖으로 나가는 거리.
    static func chipOffset(width: CGFloat) -> CGFloat { width - hInset + chipGap }
}

/// 떠 있는 패널(팝오버)의 폭.
enum PopoverWidth {
    /// 푸터 팝오버(사용량·서비스·백그라운드) 공통 폭.
    /// **셋이 같은 폭이어야 한 시스템으로 읽힌다** — 240/260이 섞이면 같은 줄에서 열리는 창들이 제각각으로 보인다.
    /// 260에선 긴 명령·경로가 곧바로 잘려서, 자를 자리를 조금 벌린 값(300)으로 통일한다.
    static let footer: CGFloat = 300
}

/// 떠 있는 판(커스텀 메뉴·푸터 팝오버)의 고도(elevation) — 그림자와 그 그림자가 살 자리.
/// **메뉴와 팝오버가 같은 값을 쓴다** — 같은 푸터에서 열리는 판들이 제각각으로 보이면 안 된다.
enum Elevation {
    /// 키 그림자 — 넓고 옅게, 아래로. "떠 있다"를 만든다.
    static let keyOpacity: Double = 0.22
    static let keyRadius: CGFloat = 10
    static let keyOffsetY: CGFloat = 4
    /// 앰비언트 그림자 — 좁고 짙게. 판의 윤곽을 배경에서 떼어낸다.
    static let ambientOpacity: Double = 0.10
    static let ambientRadius: CGFloat = 2
    static let ambientOffsetY: CGFloat = 1
    /// 콘텐츠 바깥 여백 = 그림자가 흩어져 사라질 자리. **키 반경 + 오프셋보다 넉넉해야** 한다 —
    /// 좁으면 그림자가 창 경계에서 직각으로 잘려 네모난 회색 테로 보인다.
    static let margin: CGFloat = 20
    /// 앵커(칩·버튼)와 판 사이 간격.
    static let anchorGap: CGFloat = Space.sm

    /// 도킹된 콘텐츠 카드의 **상시 미세 고도** — 떠 있는 판(위 값)과는 다른 계급이다.
    ///
    /// DESIGN.md는 "콘텐츠는 크롬 위에 카드로 떠 있다"고 선언하는데, 보더 1px만으로는
    /// "떠 있는 판"이 아니라 "선 그은 칸"이 된다. 그 부족분을 **크롬 명도차를 벌려서** 메우면
    /// 크롬 자체가 도형으로 읽힌다 — 두 문제가 한 뿌리였다. 카드에 고도를 주고 크롬은 조용히 둔다.
    enum Card {
        /// 카드 그림자 — 다크는 짙게, 라이트는 옅게(배경이 흰색이라 조금만 넣어도 뜬다).
        static let shadowOpacity: (light: Double, dark: Double) = (0.06, 0.34)
        static let shadowRadius: CGFloat = 3
        static let shadowOffsetY: CGFloat = 1
        /// 카드 **상단 1px 인셋 하이라이트**(다크 전용) — 어두운 유리판의 윗면 반사.
        /// 다크 UI에서 고도는 그림자보다 이 한 줄이 만든다.
        static let insetHighlight: Double = 0.05
    }

    /// **peek로 펼쳐진 사이드바**가 카드 위에 드리우는 그림자 — 도킹 상태엔 그리지 않는다
    /// (크롬끼리 같은 배경으로 이어지는 자리에 그림자를 깔면 얼룩으로 보인다).
    ///
    /// peek 사이드바는 카드 고도의 **사각지대**다 — 사이드바가 카드보다 *위* 레이어라 카드 그림자가
    /// 이쪽을 못 비춘다. 그런데 정작 여기가 "판이 콘텐츠 위에 떠 있다"를 가장 말해야 하는 자리다
    /// (2단 트리라 떠 있는 면적이 넓다). 남는 신호가 1px 하선뿐이면 트리가 터미널에 얹힌 것처럼 보인다.
    ///
    /// **오른쪽으로만 민다**(x 오프셋). 위아래로 번지면 크롬 위에 그늘이 지고, 왼쪽 번짐은
    /// 사이드바 자기 불투명 면에 어차피 가려진다.
    enum Peek {
        static let shadowOpacity: (light: Double, dark: Double) = (0.10, 0.45)
        static let shadowRadius: CGFloat = 4
        static let shadowOffsetX: CGFloat = 3
    }
}

/// 색 위에 얹는 옅은 배경 틴트의 불투명도 — 전경색 하나만 정하면 배경이 따라오게 한다(배지 `Pill`과 같은 규칙).
enum Tint {
    static let subtle: Double = 0.14
}

/// 전환 — 종류를 늘리지 않는다. 크롬의 미세 전환은 전부 `fast`.
enum Motion {
    /// hover·포커스 같은 즉각 피드백.
    static let fast = Animation.easeOut(duration: 0.12)
    /// 패널 열림처럼 조금 더 보이는 전환.
    static let medium = Animation.easeOut(duration: 0.18)
}
