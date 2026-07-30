import Foundation

/// `AgentChangeSet`의 영속 경계 — 파일 IO만. 판정(`orphans`)은 순수 함수로 떼어내 테스트한다.
///
/// **키는 탭 id가 아닐 수 있다.** 지속(∞) 탭은 tmux 세션명을 키로 쓴다 — `reattach`가
/// 백그라운드 세션을 되찾을 때 새 `TabID`에 기존 세션 이름을 물려주므로, 탭 id로 파일을 잡으면
/// 되찾은 순간 기록이 고아가 된다(`IdeSessionLedger`가 같은 지점에서 받은 리뷰 지적 I-1).
/// 일반 탭은 `TabID` 문자열을 그대로 쓴다.
enum AgentChangeStore {
    static let directory: URL = MuxaSupportDir.subdirectory("agent-changes")

    /// GC의 mtime 유예 — 방금 쓰였는데 아직 스냅샷에 안 실린 파일을 실수로 지우지 않게
    /// 유예 안쪽에 수정된 파일은 무조건 보존한다(`ScrollbackStore`와 같은 값·같은 이유).
    static let orphanGraceInterval: TimeInterval = 3600

    // MARK: 키 검증

    /// 키가 파일명으로 안전한가 — **화이트리스트**.
    ///
    /// 키는 그대로 파일명이 되므로 경로 구분자·상위참조가 통과하면 지정 폴더 밖에 쓰게 된다.
    /// 실제로 쓰는 값(tmux 세션명 `muxa__…__term__…`, `TabID` UUID)은 형식이 알려져 있으니
    /// 형식으로 검증한다 — 금지 문자를 세는 블랙리스트는 늘 빠뜨린다
    /// (`ClaudeSessionIndex.isSafeSessionId`가 같은 이유로 UUID 형식만 통과시킨다).
    static func isSafeKey(_ key: String) -> Bool {
        guard !key.isEmpty, key != ".", key != ".." else { return false }
        return key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    }

    /// 키의 저장 경로. 안전하지 않은 키는 nil — 쓰지도, 읽지도 않는다.
    static func fileURL(for key: String, in directory: URL = Self.directory) -> URL? {
        guard isSafeKey(key) else { return nil }
        return directory.appendingPathComponent("\(key).json")
    }

    // MARK: 읽기·쓰기

    /// 원자적으로 쓴다 — 쓰는 중에 앱이 죽어도 반쪽 JSON이 남지 않는다.
    /// 호출은 디바운스를 거친다(`FileWatcher`의 trailing 0.5s / maxWait 1.5s) — 여기서는 매번 쓴다.
    static func write(_ set: AgentChangeSet, key: String, in directory: URL = Self.directory) {
        guard let url = fileURL(for: key, in: directory),
              let data = try? JSONEncoder().encode(set) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// 없거나 깨졌으면 nil — 파싱 실패로 앱을 죽이지 않는다(기록 하나를 잃을 뿐이다).
    static func load(key: String, in directory: URL = Self.directory) -> AgentChangeSet? {
        guard let url = fileURL(for: key, in: directory),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentChangeSet.self, from: data)
    }

    /// 탭이 **kill로** 닫힐 때 호출. 백그라운드 keep은 세션이 살아 있으므로 지우지 않는다.
    static func delete(key: String, in directory: URL = Self.directory) {
        guard let url = fileURL(for: key, in: directory) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: 고아 파일 GC

    /// GC 판정 입력(순수) — 경로·키(파일명에서 확장자 제거)·수정시각.
    struct ChangeFile: Equatable {
        let path: String
        let key: String
        let modified: Date
    }

    /// 삭제해도 안전한 고아 경로를 고른다(순수). 보존 조건 — 하나라도 참이면 남긴다:
    ///  1) 살아있는 탭·세션의 파일 (key ∈ liveKeys)
    ///  2) 스냅샷이 아직 참조하는 파일 (path ∈ referencedPaths) — 아직 안 연 lazy 프로젝트 보존
    ///  3) 유예 안쪽에 수정됨 — 방금 쓰였는데 아직 참조에 안 실린 파일 방어
    static func orphans(in files: [ChangeFile], liveKeys: Set<String>,
                        referencedPaths: Set<String>, now: Date,
                        graceInterval: TimeInterval) -> [String] {
        files.filter { file in
            if liveKeys.contains(file.key) { return false }
            if referencedPaths.contains(file.path) { return false }
            if now.timeIntervalSince(file.modified) < graceInterval { return false }
            return true
        }.map(\.path)
    }

    /// 복원이 끝난 뒤 호출. 스캔·삭제(부작용)만 여기, 판정은 `orphans`에 위임한다.
    /// **판정 못 하면(스캔 실패) 아무것도 안 지운다.**
    static func collectGarbage(liveKeys: Set<String>, referencedPaths: Set<String>,
                              now: Date = Date(),
                              graceInterval: TimeInterval = orphanGraceInterval,
                              in directory: URL = Self.directory) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let files: [ChangeFile] = entries.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            // mtime을 못 읽으면 distantFuture로 둬(=항상 유예 안쪽) 삭제 대상이 안 되게 한다.
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? Date.distantFuture
            return ChangeFile(path: url.path,
                              key: url.deletingPathExtension().lastPathComponent,
                              modified: modified)
        }
        for path in orphans(in: files, liveKeys: liveKeys, referencedPaths: referencedPaths,
                            now: now, graceInterval: graceInterval) {
            try? fm.removeItem(at: URL(fileURLWithPath: path))
        }
    }
}
