import SwiftUI

/// 타이포 스케일 — 크롬에서 쓰는 글자 크기는 이 5단이 전부다.
/// 기존 코드가 9~13을 산발적으로 쓰던 것을 의미 단위로 승격했다.
enum TypeScale: CGFloat {
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
}
