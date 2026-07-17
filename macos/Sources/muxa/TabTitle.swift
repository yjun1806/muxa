import Foundation

/// 터미널 탭 제목 다듬기 — 순수 로직.
///
/// 셸이 보내는 제목(OSC 0/2)은 보통 `user@host:~/path/to/dir` 꼴이라 탭 폭(수십~200pt)에 절대 안 들어간다.
/// 사람이 탭을 구분할 때 쓰는 건 사용자명·호스트명이 아니라 **마지막 폴더 이름**이므로 그것만 남긴다.
/// 이 형식이 아니면(에이전트가 실행 중이라 명령명을 보내는 경우 등) 손대지 않는다.
enum TabTitle {
    static func shorten(_ raw: String) -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // "user@host:path" 형태인지 — 콜론 앞이 공백 없는 `user@host` 한 덩어리여야 셸 기본 제목으로 본다.
        // (@만 보면 "vim user@host:config" 같은 명령 제목까지 잘라내 버린다.)
        guard let colon = title.firstIndex(of: ":") else { return title }
        let prefix = title[title.startIndex..<colon]
        guard prefix.contains("@"), !prefix.contains(" ") else { return title }

        let path = title[title.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return title }
        if path == "~" || path == "/" { return path } // 홈·루트는 그 자체가 이름

        let last = path.split(separator: "/").last.map(String.init)
        return last.flatMap { $0.isEmpty ? nil : $0 } ?? path
    }

    /// 지속 세션(∞) 탭의 **표시 제목** 장식 — 앞에 "∞ "를 단다(멱등).
    ///
    /// 탭의 왼쪽 슬롯은 하나뿐이라 에이전트 상태 마크(스피너·⏸·✓)가 뜨는 동안 ∞ 아이콘이 밀려난다 —
    /// 에이전트 탭은 대부분의 시간이 그 상태여서 "어느 탭이 tmux 안인가"가 사실상 안 보였다(실측 불만).
    /// 제목은 상태 마크와 경쟁하지 않는 채널이므로 여기에 싣는다.
    ///
    /// **원본 저장소(manualTitles·engineTitles)에는 넣지 않는다** — 로직(tabTitle)·스냅샷·detached 기록이
    /// 읽는 원본은 무장식으로 두고, Bonsplit으로 나가는 경계에서만 장식한다(이중 접두·기록 오염 방지).
    /// 멱등 가드: 사용자가 손수 "∞ "로 시작하는 이름을 지어도 겹으로 붙이지 않는다.
    static let persistentPrefix = "∞ "

    static func decorate(_ title: String, persistent: Bool) -> String {
        guard persistent, !title.hasPrefix(persistentPrefix) else { return title }
        return persistentPrefix + title
    }
}
