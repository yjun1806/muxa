import SwiftUI

/// 타이포 스케일 — 크롬에서 쓰는 글자 크기는 이 5단이 전부다.
/// 기존 코드가 9~13을 산발적으로 쓰던 것을 의미 단위로 승격했다.
enum TypeScale: CGFloat {
    /// 8 — 탭 닫기 ×, 배지 숫자처럼 최소 크기 기호.
    case nano = 8
    /// 9 — 배지 안 아이콘처럼 아주 작은 보조 기호.
    case micro = 9
    /// 10 — 메타 정보(해시·날짜·개수·섹션 제목).
    case caption = 10
    /// 11 — 라벨·버튼 텍스트.
    case label = 11
    /// 12 — 본문(파일명·커밋 제목). 크롬의 기본 크기.
    case body = 12
    /// 13 — 패널·화면 제목.
    case title = 13
}

extension Font {
    /// 크롬 기본 글꼴. 크기는 `TypeScale`에서만 고른다.
    static func muxa(_ scale: TypeScale, weight: Font.Weight = .regular) -> Font {
        .system(size: scale.rawValue, weight: weight)
    }

    /// 고정폭 — 해시·카운터처럼 자릿수가 흔들리면 안 되는 값.
    static func muxaMono(_ scale: TypeScale, weight: Font.Weight = .regular) -> Font {
        .system(size: scale.rawValue, weight: weight, design: .monospaced)
    }

    /// 소섹션 라벨 — 사이드바의 워크스페이스 이름처럼 **목록을 이끄는 머리글**.
    /// 8~13pt 사이의 1pt 계단만으로는 위계가 안 선다. 크기를 낮추는 대신
    /// **굵기(semibold) + 자간 + 대문자**로 "이건 항목이 아니라 머리글"이라고 말한다.
    /// (대문자 변환은 `.textCase(.uppercase)`가 호출부에서 함께 붙는다 — 한글은 변환되지 않으니
    ///  자간·굵기만으로도 라벨로 읽혀야 한다.)
    static let muxaLabel = Font.system(size: TypeScale.caption.rawValue, weight: .semibold)
}

/// 라벨 자간 — `Font.muxaLabel`과 짝. SwiftUI는 자간이 `Font`가 아니라 `.tracking()` 모디파이어라 값만 둔다.
enum Tracking {
    /// 대문자 소섹션 라벨(≈ +0.06em @ 10pt).
    static let label: CGFloat = 0.6
}
