import Foundation

/// muxa 고유 설정(값 타입) — `~/.config/muxa/config`에서 로드. (DESIGN 4.6)
///
/// 폰트·테마 등 터미널 코어 설정은 ghostty config(`~/.config/ghostty/config`)를 그대로
/// 재사용한다(GhosttyRuntime). 이 타입은 그와 별개로 muxa 크롬·동작에만 관여하는 설정 표면이다.
///
/// 파싱은 순수 함수(`parse`) — 부작용 없음, 테스트 가능. 파일 I/O는 경계 타입(`MuxaConfigLoader`)에만.
/// 없는 값·인식 못 하는 키는 무시하고 기본값(`defaults`)을 유지한다.
struct MuxaConfig: Equatable {
    /// 사이드바 기본 표시 모드. 세션에 사용자가 토글한 값이 저장돼 있으면 그쪽이 우선(이건 초기 기본).
    var sidebarMode: SidebarMode
    /// 종료 시 확인 대화상자 표시 여부.
    var confirmQuit: Bool
    /// 정상·짧게 끝난 명령의 완료 배지를 억제하는 임계 시간(초). 이보다 오래 걸린 명령만 알린다.
    var commandFinishedThresholdSec: Double
    /// 첫 실행 시 초기 워크스페이스로 열 경로(없으면 현재 디렉토리/홈).
    var defaultWorkspacePath: String?

    /// 전부 기본값(= 빈 설정 파일과 동일). 각 항목의 단일 진실 원천.
    static let defaults = MuxaConfig(
        sidebarMode: .expanded,
        confirmQuit: true,
        commandFinishedThresholdSec: 8,
        defaultWorkspacePath: nil
    )

    /// 완료 배지 임계를 나노초로 환산 — TerminalStore가 이 단위로 비교한다. 음수는 0으로 클램프.
    var commandFinishedThresholdNs: UInt64 {
        UInt64(max(0, commandFinishedThresholdSec) * 1_000_000_000)
    }
}

extension MuxaConfig {
    /// 순수 파서 — ghostty 스타일 `key = value` 한 줄 포맷(주석은 `#`으로 시작하는 줄). 부작용 없음.
    /// 인식 못 하는 키·잘못된 값은 조용히 무시하고 해당 항목은 기본값을 유지한다.
    static func parse(_ text: String) -> MuxaConfig {
        let pairs = parsePairs(text)
        return MuxaConfig(
            sidebarMode: pairs["sidebar_mode"].flatMap(SidebarMode.init(rawValue:)) ?? defaults.sidebarMode,
            confirmQuit: pairs["confirm_quit"].flatMap(parseBool) ?? defaults.confirmQuit,
            commandFinishedThresholdSec: pairs["command_finished_threshold_sec"].flatMap(Double.init)
                ?? defaults.commandFinishedThresholdSec,
            defaultWorkspacePath: pairs["default_workspace_path"] ?? defaults.defaultWorkspacePath
        )
    }

    /// 원문을 `key → value` 사전으로 분해한다(순수). 빈 줄·`#` 주석 줄·`=` 없는 줄은 건너뛴다.
    /// 뒤에 오는 같은 키가 앞을 덮는다(ghostty와 동일한 last-wins).
    static func parsePairs(_ text: String) -> [String: String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).reduce(into: [:]) { acc, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { return }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return }
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            acc[key] = value
        }
    }

    /// 흔한 불리언 표기를 관대하게 해석(true/false·yes/no·on/off·1/0). 그 외는 nil.
    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "true", "yes", "on", "1": return true
        case "false", "no", "off", "0": return false
        default: return nil
        }
    }

    /// 경로 항목의 `~`를 홈 경로로 확장한 새 설정을 돌려준다(immutable). 파서는 순수하게 두고
    /// 홈 의존 확장은 로더 경계에서 1회 수행한다.
    func expandingPaths(home: String) -> MuxaConfig {
        var next = self
        next.defaultWorkspacePath = defaultWorkspacePath.map { path in
            path == "~" ? home
                : path.hasPrefix("~/") ? home + path.dropFirst(1)
                : path
        }
        return next
    }
}

/// 설정 파일 로더 — 파일 I/O를 격리하는 경계 타입. 없으면 기본값(전부 디폴트)으로 시작한다.
enum MuxaConfigLoader {
    /// 설정 파일 경로 — `~/.config/muxa/config` (XDG 관례, ghostty와 나란히).
    static var fileURL: URL {
        URL(fileURLWithPath: SystemPaths.home)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("muxa", isDirectory: true)
            .appendingPathComponent("config")
    }

    /// 파일을 읽어 파싱한다. 파일이 없거나 읽기 실패 시 기본값. 파싱 후 `~` 경로를 확장한다.
    static func load() -> MuxaConfig {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return .defaults
        }
        return MuxaConfig.parse(text).expandingPaths(home: SystemPaths.home)
    }
}
