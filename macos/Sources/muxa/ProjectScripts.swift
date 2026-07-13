import Foundation

/// 패키지 매니저 — **추측하지 않는다. lock 파일이 진실이다.**
///
/// pnpm 프로젝트에 `npm run`을 넣으면 lock이 깨지거나 엉뚱한 의존성이 깔린다.
/// lock 파일이 없으면 `nil`이고, 그때는 사용자가 직접 고른다(지어내지 않는다).
enum PackageManager: String, CaseIterable, Identifiable {
    case pnpm, yarn, bun, npm

    var id: String { rawValue }

    /// lock 파일 → 매니저. 여러 개면 이 순서(배열 순서)가 우선순위다 — 판정이 흔들리지 않게 고정한다.
    private var lockfiles: [String] {
        switch self {
        case .pnpm: return ["pnpm-lock.yaml"]
        case .yarn: return ["yarn.lock"]
        case .bun: return ["bun.lockb", "bun.lock"]
        case .npm: return ["package-lock.json"]
        }
    }

    static func detect(files: [String]) -> PackageManager? {
        let names = Set(files)
        return allCases.first { pm in pm.lockfiles.contains { names.contains($0) } }
    }

    func runCommand(_ script: String) -> String {
        "\(rawValue) run \(script)"
    }
}

/// 프로젝트에서 실행할 만한 스크립트 하나.
struct ProjectScript: Identifiable, Equatable {
    var id: String { name }
    let name: String // "dev"
    let body: String // "vite" — 실제로 도는 명령
    /// 사람이 붙인 설명(있으면). package.json 주석 관례에서 읽는다.
    let note: String?
}

/// 프로젝트 스크립트 탐지 — 순수 파싱은 여기, 파일 읽기(부작용)는 `discover`에만.
enum ProjectScripts {
    /// package.json 문자열 → 스크립트 목록. 깨진 JSON이면 빈 배열(죽지 않고, 지어내지도 않는다).
    ///
    /// **설명(주석)** — package.json은 JSON이라 진짜 주석이 없다. 실제로 쓰이는 두 관례를 읽는다:
    ///  1. `"scripts-info": { "dev": "..." }` — npm-scripts-info 관례. 설명하려고 만든 필드라 **우선한다**.
    ///  2. `"scripts": { "//dev": "...", "dev": "vite" }` — npm이 `//` 키를 무시하는 성질을 쓴 주석
    ///     (`"// dev"`처럼 공백을 넣기도 한다). 주석 키 자체는 목록에 넣지 않는다.
    static func parsePackageScripts(_ json: String) -> [ProjectScript] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = root["scripts"] as? [String: Any] else { return [] }

        let info = root["scripts-info"] as? [String: String] ?? [:]

        // `//dev` · `// dev` → dev 의 설명
        var comments: [String: String] = [:]
        for (key, value) in scripts {
            guard key.hasPrefix("//"), let text = value as? String else { continue }
            let target = key.dropFirst(2).trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { continue } // 단독 "//"는 어느 스크립트의 설명인지 알 수 없다
            comments[target] = text
        }

        return scripts.compactMap { name, value -> ProjectScript? in
            guard !name.hasPrefix("//"), let body = value as? String else { return nil }
            return ProjectScript(name: name, body: body, note: info[name] ?? comments[name])
        }
        // JSON 딕셔너리는 순서가 없다 — 목록이 매번 뒤바뀌지 않도록 이름순으로 고정한다.
        .sorted { $0.name < $1.name }
    }

    /// 디렉터리를 훑어 스크립트와 패키지 매니저를 찾는다(파일 IO — 경계).
    /// package.json이 없으면 빈 목록이고, UI는 "직접 입력"만 보여준다.
    static func discover(in dir: String?) -> (scripts: [ProjectScript], manager: PackageManager?) {
        guard let dir,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return ([], nil) }
        let manager = PackageManager.detect(files: files)
        guard files.contains("package.json"),
              let json = try? String(contentsOfFile: (dir as NSString).appendingPathComponent("package.json"),
                                     encoding: .utf8) else { return ([], manager) }
        return (parsePackageScripts(json), manager)
    }
}
