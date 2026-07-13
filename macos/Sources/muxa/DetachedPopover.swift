import SwiftUI

/// 백그라운드 세션 상세 — 되찾거나(열기) 버린다(종료). **되찾을 수 없으면 남긴 의미가 없다.**
///
/// 행 전체가 "되찾기" 버튼이고(주 동작), 파괴적인 종료만 오른쪽 끝에 따로 둔다(빨강 hover).
/// 셸(헤더·구분선·폭)은 `FooterPopover` — 사용량·서비스 팝오버와 같은 틀.
///
/// **"claude"라는 이름만으로는 어느 세션인지 모른다.** 같은 걸 여러 탭에서 돌렸다면 구별할 방법이
/// 없다. 그래서 탭 이름·닫은 시각을 함께 보여주고, **마지막 화면 몇 줄을 tmux에서 직접 읽어** 붙인다
/// — "아 이거였지"를 열기 전에 알게 하는 게 목적이다.
struct DetachedPopover: View {
    let state: AppState
    let project: Project
    /// 되찾거나 종료해 목록이 바뀌면 팝오버를 닫는다(빈 창이 떠 있지 않게).
    let onDone: () -> Void

    private var sessions: [DetachedSession] { project.detached ?? [] }
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// 세션명 → 마지막 화면. 저장하지 않는다 — 열 때마다 tmux에서 최신을 읽는다(오래된 미리보기는 거짓말).
    @State private var previews: [String: String] = [:]

    var body: some View {
        FooterPopover(title: "백그라운드 터미널", subtitle: "\(sessions.count)개 실행 중") {
            FooterMark(icon: "moon.zzz")
        } content: {
            ForEach(sessions) { session in
                row(session)
            }
        }
        .task(id: sessions.map(\.session).joined()) {
            for session in sessions where previews[session.session] == nil {
                previews[session.session] = await preview(of: session)
            }
        }
    }

    /// 미리보기를 어디서 읽을지 — **에이전트는 화면이 아니라 대화 기록에서 읽는다.**
    ///
    /// claude는 TUI라 화면 마지막 줄이 입력 상자·상태 HUD(`[Resume session …]`, `ACTIVE thinking…`)뿐이다.
    /// 화면을 아무리 잘 걸러도 "무슨 얘기를 하던 세션인지"는 거기 없다 — transcript(JSONL)의
    /// **마지막 assistant 메시지**가 그 답이다(알림 본문이 쓰는 것과 같은 출처).
    /// 기록을 못 찾으면(세션 없음·권한) 화면 꼬리로 물러난다 — 빈 미리보기보다는 낫다.
    private func preview(of session: DetachedSession) async -> String {
        if session.command == "claude", let cwd = session.cwd,
           let path = ClaudeSessionIndex.latestTranscriptPath(forCwd: cwd),
           let message = await TranscriptTail.lastAssistantMessage(atPath: path) {
            return ScreenPreview.message(message)
        }
        return await TmuxService.tail(session: session.session, cwd: session.cwd)
    }

    /// 세션 한 줄 — [출처 마크] [제목 · 시각 / 경로 / 마지막 화면] + [종료].
    private func row(_ session: DetachedSession) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Button { state.reattachDetached(session, in: project.id); onDone() } label: {
                HStack(alignment: .top, spacing: Space.sm) {
                    mark(session)
                    VStack(alignment: .leading, spacing: Space.tight) {
                        headline(session)
                        if let cwd = session.cwd {
                            Text(displayPath(cwd, home: home))
                                .font(.muxa(.caption))
                                .foregroundStyle(Color.pMuted)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        preview(session)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(helpText(session))

            FooterAction(icon: "trash", help: "종료 — 안에서 돌던 프로세스까지 끝냅니다",
                         destructive: true) {
                state.killDetached(session.session, from: project.id)
                onDone()
            }
        }
        .padding(.vertical, Space.xs)
        .panelRow(height: nil) // hover 배경이 좌우 끝까지 — "이 줄 전체가 버튼"이 보인다
    }

    /// 출처 마크 — claude는 자기 심볼로, 나머지는 터미널 글리프. 무엇이 도는지 한눈에 갈린다.
    @ViewBuilder
    private func mark(_ session: DetachedSession) -> some View {
        if session.command == "claude" {
            ClaudeMark(size: 13).padding(.top, 1)
        } else {
            Image(systemName: "terminal")
                .font(.muxa(.label))
                .foregroundStyle(Color.pMuted)
                .padding(.top, 1)
        }
    }

    /// 제목 줄 — **탭 이름이 있으면 그게 제목**(사용자가 붙인 이름이 가장 강한 단서다).
    /// 없으면 명령이 제목이 된다. 닫은 시각은 오른쪽에 붙여 "방금 그거"를 짚게 한다.
    private func headline(_ session: DetachedSession) -> some View {
        HStack(spacing: Space.xs) {
            Text(session.title ?? session.command)
                .font(.muxa(.label, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .lineLimit(1)
                .truncationMode(.middle)
            // 탭 이름이 제목을 가져갔으면 명령은 보조로 내려간다 — 둘 다 알아야 한다.
            if session.title != nil {
                Text(session.command)
                    .font(.muxaMono(.caption))
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.xs)
            if let at = session.detachedAt {
                Text(closedText(at))
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
                    .fixedSize()
            }
        }
    }

    /// 언제 닫았는지 — 목록이 여럿일 때 "방금 그거"를 짚는 기준.
    private func closedText(_ at: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(at)) / 60
        if minutes < 1 { return "방금" }
        if minutes < 60 { return "\(minutes)분 전" }
        return "\(minutes / 60)시간 전"
    }

    /// 마지막 화면 — tmux가 화면을 갖고 있으니 읽어서 보여준다. 이게 "어느 세션이었지"의 진짜 답이다.
    @ViewBuilder
    private func preview(_ session: DetachedSession) -> some View {
        if let text = previews[session.session], !text.isEmpty {
            Text(text)
                .font(.muxaMono(.caption))
                .foregroundStyle(Color.pMuted)
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .padding(.top, Space.tight)
        }
    }

    private func helpText(_ session: DetachedSession) -> String {
        var lines = ["클릭하면 탭으로 되찾습니다 — \(session.command)"]
        if let cwd = session.cwd { lines.append(cwd) }
        if let text = previews[session.session], !text.isEmpty {
            lines.append("")
            lines.append(text)
        }
        return lines.joined(separator: "\n")
    }
}
