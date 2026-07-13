import Foundation

/// 상태 파일 2단 폴백 **판정**(순수). 파일 읽기·디코드 같은 부작용은 호출자(`AppState.load`)가 한다.
///
/// 판정을 분리한 이유: "primary가 손상되면 정말 백업을 쓰는가"를 앱을 띄우지 않고 검증하기 위해서다.
/// I/O와 섞여 있으면 이 결정을 테스트할 방법이 없다.
enum StateLoad {
    /// 상태 파일 하나의 상태.
    enum FileState {
        case valid   // 읽었고 디코드도 됐다
        case corrupt // 파일은 있는데 디코드 실패
        case missing // 파일 없음
    }

    /// 어느 파일로 복원할지.
    enum Source {
        case primary
        case backup
        case none // 복원할 것이 없다 — 빈 상태로 시작
    }

    struct Decision {
        let source: Source
        /// primary를 백업으로 복사할지. 정상 로드에 성공했을 때만 true —
        /// 손상본이 백업까지 덮으면 유일한 복구 경로가 사라진다.
        let refreshBackup: Bool
        /// 사용자에게 알릴 유실. 최초 실행(파일 없음)은 유실이 아니므로 비어 있다.
        let warnings: [String]
    }

    static func choose(primary: FileState, backup: FileState) -> Decision {
        switch (primary, backup) {
        case (.valid, _):
            return Decision(source: .primary, refreshBackup: true, warnings: [])

        case (.corrupt, .valid):
            return Decision(source: .backup, refreshBackup: false,
                            warnings: ["이전 세션 파일이 손상돼 백업에서 복원했습니다."])

        case (.missing, .valid):
            // 저장 도중 크래시로 primary만 날아간 경우 — 백업이 직전 정상 세션이다.
            return Decision(source: .backup, refreshBackup: false,
                            warnings: ["이전 세션 파일이 없어 백업에서 복원했습니다."])

        case (.missing, .missing):
            return Decision(source: .none, refreshBackup: false, warnings: []) // 최초 실행

        default:
            // primary 손상 + 백업도 없거나 손상 — 되살릴 것이 없다.
            return Decision(source: .none, refreshBackup: false,
                            warnings: ["이전 세션을 불러오지 못했습니다 — 새 세션으로 시작합니다."])
        }
    }
}
