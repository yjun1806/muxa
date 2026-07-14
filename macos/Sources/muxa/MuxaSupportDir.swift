import Foundation

/// muxa의 Application Support 베이스 디렉터리(`~/Library/Application Support/muxa`).
/// 세션 상태(state.v4.json)·스크롤백·크래시 마커가 공유하는 단일 경로 소유자 —
/// 같은 경로 계산을 여러 곳에 흩뿌리지 않는다. 최초 접근 시 디렉터리를 만든다.
///
/// **개발 빌드는 워크트리마다 따로 쓴다**(`muxa-dev-<워크트리>-<해시>`). 워크트리마다 개발빌드를
/// 띄우는 게 일상인데 저장소를 공유하면 서로의 세션을 덮어쓴다 — 실제로 그렇게 터졌다(AppInfo.devKey).
/// 릴리스는 격리하지 않는다(사용자 데이터는 하나뿐이다).
enum MuxaSupportDir {
    /// 저장소 디렉터리 이름 — 릴리스는 `muxa`, 개발 빌드는 워크트리별로 갈린다.
    static let folderName: String = {
        guard let key = AppInfo.devKey else { return "muxa" }
        return "muxa-dev-\(key)"
    }()

    static let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// muxa 베이스 아래 하위 디렉터리(없으면 생성).
    static func subdirectory(_ name: String) -> URL {
        let dir = url.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: 유령 저장소 GC — 워크트리를 지워도 저장소가 영영 남는 것을 막는다
    //
    // 개발빌드를 워크트리마다 띄우면 저장소도 워크트리마다 생긴다(위). 워크트리를 지우면 그 저장소는
    // **아무도 다시 열지 않는데 영영 남는다**. 워크트리를 자주 만들고 지우면 유령이 쌓인다.
    //
    // 삭제는 파괴적이라 판정을 좁게 잡는다: 저장소가 자기 출처(워크트리 경로)를 적어두고,
    // **그 경로가 사라졌고 유예도 지났을 때만** 고아로 본다. 판단 근거가 없으면(출처 미기록) 안 지운다.
    // (ScrollbackStore.orphans와 같은 원칙 — 의심되면 안 지운다.)

    /// 개발 저장소의 출처를 적어두는 파일. 이게 있어야 나중에 "그 워크트리가 아직 있나"를 물을 수 있다.
    static let originFileName = ".origin"

    /// 유예 — 방금 지운 워크트리를 되살릴 수도 있고, 경로가 일시적으로 안 보일 수도 있다(외장 디스크 등).
    static let orphanGraceInterval: TimeInterval = 7 * 86_400 // 7일

    /// GC 판정 입력(순수) — 저장소 경로·출처(없을 수 있음)·마지막 수정 시각.
    struct DevStore: Equatable {
        let path: String
        /// 이 저장소를 만든 빌드의 경로(`.origin`). 못 읽으면 nil.
        let origin: String?
        let modified: Date
    }

    /// 지워도 안전한 '유령' 저장소를 고른다(순수, 부작용 없음).
    ///
    /// 보존(=안 지움) 조건 — 하나라도 참이면 남긴다:
    ///  1) 개발 저장소가 아님(`muxa-dev-` 접두사가 아니다) — **릴리스 데이터는 절대 건드리지 않는다**
    ///  2) 지금 이 프로세스가 쓰는 저장소
    ///  3) 출처를 모름(`.origin` 없음, **또는 비었음/공백뿐임**) — 판단 근거가 없으면 안 지운다.
    ///     빈 `.origin`(0바이트 파일·쓰기 도중 중단)은 nil이 아니라 `""`로 읽히는데, 그대로 두면
    ///     `exists("")`=false라 **살아있는 워크트리의 저장소를 지운다**. 빈 출처 = 출처 모름이다.
    ///  4) 출처 워크트리가 아직 있음 — 지금 쓰는 개발빌드의 세션이다
    ///  5) 유예 안쪽(최근 수정) — 방금 지운 워크트리를 되살릴 수 있다
    static func orphans(_ stores: [DevStore], now: Date, graceInterval: TimeInterval,
                        exists: (String) -> Bool, currentPath: String? = nil) -> [String] {
        stores.filter { store in
            guard (store.path as NSString).lastPathComponent.hasPrefix("muxa-dev-") else { return false }
            if store.path == currentPath { return false }
            guard let origin = store.origin,
                  !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            if exists(origin) { return false }
            if now.timeIntervalSince(store.modified) < graceInterval { return false }
            return true
        }.map(\.path)
    }

    /// 이 저장소의 출처(**워크트리 루트**)를 기록한다. 개발 빌드만 — 릴리스는 격리 대상이 아니다.
    /// 앱 시작 시 1회. 매번 덮어써서 mtime을 갱신한다 — "이 저장소는 지금도 쓰인다"는 표식이 된다.
    ///
    /// 실행 파일 경로가 아니라 워크트리 루트를 적는 이유: `make clean`으로 `.build`만 지워도
    /// 워크트리는 그대로인데, 실행 파일을 기준 삼으면 멀쩡한 저장소를 유령으로 오판한다(AppInfo).
    ///
    /// 워크트리 루트를 못 뽑으면(개발 `.app`을 `.build` 밖으로 복사해 실행 — 경로에 `.build`가 없다)
    /// **번들 경로라도 적는다**. 안 적으면 저장소는 생기는데 출처가 없어 보존규칙 3에 걸려 영영 남는다
    /// — 유령을 막으려는 GC가 유령을 만든다. 이 폴백은 `.build`가 경로에 없을 때만 쓰이므로
    /// `make clean` 오판(위)은 성립하지 않는다.
    static func stampOrigin() {
        guard AppInfo.devKey != nil else { return }
        let root = AppInfo.worktreeRoot ?? Bundle.main.bundlePath
        let file = url.appendingPathComponent(originFileName)
        try? root.write(to: file, atomically: true, encoding: .utf8)
    }

    /// 유령 저장소를 지운다(부작용 — 스캔·삭제만. 판정은 orphans에 위임).
    /// 개발 빌드에서만 돈다. 판정 못 하면(스캔 실패) 아무것도 안 지운다.
    /// - Returns: 실제로 지운 저장소 이름들.
    @discardableResult
    static func collectGarbage(now: Date = Date(),
                               graceInterval: TimeInterval = orphanGraceInterval) -> [String] {
        guard AppInfo.devKey != nil else { return [] } // 릴리스는 청소하지 않는다
        let fm = FileManager.default
        let base = url.deletingLastPathComponent()
        guard let entries = try? fm.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        let stores: [DevStore] = entries.compactMap { dir in
            guard dir.lastPathComponent.hasPrefix("muxa-dev-") else { return nil }
            let originFile = dir.appendingPathComponent(originFileName)
            // 0바이트 `.origin`은 nil이 아니라 ""로 읽힌다 — 비면 nil로 접는다(= 출처 모름 = 보존).
            let raw = try? String(contentsOf: originFile, encoding: .utf8)
            let origin = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
            // mtime을 못 읽으면 distantFuture(=항상 유예 안쪽) — 절대 삭제 대상이 안 된다(안전).
            let modified = (try? dir.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantFuture
            return DevStore(path: dir.path, origin: (origin?.isEmpty == true) ? nil : origin,
                            modified: modified)
        }

        let doomed = orphans(stores, now: now, graceInterval: graceInterval,
                             exists: { fm.fileExists(atPath: $0) }, currentPath: url.path)
        for path in doomed { try? fm.removeItem(atPath: path) }
        return doomed.map { ($0 as NSString).lastPathComponent }
    }
}
