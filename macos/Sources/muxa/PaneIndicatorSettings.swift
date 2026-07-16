import SwiftUI

/// 칸(패인) 상태 테두리의 **형태**. 모션(펄스·흐름·글로우)과 직교하는 별개 축 — 여기선 형태만 정한다.
///
/// 순수 값이다(라벨·rawValue만). 실제 그리기는 `ContentCard`의 테두리 레이어가, 칸에 얹는 일은
/// `BonsplitWorkspaceView`가 맡는다(경계 분리). `.ring`이 기존 기본(전체 링)이라 하위호환된다.
enum PaneIndicatorForm: String, CaseIterable, Identifiable {
    case ring       // 전체 링 — 네 변 다
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

/// 한 상태(작업중·대기·완료)의 칸 표시 스타일 — 형태 + 모션 + 치수. 순수 값(부작용 없음).
/// 색은 여기 없다 — 상태가 정한다(`PaneIndicatorState.color`, 상태색 시스템 불변).
struct PaneIndicatorStyle: Equatable {
    var form: PaneIndicatorForm
    var motion: PaneMotion
    var thickness: Double
    var bracketInset: Double
    var speed: Double
    var glowSpread: Double
}

/// 칸 표시를 가르는 상태 — **유휴는 여기 없다**(표시 안 함). 색은 상태 고정(작업=인디고·대기=로즈·완료=세이지).
enum PaneIndicatorState: String, CaseIterable, Identifiable {
    case working, waiting, done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .working: return "작업 중"
        case .waiting: return "입력 대기"
        case .done: return "완료"
        }
    }

    var color: NSColor {
        switch self {
        case .working: return Palette.work
        case .waiting: return Palette.waiting
        case .done: return Palette.done
        }
    }

    /// 상태별 기본 스타일 — 작업중은 "진행 중"이 읽히게 상단 진행바(흐름), 대기는 시선 끌 펄스 링,
    /// 완료는 조용한 정적 링. 사용자가 설정에서 각각 바꾼다.
    var defaultStyle: PaneIndicatorStyle {
        switch self {
        case .working: return PaneIndicatorStyle(form: .top, motion: .flow, thickness: 2, bracketInset: 7, speed: 1.6, glowSpread: 18)
        case .waiting: return PaneIndicatorStyle(form: .ring, motion: .pulse, thickness: 2, bracketInset: 7, speed: 1.6, glowSpread: 18)
        case .done: return PaneIndicatorStyle(form: .ring, motion: .none, thickness: 2, bracketInset: 7, speed: 1.6, glowSpread: 18)
        }
    }
}

/// 칸 상태 표시의 사용자 설정 — **상태별(working/waiting/done)** 스타일을 각각 담고 UserDefaults에 즉시 영속한다.
///
/// 값은 순수하다(스타일 값 타입·불리언). 소비는 경계(`ContentCard` 렌더·`TerminalStore.acknowledgeAgent`)가 맡는다.
@Observable
final class PaneIndicatorSettings {
    @MainActor static let shared = PaneIndicatorSettings()

    var working: PaneIndicatorStyle { didSet { Self.persist(defaults, .working, working) } }
    var waiting: PaneIndicatorStyle { didSet { Self.persist(defaults, .waiting, waiting) } }
    var done: PaneIndicatorStyle { didSet { Self.persist(defaults, .done, done) } }
    /// 포커싱(탭 열람) 시 waiting/done 칸 테두리를 지울지. **기본 false = 유지**(봐도 안 사라진다).
    /// false여도 다음 실제 활동(출력→working)엔 자연히 바뀐다 — "본다고 끄지 않을 뿐". (작업중은 원래 안 지운다.)
    var clearOnFocus: Bool { didSet { defaults.set(clearOnFocus, forKey: Self.focusKey) } }

    /// 슬라이더 범위(뷰와 클램프가 한 출처를 쓰게).
    static let thicknessRange: ClosedRange<Double> = 1...5
    static let bracketInsetRange: ClosedRange<Double> = 2...16
    static let speedRange: ClosedRange<Double> = 0.5...3.0
    static let glowSpreadRange: ClosedRange<Double> = 6...36

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        working = Self.load(defaults, .working)
        waiting = Self.load(defaults, .waiting)
        done = Self.load(defaults, .done)
        clearOnFocus = defaults.object(forKey: Self.focusKey) != nil ? defaults.bool(forKey: Self.focusKey) : false
    }

    /// 상태의 현재 스타일.
    func style(for state: PaneIndicatorState) -> PaneIndicatorStyle {
        switch state {
        case .working: return working
        case .waiting: return waiting
        case .done: return done
        }
    }

    /// 상태의 스타일을 통째로 갱신(뷰 바인딩용) — 해당 didSet가 영속한다.
    func setStyle(_ style: PaneIndicatorStyle, for state: PaneIndicatorState) {
        switch state {
        case .working: working = style
        case .waiting: waiting = style
        case .done: done = style
        }
    }

    // MARK: 영속(상태 × 필드 별 키)

    private static func load(_ d: UserDefaults, _ state: PaneIndicatorState) -> PaneIndicatorStyle {
        let def = state.defaultStyle
        let form = d.string(forKey: key(state, "form")).flatMap(PaneIndicatorForm.init(rawValue:)) ?? def.form
        let motion = d.string(forKey: key(state, "motion")).flatMap(PaneMotion.init(rawValue:)) ?? def.motion
        return PaneIndicatorStyle(
            form: form,
            motion: motion,
            thickness: stored(d, state, "thickness", default: def.thickness, in: thicknessRange),
            bracketInset: stored(d, state, "bracketInset", default: def.bracketInset, in: bracketInsetRange),
            speed: stored(d, state, "speed", default: def.speed, in: speedRange),
            glowSpread: stored(d, state, "glowSpread", default: def.glowSpread, in: glowSpreadRange)
        )
    }

    private static func persist(_ d: UserDefaults, _ state: PaneIndicatorState, _ s: PaneIndicatorStyle) {
        d.set(s.form.rawValue, forKey: key(state, "form"))
        d.set(s.motion.rawValue, forKey: key(state, "motion"))
        d.set(s.thickness, forKey: key(state, "thickness"))
        d.set(s.bracketInset, forKey: key(state, "bracketInset"))
        d.set(s.speed, forKey: key(state, "speed"))
        d.set(s.glowSpread, forKey: key(state, "glowSpread"))
    }

    private static func stored(_ d: UserDefaults, _ state: PaneIndicatorState, _ field: String,
                               default def: Double, in range: ClosedRange<Double>) -> Double {
        guard d.object(forKey: key(state, field)) != nil else { return def }
        return min(max(d.double(forKey: key(state, field)), range.lowerBound), range.upperBound)
    }

    private static func key(_ state: PaneIndicatorState, _ field: String) -> String {
        "muxa.paneindicator.\(state.rawValue).\(field)"
    }
    private static let focusKey = "muxa.paneindicator.clearOnFocus"
}
