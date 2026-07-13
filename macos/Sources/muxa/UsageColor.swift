import SwiftUI

/// 사용량 색 규칙 — 상태바와 팝오버가 같은 판단을 쓰도록 한 곳에 둔다.
/// (색 값 자체는 `Palette`가 소유하고, 여기선 "언제 어떤 색인가"만 정한다.)
enum UsageColor {
    /// 한도에 다가갈수록 경고색. 서버 severity를 우선 믿고, 없으면 비율로 판단한다. 평시엔 nil.
    static func warn(_ limit: UsageLimit) -> Color? {
        if limit.isWarning || limit.percent >= 90 { return Color.pDanger }
        if limit.percent >= 70 { return Color(nsColor: Palette.gitModified) }
        return nil
    }

    /// 막대 — 평시엔 브랜드 키 컬러(teal).
    static func meter(_ limit: UsageLimit) -> Color { warn(limit) ?? Color.pBrand }

    /// 숫자 — 평시엔 읽기 쉬운 전경색, 경고일 때만 물든다(평소에 시끄럽지 않게).
    static func text(_ limit: UsageLimit) -> Color { warn(limit) ?? Color.pFg }
}
