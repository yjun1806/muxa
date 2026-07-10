import CoreServices
import Foundation
import Observation

/// 디렉토리 트리 변경 감시(FSEvents). 변경이 오면 `changeSeq`를 올려 SwiftUI가 반응한다(B-2).
/// FSEvents 자체 latency(0.3s)로 디바운스된다. 익스플로러 트리·git 패널이 각자 소유해 자동 갱신에 쓴다.
/// 무시 경로 판별은 소비 측(FileTree.ignored)에 맡긴다 — 여기선 원시 이벤트만 전달한다.
@MainActor
@Observable
final class FileWatcher {
    /// 변경 발생 카운터 — 뷰가 이 값 변화를 .onChange로 관찰해 리로드한다.
    private(set) var changeSeq = 0
    /// 마지막 변경 경로들(리로드 대상 디렉토리 판별용).
    @ObservationIgnored private(set) var lastPaths: [String] = []

    @ObservationIgnored private var stream: FSEventStreamRef?

    init(path: String) {
        start(path: path)
    }

    private func start(path: String) {
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        // 콜백은 C 함수 포인터라 캡처 불가 — info로 인스턴스를 복원한다(GhosttyRuntime 콜백과 동일 패턴).
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            DispatchQueue.main.async { MainActor.assumeIsolated { watcher.bump(paths) } }
        }
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagIgnoreSelf
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &ctx,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // latency 초 — 이벤트 폭주를 병합(디바운스)
            flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    private func bump(_ paths: [String]) {
        lastPaths = paths
        changeSeq &+= 1
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
