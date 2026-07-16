import Foundation

/// git remote URL → GitHub 슬러그(owner/repo) → owner 아바타 URL — **순수 파싱**.
///
/// 워크스페이스 아이콘을 orca처럼 리포에서 끌어온다: orca의 기본 리포 아이콘이 정확히 이 출처다
/// (`githubAvatarIcon` — `https://github.com/<owner>.png?size=64`). GitHub은 리포별 아이콘이 없어
/// **owner 아바타**가 리포 아이콘 관례다. github.com이 아니면(사내 GHE·GitLab·remote 없음) nil —
/// 폴백(레이어 글리프·이니셜)이 맡는다. 부작용 0 — 셸아웃은 `GitService.remoteURL`, 캐시는 AppState.
enum RepoRemote {
    struct Slug: Equatable {
        let owner: String
        let repo: String
    }

    /// remote URL에서 GitHub 슬러그를 뽑는다. 지원 형태:
    /// `git@github.com:owner/repo.git` · `ssh://git@github.com/owner/repo.git` · `https://github.com/owner/repo(.git)`.
    static func githubSlug(from remote: String) -> Slug? {
        let s = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let path: String
        if let scp = scpPath(s) {
            path = scp
        } else if let url = URL(string: s), url.host == "github.com" {
            path = url.path
        } else {
            return nil
        }
        var parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        if parts[1].hasSuffix(".git") { parts[1] = String(parts[1].dropLast(4)) }
        guard !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return Slug(owner: parts[0], repo: parts[1])
    }

    /// scp 형태(`[user@]github.com:path`) — `://`가 없고 콜론 앞 호스트가 github.com일 때만.
    private static func scpPath(_ s: String) -> String? {
        guard !s.contains("://"), let colon = s.firstIndex(of: ":") else { return nil }
        let hostPart = String(s[..<colon])
        let host = hostPart.split(separator: "@").last.map(String.init) ?? hostPart
        guard host == "github.com" else { return nil }
        return String(s[s.index(after: colon)...])
    }

    /// owner 아바타 URL(64px — 13~24pt 표시엔 retina까지 충분).
    static func avatarURL(_ slug: Slug) -> URL? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "github.com"
        comps.path = "/\(slug.owner).png"
        comps.queryItems = [URLQueryItem(name: "size", value: "64")]
        return comps.url
    }
}
