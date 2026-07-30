import SwiftUI

/// 하단 푸터 — [claude 사용량] [에이전트 활동] ····· [백그라운드 세션] [명령 실행 중] [서비스 종료됨].
///
/// 경로·브랜치는 여기 있지 않다 — **경로는 상단바 브레드크럼 옆**(선택한 프로젝트의 경로, `ContentView.topBar`),
/// **브랜치는 Git 패널**(⎇ 헤더)이 맡는다.
///
/// 오른쪽 세 칩은 **전부 "있을 때만"** 나타난다(YJ-8) — 도구 진입점은 액티비티 레일이 맡으므로 이 바는
/// **지금 벌어지는 일**만 말한다: 닫아도 도는 세션 · 실행 중/방금 끝난 명령 · 비정상 종료된 서비스.
/// 그래서 오른쪽이 비어 있으면 볼 일이 없다는 뜻이고, 뭐라도 보이면 볼 일이 있다는 뜻이다.
///
/// 사용량 칩은 이제 위치가 설정에 따라 바뀐다(`StatusBarSettings.position`) — 푸터 좌/우면 여기,
/// 헤더 좌/우면 `ContentView.topBar`가 그린다(`UsageChip`은 어디서든 같은 칩).
struct StatusBar: View {
    let state: AppState

    private let settings = StatusBarSettings.shared

    /// 포커스된 칸의 에이전트가 지금 뭘 하고 있나("편집 중: TermView.swift") — 훅의 도구 이벤트에서 온다.
    /// 훅이 없으면 nil이다. 추정(출력 idle)으로는 "작업 중"까지만 알지 "무엇을"은 알 수 없다.
    private var agentDetail: String? {
        guard let ws = state.activeWorkspace, let project = ws.activeProject else { return nil }
        return state.store(for: project, in: ws).focusedAgentDetail
    }

    var body: some View {
        // 아이콘·텍스트·막대가 섞이는 줄이라 정렬을 명시한다.
        HStack(alignment: .center, spacing: Space.md) {
            // 사용량 칩이 푸터 왼쪽에 놓이는 설정이면 여기가 주인공.
            if settings.position == .footerLeft { UsageChip(state: state) }
            // 훅이 없으면 여기서 설치를 유도한다 — 훅이 있어야 아래 "에이전트 활동"도 뜨므로, 둘은 한 자리를
            // 상호배타로 나눠 쓴다(미설치=설치 유도, 설치됨=활동). 설치되면 칩은 사라진다.
            if state.needsHookInstall {
                HookInstallChip(state: state)
            } else if let agentDetail {
                HStack(alignment: .center, spacing: Space.xs) {
                    Image(systemName: "bolt.fill").font(.muxa(.label))
                    Text(agentDetail).font(.muxa(.label)).lineLimit(1)
                }
                .foregroundStyle(Color(nsColor: Palette.brand))
                .fixedSize()
                .help("에이전트 진행 상황(Claude 훅)")
            }
            Spacer(minLength: Space.md)
            // 오른쪽 = **지금 벌어지는 일**. 셋 다 해당 사건이 없으면 렌더하지 않아 자리도 안 차지한다.
            if let ws = state.activeWorkspace, let project = ws.activeProject {
                // 닫았지만 살아 있는 터미널 세션.
                DetachedStrip(state: state, project: project)
                // 명령(끝이 있는 명령) — 실행 중이거나 방금 끝난 것이 있을 때만.
                ScriptStrip(state: state, project: project)
                // 서비스 — 비정상 종료가 있을 때만(정상 실행 중은 레일 아이콘이 말한다).
                ServiceStrip(state: state, project: project)
            }
            // 사용량 칩이 푸터 오른쪽 설정이면 떠 있는 것들 뒤(가장 오른쪽)에 둔다.
            if settings.position == .footerRight { UsageChip(state: state) }
        }
        .panelBar(height: RowHeight.toolbar) // 내용이 세로 중앙에 오도록 여유를 준다
        .background(Color.pPanel)
        // 스크립트 추가 시트는 이제 **서비스 도크가 호스팅**한다(도크는 메인 창이라 .sheet 정상) —
        // 팝오버가 별도 NSWindow라 시트를 못 띄우던 제약이 사라져 여기(StatusBar)의 우회가 필요 없어졌다.
    }
}
