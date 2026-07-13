import SwiftUI

/// 하단 푸터 — [활성 터미널 pwd] ····· [git 브랜치] [claude 사용량].
///
/// 상단바의 경로는 *프로젝트 경로*(고정)지만, 여기 pwd는 포커스된 칸의 셸이 실제로 있는 곳(OSC 7)이라
/// `cd`를 따라 움직인다. 에이전트가 어디서 돌고 있는지를 항상 한 줄로 보여주는 게 이 바의 목적이다.
struct StatusBar: View {
    let state: AppState
    let home: String

    /// @Observable 싱글턴 — body에서 읽는 프로퍼티만 관측된다(조회 중·실패·값 변화에 자동 재렌더).
    private let usage = ClaudeUsageService.shared

    @State private var branch: String?
    @State private var showUsage = false
    @State private var usageHovered = false
    /// 리셋 카운트다운("3h 38m")이 굳지 않도록 1분마다 흐르는 현재 시각.
    @State private var now = Date()

    /// 활성 프로젝트의 실효 경로 — 브랜치 조회 기준이자 pwd 폴백.
    private var projectDir: String? {
        guard let ws = state.activeWorkspace else { return nil }
        return ws.activeProject?.path ?? ws.path
    }

    /// 포커스된 칸의 셸 pwd(OSC 7). 모르면 nil — **프로젝트 경로로 폴백하지 않는다.**
    /// 폴백하면 셸이 OSC 7을 안 쏘는 경우(shell integration 없는 bash 등)에 프로젝트 경로를
    /// "터미널이 있는 곳"인 양 보여주게 되고, 사용자가 `cd` 해도 안 움직이니 고장으로 읽힌다.
    /// 모르면 침묵하는 편이 거짓말보다 낫다.
    private var pwd: String? {
        guard let ws = state.activeWorkspace, let project = ws.activeProject else { return nil }
        return state.store(for: project, in: ws).focusedPwd
    }

    /// 포커스된 칸의 에이전트가 지금 뭘 하고 있나("편집 중: TermView.swift") — 훅의 도구 이벤트에서 온다.
    /// 훅이 없으면 nil이다. 추정(출력 idle)으로는 "작업 중"까지만 알지 "무엇을"은 알 수 없다.
    private var agentDetail: String? {
        guard let ws = state.activeWorkspace, let project = ws.activeProject else { return nil }
        return state.store(for: project, in: ws).focusedAgentDetail
    }

    var body: some View {
        // 아이콘·텍스트·막대가 섞이는 줄이라 정렬을 명시한다. 아이콘 글꼴을 옆 텍스트와 같은 스케일로
        // 맞춰야(둘 다 .label) 시각 중심이 어긋나지 않는다 — 크기가 다르면 center 정렬도 삐뚤어 보인다.
        HStack(alignment: .center, spacing: Space.md) {
            // 경로와 브랜치는 "지금 어디서 작업 중인가"라는 한 가지 사실이라 왼쪽에 붙여 둔다.
            // (사용량은 성격이 다른 정보라 반대쪽 끝으로 밀어낸다.)
            if let pwd {
                HStack(alignment: .center, spacing: Space.xs) {
                    Image(systemName: "folder").font(.muxa(.label))
                    Text(displayPath(pwd, home: home))
                        .font(.muxa(.label))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .foregroundStyle(Color.pMuted)
                .help(pwd)
            }
            if let branch {
                HStack(alignment: .center, spacing: Space.xs) {
                    Image(systemName: "arrow.triangle.branch").font(.muxa(.label))
                    Text(branch).font(.muxa(.label)).lineLimit(1)
                }
                .foregroundStyle(Color.pMuted)
                .fixedSize() // 경로가 길어도 브랜치는 안 잘린다(잘려야 할 건 경로 쪽)
                .help("현재 브랜치")
            }
            // 에이전트가 지금 하는 일 — 있을 때만 뜨고, 턴이 끝나면 사라진다.
            // 경로·브랜치("어디서")와 성격이 이어지는 정보라("무엇을") 같은 왼쪽 묶음에 둔다.
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
            usageView
        }
        .panelBar(height: RowHeight.toolbar) // 내용이 세로 중앙에 오도록 여유를 준다(24는 빡빡해 아래로 붙어 보인다)
        .background(Color.pPanel)
        .task(id: projectDir) {
            branch = if let dir = projectDir { await GitService.currentBranch(in: dir) } else { nil }
            await usage.refreshIfStale()
        }
        .tick(every: 60, into: $now) // 리셋 카운트다운이 굳지 않게
        .onChange(of: now) { _, _ in
            Task { await usage.refreshIfStale() } // 캐시가 만료됐으면 조용히 재조회(성공 5분·실패 45초)
        }
    }

    /// claude 사용량 — [✳ | 5h ▬▬ 9% | wk ▬▬ 54% | 3h 38m]. 클릭하면 상세 팝오버가 열린다.
    ///
    /// **하나의 칩(알약)으로 묶는다.** 로고·막대·숫자·시계가 맨바닥에 흩어져 있으면 (1) 어디까지가
    /// 한 덩어리인지 안 읽히고 (2) 누를 수 있는 것처럼 보이지 않는다. 칩 배경 + hover/열림 상태로
    /// "여기가 버튼"임을 드러낸다(상단바 토글 버튼과 같은 규칙 — 배경·반경을 공유한다).
    /// 항목 사이는 여백이 아니라 얇은 세로선으로 가른다 — 여백만으로는 "5h 9%"와 "wk 54%"가 붙어 읽힌다.
    @ViewBuilder
    private var usageView: some View {
        Button { showUsage.toggle() } label: {
            HStack(alignment: .center, spacing: Space.sm) {
                ClaudeMark(size: 13)
                if shown.isEmpty {
                    Text(placeholder)
                        .font(.muxa(.label))
                        .foregroundStyle(Color.pMuted.opacity(0.7))
                } else {
                    ForEach(shown) { limit in
                        VDivider(height: 12)
                        limitView(limit)
                    }
                    if let reset = sessionReset {
                        // 리셋은 세션 것 하나만 — 주간·모델 리셋까지 늘어놓으면 상태바가 숫자밭이 된다.
                        VDivider(height: 12)
                        // 내부 간격은 limitView와 같은 xs — 여기만 tight(2)면 아이콘·글자가 유독 붙어
                        // 보여서 옆 항목들과 리듬이 어긋난다.
                        HStack(alignment: .center, spacing: Space.xs) {
                            // 시계 아이콘이 없으면 "3h 38m"이 또 하나의 사용량 수치처럼 읽힌다 — 남은 시간임을 표시.
                            Image(systemName: "clock").font(.muxa(.micro))
                            Text(reset).font(.muxaMono(.caption))
                        }
                        .foregroundStyle(Color.pMuted)
                        .help("5시간 세션 한도가 리셋되기까지")
                    }
                    if usage.failed {
                        // 값은 있지만 마지막 갱신이 실패 — 지금 보이는 건 이전 조회 결과다.
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.muxa(.micro))
                            .foregroundStyle(UsageColor.stale)
                            .help("갱신 실패 — 이전 값입니다")
                    }
                }
                if usage.loading {
                    ProgressView().controlSize(.small).scaleEffect(0.5).frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, Space.sm)
            .frame(height: RowHeight.tight)
            .background(usageChipColor, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { usageHovered = $0 }
        .animation(Motion.fast, value: usageHovered)
        .help("claude 사용량 — 클릭해 상세 보기(모델별 한도 포함)")
        .popover(isPresented: $showUsage, arrowEdge: .top) {
            UsagePopover()
        }
    }

    /// 칩 배경 — 팝오버가 열려 있으면 계속 눌린 상태로 둔다(어디서 나온 창인지 보이게).
    private var usageChipColor: Color {
        if showUsage { return Color.pBtnActive }
        return usageHovered ? Color.pBtnHover : Color.pBtnHover.opacity(0.5)
    }

    /// 상태바에 띄울 한도 — 모델 전용(Fable 등)은 뺀다. 상세는 팝오버에서 본다.
    private var shown: [UsageLimit] { ClaudeUsage.statusBar(usage.limits) }

    /// 세션(5h) 한도의 리셋까지 남은 시간 — 상태바엔 이것 하나만 띄운다.
    private var sessionReset: String? {
        guard let session = usage.limits.first(where: \.isSession) else { return nil }
        return ClaudeUsage.resetShort(session.resetsAt, now: now)
    }

    /// 보여줄 한도가 없을 때의 문구 — 조회 전·실패·빈 응답을 구분한다.
    private var placeholder: String {
        switch usage.state {
        case .idle: return "사용량 …"
        case .failed: return "사용량 —"
        case .empty: return "사용량 없음"
        case .ok: return "사용량 없음" // 성공했는데 항목이 없다면 표시할 게 없다
        }
    }

    /// 한도 하나 — [라벨][막대][%]. 리셋 시각은 세션 것만 따로 한 번 띄운다(위).
    ///
    /// 읽는 순서를 만든다: **숫자가 주인공**(굵은 고정폭 + 상태색), 라벨은 그 숫자가 무엇인지 알려주는
    /// 보조라 한 단 작고 흐리게. 셋이 같은 크기·굵기면 눈이 어디부터 봐야 할지 정하지 못한다.
    private func limitView(_ limit: UsageLimit) -> some View {
        HStack(alignment: .center, spacing: Space.xs) {
            Text(limit.label)
                .font(.muxa(.caption))
                .foregroundStyle(Color.pMuted)
            Meter(value: Double(limit.percent) / 100, color: UsageColor.meter(limit), width: 28, height: 4)
            Text("\(limit.percent)%")
                .font(.muxaMono(.label, weight: .semibold))
                .foregroundStyle(UsageColor.text(limit))
                // 폭을 고정하지 않는다. 고정하면(width 30, leading) 짧은 값("9%")일 때 오른쪽에 남는
                // 빈 자리가 칩 spacing에 더해져, **구분선이 항목마다 다른 거리에** 놓인다("9%" 뒤 20pt,
                // "54%" 뒤 12pt). 고정폭이 지키려던 건 "자릿수가 늘어도 뒤가 안 밀린다"인데, 모노 글꼴이라
                // 같은 자릿수면 어차피 폭이 같고 자릿수가 바뀌는 일은 드물다. 흔들림보다 간격이 중요하다.
        }
        .help(detail(limit))
    }

    /// 항목 툴팁 — 상태바에서 뺀 정보(리셋 시각)를 hover로 되돌려준다.
    private func detail(_ limit: UsageLimit) -> String {
        let base = "\(limit.label) 한도 \(limit.percent)% 사용"
        guard let reset = ClaudeUsage.resetText(limit.resetsAt, now: now) else { return base }
        return "\(base) · \(reset) 리셋"
    }
}
