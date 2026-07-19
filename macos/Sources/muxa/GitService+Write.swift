import Foundation

/// git 쓰기 = **거부(버리기·되돌리기)만**. 읽기와 같은 CLI 셸아웃(GitService.run).
/// 결과는 exitCode로 성공 판정. FSEvents가 이후 상태를 자동 갱신한다.
///
/// **스테이징·커밋은 없다(의도).** muxa는 편집을 에이전트에게 맡기는 앱이라 사람이 커밋을 조립하지
/// 않는다 — 무엇을 바꿨는지 아는 쪽이 메시지도 더 잘 쓴다. 스테이징은 커밋을 조립하는 수단이라
/// 커밋이 없으면 존재 이유가 함께 사라진다. 사람이 굳이 커밋해야 하면 **바로 옆 칸 터미널**에서 한다.
///
/// 남은 쓰기는 전부 **리뷰 판정의 "거부" 반쪽**이다(ARCHITECTURE 4.4) — 그건 저작이 아니라 판정이고,
/// 파괴적이라 확인 시트가 붙은 UI가 터미널 타이핑보다 안전하다.
extension GitService {









    /// stdin으로 입력을 넣고 stderr까지 캡처하는 실행 변형(git apply 전용). 패치가 작아(파이프 버퍼 내)
    /// stdin을 먼저 다 쓰고 닫은 뒤 출력을 읽어 데드락을 피한다.
    static func runWithStdin(_ args: [String], stdin input: String, in dir: String) async -> FullResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = gitArgs(args)
                proc.currentDirectoryURL = URL(fileURLWithPath: dir)
                let inPipe = Pipe()
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardInput = inPipe
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                do {
                    try proc.run()
                    if let data = input.data(using: .utf8) {
                        try? inPipe.fileHandleForWriting.write(contentsOf: data)
                    }
                    try? inPipe.fileHandleForWriting.close()
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
