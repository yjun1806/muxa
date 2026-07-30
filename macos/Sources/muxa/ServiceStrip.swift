import SwiftUI

/// 푸터의 서비스 칩 — **무언가 비정상 종료됐을 때만** 나타난다. 클릭하면 서비스 도크(`ServiceDock`)가
/// 열려 목록·로그를 다 보여준다.
///
/// 예전엔 상시였다(등록 0개면 플레이스홀더). 진입점이 액티비티 레일로 갔으므로(YJ-8) 그 근거가
/// 소멸했다 — 푸터는 **지금 벌어지는 일**만 말한다. 서비스에서 그건 "정상 실행 중"이 아니라
/// **죽었다**다(정상 실행은 상시 상태라 남기면 아무것도 안 사라진다). 명령 칩의 "실행 중"과 대칭.
///
/// **두 세그먼트로 나뉜다** — 사용량 칩과 같은 문법(하나의 알약 + 얇은 세로선):
///  - 앞 [**지금**] = 활성 프로젝트의 서비스. 클릭 → 그 로그(도크). 도크가 보여주는 것과 정확히 같다.
///  - 뒤 [**전체**] = 창 전체(모든 워크스페이스·프로젝트). 클릭 → 전역 목록(팝오버 고정).
///
/// 나눈 이유: 전역 요약만 있으면 "여기 뭐가 도나"를 모르고, 활성 프로젝트만 있으면 다른
/// 워크스페이스의 dev 서버가 죽어도 거기 들어가야만 안다 — **둘 다 필요하다.**
/// 다만 전역과 현재가 같으면(워크스페이스·프로젝트가 하나뿐) 뒤 세그먼트는 숨긴다 — 같은 말을
/// 두 번 하지 않는다.
struct ServiceStrip: View {
    let state: AppState
    let project: Project

    @State private var hovered = false

    /// 지금 보고 있는 프로젝트의 서비스 — **도크가 보여주는 것과 같은 집합**.
    private var current: [Service] { state.services(of: project.id) }
    /// 창 전체의 서비스(모든 워크스페이스·프로젝트).
    private var all: [LocatedService] { state.allLocatedServices }

    /// 전체가 현재보다 많을 때만 [전체] 세그먼트가 의미 있다.
    private var showsGlobal: Bool { all.count > current.count }

    /// 푸터에 나타나야 하나 — **비정상 종료가 하나라도 있을 때만**(이 프로젝트든 창 전체든).
    /// tmux가 없거나 등록이 0개면 죽을 것도 없어 자연히 숨는다(그 발견 지점은 이제 레일이다).
    private var visible: Bool { deadCount(of: current.map(\.id)) > 0 || globalDead > 0 }

    @ViewBuilder var body: some View {
        if visible {
            HStack(spacing: 0) {
                currentSegment
                if showsGlobal {
                    VDivider(height: 12)
                    globalSegment
                }
            }
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.tight)
            .background(chipColor, in: RoundedRectangle(cornerRadius: Radius.sm))
            .onHover { hovered = $0 } // hover는 배경색까지만
            .animation(Motion.fast, value: hovered)
        }
    }

    /// 칩 클릭 = 서비스 도크 토글. **서비스 탭을 명시**한다(예전엔 탭을 유지해, 도크가 명령 탭으로
    /// 열려 있으면 "죽었다"를 눌렀는데 죽은 서비스가 안 보였다). 진입점은 자기 탭으로 데려간다.
    private func toggleDock() {
        if isOpen { state.closeServiceDock() }
        else { state.openServiceDock(serviceId: nil, tab: .services) }
    }

    /// 이 칩이 연 도크가 지금 떠 있나 — 명령 칩·레일과 같은 판정(`showServiceDock`만 보면 명령 탭이
    /// 열려 있을 때도 눌린 것처럼 보인다).
    private var isOpen: Bool { state.showServiceDock && state.dockTab == .services }

    // MARK: 앞 — 지금 이 프로젝트 (클릭 = 도크 열기)

    private var currentSegment: some View {
        Button {
            toggleDock() // 클릭 = 서비스 도크 토글.
        } label: {
            HStack(alignment: .center, spacing: Space.xs) {
                if current.isEmpty {
                    // 창 어딘가엔 서비스가 있지만 **여기엔 없다** — 그 사실을 말한다(0을 띄우지 않는다).
                    Image(systemName: "circle.dotted")
                        .font(.muxa(.micro))
                        .foregroundStyle(Color.pMuted)
                    Text("없음")
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pMuted)
                } else {
                    let summary = ServiceStatusStyle.summarize(statuses(of: current.map(\.id)))
                    Image(systemName: ServiceStatusStyle.glyph(summary))
                        .font(.muxa(.micro))
                        .foregroundStyle(ServiceStatusStyle.color(summary))
                    Text("\(current.count)")
                        .font(.muxaMono(.label, weight: .semibold))
                        .foregroundStyle(Color.pFg)
                    if deadCount(of: current.map(\.id)) > 0 {
                        Text("· \(deadCount(of: current.map(\.id))) 종료됨")
                            .font(.muxa(.caption))
                            .foregroundStyle(Color.pServiceExited)
                    }
                }
            }
            .padding(.trailing, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(currentHelp)
    }

    // MARK: 뒤 — 창 전체 (클릭 = 전역 목록)

    private var globalSegment: some View {
        Button { toggleDock() } label: {
            HStack(alignment: .center, spacing: Space.xs) {
                Image(systemName: "square.stack.3d.up")
                    .font(.muxa(.micro))
                    .foregroundStyle(globalDead > 0 ? Color.pServiceExited : Color.pMuted)
                Text("\(all.count)")
                    .font(.muxaMono(.label, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
                if globalDead > 0 {
                    // 다른 프로젝트에서 죽은 게 있으면 **여기서 말한다** — 그러려고 만든 세그먼트다.
                    Text("· \(globalDead) 종료됨")
                        .font(.muxa(.caption))
                        .foregroundStyle(Color.pServiceExited)
                }
            }
            .padding(.leading, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .help(globalHelp)
    }

    // MARK: 집계

    private func statuses(of ids: [String]) -> [ServiceState] {
        ids.map { state.serviceMonitor.state(of: $0) }
    }

    /// 비정상 종료만 센다 — "무엇이 비정상인가"는 `ServiceState.isFailure`가 혼자 정한다.
    private func deadCount(of ids: [String]) -> Int {
        statuses(of: ids).filter(\.isFailure).count
    }

    private var globalDead: Int { deadCount(of: all.map(\.service.id)) }

    private var chipColor: Color { .footerChip(isOpen: isOpen, hovered: hovered) }

    private var currentHelp: String {
        if current.isEmpty { return "이 프로젝트엔 서비스가 없습니다 — 클릭해 추가" }
        let dead = deadCount(of: current.map(\.id))
        if dead > 0 { return "이 프로젝트: \(current.count)개 중 \(dead)개 종료됨 — 클릭해 로그 보기 (⌘J)" }
        return "이 프로젝트: \(current.count)개 실행 중 — 클릭해 로그 보기 (⌘J)"
    }

    private var globalHelp: String {
        if globalDead > 0 { return "창 전체: \(all.count)개 중 \(globalDead)개 종료됨 — 클릭해 전체 보기" }
        return "창 전체: \(all.count)개 실행 중 — 클릭해 전체 보기"
    }
}
