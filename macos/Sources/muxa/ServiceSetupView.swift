import SwiftUI

/// tmux가 없을 때 도크에 뜨는 안내 — 왜 필요한지 말하고, 설치를 **터미널에서** 하게 한다.
///
/// **앱이 직접 `brew install`을 실행하지 않는다.** 시스템에 패키지를 까는 일이라 되돌리기 번거롭고,
/// 앱이 삼키면 실패 원인도 안 보인다. muxa는 터미널 앱이니 명령을 터미널에 넣어주기만 하고
/// **Enter는 사용자가 누른다** — 설치 과정이 눈에 보이고, 중간에 그만둘 수도 있다.
/// (리뷰 코멘트를 터미널에 붙여넣는 기존 규칙과 같다: 주입은 하되 커밋은 사용자가.)
struct ServiceSetupView: View {
    let state: AppState
    /// 설치 명령을 터미널에 넣는다. 넣을 터미널이 없으면 false.
    let onInject: (String) -> Bool

    @State private var injected = false
    @State private var stillMissing = false

    private var brewInstalled: Bool { TmuxService.brew != nil }
    private let installCommand = "brew install tmux"

    var body: some View {
        VStack(spacing: Space.lg) {
            Image(systemName: "shippingbox")
                .font(.system(size: 28))
                .foregroundStyle(Color.pMuted.opacity(0.6))

            VStack(spacing: Space.xs) {
                Text("서비스를 쓰려면 tmux가 필요합니다")
                    .font(.muxa(.body, weight: .semibold))
                    .foregroundStyle(Color.pFg)
                Text("dev 서버를 muxa 바깥에서 살려두는 일을 tmux가 맡습니다.\nmuxa를 꺼도 프로세스가 계속 돌 수 있는 건 그 덕분입니다.")
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
                    .multilineTextAlignment(.center)
            }

            if brewInstalled {
                VStack(spacing: Space.sm) {
                    Button(injected ? "터미널에 넣었습니다 — Enter를 누르세요" : "설치 명령을 터미널에 넣기") {
                        injected = onInject(installCommand)
                    }
                    .font(.muxa(.label))
                    .disabled(injected)

                    Text(installCommand)
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color.pMuted)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Space.tight)
                        .background(Color.pBtnHover.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.sm))

                    // 설치가 끝났는지는 앱이 알 수 없다(사용자가 터미널에서 돌린다) — 직접 확인하게 한다.
                    Button("설치했습니다 — 다시 확인") {
                        if TmuxService.refresh() {
                            stillMissing = false
                            state.startServices() // 찾았으면 저장된 서비스를 바로 띄운다
                        } else {
                            stillMissing = true
                        }
                    }
                    .font(.muxa(.caption))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.pMuted)

                    if stillMissing {
                        Text("아직 tmux를 찾지 못했습니다. 설치가 끝났는지 확인해 주세요.")
                            .font(.muxa(.caption))
                            .foregroundStyle(Color.pDanger)
                    }
                }
            } else {
                // Homebrew도 없다 — 여기서 brew 설치까지 대신 해주진 않는다(범위를 넘는다).
                VStack(spacing: Space.xs) {
                    Text("Homebrew가 없어 자동 설치를 제안할 수 없습니다.")
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pMuted)
                    Text("brew.sh 에서 Homebrew를 설치한 뒤 `brew install tmux`를 실행하거나,\ntmux를 직접 설치해 주세요.")
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pMuted.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
    }
}
