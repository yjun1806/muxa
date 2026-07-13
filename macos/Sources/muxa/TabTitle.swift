import Foundation

/// 터미널 탭 제목 다듬기 — 순수 로직.
///
/// 셸이 보내는 제목(OSC 0/2)은 보통 `user@host:~/path/to/dir` 꼴이라 탭 폭(수십~200pt)에 절대 안 들어간다.
/// 사람이 탭을 구분할 때 쓰는 건 사용자명·호스트명이 아니라 **마지막 폴더 이름**이므로 그것만 남긴다.
/// 이 형식이 아니면(에이전트가 실행 중이라 명령명을 보내는 경우 등) 손대지 않는다.
enum TabTitle {
    static func shorten(_ raw: String) -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // "user@host:path" 형태인지 — 콜론 앞에 @가 있어야 셸 기본 제목으로 본다.
        guard let colon = title.firstIndex(of: ":"),
              title[title.startIndex..<colon].contains("@") else { return title }

        let path = title[title.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return title }
        if path == "~" || path == "/" { return path } // 홈·루트는 그 자체가 이름

        let last = path.split(separator: "/").last.map(String.init)
        return last.flatMap { $0.isEmpty ? nil : $0 } ?? path
    }
}
