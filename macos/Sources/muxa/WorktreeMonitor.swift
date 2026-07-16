import Foundation
import Observation

/// 워크트리 감지(경계) — 각 워크스페이스의 공통 `.git`을 **FSEvents로 감시**(폴링 아님)하고, 변화가 오면
/// `git worktree list`를 다시 읽어 `detected`를 갱신한다. 결정·근거는 ARCHITECTURE D31.
///
/// **승격하지 않는다.** 감지만 값으로 노출하고, "추가?" 제안·baseline은 AppState가 소유한다(orca 인박스 모델의
/// 경량 이식). `FileWatcher`(0.3s latency + 디바운스)를 재사용해 준실시간·idle 0 — 이벤트가 폭주해도
/// 디바운스가 flush 1회 = worktreeList 1회로 묶어 비용이 상한에 걸린다(FileWatcher의 npm-install 방어와 동일).
@MainActor
@Observable
final class WorktreeMonitor {
    /// workspaceId → 현재 디스크의 워크트리 목록. 인박스 offer 계산의 원천(관측 대상 — 뷰가 반응).
    private(set) var detected: [String: [GitWorktree]] = [:]

    /// 공통 `.git`이 움직일 때마다(디바운스 후) 부른다 — 목록 변화 여부와 무관하게 1회.
    /// 승격은 여전히 안 한다(감지만). "폴더가 사라졌나" 같은 **디스크 파생 재판정**을 AppState가 걸 훅일 뿐이다.
    @ObservationIgnored var onChange: (() -> Void)?

    private struct Entry {
        let watcher: FileWatcher
        let listDir: String   // repo 루트(worktree list 실행 기준)
        let sourceDir: String // 이 감시자를 만든 워크스페이스 경로 — 경로가 바뀌면 재attach 판별에 쓴다
    }
    @ObservationIgnored private var entries: [String: Entry] = [:]
    /// id → 감시할 워크스페이스 경로(sync가 갱신하는 **의도** 상태). attach가 await 뒤 "아직 이 dir을 원하나"를
    /// 이걸로 확인해 제거된 워크스페이스에 orphan 감시자가 붙는 것을 막는다(리뷰).
    @ObservationIgnored private var wanted: [String: String] = [:]

    /// 현재 워크스페이스 집합에 감시자를 맞춘다(멱등) — 새 repo엔 붙이고, 사라졌거나 **경로가 바뀐** 건 뗀다.
    /// 경로 없는 워크스페이스는 건너뛴다(git 실행할 dir이 없다). 워크스페이스 add/remove/경로변경/복제 시 AppState가 부른다.
    func sync(_ workspaces: [Workspace]) {
        wanted = workspaces.reduce(into: [:]) { if let p = $1.path { $0[$1.id] = p } }
        // 떼기: 사라졌거나(제거·경로 nil) **경로가 바뀐** 워크스페이스 — id만 보면 repo 변경(같은 id·다른 repo)을 놓친다.
        for (id, entry) in entries where wanted[id] != entry.sourceDir {
            entries[id] = nil   // FileWatcher deinit → FSEvents 스트림 해제
            detected[id] = nil
        }
        // 붙이기: 감시 대상인데 아직 없는 것.
        for (id, dir) in wanted where entries[id] == nil {
            Task { await attach(id, dir: dir) }
        }
    }

    /// git 공통 `.git`에 FileWatcher를 걸고 즉시 1회 스캔한다. git 저장소가 아니면 감시하지 않는다.
    private func attach(_ id: String, dir: String) async {
        guard entries[id] == nil else { return } // 레이스: 이미 붙음
        guard let gitDir = await GitService.gitCommonDir(in: dir),
              let listDir = await GitService.repoRoot(in: dir) else { return }
        // await 사이에 워크스페이스가 제거되거나(orphan 방지) 경로가 바뀌거나 이미 붙었으면 그만둔다.
        guard wanted[id] == dir, entries[id] == nil else { return }
        let watcher = FileWatcher(path: gitDir)
        watcher.onFlush = { [weak self] in
            Task { await self?.rescan(id, listDir: listDir) }
        }
        entries[id] = Entry(watcher: watcher, listDir: listDir, sourceDir: dir)
        await rescan(id, listDir: listDir) // 붙는 즉시 1회 — 이미 있는 워크트리(외부 생성분 포함)도 반영
    }

    /// 워크트리 목록을 다시 읽어 바뀌었을 때만 `detected`를 갱신한다.
    private func rescan(_ id: String, listDir: String) async {
        guard entries[id] != nil else { return } // 떨어진 뒤 늦게 온 rescan 무시
        let trees = await GitService.worktreeList(in: listDir)
        // 빈 목록 = git 일시 실패다(실 저장소는 언제나 메인 워크트리 ≥1개). known-good을 []로 덮지 않는다.
        guard !trees.isEmpty else { return }
        guard entries[id] != nil else { return }
        // path+branch로 비교 — 경로 그대로 브랜치만 바뀐 워크트리도 갱신한다(offer 라벨=브랜치).
        func key(_ list: [GitWorktree]) -> [String] { list.map { $0.path + "\u{0}" + ($0.branch ?? "") } }
        if detected[id].map({ key($0) }) != key(trees) {
            detected[id] = trees   // 목록이 실제로 바뀐 경우만 관측 상태 갱신(뷰 반응)
        }
        // 목록 불변이어도 .git이 움직였으니 배지 재판정은 돌린다 — git 없이 폴더만 지워졌을 때(worktree list엔
        // 아직 남지만 실폴더는 사라진 경우)까지 잡는다. reconcile은 stat 몇 번이라 값싸고 디바운스로 묶인다.
        onChange?()
    }
}
