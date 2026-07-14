import Bonsplit
import SwiftUI

/// 복원된 터미널 탭(칸) 위에 얹는 에이전트 세션 재개 배너(D2) — controlled 트리거 뷰.
///
/// 표시 조건: 그 탭에 복원된 재개 바인딩이 있고(store.resumeTabs로 관측), 설정 `agent_resume`이 off가 아닐 때.
/// 실행 로직은 store가 소유한다(executeResume) — 이 뷰는 store 상태를 렌더하고 실행을 위임만 한다(상태는 위, 표현은 아래).
///
/// 신뢰 경계: command는 훅이 넘긴 임의 셸 명령이다. 기본(manual)은 사용자가 버튼을 눌러야 실행돼 무단
/// 자동 실행을 막는다. auto는 사용자가 명시적으로 켰을 때만 — 배너가 뜬 뒤 짧은 지연을 두고 자동 실행한다.
struct ResumeOverlay: View {
    let store: TerminalStore
    let tabId: TabID

    var body: some View {
        // resumeTabs(관측)가 소비 시 줄어들며 배너가 자동으로 사라진다. 전략이 .none(off)면 아예 그리지 않는다.
        let strategy = store.resumeStrategy(for: tabId)
        if store.resumeTabs.contains(tabId), strategy != .none,
           let binding = store.resumeBinding(for: tabId) {
            ResumeBanner(
                label: binding.agentLabel.flatMap { $0.isEmpty ? nil : $0 } ?? "에이전트",
                command: binding.command,
                strategy: strategy,
                isGuess: binding.source == .scan
            ) {
                store.executeResume(for: tabId)
            }
            .padding(.top, 8)
            .transition(.opacity)
        }
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
    let onResume: () -> Void

    /// auto 자동 실행 전 지연 — 새 셸이 뜨고 프롬프트가 준비될 시간을 준다. 완벽한 프롬프트 감지는
    /// 과설계라 고정 지연으로 완화한다(그 전에 보내면 입력이 유실될 수 있음, D2 타이밍 리스크).
    private static let autoDelayNs: UInt64 = 800_000_000

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onResume) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.muxa(.caption))
                    Text("\(label) 세션 재개").font(.muxa(.body, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                // 1급 CTA는 텍스트 등급 토큰으로 칠한다 — `borderFocus`는 비텍스트(3:1) 등급이라
                // 흰 글자를 얹으면 다크에서 4.10:1로 AA에 미달했다. brand + onBrand는 양 모드 AA 통과.
                .background(Color.pBrand)
                .foregroundStyle(Color.pOnBrand)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.pBorder, lineWidth: 1))
        .frame(maxWidth: 520)
        .padding(.horizontal, 12)
        .onAppear {
            guard strategy.isAuto else { return }
            // 배너가 뜬 뒤 지연 후 자동 실행. 소비가 뒤따르므로 재발화·중복 호출은 store가 무동작 처리한다.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.autoDelayNs)
                onResume()
            }
        }
    }
}
