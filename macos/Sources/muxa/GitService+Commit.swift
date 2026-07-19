import Foundation

/// 커밋 하나의 **구조화된** 파일 내역 — 히스토리·리뷰 탭의 커밋 펼침이 쓴다.
///
/// 기존 `commitDiff`(`show --stat -p`)는 사람이 읽는 **텍스트 덩어리**라 목록으로 못 쓴다.
/// 여기서 상태·경로·줄 수를 값으로 뽑아 패널이 행으로 그릴 수 있게 한다.
extension GitService {

    /// 커밋이 건드린 파일 목록. git 저장소가 아니거나 해시가 유효하지 않으면 빈 배열.
    ///
    /// **왜 두 번 부르나** — `--name-status`와 `--numstat`을 한 명령에 같이 주면 뒤엣것이 앞엣것을
    /// 덮어써서 하나만 나온다(실측). 둘을 **병렬로** 띄우고 경로로 잇는다(`GitCommitFileParse.merge`).
    /// 커밋은 불변이라 호출부가 해시로 캐시하면 이 왕복은 커밋당 한 번뿐이다.
    ///
    /// `-M`(리네임 추적)을 주므로 대량 이동 커밋이 `D`+`A` 쌍이 아니라 `R` 한 줄로 온다.
    static func commitFiles(_ hash: String, in dir: String) async -> [GitCommitFile] {
        async let statusOut = run(["show", "--no-color", "--format=", "--name-status", "-M", hash], in: dir)
        async let statOut = run(["show", "--no-color", "--format=", "--numstat", "-M", hash], in: dir)
        let (s, n) = await (statusOut, statOut)
        guard s.exitCode == 0 else { return [] }
        return GitCommitFileParse.merge(nameStatus: s.stdout, numstat: n.stdout)
    }

    /// 커밋 안 **파일 하나**의 diff — 커밋 파일 행 클릭이 여는 것.
    /// 통짜 `commitDiff`와 달리 한 파일만 담아 좁은 리뷰 동선에 맞는다.
    ///
    /// 리네임이면 옛 경로도 함께 넘겨야 diff가 빈다 — git은 리네임된 파일을 새 경로만으로는
    /// 그 커밋에서 못 찾는 경우가 있다(`--follow` 없이는 경로 필터가 문자 그대로다).
    static func commitFileDiff(hash: String, path: String, oldPath: String? = nil,
                               in dir: String) async -> String {
        var args = ["show", "--no-color", "--format=", "-M", hash, "--"]
        args.append(path)
        if let oldPath, oldPath != path { args.append(oldPath) }
        return await run(args, in: dir).stdout
    }

    /// 특정 리비전의 파일 **내용**(`git show <rev>:<path>`) — 문서 diff의 옛/새 원문.
    ///
    /// 워크트리를 안 보므로 **원본 파일이 지워졌어도** 과거 문서를 렌더할 수 있다.
    /// 그 리비전에 파일이 없으면(생성 직전 부모, 루트 커밋의 `^` 등) **빈 문자열**을 준다 —
    /// nil과 갈라 두지 않는 이유는 문서 diff에서 "없음"과 "빈 문서"가 같은 뜻이기 때문이다.
    static func fileAtRevision(rev: String, path: String, in dir: String) async -> String {
        let r = await run(["show", "--no-color", "\(rev):\(path)"], in: dir)
        return r.exitCode == 0 ? r.stdout : ""
    }

    /// 파일 하나의 blob 해시(그 커밋 시점의 내용 신원) — 파일별 리뷰 상태가 "그 후 또 바뀌었나"를
    /// 판정하는 키다. 경로만으로 잡으면 에이전트가 같은 파일을 또 고쳤을 때 "봤음"이 잘못 유지된다.
    /// 파일이 그 리비전에 없으면 nil.
    static func blobHash(path: String, rev: String = "HEAD", in dir: String) async -> String? {
        let r = await run(["rev-parse", "\(rev):\(path)"], in: dir)
        guard r.exitCode == 0 else { return nil }
        let h = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return h.isEmpty ? nil : h
    }

    /// 워크트리에 있는 **현재** 파일 내용의 blob 해시 — 커밋 안 된 변경까지 반영한다.
    /// `rev-parse HEAD:path`는 커밋된 내용만 보므로, 리뷰 중 에이전트가 파일을 또 고친 걸
    /// 잡으려면 이쪽이어야 한다. 파일이 없으면(삭제됨) nil.
    static func worktreeBlobHash(path: String, in dir: String) async -> String? {
        let full = (dir as NSString).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: full) else { return nil }
        let r = await run(["hash-object", "--", path], in: dir)
        guard r.exitCode == 0 else { return nil }
        let h = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return h.isEmpty ? nil : h
    }
}
