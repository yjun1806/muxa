import Testing
@testable import muxa

/// git remote URL → GitHub 슬러그·아바타 URL 순수 파싱(워크스페이스 리포 아이콘의 판정층).
struct RepoRemoteTests {
    @Test func scp_형태를_파싱한다() {
        #expect(RepoRemote.githubSlug(from: "git@github.com:yjun1806/muxa.git")
            == RepoRemote.Slug(owner: "yjun1806", repo: "muxa"))
    }

    @Test func https_형태를_git_확장자_유무와_무관하게_파싱한다() {
        let expected = RepoRemote.Slug(owner: "owner", repo: "repo")
        #expect(RepoRemote.githubSlug(from: "https://github.com/owner/repo.git") == expected)
        #expect(RepoRemote.githubSlug(from: "https://github.com/owner/repo") == expected)
        #expect(RepoRemote.githubSlug(from: "https://github.com/owner/repo/") == expected)
    }

    @Test func ssh_스킴_형태를_파싱한다() {
        #expect(RepoRemote.githubSlug(from: "ssh://git@github.com/owner/repo.git")
            == RepoRemote.Slug(owner: "owner", repo: "repo"))
    }

    /// GitHub이 아니면 nil — 폴백 글리프가 맡는다(GitLab·사내 GHE·빈 값 전부).
    @Test func 비_GitHub은_nil() {
        #expect(RepoRemote.githubSlug(from: "git@gitlab.com:owner/repo.git") == nil)
        #expect(RepoRemote.githubSlug(from: "https://gitlab.com/owner/repo.git") == nil)
        #expect(RepoRemote.githubSlug(from: "git@ghe.corp.com:owner/repo.git") == nil)
        #expect(RepoRemote.githubSlug(from: "") == nil)
        #expect(RepoRemote.githubSlug(from: "   ") == nil)
        #expect(RepoRemote.githubSlug(from: "/local/path/repo") == nil)
    }

    @Test func 슬러그가_불완전하면_nil() {
        #expect(RepoRemote.githubSlug(from: "https://github.com/owneronly") == nil)
        #expect(RepoRemote.githubSlug(from: "git@github.com:") == nil)
    }

    @Test func 아바타_URL은_owner_기준이다() {
        let slug = RepoRemote.Slug(owner: "yjun1806", repo: "muxa")
        #expect(RepoRemote.avatarURL(slug)?.absoluteString == "https://github.com/yjun1806.png?size=64")
    }
}
