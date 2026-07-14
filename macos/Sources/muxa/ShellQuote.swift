import Foundation

/// 셸 명령 문자열에 값을 안전하게 끼워 넣는 인용(순수).
///
/// muxa는 사용자 경로·env 값·tmux 실행 파일 경로를 `sh -c '…'`나 셸 stdin 주입 문자열에 보간한다.
/// 값 안의 작은따옴표를 탈출하지 않으면 따옴표가 조기에 닫혀 명령이 깨지거나(예: `~/Bob's app`),
/// `'; rm -rf … ; '`처럼 임의 명령이 주입된다. 표준 POSIX 관용구 `'\''`로 감싼다.
enum ShellQuote {
    /// 값을 작은따옴표로 감싸고 내부 `'`를 `'\''`로 탈출한다. 반환값은 따옴표를 포함한 완성된 토큰이다.
    static func single(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
