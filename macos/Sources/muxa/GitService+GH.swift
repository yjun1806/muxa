import Foundation

/// GitHub 연동(gh CLI 셸아웃) — 현재 브랜치의 PR·CI 상태를 읽어 Git 헤더 배지로 보인다.
/// 전 경로 가드: gh 미설치·미인증·github 아님·PR 없음이면 조용히 nil(배지 숨김). 절대 크래시/블로킹 없음.
/// 네트워크 호출이라 백그라운드에서 1회 로드 + 새로고침 시에만 갱신(과한 폴링 금지).
extension GitService {
    /// 현재 브랜치의 PR 요약 + CI 롤업. gh가 없거나 PR이 없으면 nil.
    struct GHStatus {
        let prNumber: Int
        let state: String // OPEN / MERGED / CLOSED
        let url: String
        let passing: Int
        let failing: Int
        let pending: Int

        /// CI 체크 하나의 판정.
        enum Check { case passing, failing, pending }

        /// 전체 CI 롤업 — 실패 우선, 다음 진행중, 다음 통과. 체크가 없으면 nil.
        var rollup: Check? {
            if failing > 0 { return .failing }
            if pending > 0 { return .pending }
            if passing > 0 { return .passing }
            return nil
        }
    }

    /// 현재 브랜치 PR 상태를 gh로 읽는다. 실패는 전부 조용히 nil.
    static func ghStatus(in dir: String) async -> GHStatus? {
        guard ghPath != nil else { return nil } // gh 미설치 → 배지 없음
        let r = await runGH(["pr", "view", "--json", "number,state,url,statusCheckRollup"], in: dir)
        guard r.exitCode == 0 else { return nil } // 미인증·github 아님·PR 없음 등
        return parseGHStatus(r.stdout)
    }

    /// PR을 브라우저에서 연다(안전한 읽기 액션). 실패해도 조용히 무시.
    static func ghOpenPR(in dir: String) async {
        guard ghPath != nil else { return }
        _ = await runGH(["pr", "view", "--web"], in: dir)
    }

    // MARK: 파싱

    /// `gh pr view --json ...` JSON을 값 타입으로. 스키마가 안 맞으면 nil.
    static func parseGHStatus(_ json: String) -> GHStatus? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = obj["number"] as? Int,
              let state = obj["state"] as? String else { return nil }
        let url = obj["url"] as? String ?? ""

        var passing = 0, failing = 0, pending = 0
        if let rollup = obj["statusCheckRollup"] as? [[String: Any]] {
            for item in rollup {
                switch classifyCheck(item) {
                case .passing: passing += 1
                case .failing: failing += 1
                case .pending: pending += 1
                }
            }
        }
        return GHStatus(prNumber: number, state: state, url: url,
                        passing: passing, failing: failing, pending: pending)
    }

    /// 롤업 항목 하나(CheckRun 또는 StatusContext)를 통과/실패/진행중으로 분류.
    /// CheckRun은 status(진행 단계)+conclusion(결과), StatusContext는 state를 쓴다.
    private static func classifyCheck(_ item: [String: Any]) -> GHStatus.Check {
        let status = (item["status"] as? String ?? "").uppercased()
        if !status.isEmpty && status != "COMPLETED" { return .pending } // 큐잉·진행중

        let conclusion = (item["conclusion"] as? String ?? "").uppercased()
        let verdict = conclusion.isEmpty ? (item["state"] as? String ?? "").uppercased() : conclusion
        switch verdict {
        case "SUCCESS", "NEUTRAL", "SKIPPED":
            return .passing
        case "FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE":
            return .failing
        default:
            return .pending // PENDING·EXPECTED·QUEUED·빈 값 등
        }
    }

    // MARK: 실행기

    /// gh 실행 파일 경로 — 흔한 설치 위치 + $PATH 탐색. 없으면 nil(전 경로 가드).
    private static let ghPath: String? = {
        let fm = FileManager.default
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh", "/opt/local/bin/gh"]
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return found }
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for d in envPath.split(separator: ":") {
                let p = "\(d)/gh"
                if fm.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }()

    /// gh를 백그라운드로 실행하고 stdout/stderr/exit을 캡처(FullResult 재사용).
    /// gh는 내부적으로 git을 부르므로 PATH에 gh 디렉토리와 시스템 경로를 넣어준다.
    private static func runGH(_ args: [String], in dir: String) async -> FullResult {
        guard let ghPath else { return FullResult(stdout: "", stderr: "gh not found", exitCode: -1) }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: ghPath)
                proc.arguments = args
                proc.currentDirectoryURL = URL(fileURLWithPath: dir)
                var env = ProcessInfo.processInfo.environment
                let ghDir = (ghPath as NSString).deletingLastPathComponent
                let base = env["PATH"] ?? ""
                env["PATH"] = "\(ghDir):/usr/bin:/bin\(base.isEmpty ? "" : ":" + base)"
                proc.environment = env
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                do {
                    try proc.run()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    cont.resume(returning: FullResult(
                        stdout: String(decoding: outData, as: UTF8.self),
                        stderr: String(decoding: errData, as: UTF8.self),
                        exitCode: proc.terminationStatus
                    ))
                } catch {
                    cont.resume(returning: FullResult(stdout: "", stderr: error.localizedDescription, exitCode: -1))
                }
            }
        }
    }
}
