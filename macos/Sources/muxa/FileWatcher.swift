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

    /// 소비 측 재갱신 디바운스(트레일링). FSEvents 자체 latency(0.3s)는 배치를 묶을 뿐, `npm install`처럼
    /// 파일이 수만 개 흐르면 0.3초마다 배치가 계속 온다 — 그때마다 소비 측이 git 셸아웃 4번 +
    /// 트리 재열람을 돌아 메인 스레드가 끊긴다. 마지막 신호가 이긴다(정착한 뒤 1회 갱신).
    static let debounce: TimeInterval = 0.5

    /// 정착 대기 **상한**. 트레일링만 두면 배치(0.3s)가 디바운스(0.5s)보다 촘촘히 계속 오는 동안
    /// 재예약이 무한 반복돼 flush가 **한 번도** 안 돈다 — `npm install`이 도는 내내 git 패널·익스플로러가
    /// 얼어붙고 pending 경로가 끝없이 쌓인다. 첫 신호로부터 이 시간이 지나면 폭주 중이어도 강제로 흘린다.
    static let maxWait: TimeInterval = 1.5

    @ObservationIgnored private var pending: [String] = []
    @ObservationIgnored private var debounceWork: DispatchWorkItem?
    /// 지금 모으는 중인 배치의 첫 신호 시각(maxWait 기준점). flush하면 비운다.
    @ObservationIgnored private var firstSignal: TimeInterval?

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
        let now = Date.timeIntervalSinceReferenceDate
        let first = firstSignal ?? now
        firstSignal = first
        pending.append(contentsOf: paths)
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.flush() } }
        debounceWork = work
        let delay = DebounceSchedule.delay(now: now, firstSignal: first,
                                           debounce: Self.debounce, maxWait: Self.maxWait)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 디바운스 창이 지난 뒤 1회만 관측값을 올린다 — 모아 둔 경로를 함께 넘긴다.
    private func flush() {
        lastPaths = pending
        pending = []
        firstSignal = nil
        changeSeq &+= 1
    }

    /// 디바운스 예약 시각 계산(순수) — 부작용 없는 판정이라 여기서 떼어내 테스트한다.
    enum DebounceSchedule {
        /// 지금부터 flush까지 기다릴 시간. 트레일링(now+debounce)이 원칙이되,
        /// **첫 신호 + maxWait를 넘기지 않는다**(폭주 중에도 최소 그 주기로는 갱신된다).
        static func delay(now: TimeInterval, firstSignal: TimeInterval,
                          debounce: TimeInterval, maxWait: TimeInterval) -> TimeInterval {
            max(0, min(now + debounce, firstSignal + maxWait) - now)
        }
    }

    deinit {
        debounceWork?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
