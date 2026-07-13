import Foundation

/// muxa 설정 파일(`~/.config/muxa/config`) 하나를 감시하는 경계 타입 — 저장 시 자동 재적용을 위한 트리거. (ARCHITECTURE 4.6)
///
/// 순수하지 않은 파일 I/O·FS 이벤트를 여기에만 격리한다. 파싱은 MuxaConfig.parse(순수)가, 재적용은
/// 소비 측(AppDelegate)이 맡는다 — 이 타입은 "바뀌었다"만 알린다(onChange).
///
/// 감시 방식:
///  - 파일 자체를 `DispatchSource`(.write/.extend/.delete/.rename/.attrib)로 본다 — 제자리 저장을 잡는다.
///  - 에디터의 atomic write(임시 파일 → rename으로 교체)는 우리 fd의 inode를 갈아치우므로 .delete/.rename이
///    오는데, 이때 fd를 닫고 새 경로로 재부착(reattach)한다 — 안 하면 이후 변경을 놓친다.
///  - 파일이 아직 없을 때(처음 만드는 경우)를 위해 부모 디렉토리도 감시해 생성 시 파일 워처를 붙인다.
///  - 버스트(에디터가 여러 이벤트 발사)는 짧게 디바운스해 onChange를 1회로 합친다.
@MainActor
final class ConfigWatcher {
    private let fileURL: URL
    private let onChange: () -> Void

    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?

    /// 디바운스 세대 토큰 — 마지막 예약만 발화(버스트 병합).
    private var pending = 0
    private static let debounce: TimeInterval = 0.1
    /// atomic rename 후 새 파일이 자리 잡을 짧은 지연(재부착 경합 회피).
    private static let reattachDelay: TimeInterval = 0.05

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        watchDirectory()
        watchFile()
    }

    deinit {
        // 취소 핸들러가 각 fd를 닫는다. deinit(nonisolated)에서 취소만 요청 — 스레드 안전.
        fileSource?.cancel()
        dirSource?.cancel()
    }

    // MARK: 파일 감시

    /// 파일이 존재하면 감시를 붙인다(이미 붙어 있으면 무시). 없으면 조용히 스킵 — 디렉토리 감시가 생성을 잡는다.
    private func watchFile() {
        guard fileSource == nil else { return }
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handleFileEvent() }
        }
        source.setCancelHandler { close(fd) }
        fileSource = source
        source.resume()
    }

    private func handleFileEvent() {
        let flags = fileSource?.data ?? []
        notifyDebounced()
        // inode 교체(atomic write) → 기존 fd는 더는 새 파일을 못 본다. 닫고 재부착.
        if flags.contains(.delete) || flags.contains(.rename) {
            reattachFile()
        }
    }

    private func reattachFile() {
        fileSource?.cancel()
        fileSource = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reattachDelay) { [weak self] in
            MainActor.assumeIsolated { self?.watchFile() }
        }
    }

    // MARK: 디렉토리 감시 (파일 생성/교체 포착)

    /// 부모 디렉토리를 감시한다 — 파일이 없다가 생기거나 rename으로 교체될 때 파일 워처를 (재)부착한다.
    /// 디렉토리가 없으면 스킵(파일도 없을 것). 부모 디렉토리는 앱 실행 중 사라지지 않는다고 본다.
    private func watchDirectory() {
        let dir = fileURL.deletingLastPathComponent()
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handleDirEvent() }
        }
        source.setCancelHandler { close(fd) }
        dirSource = source
        source.resume()
    }

    private func handleDirEvent() {
        // 파일이 없던 상태에서 새로 붙었으면(=처음 생성) 최초 반영을 알린다.
        // 이미 감시 중이면 파일 워처가 자기 이벤트로 처리하므로 여기선 중복 통지하지 않는다.
        let hadFile = fileSource != nil
        watchFile()
        if !hadFile, fileSource != nil { notifyDebounced() }
    }

    // MARK: 디바운스

    private func notifyDebounced() {
        pending += 1
        let token = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, token == self.pending else { return }
                self.onChange()
            }
        }
    }
}
