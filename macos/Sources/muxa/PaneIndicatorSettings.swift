import SwiftUI

/// 칸(패인) 상태 테두리의 **형태**. 모션(펄스·흐름·글로우)과 직교하는 별개 축 — 여기선 형태만 정한다.
///
/// 순수 값이다(라벨·rawValue만). 실제 그리기는 `ContentCard`의 테두리 레이어가, 칸에 얹는 일은
/// `BonsplitWorkspaceView`가 맡는다(경계 분리). `.ring`이 기존 기본(전체 링)이라 하위호환된다.
enum PaneIndicatorForm: String, CaseIterable, Identifiable {
    case ring       // 전체 링 — 네 변 다(현재 기본)
    case top        // 상단 바
    case bottom     // 하단 바
    case left       // 좌측 레일
    case bracket    // 네 모서리 브래킷
    case corner     // 우상단 코너 배지(점)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ring: return "전체 링"
        case .top: return "상단 바"
        case .bottom: return "하단 바"
        case .left: return "좌측 레일"
        case .bracket: return "브래킷"
        case .corner: return "코너 배지"
        }
    }
}

/// 칸 상태 테두리의 **모션** — 형태와 직교하는 별개 축. 정적/펄스/흐름/글로우.
///
/// 완전 자유 조합은 아니다: **흐름(진행)은 바(상·하·좌)에만** 의미 있어, 링·브래킷·코너에선
/// 펄스로 내린다(`resolved(for:)`). 이 판정은 순수 함수라 테스트로 못박는다.
enum PaneMotion: String, CaseIterable, Identifiable {
    case none       // 정적
    case pulse      // 불투명도 호흡 — 아무 형태나
    case flow       // 진행 하이라이트 — 바 전용(펄스 진행바)
    case glow       // 이너 글로우 호흡(분할 시 옆 칸 안 침범)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "없음"
        case .pulse: return "펄스"
        case .flow: return "흐름"
        case .glow: return "글로우"
        }
    }

    /// 이 형태에서 실제로 쓸 모션 — 흐름은 바(상·하·좌)에만, 나머지 형태면 펄스로 내린다.
    func resolved(for form: PaneIndicatorForm) -> PaneMotion {
        guard self == .flow else { return self }
        switch form {
        case .top, .bottom, .left: return .flow
        case .ring, .bracket, .corner: return .pulse
        }
    }
}

/// 칸 상태 표시의 사용자 설정 — 종합 설정 패널에서 바꾸고 UserDefaults에 즉시 영속한다.
///
/// 값은 순수하다(형태 enum·치수·불리언). `TabStyleSettings`와 같은 패턴 —
/// 소비는 경계(`ContentCard` 렌더·`TerminalStore.acknowledgeAgent`)가 맡는다.
@Observable
final class PaneIndicatorSettings {
    @MainActor static let shared = PaneIndicatorSettings()

    var form: PaneIndicatorForm { didSet { defaults.set(form.rawValue, forKey: Self.key("form")) } }
    var motion: PaneMotion { didSet { defaults.set(motion.rawValue, forKey: Self.key("motion")) } }
    /// 선·링 두께(1~5).
    var thickness: Double { didSet { defaults.set(thickness, forKey: Self.key("thickness")) } }
    /// 브래킷 모서리 여백(2~16) — 브래킷 형태에만 유효.
    var bracketInset: Double { didSet { defaults.set(bracketInset, forKey: Self.key("bracketInset")) } }
    /// 모션 한 사이클 시간(초, 0.5~3.0) — 작을수록 빠르다. 없음 형태엔 무의미.
    var speed: Double { didSet { defaults.set(speed, forKey: Self.key("speed")) } }
    /// 글로우 번짐 반경(6~36) — 글로우 모션에만 유효.
    var glowSpread: Double { didSet { defaults.set(glowSpread, forKey: Self.key("glowSpread")) } }
    /// 포커싱(탭 열람) 시 waiting/done 칸 테두리를 지울지. **기본 false = 유지**(봐도 안 사라진다).
    /// false여도 다음 실제 활동(출력→working)엔 자연히 바뀐다 — "본다고 끄지 않을 뿐".
    var clearOnFocus: Bool { didSet { defaults.set(clearOnFocus, forKey: Self.key("clearOnFocus")) } }

    /// 슬라이더 범위(뷰와 클램프가 한 출처를 쓰게).
    static let thicknessRange: ClosedRange<Double> = 1...5
    static let bracketInsetRange: ClosedRange<Double> = 2...16
    static let speedRange: ClosedRange<Double> = 0.5...3.0
    static let glowSpreadRange: ClosedRange<Double> = 6...36

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        form = defaults.string(forKey: Self.key("form")).flatMap(PaneIndicatorForm.init(rawValue:)) ?? .ring
        motion = defaults.string(forKey: Self.key("motion")).flatMap(PaneMotion.init(rawValue:)) ?? .none
        thickness = Self.stored(defaults, "thickness", default: 2, in: Self.thicknessRange)
        bracketInset = Self.stored(defaults, "bracketInset", default: 7, in: Self.bracketInsetRange)
        speed = Self.stored(defaults, "speed", default: 1.6, in: Self.speedRange)
        glowSpread = Self.stored(defaults, "glowSpread", default: 18, in: Self.glowSpreadRange)
        clearOnFocus = defaults.object(forKey: Self.key("clearOnFocus")) != nil
            ? defaults.bool(forKey: Self.key("clearOnFocus")) : false
    }

    private static func stored(_ d: UserDefaults, _ name: String, default def: Double, in range: ClosedRange<Double>) -> Double {
        guard d.object(forKey: key(name)) != nil else { return def }
        return min(max(d.double(forKey: key(name)), range.lowerBound), range.upperBound)
    }

    private static func key(_ name: String) -> String { "muxa.paneindicator.\(name)" }
}
