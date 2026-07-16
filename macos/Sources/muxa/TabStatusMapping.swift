import Bonsplit

/// `AgentActivity` → Bonsplit `TabStatus`(탭 좌측 슬롯 상태 마크).
///
/// **사이드바 `StatusMark`와 같은 어휘·색·모션을 탭에도** — 통일이 목적이다:
/// - 작업중 = 회전 스피너(인디고), 대기 = ⏸ pause.fill 펄스(로즈), 완료 = ✓ checkmark 정적(세이지),
/// - 유휴 = nil(마크 없음 → 탭은 타입 아이콘으로 폴백).
///
/// 색 hex는 `Palette.StatusHex`(상태색 SSOT)에서 온다 — 사이드바·칸 테두리와 **같은 값**을 보장(드리프트 없음).
/// Bonsplit이 hex를 받아 라이트/다크로 리졸브한다(값 타입 스냅샷이라 NSColor 대신 hex로 넘긴다).
enum TabStatusMapping {
    static func status(for activity: AgentActivity) -> TabStatus? {
        switch activity {
        case .working:
            return TabStatus(symbol: "", tintLightHex: Palette.StatusHex.work.light,
                             tintDarkHex: Palette.StatusHex.work.dark, motion: .spin)
        case .waiting:
            return TabStatus(symbol: StatusStyle.glyph(.attention), tintLightHex: Palette.StatusHex.waiting.light,
                             tintDarkHex: Palette.StatusHex.waiting.dark, motion: .pulse)
        case .done:
            return TabStatus(symbol: StatusStyle.glyph(.success), tintLightHex: Palette.StatusHex.done.light,
                             tintDarkHex: Palette.StatusHex.done.dark, motion: .none)
        case .idle:
            return nil
        }
    }
}
