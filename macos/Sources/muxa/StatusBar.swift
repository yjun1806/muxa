import SwiftUI

/// 하단 푸터 — [claude 사용량] [에이전트 활동] ····· [백그라운드 세션] [스크립트] [서비스].
///
/// 경로·브랜치는 여기 있지 않다 — **경로는 상단바 브레드크럼 옆**(선택한 프로젝트의 경로, `ContentView.topBar`),
/// **브랜치는 Git 패널**(⎇ 헤더)이 맡는다. 이 바는 **상태**(사용량·에이전트 활동)와
/// **떠 있는 것들**(백그라운드·서비스)만 말한다.
///
/// 사용량 칩은 이제 위치가 설정에 따라 바뀐다(`StatusBarSettings.position`) — 푸터 좌/우면 여기,
/// 헤더 좌/우면 `ContentView.topBar`가 그린다(`UsageChip`은 어디서든 같은 칩).
struct StatusBar: View {
    let state: AppState

    private let settings = StatusBarSettings.shared

    /// 스크립트 추가 시트 — **칩(ScriptStrip)이 아니라 여기서** 띄운다. 팝오버는 별도
    /// NSWindow(FloatingPanelHost)라 그 안의 `.sheet`는 메인 창에 붙지 못한다. 푸터는 항상
    /// 렌더되니 원샷 플래그(requestAddScript)의 소비자로 안전하다(⌘K 경로도 여기로 온다).
    @State private var showAddScript = false

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
            // 에이전트가 지금 하는 일 — 있을 때만 뜨고, 턴이 끝나면 사라진다("무엇을 하는가").
            if let agentDetail {
                HStack(alignment: .center, spacing: Space.xs) {
                    Image(systemName: "bolt.fill").font(.muxa(.label))
                    Text(agentDetail).font(.muxa(.label)).lineLimit(1)
                }
                .foregroundStyle(Color(nsColor: Palette.brand))
                .fixedSize()
                .help("에이전트 진행 상황(Claude 훅)")
            }
            Spacer(minLength: Space.md)
            // 오른쪽 = **떠 있는 것들**(닫아도 도는 백그라운드 세션·스크립트·서비스). 폭이 고정된 요약칩이다.
            if let ws = state.activeWorkspace, let project = ws.activeProject {
                // 닫았지만 살아 있는 터미널 세션 — 있을 때만 나타난다(없으면 자리도 안 차지한다).
                DetachedStrip(state: state, project: project)
                // 스크립트(끝이 있는 명령) — 등록 0개여도 상시(서비스 칩과 같은 발견성 철학).
                ScriptStrip(state: state, project: project)
                ServiceStrip(state: state, project: project)
            }
            // 사용량 칩이 푸터 오른쪽 설정이면 떠 있는 것들 뒤(가장 오른쪽)에 둔다.
            if settings.position == .footerRight { UsageChip(state: state) }
        }
        .panelBar(height: RowHeight.toolbar) // 내용이 세로 중앙에 오도록 여유를 준다
        .background(Color.pPanel)
        .sheet(isPresented: $showAddScript) { scriptAddSheet }
        .onChange(of: state.scriptAddRequested, initial: true) { _, requested in
            guard requested else { return }
            state.scriptAddRequested = false
            // 등록할 프로젝트가 없으면 시트를 못 띄운다 — 요청만 내린다(⌘K는 빈 상태에서도 부를 수 있다).
            guard state.activeProject != nil else { return }
            showAddScript = true
        }
    }

    // MARK: 스크립트 추가 시트 — 서비스 추가 시트를 문구만 바꿔 재사용(스캔·매니저 감지 로직이 같다)

    /// 시트는 창 모달이라 떠 있는 동안 프로젝트가 못 바뀐다 — 확정 시점의 활성 프로젝트가 곧 대상이다.
    private var scriptAddSheet: some View {
        ServiceAddSheet(
            cwd: state.activeProjectCwd,
            title: "스크립트 추가",
            footnote: "실행 경로에서 로그인 셸로 1회, 백그라운드에서 실행됩니다(탭이 뜨지 않습니다). 출력과 종료 로그는 서비스 도크(⌘J)에서 봅니다.\n명령은 평문으로 저장됩니다 — 토큰·API 키는 명령에 적지 말고 .env에 두세요."
        ) { name, command, cwd in
            guard let projectId = state.activeProject?.id else { return }
            state.addScript(name: name, command: command, to: projectId, cwd: cwd)
        }
    }
}
