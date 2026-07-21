import Foundation

/// 명령 실행 로그의 **영속 저장** — 실행 id(`CommandExecution.id`)마다 파일 하나. 세션이 사라져도(재시작·
/// tmux 정리) 과거 실행 출력을 다시 본다. 용량은 명령당 실행 10개(`CommandStore.execLimit`)로 상한이
/// 걸려 있고, 밀려난 실행 id는 `delete`로 함께 지운다(파일이 유령으로 남지 않게).
///
/// 순수 로직(`CommandStore`)과 분리된 **파일 IO 경계**다. 실패는 조용히 무시한다 — 로그는 보조 정보라
/// 저장·삭제가 실패해도 앱 동작을 막지 않는다.
enum CommandLogStore {
    /// 로그 디렉터리 — 빌드별 저장소 아래(state와 같은 격리: 개발/워크트리/릴리스가 각자).
    private static var directory: URL { MuxaSupportDir.subdirectory("command-logs") }

    private static func url(_ execId: String) -> URL {
        directory.appendingPathComponent("\(execId).log")
    }

    /// 실행 로그를 원자적으로 쓴다(빈 로그는 파일을 만들지 않는다).
    static func save(_ execId: String, _ log: String) {
        guard !log.isEmpty else { return }
        try? log.write(to: url(execId), atomically: true, encoding: .utf8)
    }

    /// 저장된 실행 로그(없으면 nil).
    static func load(_ execId: String) -> String? {
        try? String(contentsOf: url(execId), encoding: .utf8)
    }

    /// 밀려나거나 지워진 실행들의 로그 파일을 정리한다.
    static func delete(_ execIds: [String]) {
        for id in execIds { try? FileManager.default.removeItem(at: url(id)) }
    }
}
