import Foundation
import Testing
@testable import muxa

/// 수집 기록 → 화면. `PreToolUse`는 실행 **전** 신호라 거부·실패한 편집도 섞여 있고,
/// 훅은 `Bash` 경유 변경을 아예 못 본다 — 그 둘을 git·mtime과 교차해 접는 판정이 여기 있다.
struct AgentChangeGroupTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)
    private let t2 = Date(timeIntervalSince1970: 3_000)

    private func entry(_ path: String, first: Date, last: Date, seen: Date? = nil) -> AgentChangeEntry {
        AgentChangeEntry(path: path, firstTouchedAt: first, lastTouchedAt: last,
                         touchCount: 1, lastSessionId: nil, seenAt: seen)
    }

    // MARK: 읽음 판정

    @Test func 한_번도_안_열었으면_안_봤음이다() {
        #expect(AgentChangeDisplay.isUnread(entry: entry("/a", first: t0, last: t0), mtime: t0))
    }

    @Test func 열어봤고_그_뒤_안_바뀌면_봤음이다() {
        let e = entry("/a", first: t0, last: t0, seen: t1)
        #expect(!AgentChangeDisplay.isUnread(entry: e, mtime: t0))
    }

    @Test func 봤어도_에이전트가_다시_고치면_안_봤음으로_돌아온다() {
        let e = entry("/a", first: t0, last: t2, seen: t1)
        #expect(AgentChangeDisplay.isUnread(entry: e, mtime: t0))
    }

    /// 훅은 `Bash`(sed·스크립트)로 한 변경을 못 본다 — `lastTouchedAt`만 믿으면
    /// **실제로 바뀐 파일이 "봤음"으로 남는다**. 이 기능에서 가장 나쁜 실패다.
    @Test func 훅이_못_본_변경도_mtime이_잡는다() {
        let e = entry("/a", first: t0, last: t0, seen: t1)   // 훅 기준으론 t0에서 멈췄다
        #expect(AgentChangeDisplay.isUnread(entry: e, mtime: t2), "mtime이 더 최신이면 다시 봐야 한다")
    }

    @Test func mtime을_모르면_훅_기록만으로_판정한다() {
        #expect(!AgentChangeDisplay.isUnread(entry: entry("/a", first: t0, last: t0, seen: t1), mtime: nil))
        #expect(AgentChangeDisplay.isUnread(entry: entry("/a", first: t0, last: t2, seen: t1), mtime: nil))
    }

    // MARK: 억제 판정 — 시도했으나 안 바뀐 것

    @Test func git이_아는_변경은_억제하지_않는다() {
        #expect(!AgentChangeDisplay.isSuppressed(entry: entry("/a", first: t1, last: t1),
                                                 status: "M", mtime: nil))
    }

    /// 승인이 거부된 편집 — 파일이 아예 안 생겼다.
    @Test func 파일이_없으면_억제한다() {
        #expect(AgentChangeDisplay.isSuppressed(entry: entry("/a", first: t1, last: t1),
                                                status: nil, mtime: nil))
    }

    /// 내용이 같아 no-op이었다 — 만지기 **전** 시각 그대로다.
    @Test func 만지기_전_상태_그대로면_억제한다() {
        #expect(AgentChangeDisplay.isSuppressed(entry: entry("/a", first: t1, last: t1),
                                                status: nil, mtime: t0))
    }

    /// git은 조용한데 디스크는 우리가 만진 뒤로 바뀌었다 = 커밋됐다. 억제하지 않는다.
    @Test func 커밋된_변경은_억제하지_않는다() {
        #expect(!AgentChangeDisplay.isSuppressed(entry: entry("/a", first: t0, last: t1),
                                                 status: nil, mtime: t1))
        #expect(AgentChangeDisplay.mark(status: nil) == .committed)
    }

    @Test func git_상태가_있으면_그_문자를_쓴다() {
        #expect(AgentChangeDisplay.mark(status: "A") == .git("A"))
    }

    // MARK: 그룹 조립

    private func set(_ paths: [(String, Date)], origin: String? = nil) -> AgentChangeSet {
        var s = AgentChangeSet()
        for (p, at) in paths { s.record(path: p, sessionId: nil, prompt: origin, at: at) }
        return s
    }

    @Test func 최근_만진_순으로_정렬한다() {
        let s = set([("/old.swift", t0), ("/new.swift", t2), ("/mid.swift", t1)])
        let g = AgentChangeDisplay.group(from: s, status: ["/old.swift": "M", "/new.swift": "M", "/mid.swift": "M"],
                                        mtimes: [:])
        #expect(g.rows.map(\.path) == ["/new.swift", "/mid.swift", "/old.swift"])
    }

    /// 안 본 것이 머리에 **연속 블록**으로 모여야 "위에서 몇 줄까지"로 스캔이 끝난다.
    /// 굵기 차이만으로는 50행 목록을 훑을 기준선이 안 된다.
    @Test func 안_본_것이_최근순보다_먼저다() {
        var s = AgentChangeSet()
        s.record(path: "/new-seen.swift", sessionId: nil, prompt: nil, at: t2)   // 최신인데 봤음
        s.record(path: "/old-unread.swift", sessionId: nil, prompt: nil, at: t0) // 오래됐는데 안 봄
        s.markSeen(path: "/new-seen.swift", at: t2)

        let st = ["/new-seen.swift": Character("M"), "/old-unread.swift": "M"]
        let g = AgentChangeDisplay.group(from: s, status: st, mtimes: [:])
        #expect(g.rows.map(\.path) == ["/old-unread.swift", "/new-seen.swift"])
    }

    /// 딕셔너리 순회는 불안정하다 — 같은 시각이면 경로로 갈라 순서를 고정한다.
    @Test func 같은_시각이면_순서가_결정적이다() {
        let s = set([("/b.swift", t0), ("/a.swift", t0), ("/c.swift", t0)])
        let st = ["/a.swift": Character("M"), "/b.swift": "M", "/c.swift": "M"]
        let first = AgentChangeDisplay.group(from: s, status: st, mtimes: [:]).rows.map(\.path)
        let again = AgentChangeDisplay.group(from: s, status: st, mtimes: [:]).rows.map(\.path)
        #expect(first == ["/a.swift", "/b.swift", "/c.swift"])
        #expect(first == again)
    }

    @Test func 억제된_행은_목록에_없다() {
        var s = AgentChangeSet()
        s.record(path: "/real.swift", sessionId: nil, prompt: nil, at: t1)
        s.record(path: "/rejected.swift", sessionId: nil, prompt: nil, at: t1)

        let g = AgentChangeDisplay.group(from: s, status: ["/real.swift": "M"], mtimes: [:])
        #expect(g.rows.map(\.path) == ["/real.swift"])
        #expect(g.unreadCount == 1, "억제된 것은 안 본 개수에도 안 든다")
    }

    @Test func 제목은_얼린_첫_프롬프트다() {
        let s = set([("/a.swift", t0)], origin: "diff 뷰어 연결 설계")
        #expect(AgentChangeDisplay.group(from: s, status: ["/a.swift": "M"], mtimes: [:]).title
                == "diff 뷰어 연결 설계")
    }

    // MARK: 상한 — 접기와 잘림은 다른 사건이다

    @Test func 상한을_넘으면_지우지_않고_접는다() {
        let paths = (0..<5).map { ("/f\($0).swift", t0.addingTimeInterval(Double($0))) }
        let s = set(paths)
        let st = Dictionary(uniqueKeysWithValues: paths.map { ($0.0, Character("M")) })

        let g = AgentChangeDisplay.group(from: s, status: st, mtimes: [:], limit: 2)
        #expect(g.rows.count == 2)
        #expect(g.hiddenCount == 3)
    }

    /// 접힌 행에 안 본 게 있는데 배지가 침묵하면 "다 봤다"로 읽힌다 — 보이는 것 전부를 센다.
    @Test func 안_본_개수는_접힌_행까지_센다() {
        let paths = (0..<5).map { ("/f\($0).swift", t0) }
        let s = set(paths)
        let st = Dictionary(uniqueKeysWithValues: paths.map { ($0.0, Character("M")) })

        let g = AgentChangeDisplay.group(from: s, status: st, mtimes: [:], limit: 2)
        #expect(g.unreadCount == 5)
    }

    /// 천장에 닿아 **못 받은** 것과 화면에서 **접은** 것은 다른 사건이라 따로 말한다.
    @Test func 잘림은_접힘과_따로_전달된다() {
        var s = AgentChangeSet()
        s.record(path: "/a.swift", sessionId: nil, prompt: nil, at: t0, ceiling: 1)
        s.record(path: "/b.swift", sessionId: nil, prompt: nil, at: t0, ceiling: 1)

        let g = AgentChangeDisplay.group(from: s, status: ["/a.swift": "M"], mtimes: [:])
        #expect(g.truncatedCount == 1)
        #expect(g.hiddenCount == 0)
    }

    // MARK: 참고 목록

    // MARK: 참고 폴더 그룹핑

    private func refSet(_ paths: [String]) -> AgentChangeSet {
        var s = AgentChangeSet()
        for p in paths {
            s.record(reference: AgentReference(kind: .file, value: p, lastSeenAt: t0), at: t0)
        }
        return s
    }

    @Test func 폴더별로_묶고_알파벳순으로_세운다() {
        let s = refSet(["/repo/src/b.js", "/repo/docs/a.md", "/repo/src/a.js"])
        let folders = AgentChangeDisplay.referenceFolders(from: s, root: "/repo")
        #expect(folders.map(\.label) == ["docs", "src"])
        #expect(folders[1].files.map { basename($0.value) } == ["a.js", "b.js"])
    }

    @Test func 루트_바로_아래는_루트로_적는다() {
        #expect(AgentChangeDisplay.folderLabel(for: "/repo/README.md", root: "/repo") == "루트")
        #expect(AgentChangeDisplay.folderLabel(for: "/repo/docs/x.md", root: "/repo/") == "docs")
    }

    /// 저장소 밖(설정·임시 파일)도 읽는다 — 홈은 `~`로 접어 길이를 줄인다.
    @Test func 저장소_밖은_홈을_접는다() {
        let home = NSHomeDirectory()
        #expect(AgentChangeDisplay.folderLabel(for: "\(home)/notes/x.md", root: "/repo") == "~/notes")
        #expect(AgentChangeDisplay.folderLabel(for: "/etc/hosts", root: "/repo") == "/etc")
    }

    @Test func 루트를_모르면_절대경로로_적는다() {
        #expect(AgentChangeDisplay.folderLabel(for: "/a/b/c.md", root: nil) == "/a/b")
    }

    /// 웹 항목은 폴더 그룹핑 대상이 아니다.
    @Test func 폴더_그룹핑은_파일만_담는다() {
        var s = refSet(["/repo/a.md"])
        s.record(reference: AgentReference(kind: .web, value: "https://x.test/", lastSeenAt: t0), at: t0)
        let folders = AgentChangeDisplay.referenceFolders(from: s, root: "/repo")
        #expect(folders.flatMap(\.files).count == 1)
    }

    /// 읽기만 한 세션도 제목이 있어야 한다 — 예전엔 편집 기록에서만 얼려서 이름이 없었다.
    @Test func 읽기만_해도_제목이_얼린다() {
        var s = AgentChangeSet()
        s.freezeOrigin("이 저장소 구조 파악해줘")
        s.record(reference: AgentReference(kind: .file, value: "/a.md", lastSeenAt: t0), at: t0)
        #expect(s.originPrompt == "이 저장소 구조 파악해줘")
        #expect(s.entries.isEmpty, "읽기는 변경 목록을 채우지 않는다")
    }

    @Test func 제목은_한_번만_얼린다() {
        var s = AgentChangeSet()
        s.freezeOrigin("첫 지시")
        s.freezeOrigin("나중 지시")
        #expect(s.originPrompt == "첫 지시")
    }

    @Test func 빈_프롬프트는_제목을_차지하지_않는다() {
        var s = AgentChangeSet()
        s.freezeOrigin(nil)
        s.freezeOrigin("")
        s.freezeOrigin("진짜 지시")
        #expect(s.originPrompt == "진짜 지시")
    }

    // MARK: 맥락

    /// 목록만으로는 "왜 이걸 봤지"가 안 풀린다 — 그 턴의 프롬프트를 함께 남긴다.
    @Test func 맥락이_함께_기록된다() {
        let ref = AgentChangeSet.reference(toolName: "Read", input: ["file_path": "/a/x.md"],
                                           cwd: nil, context: "초록 벽 걷어내줘", at: t0)
        #expect(ref?.context == "초록 벽 걷어내줘")
    }

    /// 프롬프트를 못 읽은 턴이 이미 아는 맥락을 지우면 안 된다.
    @Test func 맥락_없는_재방문은_기존_맥락을_지우지_않는다() {
        var s = AgentChangeSet()
        s.record(reference: AgentReference(kind: .file, value: "/a.md", lastSeenAt: t0,
                                           context: "첫 맥락"), at: t0)
        s.record(reference: AgentReference(kind: .file, value: "/a.md", lastSeenAt: t1,
                                           context: nil), at: t1)
        #expect(s.references.values.first?.context == "첫 맥락")
    }

    @Test func 참고는_종류별로_갈라_최근순이다() {
        var s = AgentChangeSet()
        s.record(reference: AgentReference(kind: .file, value: "/a/DESIGN.md", lastSeenAt: t0), at: t0)
        s.record(reference: AgentReference(kind: .file, value: "/a/STATUS.md", lastSeenAt: t2), at: t2)
        s.record(reference: AgentReference(kind: .web, value: "https://x.test/", lastSeenAt: t1), at: t1)

        #expect(AgentChangeDisplay.references(from: s, kind: .file).map(\.value)
                == ["/a/STATUS.md", "/a/DESIGN.md"])
        #expect(AgentChangeDisplay.references(from: s, kind: .web).map(\.value) == ["https://x.test/"])
    }
}
