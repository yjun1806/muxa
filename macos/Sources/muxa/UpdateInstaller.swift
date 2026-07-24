import Foundation

/// 자기-업데이트 실행(부작용 경계) — 소스 저장소에서 `pull → bootstrap → 재설치`를 **백그라운드**로 돌린다.
///
/// 화면에 터미널을 띄우지 않는다(사용자 선택). 진행은 안 보이고, 출력은 로그 파일로만 남겨 **실패 진단**에 쓴다.
/// **자동 재실행하지 않는다** — 새 `/Applications/muxa.app`이 자리에 놓이면 재시작은 사용자 몫이다.
///
/// 명령을 **로그인 셸(`$SHELL -l -c`)로 감싼다.** `.app`은 launchd가 띄워 로그인 셸 PATH를 상속하지
/// 않으므로(`/opt/homebrew/bin`이 없다), 감싸지 않으면 `git`·`swift`·`make`가 `command not found`로
/// 즉사한다 — TmuxService와 같은 이유·같은 방식.
enum UpdateInstaller {
    /// 업데이트 실패 — 사용자에게 보일 메시지 + (있으면) 로그 경로.
    struct Failure: Error {
        let message: String
        let logPath: String?
    }

    /// 업데이트 로그 파일 — 실패 팝오버가 "로그 보기"로 연다. 빌드별 지원 폴더(릴리스는 하나뿐).
    static var logURL: URL { MuxaSupportDir.url.appendingPathComponent("update.log") }

    /// 재빌드 명령 — pull(빠른 진행만·태그 포함) → 터미널 코어 확인 → release 빌드·설치.
    /// bootstrap은 이미 있으면 멱등(재다운로드 안 함), release-install은 `/Applications`를 덮어쓴다.
    ///
    /// **신뢰 모델**: `origin/main`을 그대로 빌드·실행한다 — 서명·체크섬 검증은 없다(자기 저장소를
    /// 소스로 쓰는 설치 방식의 본질). `--ff-only`라 로컬과 갈라지면 병합을 강제하지 않고 실패로 끝나며,
    /// 소스 루트는 muxa 저장소로 검증된다(`AppInfo.sourceRoot`). 즉 신뢰 경계는 **origin 원격**이다 —
    /// 원격이 탈취되면 다음 업데이트가 임의 코드를 실행할 수 있다(curl 재설치와 동일한 신뢰 수준).
    private static let command =
        "git pull --ff-only --tags && ./scripts/bootstrap.sh && make release-install"

    /// 소스 저장소에서 업데이트를 실행한다. 성공하면 정상 반환, 실패하면 `Failure`를 던진다.
    /// 표준 출력·에러는 로그 파일로 리다이렉트한다(화면에 안 보이므로 유일한 진단 통로).
    static func run(sourceRoot: String) async throws {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let logURL = self.logURL
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                // 매 실행마다 로그를 새로 연다 — 직전 실패 로그가 성공 로그와 섞이지 않게.
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                guard let handle = try? FileHandle(forWritingTo: logURL) else {
                    cont.resume(throwing: Failure(message: "로그 파일을 열 수 없습니다.", logPath: nil))
                    return
                }
                defer { try? handle.close() }

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: shell)
                proc.arguments = ["-l", "-c", command]
                proc.currentDirectoryURL = URL(fileURLWithPath: sourceRoot)
                proc.standardOutput = handle
                proc.standardError = handle
                do {
                    try proc.run()
                    proc.waitUntilExit()
                } catch {
                    cont.resume(throwing: Failure(
                        message: "업데이트 실행을 시작하지 못했습니다: \(error.localizedDescription)",
                        logPath: logURL.path))
                    return
                }
                guard proc.terminationStatus == 0 else {
                    cont.resume(throwing: Failure(
                        message: "재빌드가 실패했습니다 (코드 \(proc.terminationStatus)).",
                        logPath: logURL.path))
                    return
                }
                cont.resume(returning: ())
            }
        }
    }
}
