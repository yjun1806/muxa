import AppKit
import Bonsplit
import Carbon.HIToolbox

// 앱 크롬 단축키 판정을 데이터 테이블로 표현하는 순수 타입. (DESIGN 7 "키 라우팅 충돌")
//
// main.swift의 로컬 키 모니터는 "무엇을 할지" 판정만 이 타입에 위임하고(부작용 없음),
// 실제 실행(AppState·컨트롤러 호출)은 호출부(AppDelegate)가 맡는다.
//
// 라우팅 규칙(DESIGN 4.6 · 7 리스크):
//   ① 테이블 매치 → Action 반환 → 호출부가 실행하고 이벤트를 소비(터미널로 안 흘림)
//   ② 미매치 → nil → 이벤트를 그대로 터미널로 통과(포커스된 ghostty가 먹는다)
// 모든 기본 바인딩이 ⌘·⌘⇧·⌘⌥ 조합(탭 순환만 ⌃Tab)이라 터미널 안 vim 평문(hjkl 등)과 충돌하지 않는다.

/// 크롬 동작(부작용 없는 값) — 실행은 호출부가 맡는다. keyCode·수정자 판정 결과의 도메인 표현.
enum KeymapAction {
    case switchWorkspace(Int)           // ⌘1-8
    case cycleProject(forward: Bool)    // ⌘⇧[ / ⌘⇧]
    case toggleExplorer                 // ⌘⇧E
    case toggleGitPanel                 // ⌘⇧G
    case newTerminal                    // ⌘T
    case split(vertical: Bool)          // ⌘D(수평) / ⌘⇧D(수직)
    case closeTab                       // ⌘W
    case find                           // ⌘F
    case focusPane(NavigationDirection) // ⌘⌥←→↑↓ / ⌘⌥hjkl
    case cycleTab(forward: Bool)        // ⌃Tab / ⌃⇧Tab
    case jumpToNextWaiting              // ⌘⇧A — 다음 대기 세션 전역 점프
    case quickSwitch                    // ⌘K — 빠른 전환기(명령 팔레트)
}

/// (keyCode, 수정자) → KeymapAction 매핑 테이블 + 순수 판정 함수. 설정의 재정의를 기본 위에 얹는다.
struct KeymapResolver {
    /// 우리가 구분하는 수정자만(command·shift·option·control). 화살표의 .function/.numericPad 등은 무시한다.
    struct Mods: Hashable {
        let command, shift, option, control: Bool

        init(command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
            self.command = command; self.shift = shift; self.option = option; self.control = control
        }

        init(_ flags: NSEvent.ModifierFlags) {
            self.init(command: flags.contains(.command), shift: flags.contains(.shift),
                      option: flags.contains(.option), control: flags.contains(.control))
        }
    }

    /// 테이블 키 — 물리 keyCode + 우리가 구분하는 수정자 조합.
    struct Binding: Hashable {
        let keyCode: Int
        let mods: Mods
    }

    /// 기본 테이블 + 설정 재정의(있으면 우선). 둘 다 (keyCode, mods) → action.
    private let table: [Binding: KeymapAction]

    /// 이 리졸버를 빌드하며 감지한 재정의 진단(파싱 실패·미인식 동작·예약키 침범·충돌).
    /// 동작 회귀는 없다(last-wins 유지) — 경고만 담는다. 노출·로깅은 호출부(main·AppState)가 맡는다.
    let diagnostics: [KeymapDiagnostic]

    /// 기본 바인딩만 담은 리졸버(설정 재정의 없음).
    static let `default` = KeymapResolver(overrides: [:])

    /// 설정의 keybinding 재정의를 기본 테이블 위에 얹어 만든다. 순수 판정(Self.build)에 위임한다.
    /// 파싱 실패·예약키 침범은 무시(기본 유지)하되 진단으로 기록하고, 충돌은 last-wins 유지 + 진단만 남긴다.
    init(overrides: [String: String]) {
        let result = Self.build(overrides: overrides)
        table = result.table
        diagnostics = result.diagnostics
    }

    /// 키 입력 → 크롬 동작(없으면 nil = 터미널로 통과). 순수 함수 — 부작용 없음.
    func resolve(keyCode: Int, characters: String?, flags: NSEvent.ModifierFlags) -> KeymapAction? {
        // ⌘ + 숫자 1-8 → 워크스페이스 전환. 물리 keyCode는 자판마다 달라서, 숫자만은 characters로 읽는다(자판 무관).
        if flags.contains(.command), let s = characters, let n = Int(s), (1 ... 8).contains(n) {
            return .switchWorkspace(n)
        }
        return table[Binding(keyCode: keyCode, mods: Mods(flags))]
    }

    /// 기본 바인딩 테이블 — 여기가 단축키의 단일 진실 원천. 새 단축키는 이 표에만 추가한다.
    private static let defaultTable: [Binding: KeymapAction] = {
        let cmd = Mods(command: true)
        let cmdShift = Mods(command: true, shift: true)
        let cmdOpt = Mods(command: true, option: true)
        let ctrl = Mods(control: true)
        let ctrlShift = Mods(shift: true, control: true)

        var table: [Binding: KeymapAction] = [
            Binding(keyCode: kVK_ANSI_T, mods: cmd): .newTerminal,
            Binding(keyCode: kVK_ANSI_D, mods: cmd): .split(vertical: false),
            Binding(keyCode: kVK_ANSI_W, mods: cmd): .closeTab,
            Binding(keyCode: kVK_ANSI_F, mods: cmd): .find,
            Binding(keyCode: kVK_ANSI_LeftBracket, mods: cmdShift): .cycleProject(forward: false),
            Binding(keyCode: kVK_ANSI_RightBracket, mods: cmdShift): .cycleProject(forward: true),
            Binding(keyCode: kVK_ANSI_E, mods: cmdShift): .toggleExplorer,
            Binding(keyCode: kVK_ANSI_G, mods: cmdShift): .toggleGitPanel,
            Binding(keyCode: kVK_ANSI_D, mods: cmdShift): .split(vertical: true),
            Binding(keyCode: kVK_Tab, mods: ctrl): .cycleTab(forward: true),
            Binding(keyCode: kVK_Tab, mods: ctrlShift): .cycleTab(forward: false),
            Binding(keyCode: kVK_ANSI_A, mods: cmdShift): .jumpToNextWaiting,
            Binding(keyCode: kVK_ANSI_K, mods: cmd): .quickSwitch,
        ]
        // 칸 방향 포커스 이동(⌘⌥) — 화살표와 vim hjkl 둘 다 받아 근육기억에 맞춘다.
        let focus: [(Int, NavigationDirection)] = [
            (kVK_LeftArrow, .left), (kVK_RightArrow, .right), (kVK_UpArrow, .up), (kVK_DownArrow, .down),
            (kVK_ANSI_H, .left), (kVK_ANSI_L, .right), (kVK_ANSI_K, .up), (kVK_ANSI_J, .down),
        ]
        for (code, dir) in focus {
            table[Binding(keyCode: code, mods: cmdOpt)] = .focusPane(dir)
        }
        return table
    }()
}

// MARK: - 설정 재정의 파싱 (순수)

extension KeymapAction {
    /// 설정 재정의용 동작 이름 → 동작. 워크스페이스 전환(숫자 파생)은 재정의 대상에서 제외한다.
    static func named(_ name: String) -> KeymapAction? {
        switch name {
        case "new_terminal": return .newTerminal
        case "close_tab": return .closeTab
        case "find": return .find
        case "toggle_explorer": return .toggleExplorer
        case "toggle_git": return .toggleGitPanel
        case "split_horizontal": return .split(vertical: false)
        case "split_vertical": return .split(vertical: true)
        case "project_next": return .cycleProject(forward: true)
        case "project_prev": return .cycleProject(forward: false)
        case "tab_next": return .cycleTab(forward: true)
        case "tab_prev": return .cycleTab(forward: false)
        case "jump_next_waiting": return .jumpToNextWaiting
        case "quick_switch": return .quickSwitch
        case "focus_left": return .focusPane(.left)
        case "focus_right": return .focusPane(.right)
        case "focus_up": return .focusPane(.up)
        case "focus_down": return .focusPane(.down)
        default: return nil
        }
    }
}

extension KeymapResolver {
    /// `cmd+shift+e` 같은 조합 문자열 → Binding(순수). 인식 못 하는 토큰이 하나라도 있으면 nil(무시).
    static func parseCombo(_ combo: String) -> Binding? {
        let tokens = combo.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !tokens.isEmpty else { return nil }

        var command = false, shift = false, option = false, control = false
        var keyCode: Int?
        for token in tokens {
            switch token {
            case "cmd", "command", "⌘": command = true
            case "shift", "⇧": shift = true
            case "opt", "option", "alt", "⌥": option = true
            case "ctrl", "control", "⌃": control = true
            default:
                guard let code = keyCodeByToken[token] else { return nil }
                keyCode = code
            }
        }
        guard let keyCode else { return nil }
        return Binding(keyCode: keyCode, mods: Mods(command: command, shift: shift, option: option, control: control))
    }

    /// 조합 문자열의 키 토큰 → 물리 keyCode. 매직 숫자를 피해 Carbon 상수를 그대로 쓴다.
    private static let keyCodeByToken: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "[": kVK_ANSI_LeftBracket, "leftbracket": kVK_ANSI_LeftBracket,
        "]": kVK_ANSI_RightBracket, "rightbracket": kVK_ANSI_RightBracket,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "tab": kVK_Tab,
    ]
}

// MARK: - 재정의 진단 (순수)

/// keybind 재정의를 흡수하며 감지한 문제. 값 타입 — 로깅·UI 노출은 호출부가 결정한다. (DESIGN 7)
/// "왜 내 단축키가 안 먹지"의 원인(파싱 실패·미인식 동작·예약키·충돌)을 조용히 삼키지 않고 표면화한다.
enum KeymapDiagnostic: Equatable {
    /// 동작 이름을 못 알아봤다(예: `keybind.zoom`). 재정의 무시.
    case unknownAction(name: String, combo: String)
    /// 조합 문자열 파싱 실패(예: `cmd+`, `hyper+z`). 재정의 무시.
    case parseFailed(name: String, combo: String)
    /// muxa가 고정 사용하는 예약 조합(⌘Q·⌘H·⌘1–8·⌘K) 침범. 재정의 거부(무시).
    case reserved(name: String, combo: String)
    /// 같은 조합을 둘 이상 동작이 노렸다. last-wins로 동작은 유지하되 어떤 동작들이 겹쳤는지 알린다.
    case conflict(combo: String, actions: [String])

    /// 로그·표면 노출용 사람이 읽을 한 줄. 값은 여기 한 곳에서만 만든다(중복 방지).
    var message: String {
        switch self {
        case let .unknownAction(name, combo):
            return "알 수 없는 동작 '\(name)' (= \(combo)) — 재정의를 무시합니다."
        case let .parseFailed(name, combo):
            return "'\(name)'의 키 조합 '\(combo)'을(를) 해석할 수 없습니다 — 재정의를 무시합니다."
        case let .reserved(name, combo):
            return "'\(combo)'은(는) muxa 예약 조합이라 '\(name)'에 재정의할 수 없습니다 — 무시합니다."
        case let .conflict(combo, actions):
            return "'\(combo)'을(를) 여러 동작이 함께 노렸습니다(\(actions.joined(separator: ", "))) — 마지막 것만 적용됩니다."
        }
    }
}

extension KeymapResolver {
    /// 순수 빌드 결과 — 병합된 테이블과 진단 목록. init이 이 값을 그대로 저장한다.
    struct BuildResult {
        let table: [Binding: KeymapAction]
        let diagnostics: [KeymapDiagnostic]
    }

    /// muxa가 고정 사용해 재정의를 받지 않는 예약 조합. ⌘Q·⌘H(메뉴), ⌘1–8(워크스페이스 전환은
    /// resolve가 characters로 먼저 가로채므로 재정의해도 무효), ⌘K(빠른 전환기). 매직값 대신 Carbon 상수.
    static let reservedBindings: Set<Binding> = {
        let cmd = Mods(command: true)
        var set: Set<Binding> = [
            Binding(keyCode: kVK_ANSI_Q, mods: cmd),
            Binding(keyCode: kVK_ANSI_H, mods: cmd),
            Binding(keyCode: kVK_ANSI_K, mods: cmd),
        ]
        for code in [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                     kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8] {
            set.insert(Binding(keyCode: code, mods: cmd))
        }
        return set
    }()

    /// 재정의를 기본 테이블 위에 얹으며 문제를 감지한다(순수 — 부작용 없음, 테스트 가능).
    /// 처리 순서를 동작 이름 정렬로 고정해 충돌 시 last-wins가 결정론적이게 만든다(사전 순회 비결정성 제거).
    static func build(overrides: [String: String]) -> BuildResult {
        var merged = defaultTable
        var diagnostics: [KeymapDiagnostic] = []
        var claimed: [Binding: String] = [:] // 재정의가 이미 차지한 조합 → 먼저 차지한 동작 이름
        for name in overrides.keys.sorted() {
            let combo = overrides[name] ?? ""
            guard let action = KeymapAction.named(name) else {
                diagnostics.append(.unknownAction(name: name, combo: combo)); continue
            }
            guard let binding = parseCombo(combo) else {
                diagnostics.append(.parseFailed(name: name, combo: combo)); continue
            }
            if reservedBindings.contains(binding) {
                diagnostics.append(.reserved(name: name, combo: combo)); continue // 거부 — 기본 유지
            }
            if let prior = claimed[binding], prior != name {
                diagnostics.append(.conflict(combo: combo, actions: [prior, name])) // last-wins 유지, 경고만
            }
            claimed[binding] = name
            merged[binding] = action
        }
        return BuildResult(table: merged, diagnostics: diagnostics)
    }
}
