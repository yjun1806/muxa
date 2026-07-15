import Bonsplit
import SwiftUI

/// **복원된** 터미널 탭(칸) 위에 얹는 에이전트 세션 재개 배너(D27) — controlled 트리거 뷰.
///
/// 표시 조건: 그 탭에 **복원된** 재개 바인딩이 있고(store.resumeTabs로 관측), 설정 `agent_resume`이 off가 아닐 때.
/// 훅으로 들어온 바인딩은 배너를 띄우지 않는다 — 에이전트가 지금 그 탭에서 돌고 있다는 뜻이라 이어서 할 게 없다.
/// 실행 로직은 store가 소유한다(executeResume) — 이 뷰는 store 상태를 렌더하고 실행을 위임만 한다(상태는 위, 표현은 아래).
///
/// 신뢰 경계: command는 훅이 넘긴 재개 명령이다. 기본(manual)은 사용자가 버튼을 눌러야 실행돼 무단
/// 자동 실행을 막는다. auto는 사용자가 명시적으로 켰을 때만 — 배너가 뜬 뒤 짧은 지연을 두고 자동 실행한다.
struct ResumeOverlay: View {
    let store: TerminalStore
    let tabId: TabID

    var body: some View {
        // resumeTabs(관측)가 소비 시 줄어들며 배너가 자동으로 사라진다. 전략이 .none(off)면 아예 그리지 않는다.
        // ZStack에 애니메이션을 걸어야 배너의 transition(등장/퇴장)이 발동한다(§paneBannerTransition).
        let strategy = store.resumeStrategy(for: tabId)
        let show = store.resumeTabs.contains(tabId) && strategy != .none
        ZStack {
            if show, let binding = store.resumeBinding(for: tabId) {
                ResumeBanner(
                    label: binding.agentLabel.flatMap { $0.isEmpty ? nil : $0 } ?? "에이전트",
                    command: binding.command,
                    strategy: strategy,
                    isGuess: binding.source == .scan,
                    hold: store.resumeBlock(for: tabId)
                ) {
                    store.executeResume(for: tabId)
                }
                .padding(.top, Space.md)
                .paneBannerTransition()
            }
        }
        .animation(Motion.medium, value: show)
    }
}

/// 재개 배너 본체(순수 프레젠테이션) — 라벨·명령 미리보기 + 재개 버튼. store를 모른다(값·콜백만 받는다).
private struct ResumeBanner: View {
    let label: String
    let command: String
    let strategy: ResumeStrategy
    /// 이 세션이 훅이 알려준 사실이 아니라 **cwd로 추측한 것**인가. 추측이면 사용자가 확인할 수 있게
    /// 그렇다고 말해 준다 — 같은 폴더에서 여러 세션을 돌렸다면 다른 대화가 잡혔을 수 있다.
    let isGuess: Bool
    /// 재개가 보류된 사유(없으면 nil) — 왜 안 보냈는지 말해 주지 않으면 버튼이 고장 난 것처럼 보인다.
    let hold: ResumeGate.Reason?
    /// 재개를 시도하고 **판정을 돌려준다** — auto가 `.notReady`(셸이 아직 준비 안 됨)를 재시도하는 근거다.
    let onResume: () -> ResumeGate.Decision

    /// auto 첫 시도 전 지연 — 새 셸이 뜰 시간을 준다.
    private static let autoDelayNs: UInt64 = 800_000_000
    /// `.notReady` 재시도 간격 — 셸 pid(250ms 폴링)와 pwd(첫 프롬프트의 OSC 7)가 잡힐 때까지 다시 묻는다.
    /// 종전엔 고정 800ms 뒤 한 번 쏘고 끝이라, 늦게 뜬 셸에선 입력이 유실됐다(D2 타이밍 리스크).
    /// 이제는 **준비됐음을 확인하고** 보낸다 — 지연을 늘려 요행을 바라는 대신 조건을 검사한다.
    private static let autoRetryDelayNs: UInt64 = 300_000_000
    /// 재시도 상한(약 5초). 이 안에 준비가 안 되면 포기하고 배너를 수동 버튼으로 남긴다.
    private static let autoMaxAttempts = 16

    var body: some View {
        HStack(spacing: 8) {
            Button { _ = onResume() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.muxa(.caption))
                    Text("\(label) 세션 재개").font(.muxa(.body, weight: .medium))
                }
                .paneBannerCTA()
            }
            .buttonStyle(.plain)
            .clickCursor()

            // 실행될 명령 미리보기 — 길면 가운데를 잘라 양끝(명령·인자)을 보이게.
            Text(command)
                .font(.muxaMono(.label))
                .foregroundStyle(Color.pMuted)
                .lineLimit(1)
                .truncationMode(.middle)

            if isGuess {
                // 훅이 없어 폴더에서 추정한 세션 — 자동 실행하지 않고, 추정이라는 사실을 밝힌다.
                Text("이 폴더에서 추정")
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pBorderActivity)
            }

            if let hold {
                // 왜 안 보냈는지 밝힌다 — 조용히 무동작하면 버튼이 고장 난 것처럼 보인다.
                Text(Self.message(for: hold))
                    .font(.muxa(.caption, weight: .medium))
                    .foregroundStyle(Color.pBorderActivity)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                switch strategy {
                case .auto:
                    Text("자동 재개 중…").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                case .manualDirty:
                    // 비정상 종료 후 복원 — 재개를 놓치지 않게 강조(자동 실행은 안 함, manual 신뢰 경계 유지).
                    Text("비정상 종료 후 복원됨")
                        .font(.muxa(.caption, weight: .medium))
                        .foregroundStyle(Color.pBorderActivity)
                case .none, .manual:
                    EmptyView()
                }
            }
        }
        .paneBannerChrome(maxWidth: 520)
        .onAppear {
            guard strategy.isAuto, hold == nil else { return }
            // 배너가 뜬 뒤 지연 후 자동 실행. 소비가 뒤따르므로 재발화·중복 호출은 store가 무동작 처리한다.
            // 셸이 아직 안 뜬 구간(.notReady)은 **실패가 아니라 이르다** — 준비될 때까지 다시 묻는다.
            // 그 밖의 보류(TUI 점유·다른 폴더)는 시간이 해결하지 않으므로 즉시 멈추고 사용자에게 넘긴다.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.autoDelayNs)
                for _ in 0 ..< Self.autoMaxAttempts {
                    guard case .hold(.notReady) = onResume() else { return }
                    try? await Task.sleep(nanoseconds: Self.autoRetryDelayNs)
                }
            }
        }
    }

    /// 보류 사유 → 사용자가 **무엇을 하면 되는지** 알 수 있는 한 줄.
    private static func message(for hold: ResumeGate.Reason) -> String {
        switch hold {
        case .notReady: return "터미널 준비 중…"
        case .foregroundBusy: return "다른 프로그램 실행 중 — 끝낸 뒤 다시 누르세요"
        case .wrongCwd(let expected): return "폴더가 다릅니다 — \(expected)에서만 재개됩니다"
        }
    }
}
