import CryptoKit
import Foundation

/// 이 프로세스가 어떤 빌드로 떠 있는지.
///
/// 워크트리마다 개발빌드를 띄우는 게 일상이라 **"muxa"가 여러 개 뜬다** — Dock·⌘Tab·창 제목이 전부
/// 똑같으면 어느 창이 어느 브랜치인지 알 수 없고, 릴리스와도 안 갈려 **테스트 중 서로 죽인다**. 그래서
/// 이름 규칙(`scripts/app-identity.sh` 단일 출처)이 dev/prod를 완전히 가른다: 릴리스 `muxa`,
/// 개발 `muxa-dev-<slug>`(번들명 `Muxa Dev · <slug>`). 여기서 그 이름을 읽어 창 제목·메뉴·워드마크가
/// 모두 같은 이름을 쓰게 한다.
///
/// bare 실행(`swift build`의 `.build/debug/muxa` 직접)은 번들이 아니라 이름을 못 박고 시스템 알림도 못 쓴다
/// — 그래서 개발은 **`make dev`/`make dev-relaunch`로 번들을 띄운다**(프로세스명 `muxa-dev-<slug>`).
/// 종료는 **`make dev-kill`**(이 워크트리 개발 앱만 — 릴리스·타 워크트리 불가침).
enum AppInfo {
    /// 앱 번들이 아니면(=bare 실행) 개발 실행이다. 번들 개발빌드는 id가 `com.muxa.dev.*`다.
    static let isDev = bundleId == nil || bundleId?.hasPrefix(devBundlePrefix) == true

    /// 표시 이름 — 번들이면 CFBundleName(개발빌드는 브랜치명 포함), bare면 "muxa (dev)".
    static let name: String = {
        if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty { return bundleName }
        return "muxa (dev)"
    }()

    /// **개발 빌드의 격리 키.** 릴리스면 nil(사용자 데이터는 하나뿐이다).
    ///
    /// 격리하지 않으면 워크트리마다 띄운 개발빌드들이 **같은 `state.v4.json`과 같은 tmux 소켓을 두고
    /// 싸운다** — 서로의 세션을 덮어쓰고, 서로의 tmux 세션을 "등록되지 않은 고아"로 오인해 죽인다.
    /// 실제로 그렇게 터졌다. 저장소·소켓을 이 키로 갈라 **구조적으로 못 섞이게** 한다.
    ///
    /// 키는 **실행 파일 경로**에서 뽑는다(브랜치명이 아니라). 같은 워크트리에서 브랜치를 갈아타도
    /// 같은 저장소를 쓰는 게 자연스럽고, 브랜치는 바뀌어도 워크트리는 그대로이기 때문이다.
    /// 로그·경로에서 알아볼 수 있게 `<워크트리이름>-<해시6>` 형태로 만든다(해시가 있어 충돌하지 않는다).
    static let devKey: String? = {
        guard isDev else { return nil }
        let path = Bundle.main.bundlePath
        let digest = SHA256.hash(data: Data(path.utf8))
        let hash = digest.prefix(3).map { String(format: "%02x", $0) }.joined() // 6자
        return "\(worktreeLabel(from: path))-\(hash)"
    }()

    /// 이 개발빌드가 나온 **워크트리 루트** 경로(릴리스면 nil).
    ///
    /// 저장소 GC가 "이 저장소의 주인이 아직 있나"를 묻는 기준이다. **실행 파일 경로가 아니라
    /// 워크트리 루트여야 한다** — `make clean`으로 `.build`만 지워도 워크트리는 그대로인데,
    /// 실행 파일 경로를 기준 삼으면 멀쩡한 저장소를 유령으로 오판한다.
    static let worktreeRoot: String? = {
        guard isDev else { return nil }
        let parts = Bundle.main.bundlePath.split(separator: "/").map(String.init)
        // `…/<워크트리>/macos/.build/…` — `.build` 두 단계 위가 워크트리 루트다.
        guard let buildIdx = parts.firstIndex(of: ".build"), buildIdx >= 2 else { return nil }
        return "/" + parts[..<(buildIdx - 1)].joined(separator: "/")
    }()

    /// 경로에서 사람이 알아볼 이름을 뽑는다 — `…/muxa-services/macos/.build/…` → `muxa-services`.
    private static func worktreeLabel(from path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        // `.build`(SPM 산출물) 바로 앞이 `macos`, 그 앞이 워크트리 루트다.
        if let buildIdx = parts.firstIndex(of: ".build"), buildIdx >= 2 {
            return sanitize(parts[buildIdx - 2])
        }
        return parts.last.map(sanitize) ?? "dev"
    }

    /// 소켓·디렉터리 이름에 안전한 문자만 남긴다.
    private static func sanitize(_ s: String) -> String {
        let allowed = s.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return allowed.isEmpty ? "dev" : String(allowed.prefix(24))
    }

    private static let bundleId = Bundle.main.bundleIdentifier
    private static let devBundlePrefix = "com.muxa.dev."
}
