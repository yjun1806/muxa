import Foundation

/// 경로 자동완성 — 터미널 `cd`처럼 입력하면 상위/하위 폴더가 리스트로 뜬다(Warp·Kiro CLI 방식).
///
/// 경로 **분해**(입력 → 스캔할 부모 디렉토리 + 매칭 접두사)는 순수, 디렉토리 **읽기**는 경계(`directories`).
/// `~`·절대(`/`)·상대(base 기준)·`..` 정규화를 지원해 숨김 폴더·루트까지 타이핑으로 어디든 간다.
enum PathComplete {
    /// `~`·상대경로를 절대경로로 정규화한다(순수). 상대는 `base`(현재 프로젝트) 기준, `..`도 접는다.
    static func expand(_ input: String, base: String) -> String {
        if input.hasPrefix("~") {
            return (input as NSString).expandingTildeInPath
        }
        if input.hasPrefix("/") {
            return URL(fileURLWithPath: input).standardizedFileURL.path
        }
        return URL(fileURLWithPath: base).appendingPathComponent(input).standardizedFileURL.path
    }

    /// 입력을 **(스캔할 부모 디렉토리, 매칭 접두사)** 로 분해한다(순수).
    /// 끝이 `/`면 그 디렉토리 전체(접두사 없음), 아니면 마지막 조각이 접두사다.
    ///  - `""`            → (base, "")          현재 프로젝트 하위 전부
    ///  - `"src"`         → (base, "src")        base에서 src… 로 시작하는 폴더
    ///  - `"apps/"`       → (base/apps, "")       apps 하위 전부
    ///  - `"/usr/lo"`     → ("/usr", "lo")        루트 절대경로
    ///  - `"../"`         → (base 상위, "")        상위 폴더
    static func split(_ input: String, base: String) -> (dir: String, prefix: String) {
        if input.isEmpty { return (base, "") }
        let expanded = expand(input, base: base)
        if input.hasSuffix("/") { return (expanded, "") }
        let url = URL(fileURLWithPath: expanded)
        return (url.deletingLastPathComponent().path, url.lastPathComponent)
    }

    /// `dir` 아래의 **하위 디렉토리** 중 `prefix`로 시작하는 것(경계 — 파일 IO). 대소문자 무시, 이름순.
    /// 숨김 폴더는 접두사가 `.`으로 시작할 때만 노출한다(`cd .g`로 `.git`을 찾게).
    static func directories(in dir: String, prefix: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        let showHidden = prefix.hasPrefix(".")
        let lowerPrefix = prefix.lowercased()
        let fm = FileManager.default
        return names.filter { name in
            guard showHidden || !name.hasPrefix(".") else { return false }
            guard name.lowercased().hasPrefix(lowerPrefix) else { return false }
            var isDir: ObjCBool = false
            let full = (dir as NSString).appendingPathComponent(name)
            return fm.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue
        }.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// 표시용 축약 — 홈은 `~`로, 그 외는 그대로(긴 절대경로가 칩을 늘리지 않게).
    static func display(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
