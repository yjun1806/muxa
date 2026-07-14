import Foundation

/// 재개 명령을 **지금 이 터미널에 보내도 되는가**를 정하는 순수 판정. (D27)
///
/// `executeResume`은 `sendText`로 명령을 치고 **Enter까지 커밋**한다 — 되돌릴 수 없다. 그 대상이 셸
/// 프롬프트라는 가정이 틀리면 명령이 엉뚱한 곳에 꽂힌다. 실제로 그랬다: 훅이 알려준 세션 바인딩이
/// **claude가 막 시작한 탭**에 배너를 띄웠고, 자동 실행이 살아 있는 claude TUI 입력창에
/// `claude --resume …`를 타이핑했다.
///
/// 그래서 보내기 전에 두 가지를 확인한다:
/// 1. **포그라운드가 셸인가** — TUI(claude·vim·less…)가 잡고 있으면 그건 그 프로그램의 입력이지 명령줄이 아니다.
/// 2. **폴더가 맞는가** — `claude --resume <id>`는 **cwd 기준으로** 세션을 찾는다. 다른 폴더에서 치면
///    남의 프로젝트에서 없는 세션을 뒤진다. 재개는 정확한 경로에서만 유효하다.
///
/// **모르는 것과 틀린 것을 가른다.** 셸 pid·pwd는 스폰 직후 잠시 비어 있다(pid 폴링 250ms · OSC 7은
/// 첫 프롬프트에 온다). 그 구간을 "차단"으로 부르면 auto가 영구히 죽고, "통과"로 부르면 검사를 안 한
/// 것과 같다 — 그래서 `.hold(.notReady)`로 따로 부르고 auto는 잠시 뒤 **다시 묻는다**.
/// 판정을 좁게, 보존을 넓게: 확신이 없으면 보내지 않는다.
enum ResumeGate {
    /// 보내지 않는 이유. 사용자에게 **무엇을 하면 되는지** 말해 줄 수 있는 단위로 나눈다.
    enum Reason: Equatable {
        /// 아직 모른다 — 셸 pid나 pwd가 안 잡혔다(스폰 직후). 곧 정해지므로 auto는 재시도한다.
        case notReady
        /// 셸이 아닌 프로그램(TUI)이 포그라운드다 → 그 입력창에 명령을 꽂지 않는다.
        case foregroundBusy
        /// 셸이 다른 폴더에 있다 → 그 폴더엔 이 세션이 없다. 기대 경로를 실어 배너가 안내한다.
        case wrongCwd(expected: String)
    }

    enum Decision: Equatable {
        case send
        case hold(Reason)
    }

    /// - Parameters:
    ///   - expectedCwd: 바인딩에 묶인 작업 디렉터리. nil이면(구 스냅샷 등) 경로 검사를 건너뛴다 —
    ///                 기록이 없는 것은 "틀렸다"는 근거가 아니라 "모른다"이므로 기존 동작을 유지한다.
    ///   - pwd: 셸의 현재 작업 디렉터리(OSC 7). 기대 경로가 있는데 이걸 모르면 아직 보내지 않는다.
    ///   - foregroundIsShell: 포그라운드가 셸 자신인가. **nil = 아직 모른다**(pid 미확보) → 보내지 않는다.
    ///
    /// 두 경로(expectedCwd·pwd)는 호출부가 `normalize`로 다듬어 넘긴다(심링크 해석은 파일시스템을
    /// 만지므로 경계의 몫이다 — 여기는 순수하게 남는다).
    static func decide(expectedCwd: String?, pwd: String?, foregroundIsShell: Bool?) -> Decision {
        guard let foregroundIsShell else { return .hold(.notReady) }
        guard foregroundIsShell else { return .hold(.foregroundBusy) }
        guard let expected = expectedCwd else { return .send }
        guard let pwd else { return .hold(.notReady) } // 기대 경로는 있는데 지금 어디인지 모른다 → 아직 안 보낸다
        guard isSamePath(pwd, expected) else { return .hold(.wrongCwd(expected: expected)) }
        return .send
    }

    /// 같은 디렉터리를 가리키는가 — 끝의 `/`와 **대소문자** 차이를 흡수한다(순수).
    ///
    /// 두 경로의 출처가 다르다: 기대 경로는 claude의 `getcwd()`(물리 경로), 현재 pwd는 셸의 `$PWD`(논리 경로)다.
    /// 심링크 차이는 호출부가 `resolvingSymlinksInPath`로 미리 지운다. 대소문자는 여기서 지운다 —
    /// APFS는 기본 case-insensitive라 `cd /users/x/repo`로 들어간 셸을 "다른 폴더"라고 부르면 정상 재개가 죽는다.
    static func isSamePath(_ a: String, _ b: String) -> Bool {
        normalize(a).compare(normalize(b), options: .caseInsensitive) == .orderedSame
    }

    /// 끝의 슬래시를 떼어 표기 차이를 없앤다(루트 `/`는 보존).
    static func normalize(_ path: String) -> String {
        var s = path
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
