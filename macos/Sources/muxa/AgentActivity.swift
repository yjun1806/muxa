import AppKit

/// 한 탭(터미널)에서 도는 에이전트의 추정 활동 상태 (DESIGN 4.5 "출력 idle + 프로세스 상태로 추정").
///
/// 순수 값이다 — 색·라벨만 알고, 전이 로직은 `AgentActivityEstimator`, 표현은 뷰가 맡는다.
/// idle=신호 없음/미실행, working=출력이 흐름, waiting=출력이 멎었고 입력 대기 추정, done=완료·종료.
enum AgentActivity: String, Equatable {
    case idle
    case working
    case waiting
    case done

    /// 패인 테두리로 지속 표시할 상태색 — 없으면(working·idle) 상시 테두리를 그리지 않는다(작업 중엔 조용히).
    /// waiting=주의색(주황), done=완료색(초록). 순간 이벤트(벨·완료 플래시)와 달리 "지금 이 칸의 상태"를 짚는다.
    var borderColor: NSColor? {
        switch self {
        case .waiting: return Palette.borderActivity // 주의 환기(주황) — "나를 기다린다"
        case .done: return Palette.gitAdded          // 완료(초록)
        case .working, .idle: return nil             // 은은 = 상시 표시 없음
        }
    }

    /// 인박스·툴팁용 한글 라벨.
    var label: String {
        switch self {
        case .idle: return "대기 없음"
        case .working: return "작업 중"
        case .waiting: return "입력 대기"
        case .done: return "완료"
        }
    }
}

/// 에이전트 상태 추정기 — 신호를 받아 상태를 전이하는 순수 값 타입(테스트 가능, 부작용 없음).
///
/// 설계 원칙(DESIGN 4.5, 보수적 버전):
/// - **명시 신호(muxa notify) 우선.** 훅이 보낸 waiting/done은 ground truth라 추정을 덮고 고정(pin)한다.
///   고정 중엔 출력 heartbeat(RENDER)를 무시한다 — 커서 깜빡임 같은 노이즈 RENDER가 상태를 되돌리지 못하게.
///   훅의 명시 working(작업 재개)만 고정을 푼다.
/// - **명시 신호가 없으면 idle 타이머로 추정.** 출력이 흐르면 working, `idleThreshold` 넘게 멎으면 waiting,
///   명령 완료(OSC 133)면 done. 이 추정 경로는 RENDER heartbeat + 주기적 tick으로 굴러간다.
///
/// 모든 전이는 `self`를 건드리지 않고 새 값을 돌려준다(immutable).
struct AgentActivityEstimator: Equatable {
    private(set) var state: AgentActivity
    /// 마지막으로 출력(heartbeat)을 관측한 시각(단조 증가 초, systemUptime). nil=아직 없음.
    private(set) var lastOutputAt: TimeInterval?
    /// 명시 신호(muxa notify)로 고정된 상태인지 — true면 heartbeat/tick 추정이 상태를 못 바꾼다.
    private(set) var pinned: Bool

    /// 출력이 이 시간(초)보다 오래 멎고 고정도 아니면 working→waiting으로 추정한다.
    let idleThreshold: TimeInterval

    init(idleThreshold: TimeInterval = 4.0) {
        self.state = .idle
        self.lastOutputAt = nil
        self.pinned = false
        self.idleThreshold = idleThreshold
    }

    /// 신호 하나를 반영한 새 추정기를 돌려준다(순수).
    func applying(_ signal: AgentSignal, now: TimeInterval) -> AgentActivityEstimator {
        var next = self
        switch signal {
        case .outputHeartbeat:
            // 고정(명시 waiting/done) 중엔 노이즈 RENDER를 무시 — 훅의 명시 working만 재개를 알린다.
            if pinned { break }
            next.lastOutputAt = now
            next.state = .working
        case .commandFinished:
            next.state = .done
            next.pinned = false // 명령 완료는 새 명령 출력이 오면 다시 추정하게 고정 해제
        case .processExited:
            // OS 레벨 결정론 종료 — done으로 확정하고 고정한다. 프로세스가 사라졌으니
            // 노이즈 RENDER heartbeat/tick이 이 상태를 되돌리지 못하게 pin한다(ground truth).
            next.state = .done
            next.pinned = true
        case .explicit(let notify):
            switch notify {
            case .working:
                next.state = .working
                next.lastOutputAt = now
                next.pinned = false // 작업 재개 — 이후 idle 추정을 다시 켠다
            case .waiting:
                next.state = .waiting
                next.pinned = true  // ground truth 고정
            case .done:
                next.state = .done
                next.pinned = true
            }
        case .tick:
            // 추정 경로: 고정이 아니고 working이며 출력이 임계값 넘게 멎었으면 waiting으로.
            guard !pinned, next.state == .working, let last = lastOutputAt,
                  now - last >= idleThreshold else { break }
            next.state = .waiting
        }
        return next
    }

    /// working 상태면 주기적 tick(idle 추정)이 의미 있다 — 스토어가 이걸로 타이머 on/off를 정한다.
    var needsIdleTick: Bool { !pinned && state == .working }
}

/// 추정기에 넣는 신호 — 부작용 없는 값. 출처: RENDER(heartbeat)·OSC 133(완료)·muxa notify(명시)·주기 tick.
enum AgentSignal: Equatable {
    /// 출력이 있었다는 저빈도 heartbeat(RENDER를 초당 1회로 다운샘플).
    case outputHeartbeat
    /// OSC 133 명령 완료.
    case commandFinished
    /// 서피스 자식 프로세스(셸)의 OS 레벨 종료(DispatchSourceProcess) — 셸 통합 없이도 잡는 결정론 done.
    case processExited
    /// muxa notify 훅의 결정론적 명시 신호(ground truth).
    case explicit(NotifyState)
    /// 주기적 idle 점검(타이머).
    case tick
}
