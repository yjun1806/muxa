import AppKit
import Bonsplit
import GhosttyKit
import Observation

/// Bonsplit 탭이 담는 내용 — 터미널(개별 탭)이거나 그룹 탭(문서·diff 묶음)이거나 워크트리 링크(정보 탭).
/// 문서/diff는 종류별로 그룹 탭 하나에 서브탭으로 모인다(2단 탭). 상태는 `groups`가 소유.
enum TabContent {
    case terminal
    case group(TabGroupKind)
    /// 워크트리 링크 탭 — "이 워크트리의 작업이 다른 프로젝트 탭에서 진행 중"을 알리는 정보 탭(D31).
    /// 셸을 띄우지 않는다. 자동 승격된 워크트리 프로젝트의 초기 화면. 영속하지 않는다(스냅샷에서 스킵).
    case worktreeLink
}

/// 워크스페이스 하나의 터미널 집합 + Bonsplit 분할·탭 컨트롤러. (cmux DockSplitStore 대응)
///
/// Bonsplit이 분할 트리·탭 레이아웃을 SwiftUI로 관리하고, 우리는 tabId마다 TermView 하나를
/// 만들어 매핑한다(패인 내용 = 그 tabId의 터미널). 수동 AppKit 레이아웃이 없어져
/// 제약 엔진 폭주(분할 크래시)가 원천 소멸한다.
@MainActor
@Observable
final class TerminalStore: NSObject, BonsplitDelegate {
    let controller: BonsplitController

    // 크롬 색은 init에서 `BonsplitChrome.colors`로 준다 (→ Design/BonsplitChrome.swift).
    //
    // 예전엔 못 줬다: `tabBarBackgroundHex`만 주면 분할 버튼 레인의 backdrop이 그 색에서 파생돼
    // **불투명해지고**, 레인 아래로 흐릿하게 흘러가야 할 탭이 뚝 잘려 보였다. 이제 backdrop에
    // 투명을 **명시**해 그 파생을 끊는다 — 레인 면만 안 칠하고 페이드는 살아남는다(둘은 독립 변수).

    @ObservationIgnored private let app: ghostty_app_t
    /// 새 셸의 기본 시작 폴더(= 프로젝트 경로, 없으면 워크스페이스 경로 상속).
    /// 워크스페이스 기본 경로가 바뀌면 AppState가 `updateCwd`로 갱신한다 — 이미 떠 있는 PTY는 못 옮기지만
    /// **앞으로 여는 터미널**은 새 폴더에서 시작해야 한다.
    @ObservationIgnored private var cwd: String?
    @ObservationIgnored private var terms: [TabID: TermView] = [:]
    /// 이 프로젝트를 그리는 창. terms의 TermView에 스탬프되어, 뷰 계층이 소유권을 보고 재부모화한다.
    /// **아직 만들어지지 않은 탭**의 TermView도 term(for:)에서 이 값을 물려받아야 스탬프를 놓치지 않는다.
    @ObservationIgnored private(set) var ownerWindowId: String = WindowID.main.rawValue
    /// 탭별로 새 셸을 띄울 작업 디렉터리 힌트. term(for:)가 TermView 생성 시 참조한다.
    /// 두 경로가 채운다 — 세션 복원(저장된 OSC 7 pwd)과 새 탭·분할(원본 칸의 현재 pwd 상속).
    /// TermView가 아직 안 만들어진 탭도 다음 저장 때 cwd를 잃지 않도록 convert의 폴백으로도 쓴다.
    @ObservationIgnored private var pendingCwd: [TabID: String] = [:]
    /// 복원된 탭의 스크롤백 파일 경로 힌트 — term(for:)가 새 셸에 env로 주입한다(④). pendingCwd와 같은 수명.
    @ObservationIgnored private var restoredScrollbackFile: [TabID: String] = [:]

    // MARK: L3 — tmux 세션(프로세스 연속성)

    /// 지속 세션 탭의 아이콘 — 일반 터미널(`terminalTabIcon`)과 **눈으로 구별되어야 한다**.
    /// 어느 탭이 tmux 안에 있는지 모르면 "닫아도 되나"를 판단할 수 없다.
    static let persistentTabIcon = "infinity"
    /// 일반 터미널 탭의 아이콘. tmux 밖으로 나온 지속 세션 탭도 여기로 돌아온다(§releaseDetachedTab).
    static let terminalTabIcon = "terminal"

    /// 지속 세션 터미널 버튼 — 탭바의 `+` 옆에 선다. tmux가 있을 때만 노출한다.
    static let persistentTerminalKind = "persistentTerminal"
    static let persistentTerminalButton = BonsplitConfiguration.SplitActionButton(
        id: persistentTerminalKind,
        systemImage: "infinity",
        tooltip: "지속 세션 터미널 — 앱을 껐다 켜도 안에서 돌던 작업이 이어집니다",
        action: .custom(persistentTerminalKind)
    )

    /// 탭이 닫혔지만 안에서 작업이 돌고 있어 백그라운드로 남겼다 — AppState가 프로젝트에 기록한다.
    /// 기록하지 않으면 다음 시작 때 GC가 고아로 보고 죽인다(= 남긴 의미가 없다).
    @ObservationIgnored var onDetachSession: ((DetachedSession) -> Void)?

    /// 이 스토어가 속한 프로젝트 id. tmux 세션 네임스페이스에 들어간다.
    @ObservationIgnored private let projectId: String
    /// 완전 일회용 스토어인가(스크래치 ~) — true면 지속(∞tmux)을 아예 제공하지 않는다:
    /// 새 터미널 기본이 일반 셸이 되고(newTerminal), ∞ 버튼도 숨긴다. 창을 닫으면 store째 버려
    /// PTY가 죽는데, tmux 세션이 하나도 없어야 그 파괴가 항상 안전하다(남길 세션이 없다).
    @ObservationIgnored private let ephemeral: Bool
    /// 탭 → tmux 세션명. 복원된 탭은 **저장된 이름**을 그대로 이어받는다(tabId가 새로 발급되므로).
    @ObservationIgnored private var tmuxSessions: [TabID: String] = [:]
    /// 이 탭을 지속 세션(tmux)으로 열었는가 — **tmux가 있으면 기본이 지속**이다(newTerminal 참조).
    ///
    /// 한때 `∞` 버튼으로 고른 탭만 지속으로 뒀다: 지속 세션은 공짜가 아니고(터미널 안의 터미널),
    /// 잠깐 `ls` 치는 탭까지 감쌀 이유가 없다는 판단이었다. 뒤집은 이유는 손실의 비대칭이다 —
    /// 불필요한 tmux 세션은 낭비로 끝나지만, 지속이 아닌 탭에서 돌던 에이전트·빌드는 앱을 닫는 순간
    /// **되돌릴 수 없이 죽는다**. 기본은 살아남는 쪽이어야 한다.
    /// 값이 서지 않은 탭(복원된 옛 일반 탭 등)은 false로 읽혀 그대로 일반 셸이다.
    @ObservationIgnored private var persistentIntent: [TabID: Bool] = [:]

    /// ∞ 탭을 닫을 때 확인 배너를 거친(=결정이 끝난) 닫기 — `shouldCloseTab`이 다시 막지 않게 통과시킨다.
    /// 배너를 띄우려면 tmux를 비동기로 조회해야 하는데 `shouldCloseTab`은 동기라, 훅에서 일단 거부(veto)하고
    /// 판정·확인 뒤 **같은 탭을 다시 닫는다**. 재진입한 닫기는 여기 있으므로 통과한다.
    @ObservationIgnored private var confirmedCloses: Set<TabID> = []
    /// 확인 배너의 결정 — `releaseTmuxSession`이 자동 판정 대신 이대로 따른다. 없으면(nil) 기존 자동 판정.
    /// keep은 표시 이름을 함께 실어, 세션을 놓는 시점에 foreground를 다시 조회하지 않아도 되게 한다.
    @ObservationIgnored private var closeOverride: [TabID: TmuxReleaseDecision] = [:]
    /// 지금 확인 배너를 띄워야 하는 탭 → 실행 중인 작업 이름. CloseConfirmOverlay가 관측해 칸 상단에 배너를 그린다.
    /// 앱 전역 모달(NSAlert) 대신 이 칸에서만 조용히 물어, "탭 닫기"가 "앱 닫기"처럼 느껴지지 않게 한다.
    private(set) var closeConfirmations: [TabID: String] = [:]

    /// ∞ 세션을 놓을 때의 결정. 셸 종료·tmux 이탈 등 자동 경로는 이 값 없이(nil) 기존 판정을 그대로 탄다.
    private enum TmuxReleaseDecision {
        case kill
        case keep(label: String)
    }

    /// 이 스토어의 살아있는 터미널 탭이 쓰는 tmux 세션명 전부 — 프로젝트를 닫을 때 이 세션들을
    /// 명시적으로 죽여 유령화를 막는다(닫힌 프로젝트는 GC의 "모르는 프로젝트" 가드에 걸려 영영 정리 불가).
    var liveTmuxSessionNames: Set<String> { Set(tmuxSessions.values) }

    /// 훅이 보낸 tabId를 **이 스토어의 살아있는 탭**으로 되짚는다. 아니면 nil(다른 스토어가 가져간다).
    ///
    /// tmux 세션 안 셸의 `MUXA_TAB_ID`는 그 세션이 처음 만들어질 때의 id다. 복원하면 tabId가 새로
    /// 발급되므로(Bonsplit createTab은 id를 지정받지 않는다) 훅은 옛 id로 신호를 보낸다. 그대로 두면
    /// **알림이 조용히 사라진다** — 세션명에 박힌 옛 id로 현재 탭을 찾아낸다(판정은 순수 함수).
    private func resolveTab(_ incoming: TabID) -> TabID? {
        if terms[incoming] != nil { return incoming }
        guard !tmuxSessions.isEmpty else { return nil }
        let byTab = Dictionary(uniqueKeysWithValues: tmuxSessions.map { ($0.key.uuid.uuidString, $0.value) })
        guard let resolved = TerminalSession.resolve(incomingTabId: incoming.uuid.uuidString,
                                                     sessionsByTab: byTab),
              let uuid = UUID(uuidString: resolved) else { return nil }
        let tab = TabID(uuid: uuid)
        return terms[tab] != nil ? tab : nil
    }

    /// 그 칸의 선택 탭이 지속 세션인가 — **분할이** 물려받을 값(cwd 상속과 같은 규칙 — newTerminal 참조).
    private func inheritedPersistence(inPane pane: PaneID?) -> Bool {
        guard let pane, let tab = controller.selectedTab(inPane: pane) else { return false }
        return persistentIntent[tab.id] == true
    }

    /// 이 탭이 지속 세션(tmux)인가 — 탭 아이콘·닫기 판정이 읽는다.
    func isPersistent(_ tabId: TabID) -> Bool { persistentIntent[tabId] == true }

    /// 이 탭이 쓸 tmux 세션명 — 복원분이 있으면 그것, 없으면 새로 발급. L3가 꺼져 있으면 nil.
    ///
    /// **발급 즉시 저장한다.** 세션명은 렌더 시점(term(for:))에 정해지는데, 그때 저장하지 않으면
    /// 스냅샷에 안 남는다. 그러면 다음 실행에서 tabId가 새로 발급되며 **새 세션을 만들고**, 옛 세션은
    /// 스냅샷이 참조하지 않으니 고아로 판정돼 죽는다 — 그 안에서 돌던 빌드·에이전트가 함께 죽는다.
    /// (실측으로 확인한 실패다. 앱을 강제 종료하면 종료 훅도 안 타므로 영영 저장되지 않는다.)
    private func tmuxSessionName(for tabId: TabID) -> String? {
        // 의도가 선 탭만 tmux다. tmux가 없으면 어느 쪽이든 일반 셸(설치를 강요하지 않는다).
        guard persistentIntent[tabId] == true, TmuxService.isAvailable else { return nil }
        if let existing = tmuxSessions[tabId] { return existing }
        let name = TerminalSession.name(projectId: projectId, tabId: tabId.uuid.uuidString)
        tmuxSessions[tabId] = name
        persist()
        syncAttachTimer()
        return name
    }

    // MARK: L3 — tmux 이탈 감지 (∞가 거짓말하지 않게)

    /// tmux를 놓친 것으로 **보이는** 횟수. 확정 전까지 참는다(아래 attachMissesToRelease).
    @ObservationIgnored private var tmuxMisses: [TabID: Int] = [:]
    /// 지속 세션 탭이 하나라도 있을 때만 도는 attach 점검 타이머(없으면 CPU를 쓰지 않게 껐다 켠다 — idleTimer와 같은 규칙).
    @ObservationIgnored private var attachTimer: Timer?
    /// 점검 주기(초). 상태 점을 갱신하는 용도라 2초면 충분하다(ServiceMonitor.pollInterval과 같은 근거).
    private static let attachTickInterval: TimeInterval = 2.0
    /// 이탈로 **확정**하기까지 필요한 연속 관측 수. 1로 하면 기동 레이스에서 오탐한다 —
    /// 탭을 막 만든 직후엔 `tmux attach`가 아직 안 떠서 포그라운드가 셸이다.
    private static let attachMissesToRelease = 2

    /// 지속 세션 탭이 있으면 타이머를 켜고, 없으면 끈다.
    private func syncAttachTimer() {
        let needsTick = !tmuxSessions.isEmpty
        if needsTick, attachTimer == nil {
            let timer = Timer(timeInterval: Self.attachTickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkTmuxAttachment() }
            }
            RunLoop.main.add(timer, forMode: .common)
            attachTimer = timer
        } else if !needsTick, let timer = attachTimer {
            timer.invalidate()
            attachTimer = nil
        }
    }

    /// 지속 세션 탭들이 **아직 tmux 안에 있는지** 훑는다. 나온 탭은 `∞`를 뗀다.
    ///
    /// 판정 입력은 그 탭 pty의 포그라운드 프로세스 이름 하나뿐이다(`proc_pidinfo` 1회 — tmux에
    /// 셸아웃하지 않는다). attach 중이면 바깥 pty의 포그라운드는 항상 tmux 클라이언트이므로
    /// 안쪽에서 뭐가 돌든 흔들리지 않는다(§TerminalSession.isAttached).
    private func checkTmuxAttachment() {
        // 키를 **스냅샷으로 뜬 뒤** 돈다 — releaseDetachedTab이 루프 안에서 tmuxSessions를 지운다.
        for tabId in Array(tmuxSessions.keys) {
            let name = terms[tabId]?.foregroundPid.flatMap(AgentProcessDetector.command(of:))
            guard !TerminalSession.isAttached(foregroundName: name) else {
                tmuxMisses[tabId] = nil // 붙어 있다 — 헛짚음 이력은 지운다(끊겼다 붙은 경우도 여기로 온다)
                continue
            }
            let misses = (tmuxMisses[tabId] ?? 0) + 1
            tmuxMisses[tabId] = misses
            guard misses >= Self.attachMissesToRelease else { continue }
            releaseDetachedTab(tabId)
        }
    }

    /// tmux 밖으로 나온 것이 **확정된** 탭 — 세션을 놓아주고 `∞`를 뗀다. 탭 자체는 살려둔다
    /// (사용자가 보는 건 멀쩡한 셸이다. 그걸 닫아버리면 화면에 있던 것을 우리가 빼앗는 셈이다).
    ///
    /// 세션을 그냥 잊으면 **GC가 죽인다** — `TerminalSession.orphans`는 살아있는 탭이 참조하지 않는
    /// 세션을 정리하므로, `⌃b d`로 detach된(=안의 빌드가 멀쩡히 돌고 있는) 세션이 그 판정에 걸린다.
    /// 그래서 탭을 닫을 때와 **똑같이** 놓아준다: 작업이 있으면 백그라운드 목록으로, 셸뿐이면 죽인다.
    private func releaseDetachedTab(_ tabId: TabID) {
        tmuxMisses[tabId] = nil
        releaseTmuxSession(of: tabId, title: tabTitle(tabId))
        persistentIntent[tabId] = nil // 이 탭은 이제 그냥 터미널이다 — 닫기 판정도 그에 맞게 바뀐다
        controller.updateTab(tabId, icon: Self.terminalTabIcon) // ∞를 뗀다(새 기호를 만들지 않는다 — 원래 아이콘으로)
        pushTitle(tabTitle(tabId), for: tabId) // 제목 접두(∞)도 함께 뗀다 — intent 해제 후라 무장식으로 나간다
        persist() // 스냅샷에서도 세션 참조를 지운다(다음 실행에서 빈 세션을 새로 만들지 않게)
        syncAttachTimer()
    }

    /// 이 탭이 붙잡고 있던 tmux 세션을 **놓는다** — 안에서 돌던 작업이 있으면 죽이지 않고 남긴다.
    ///
    /// 무조건 죽이면 ⌘W를 잘못 눌렀을 때 30분 돌던 빌드가 즉사한다(tmux를 쓰는 이유를 반쯤 버린다).
    /// 무조건 남기면 눈에 안 보이는 유령이 쌓인다. 그래서 셸만 있으면 죽이고, 작업이 있으면 남긴 뒤
    /// **목록에 기록해 되찾을 수 있게** 한다(기록이 없으면 GC가 다음 시작 때 죽인다).
    ///
    /// 탭이 닫힐 때(⌘W)와 tmux 밖으로 튕겨났을 때 둘 다 같은 처리다 — **탭이 세션을 놓는다**는 사실이
    /// 같고, 그 안의 작업을 잃으면 안 된다는 것도 같다. 세션이 이미 없으면 포그라운드가 비어
    /// kill로 떨어지는데, 없는 세션을 kill하는 건 무해하다(멱등).
    /// - Parameter title: 표시용 탭 이름. 호출부가 **맵이 비워지기 전에** 읽어 넘긴다.
    private func releaseTmuxSession(of tabId: TabID, title: String) {
        guard let session = tmuxSessions.removeValue(forKey: tabId) else { return }
        let cwd = pwds[tabId]
        // 확인 다이얼로그가 이미 결정했으면 그대로 따른다(foreground 재조회 없음). 없으면 기존 자동 판정.
        let decision = closeOverride.removeValue(forKey: tabId)
        Task { [weak self] in
            switch decision {
            case .kill:
                await TmuxService.kill(session: session)
                return
            case .keep(let label):
                await MainActor.run {
                    self?.onDetachSession?(DetachedSession(session: session, command: label, cwd: cwd,
                                                           title: title, detachedAt: Date()))
                }
                return
            case nil:
                break // 자동 판정으로 떨어진다(셸 종료·tmux 이탈·셸만인 ∞).
            }
            let foreground = await TmuxService.paneForeground(session: session)
            guard TerminalSession.shouldDetach(foreground: foreground) else {
                await TmuxService.kill(session: session)
                return
            }
            // 표시용 이름 — 셸이 아닌 첫 프로세스가 "무엇을 되찾는지"다(래퍼 셸·버전 이름에 속지 않는다).
            let label = TerminalSession.workLabel(foreground: foreground) ?? "작업"
            await MainActor.run {
                self?.onDetachSession?(DetachedSession(session: session, command: label, cwd: cwd,
                                                       title: title, detachedAt: Date()))
            }
        }
    }
    /// 복원 리플레이 명령의 완료 신호를 아직 삼키지 않은 탭들. 리플레이를 건 탭만 담고,
    /// 첫 commandFinished에서 하나씩 소비한다(§handleSignal — 복원이 만드는 "완료" 오탐 차단).
    @ObservationIgnored private var replayPendingTabs: Set<TabID> = []
    /// 탭별 에이전트 재개 바인딩(훅이 넘긴 재개 명령). 훅 알림으로 등록되고 스냅샷에 실려 복원된다.
    /// 값 자체는 관측 대상이 아니라 뷰는 아래 resumeTabs로 표시 여부만 반응한다.
    @ObservationIgnored private var resumeBindings: [TabID: ResumeBinding] = [:]
    /// **배너를 띄울** 탭들 — 재개 배너(ResumeOverlay)가 관측해 표시/소비를 반응한다.
    ///
    /// 바인딩이 있다고 배너를 띄우지 않는다. 배너는 "이어서 할래?"라는 제안이라 **이어서 할 게 있을 때**,
    /// 즉 세션 복원으로 되살아난 탭(빈 셸)에서만 뜬다(`restoreResumeBinding`). 훅으로 들어온 바인딩은
    /// 에이전트가 **지금 그 탭에서 돌고 있다**는 뜻이라 배너를 띄우지 않는다 — 띄웠더니 자동 실행이
    /// 살아 있는 claude 입력창에 `claude --resume …`를 타이핑했다(D2 회귀).
    private(set) var resumeTabs: Set<TabID> = []
    /// 재개를 **보류한** 탭과 그 사유 — 배너가 관측해 "왜 못 보냈는지"를 사용자에게 말해 준다.
    /// 보류 시 바인딩은 소비하지 않는다: 사용자가 조건을 맞추고(폴더 이동·TUI 종료) 다시 누르면 실행된다.
    private(set) var resumeBlocks: [TabID: ResumeGate.Reason] = [:]
    /// 복원된 세션 재개의 승인 게이트(off/manual/auto). 기본 manual — 임의 셸 명령 자동 실행을 막는다(신뢰 경계).
    /// 설정 라이브 리로드로 갱신될 수 있어 var — AppState가 `updateAgentResumeMode`로 전파한다. (D2)
    @ObservationIgnored private(set) var agentResumeMode: AgentResumeMode
    /// 직전 실행이 더티(비정상) 종료였는지 — AppState가 시작 시 판정해 넘긴다(세션 상수라 관측 대상 아님).
    /// 재개 전략(ResumeStrategy)에만 쓴다: manual일 때 배너를 "비정상 종료 후 복원됨"으로 강조한다.
    @ObservationIgnored private let sessionWasDirty: Bool
    /// 터미널이 아닌 탭의 종류(그룹). 없으면 .terminal.
    @ObservationIgnored private var tabContent: [TabID: TabContent] = [:]
    /// 그룹 탭(TabID) → 서브탭 상태(문서·diff 묶음). TabGroupView가 관측한다.
    @ObservationIgnored private var groups: [TabID: TabGroupState] = [:]

    /// 탭별 현재 셸 작업 디렉터리(OSC 7) — 상태바가 활성 칸의 pwd를 보여준다.
    /// TermView는 NSView라 SwiftUI가 관측하지 못해, onPwd 콜백으로 여기 미러링한다(관측 대상).
    private(set) var pwds: [TabID: String] = [:]

    /// 탭별 **에이전트(훅) cwd** — 훅 페이로드의 cwd 미러(관측 대상). 셸 pwd와 따로 두는 이유:
    /// cc의 EnterWorktree는 **셸을 cd하지 않고**(cc 프로세스만 이동) OSC 7이 안 나오며, ∞(tmux) 탭은
    /// 안쪽 셸의 OSC 7이 바깥 pty로 통과되지도 않는다(실측 — 자동 승격이 영영 안 걸렸다).
    /// 워크트리 자동 승격·링크 카드는 `effectiveCwds`(훅 우선)로 판정한다.
    private(set) var agentCwds: [TabID: String] = [:]

    /// 탭별 실효 cwd — **에이전트(훅) cwd 우선**, 없으면 셸 pwd(OSC 7). 워크트리 귀속 판정의 단일 소스.
    var effectiveCwds: [TabID: String] { pwds.merging(agentCwds) { _, agent in agent } }

    /// 백그라운드 활동(●)으로 배지가 붙은 탭들(A). 프로젝트 배지가 이걸 파생·관측한다.
    var badgedTabs: Set<TabID> = []
    /// 마지막으로 뷰어 탭으로 연 파일 경로 — 익스플로러가 관측해 그 노드로 reveal(펼침+선택+스크롤).
    var lastOpenedFilePath: String?
    /// reveal 트리거 시퀀스 — 같은 파일을 다시 열어도 재-reveal 되도록 매 openFile마다 증가.
    var revealSeq = 0
    /// 지금 활동 테두리가 깜빡이는 칸들 — 그 칸의 선택 탭 TabID 기준. BonsplitWorkspaceView가 관측해 overlay를 그린다.
    /// 보이는 칸에서 활동(완료·벨·알림)이 나면 잠깐 켰다 페이드로 끈다. 배지(안 보이는 탭)와 상호배타적 신호.
    /// 탭별 추정 에이전트 활동 상태(작업중/대기/완료/idle) — BonsplitWorkspaceView가 관측해 상시 상태 테두리를 그린다.
    /// idle은 담지 않는다(없음=idle) — 상태가 바뀔 때만 immutable 교체해 SwiftUI 갱신을 최소화한다.
    private(set) var agentActivity: [TabID: AgentActivity] = [:]
    /// 탭별 진행 표시("편집 중: TermView.swift") — 훅의 도구 이벤트에서 파생한다(관측 대상, 푸터가 읽는다).
    /// 알림이 아니라 "지금 뭘 하고 있나"의 표면이다. 턴이 끝나면(Stop·새 프롬프트) 지운다.
    private(set) var agentDetail: [TabID: String] = [:]
    /// 탭별 **마지막 입력 프롬프트**(UserPromptSubmit 훅) — 사이드바 행 제목이 읽는다(관측 대상).
    /// 진행 표시와 달리 턴이 끝나도 **남는다** — "이 탭에 마지막으로 뭘 시켰나"가 정체성이다.
    private(set) var agentPrompts: [TabID: AgentPrompt] = [:]
    /// 탭별 transcript(JSONL) 경로 미러 — hover 팝오버가 첨부 이미지를 여기서 읽는다.
    /// 관측 대상이 아니다(열람 시점에만 읽는 값) — 훅이 올 때마다 최신으로 덮는다.
    @ObservationIgnored private var agentTranscripts: [TabID: String] = [:]
    /// 배지가 하나라도 생기면 상위(AppState)에 알린다 — 프로젝트 탭 ● 표시용.
    @ObservationIgnored var onProjectActivity: (() -> Void)?
    /// 데스크톱 알림을 띄워야 할 때 상위(AppState)에 위임한다 — 라우팅 컨텍스트(프로젝트·워크스페이스)는
    /// 스토어가 모르므로 AppState가 붙인다. 이 스토어는 tabId·제목·본문만 넘긴다.
    @ObservationIgnored var onNotify: ((TabID, String, String) -> Void)?
    /// 배지가 붙는(=안 보이는 탭에 주의가 쌓이는) 순간 상위(AppState)에 알린다 — 알림 인박스 이력용.
    /// 라우팅 컨텍스트는 AppState가 붙이므로 tabId·종류·제목만 넘긴다.
    @ObservationIgnored var onAttention: ((TabID, AttentionKind, StatusTone, String) -> Void)?
    /// 탭/뷰어 구성이 바뀔 때 상위(AppState)에 알린다 — 즉시 세션 저장(⌘Q 없이도 복원되게).
    @ObservationIgnored var onStateChange: (() -> Void)?
    /// 셸 cwd(OSC 7)가 바뀔 때 상위(AppState)에 알린다 — 새 워크트리로 들어간 세션의 **자동 승격** 판정용(D31 보완).
    /// 에이전트는 워크트리를 만들고 곧장 cd하는데, FSEvents(.git)보다 이 신호가 늦게 올 수 있어 둘 다 트리거로 쓴다.
    @ObservationIgnored var onPwdChange: (() -> Void)?

    // MARK: 워크트리 링크 탭 (D31) — "이 워크트리의 작업이 다른 탭에서 진행 중" 정보 탭

    /// 링크 탭이 그릴 대상 — AppState가 `externalLiveSession(for: 이 프로젝트)`를 이어 준다
    /// (스토어는 다른 프로젝트의 탭을 모른다 — 프로젝트를 넘나드는 판정은 상위 몫).
    @ObservationIgnored var worktreeLink: (() -> ExternalWorktreeSession?)?
    /// 링크 탭의 액션 위임 — 가서 보기(원본 탭 점프)·가져오기(∞ 세션 이식)는 프로젝트를 넘나들어 AppState가 맡는다.
    @ObservationIgnored var onWorktreeLinkAction: ((ExternalWorktreeSession, WorktreeLinkAction) -> Void)?
    /// 첫 화면을 터미널 대신 **링크 탭**으로 열라는 힌트 — 자동 승격된 워크트리 프로젝트(밖에 라이브 세션이
    /// 있는)에 AppState가 store 생성 시 세운다. 복원 스냅샷이 있으면 그쪽이 우선(ensureInitialTerminal).
    @ObservationIgnored var initialWorktreeLink = false

    /// 워크트리 링크 탭을 연다 — 터미널이 아니라 셸을 띄우지 않는다(빈 프로젝트에 PTY 스폰 금지 원칙과 동일).
    @discardableResult
    func openWorktreeLinkTab(inPane pane: PaneID? = nil) -> TabID? {
        guard let id = controller.createTab(title: "진행 중인 작업", icon: "arrow.triangle.branch",
                                            inPane: pane) else { return nil }
        tabContent[id] = .worktreeLink
        syncHasTabs()
        persist()
        return id
    }

    /// 이 스토어의 워크트리 링크 탭을 모두 닫는다 — 가져오기/옮기기로 **실물(∞ 탭)이 도착하면** 안내는 치운다.
    func closeWorktreeLinkTabs() {
        let links = controller.allTabIds.filter { if case .worktreeLink = content(for: $0) { return true }; return false }
        for id in links { _ = controller.closeTab(id) }
    }

    // MARK: 이동 배너 (D31 이동 배지) — 진행 중인 세션이 다른 프로젝트의 워크트리 안에서 작업 중일 때

    /// 이 탭의 이동 대상 — AppState가 `worktreeMoveSuggestion(for:in:)`을 이어 준다(프로젝트를 넘나드는 판정은 상위 몫).
    @ObservationIgnored var moveSuggestion: ((TabID) -> WorktreeMoveSuggestion?)?
    /// 이동 실행 위임 — (tabId, 대상 프로젝트 id). 실체는 `AppState.bringPersistentTab`(∞ 세션 이식).
    @ObservationIgnored var onWorktreeMove: ((TabID, String) -> Void)?
    /// 사용자가 "여기 둠"으로 무시한 이동 제안(tabId → 대상 프로젝트 id) — 같은 대상이면 다시 조르지 않는다
    /// (관측 대상 — 배너가 반응). 다른 워크트리로 옮겨 가면 키가 달라져 배너가 다시 뜬다. 세션 한정(영속 안 함).
    private(set) var dismissedMove: [TabID: String] = [:]

    /// 이동 제안 무시 — 이 탭에 대해 같은 대상으로는 배너를 다시 띄우지 않는다.
    func dismissMoveSuggestion(_ tabId: TabID, targetId: String) {
        dismissedMove[tabId] = targetId
    }
    /// 초기 복원이 끝난 뒤에만 저장을 트리거한다(복원 중 중간 상태 저장 방지).
    @ObservationIgnored private var ready = false

    private func persist() { if ready { onStateChange?() } }

    var hasBadge: Bool { !badgedTabs.isEmpty }

    /// 이 프로젝트에서 지금 돌고 있는 에이전트가 있는가(칸 하나라도 working) — 사이드바 상태 점.
    var hasWorkingAgent: Bool { agentActivity.values.contains(.working) }

    /// 입력 대기 중인 칸이 있는가. **보고 있는 프로젝트엔 배지가 안 붙으므로**(배지는 "안 보는 동안 쌓인 것")
    /// 활성 프로젝트의 주의는 이 신호로만 잡힌다.
    var hasWaitingAgent: Bool { agentActivity.values.contains(.waiting) }

    /// 이 스토어(프로젝트)의 시작 폴더 — diff/뷰어 탭이 참조한다.
    var workingDir: String? { cwd }

    /// 최초 표시 시 복원할 통합 레이아웃 스냅샷(없으면 초기 터미널 1개). ensureInitialTerminal에서 소비.
    @ObservationIgnored private var restoreSnap: PaneSnapshot?
    /// 복원 replay 중에는 delegate 부작용(자동 새 터미널 생성)을 막는다.
    @ObservationIgnored private var restoring = false
    /// ensureInitialTerminal 1회 보장 — Bonsplit이 초기 "Welcome" 탭을 넣어 allTabIds가 비지 않으므로 플래그로 판별.
    /// 관측 대상(뷰가 showEmptyState에서 읽음) — 초기화 전엔 빈 상태 뷰를 띄우지 않게 게이트한다.
    private(set) var initialized = false
    /// 이 스토어에 살아있는 탭이 하나라도 있는지(관측 대상). controller.allTabIds는 관측 불가라
    /// 탭 생성·닫기 경계에서 syncHasTabs로 동기화한다 — 뷰가 빈 상태 분기에 쓴다.
    private(set) var hasTabs = false

    /// 메인 영역에 빈 상태 뷰("터미널 없음")를 띄울지 — 초기화가 끝났는데 살아있는 탭이 하나도 없을 때만.
    /// 초기화 전(ensureInitialTerminal 이전)엔 곧 초기 터미널이 생기므로 빈 상태를 띄우지 않는다(깜빡임 방지).
    var showEmptyState: Bool { initialized && !hasTabs }

    /// 관측 가능한 hasTabs를 컨트롤러 실제 상태로 맞춘다 — 탭 수가 0↔양수로 바뀌는 경계에서 호출한다.
    private func syncHasTabs() {
        let next = !controller.allTabIds.isEmpty
        if hasTabs != next { hasTabs = next }
    }

    init(app: ghostty_app_t, cwd: String?, restoreSnap: PaneSnapshot? = nil,
         commandFinishedThresholdNs: UInt64 = 8_000_000_000,
         agentResumeMode: AgentResumeMode = .manual,
         sessionWasDirty: Bool = false,
         projectId: String = "",
         ephemeral: Bool = false) {
        self.app = app
        self.cwd = cwd
        self.restoreSnap = restoreSnap
        self.commandFinishedThresholdNs = commandFinishedThresholdNs
        self.agentResumeMode = agentResumeMode
        self.sessionWasDirty = sessionWasDirty
        self.projectId = projectId
        self.ephemeral = ephemeral
        // keepAllAlive — 탭 전환 시 뷰(WKWebView 뷰어·터미널)를 파괴/재생성하지 않고 유지한다.
        // 기본 .recreateOnSwitch는 전환마다 뷰어를 재로드(굼뜸·상태 손실)해서 부적합.
        var config = BonsplitConfiguration(contentViewLifecycle: .keepAllAlive)
        // 탭바 내장 액션 버튼: [새 터미널(+), 우측 분할, 하단 분할]. 브라우저는 muxa에 없어 제외.
        // .newTerminal → requestNewTab(kind:"terminal") → didRequestNewTab 델리게이트 → newTerminal().
        // 새 터미널(+), 지속 세션 터미널(∞), 우측 분할, 하단 분할.
        // 지속 세션 버튼은 tmux가 있을 때만 — 없는데 버튼을 보여주면 눌러도 아무 일이 안 일어난다.
        var buttons: [BonsplitConfiguration.SplitActionButton] = [.newTerminal]
        // 일회용(스크래치)엔 지속 세션이 없다 — ∞ 버튼을 숨겨 tmux 세션이 아예 안 생기게 한다(파괴 안전).
        if !ephemeral && TmuxService.isAvailable { buttons.append(Self.persistentTerminalButton) }
        buttons.append(contentsOf: [.splitRight, .splitDown])
        config.appearance.splitButtons = buttons
        // 칸 탭바를 도구 패널(탐색기·git) 헤더와 같은 높이로 — 두 줄이 한 선에 이어져 보이게.
        config.appearance.tabBarHeight = RowHeight.header
        // 탭 폭 모드는 기본(.fixed)을 유지한다.
        // .fill로 바꾸면 탭이 "분할 버튼 레인을 뺀 폭"에 맞춰져, 탭 스크롤이 레인 앞에서 끊긴다
        // (원래는 탭이 레인 아래로 흘러가며 페이드된다 — 그 동작이 옳다).
        //
        // 탭바 색·지시선 = muxa 팔레트(→ Design/BonsplitChrome.swift).
        // 안 주면 Bonsplit이 시스템 색을 쓰는데, 거기선 **활성 탭 배경과 탭바 배경이 같은 색**이라
        // (windowBackground == controlBackground) 활성 탭의 면이 시각적으로 존재하지 않는다.
        config.appearance.chromeColors = BonsplitChrome.colors
        // 칸 사이 틈 제거 — 분할 divider를 0으로(칸이 딱 붙는다). 드래그 리사이즈는 dividerHitExpansion이
        // 별도로 히트 영역을 잡아 유지된다(그린 폭 0이어도 잡을 수 있다).
        config.appearance.dividerThickness = 0
        // 다른 칸을 보고 오면 활성 탭이 스크롤 밖에 남을 수 있다 — 포커스가 돌아오면 가운데로 데려온다.
        config.appearance.keepsSelectedTabVisible = true
        // 탭·활성 탭 스타일(패딩·반경·지시선·pill…)은 설정에서 온다. 라이브 변경은 AppState.reapplyTabAppearance.
        BonsplitChrome.applyTabStyle(TabStyleSettings.shared, to: &config.appearance)
        self.controller = BonsplitController(configuration: config)
        super.init()
        controller.delegate = self

        // 파일 드롭은 **반드시 Bonsplit을 통해** 받는다. Bonsplit이 패인마다 `.onDrop(of: [.tabTransfer, .fileURL])`을
        // 깔아두므로(PaneContainerView), 파일 드래그의 목적지는 그 중첩 호스팅 뷰가 된다. 핸들러를 안 걸면
        // Bonsplit이 드롭을 거부하고, AppKit은 거부된 목적지에서 조상 뷰로 폴백하지 않아 드롭이 통째로 죽는다.
        //
        // 레거시 `onFileDrop`이 아니라 **`onExternalFileDrop`이어야 한다.** 레거시는 center zone에서만
        // 유효한데, validateDrop의 zone 판정은 드래그가 칸에 **진입한 순간의 좌표**라 거의 항상
        // 가장자리(각 변 25%, 최소 80pt) — 세션 전체가 조용히 거부된다(빠른 드래그만 우연히 통과).
        // onExternalFileDrop은 모든 zone을 허용한다. muxa 의미론은 zone과 무관하게
        // "그 칸의 터미널에 경로 삽입"이므로 destination의 targetPane만 뽑아 쓴다.
        controller.onExternalFileDrop = { [weak self] request in
            let paneId: PaneID
            switch request.destination {
            case .insert(let targetPane, _), .split(let targetPane, _, _):
                paneId = targetPane
            }
            return self?.insertDroppedPaths(request.urls.map(\.path), inPane: paneId) ?? false
        }
        // 칸 사이 divider를 더블클릭하면 모든 칸을 같은 크기로 되돌린다.
        // 어느 divider를 눌렀는지는 무시한다 — 요청은 "전부 균등"이다.
        controller.onDividerDoubleClick = { [weak self] _ in
            self?.equalizeAllPanes()
        }
    }

    /// 모든 칸을 같은 크기로 리사이즈한다(divider 더블클릭). 각 split의 divider를 양쪽
    /// 서브트리의 칸 개수 비율로 놓아, 트리 모양과 무관하게 모든 칸이 같은 면적이 된다 —
    /// 좌우 분할만 있으면 곧 **모든 칸이 같은 너비**다(→ `SplitEqualize`).
    func equalizeAllPanes() {
        for (splitId, position) in SplitEqualize.positions(for: controller.treeSnapshot()) {
            _ = controller.setDividerPosition(position, forSplit: splitId)
        }
    }

    /// 드롭된 경로를 그 칸의 터미널 프롬프트에 셸-이스케이프해 삽입한다 — claude code는 삽입된 이미지 경로를
    /// 인식해 첨부한다. 실행(Enter)은 사용자 몫이라 개행 없이 넣기만 한다. 터미널이 아닌 탭(diff 뷰어 등)은 사양한다.
    private func insertDroppedPaths(_ paths: [String], inPane paneId: PaneID) -> Bool {
        guard !paths.isEmpty,
              let tab = controller.selectedTab(inPane: paneId),
              case .terminal = content(for: tab.id) else { return false }
        controller.focusPane(paneId)
        term(for: tab.id).sendText(TerminalDrop.insertionText(for: paths))
        return true
    }

    deinit {
        idleTimer?.invalidate() // idle 추정 타이머가 런루프에 남지 않게 정리(작업 중 스토어가 해제되는 드문 경우).
        attachTimer?.invalidate() // tmux 이탈 감시 타이머도 같이(런루프가 스토어를 붙잡지 않게).
    }

    /// 완료 배지 임계(ns)를 갱신한다 — 설정 라이브 리로드 시 AppState가 이미 실행 중인 스토어에도 전파한다.
    /// 다음 명령 완료 판정부터 새 값이 적용된다(진행 중 판정은 그대로).
    /// 기본 시작 폴더를 바꾼다(워크스페이스 기본 경로 변경). 살아 있는 터미널은 그대로 두고
    /// 앞으로 여는 탭·분할부터 새 폴더에서 시작한다 — 프로세스의 cwd는 밖에서 바꿀 수 없다.
    func updateCwd(_ path: String?) {
        cwd = path
    }

    func updateCommandFinishedThreshold(_ ns: UInt64) {
        commandFinishedThresholdNs = ns
    }

    /// 재개 승인 게이트 모드를 갱신한다 — 설정 라이브 리로드 시 AppState가 실행 중 스토어에도 전파한다. (D2)
    /// 이미 뜬 재개 배너의 다음 판정부터 새 값이 적용된다.
    func updateAgentResumeMode(_ mode: AgentResumeMode) {
        agentResumeMode = mode
    }

    // MARK: BonsplitDelegate — 분할·새탭·닫기에 터미널 생명주기를 잇는다

    /// 분할 즉시 새 패인에 터미널을 만든다 — 빈 패인을 거치지 않는다(muxa 원래 동작).
    /// 새 셸은 분할 원본 칸의 현재 작업 디렉터리를 이어받는다.
    /// 복원 중엔 replay가 탭을 직접 채우므로 자동 생성을 건너뛴다.
    func splitTabBar(_ controller: BonsplitController, didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation) {
        if restoring { return }
        // 탭을 **끌어다** 만든 분할은 그 탭이 이미 새 칸에 들어와 있다(Bonsplit이 splitPaneWithTab 뒤에
        // 이 델리게이트를 부른다) — 거기에 또 터미널을 채우면 여분 탭이 생긴다(실측 버그).
        // 빈 칸(분할 버튼)일 때만 채운다.
        guard controller.tabs(inPane: newPane).isEmpty else { return }
        newTerminal(inPane: newPane, inheritingFrom: originalPane)
    }

    /// 탭바 `+` 버튼 → 새 터미널.
    func splitTabBar(_ controller: BonsplitController, didRequestNewTab kind: String, inPane pane: PaneID) {
        newTerminal(inPane: pane)
    }

    /// 탭바의 커스텀 액션 버튼 — 지금은 `∞`(지속 세션 터미널) 하나뿐.
    ///
    /// **`.custom`은 `didRequestNewTab`으로 오지 않는다**(Bonsplit은 `requestCustomAction`으로 따로 보낸다).
    /// 이걸 구현하지 않아 버튼을 눌러도 아무 일이 없었다.
    func splitTabBar(_ controller: BonsplitController, didRequestCustomAction identifier: String, inPane pane: PaneID) {
        guard identifier == Self.persistentTerminalKind else { return }
        newTerminal(inPane: pane, persistent: true)
    }

    /// ∞ 지속 세션 탭을 **안에서 작업이 돌고 있는데** 닫으려 하면 확인을 받는다(자동으로 백그라운드에
    /// 남기지 않고 사용자가 고르게 한다). 배너를 띄우려면 tmux를 비동기로 조회해야 하는데 이 훅은 동기라,
    /// **일단 거부(veto)하고** 판정 뒤 칸 상단에 배너를 띄운다. 결정은 버튼 콜백(confirmClose*/cancelClose)이 한다.
    ///
    /// 개입 대상이 아니면(일반 탭·tmux 없음·셸만 있는 ∞·이미 확인된 닫기) 곧장 통과시켜 흐름을 바꾸지 않는다.
    func splitTabBar(_ controller: BonsplitController, shouldCloseTab tab: Tab, inPane pane: PaneID) -> Bool {
        if confirmedCloses.remove(tab.id) != nil { return true } // 재진입한 닫기 — 결정 끝, 통과
        guard let session = tmuxSessions[tab.id] else { return true } // ∞ 세션이 아니면 평소대로
        Task { [weak self] in
            let foreground = await TmuxService.paneForeground(session: session)
            guard let self else { return }
            // 셸만 있으면 되찾을 것이 없다 — 묻지 않고 기존 경로로 닫는다(releaseTmuxSession이 kill).
            guard TerminalSession.shouldDetach(foreground: foreground) else {
                self.confirmedCloses.insert(tab.id)
                _ = self.controller.closeTab(tab.id, inPane: pane)
                return
            }
            // 작업이 돈다 — 칸 상단에 확인 배너를 띄운다(관측 상태를 채우면 CloseConfirmOverlay가 그린다).
            self.closeConfirmations[tab.id] = TerminalSession.workLabel(foreground: foreground) ?? "작업"
        }
        return false // 배너에서 결정한 뒤 다시 닫는다(confirmedCloses 재진입)
    }

    /// 확인 배너 "백그라운드로 유지" — 세션을 남기고(detach) 탭을 닫는다. 표시 이름은 배너 상태에서 이어받는다.
    func confirmCloseKeeping(_ tabId: TabID) {
        let label = closeConfirmations.removeValue(forKey: tabId) ?? "작업"
        closeOverride[tabId] = .keep(label: label)
        confirmedCloses.insert(tabId)
        _ = controller.closeTab(tabId)
    }

    /// 확인 배너 "완전 종료" — tmux 세션을 죽이고 탭을 닫는다(돌던 작업이 사라진다).
    func confirmCloseKilling(_ tabId: TabID) {
        closeConfirmations[tabId] = nil
        closeOverride[tabId] = .kill
        confirmedCloses.insert(tabId)
        _ = controller.closeTab(tabId)
    }

    /// 확인 배너 "취소" — 배너만 걷고 탭은 그대로 둔다(닫기 자체를 무른다).
    func cancelClose(_ tabId: TabID) {
        closeConfirmations[tabId] = nil
    }

    /// 이 탭에 확인 배너를 띄워야 하면 실행 중인 작업 이름, 아니면 nil — CloseConfirmOverlay가 읽는다.
    func closeConfirmation(for tabId: TabID) -> String? { closeConfirmations[tabId] }

    func splitTabBar(_ controller: BonsplitController, didCloseTab tabId: TabID, fromPane pane: PaneID) {
        terms[tabId] = nil // TermView deinit이 서피스 free
        pendingCwd[tabId] = nil // 시작 cwd 힌트 해제
        restoredScrollbackFile[tabId] = nil // 스크롤백 파일 힌트 해제
        ScrollbackStore.delete(for: tabId) // 이 탭의 스크롤백 파일 정리(누수 방지)
        resumeBindings[tabId] = nil // 에이전트 재개 바인딩 해제
        resumeBlocks[tabId] = nil // 재개 차단 사유도 해제
        resumeTabs.remove(tabId) // 재개 배너 표시 상태도 해제
        tabContent[tabId] = nil
        groups[tabId] = nil // 그룹 탭이면 서브탭 상태도 해제
        badgedTabs.remove(tabId)
        clearAgentActivity(tabId) // 에이전트 추정 상태·추정기 해제(+ idle 타이머 재동기화)
        hookSessions[tabId] = nil // 훅 세션 상태(배경작업·서브에이전트 로스터) 해제 — 맵 누수 방지
        hookedTabs.remove(tabId)
        agentCwds[tabId] = nil // 에이전트(훅) cwd 미러 해제(맵 누수 방지)
        dismissedMove[tabId] = nil // 이동 제안 무시 이력 해제(맵 누수 방지)
        if agentDetail[tabId] != nil { // 진행 표시 해제(관측 맵은 immutable 교체)
            var map = agentDetail
            map[tabId] = nil
            agentDetail = map
        }
        if agentPrompts[tabId] != nil { // 마지막 프롬프트 해제(관측 맵은 immutable 교체)
            var map = agentPrompts
            map[tabId] = nil
            agentPrompts = map
        }
        agentTranscripts[tabId] = nil // transcript 경로 미러 해제(맵 누수 방지)
        lastBellAt[tabId] = nil // 벨 디바운스 상태 해제
        resetCoalescers(for: tabId) // 배지·알림 병합 이력 해제(맵 누수 방지)
        manualTitles[tabId] = nil // 수동 지정 제목 해제
        persistentIntent[tabId] = nil
        confirmedCloses.remove(tabId) // 확인 게이트 잔여 정리(취소 후 재닫기 등 — 멱등)
        closeConfirmations[tabId] = nil // 확인 배너 상태 정리(멱등)
        // 탭 이름은 **닫히기 전에** 읽어야 한다(맵이 이미 비워지는 중이다).
        releaseTmuxSession(of: tabId, title: tabTitle(tabId)) // 여기서 closeOverride를 동기로 소비한다
        closeOverride[tabId] = nil // 세션이 이미 없어 조기 반환했을 때의 잔여 결정 청소(정상 경로엔 무해 — 멱등)
        tmuxMisses[tabId] = nil
        syncAttachTimer() // 마지막 지속 세션 탭이 닫히면 감시 타이머를 끈다
        engineTitles[tabId] = nil // 엔진 제목 캐시 해제
        syncHasTabs() // 마지막 탭이 닫히면 빈 상태 뷰로 전환(관측 갱신)
        persist()
    }

    /// 탭바(Bonsplit) 컨텍스트 메뉴 액션. Bonsplit이 자체 NSMenu로 띄우고 선택 결과만 여기로 넘긴다
    /// (메뉴를 커스텀 뷰로 갈아끼울 확장점이 라이브러리에 없어 이 메뉴만 시스템 스타일이다).
    /// 처리하지 않는 액션(브라우저·SSH·fork 등 muxa에 없는 기능)은 메뉴에도 뜨지 않는다.
    func splitTabBar(_ controller: BonsplitController, didRequestTabContextAction action: TabContextAction, for tab: Tab, inPane pane: PaneID) {
        switch action {
        case .rename: promptRenameTab(tab.id)
        case .clearName: clearTabName(tab.id)
        case .closeOthers: closeTabs(inPane: pane) { $0.id != tab.id }
        case .closeToLeft: closeTabs(inPane: pane, side: .left, of: tab.id)
        case .closeToRight: closeTabs(inPane: pane, side: .right, of: tab.id)
        case .newTerminalToRight: newTerminal(inPane: pane)
        case .copyIdentifiers: copyTabId(tab.id)
        default: break
        }
    }

    private enum TabSide { case left, right }

    /// 기준 탭의 한쪽에 있는 탭을 모두 닫는다(탭바 메뉴의 "왼쪽/오른쪽 탭 닫기").
    private func closeTabs(inPane pane: PaneID, side: TabSide, of tabId: TabID) {
        let tabs = controller.tabs(inPane: pane)
        guard let pivot = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let range = side == .left ? tabs[..<pivot] : tabs[(pivot + 1)...]
        let doomed = Set(range.map(\.id))
        closeTabs(inPane: pane) { doomed.contains($0.id) }
    }

    /// 조건에 맞는 탭을 닫는다. 닫는 도중 목록이 바뀌므로 대상 id를 먼저 확정한 뒤 지운다.
    private func closeTabs(inPane pane: PaneID, where predicate: (Tab) -> Bool) {
        for id in controller.tabs(inPane: pane).filter(predicate).map(\.id) {
            _ = controller.closeTab(id, inPane: pane)
        }
    }

    /// 탭 id를 클립보드로 — muxa notify 등 훅에서 이 칸을 지목할 때 쓴다(MUXA_TAB_ID와 같은 값).
    private func copyTabId(_ tabId: TabID) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tabId.uuid.uuidString, forType: .string)
    }

    // MARK: 탭 명명 — 자동(SET_TITLE) + 수동 rename
    //
    // 엔진(셸 OSC 0/2)이 보낸 제목으로 탭 이름을 자동 갱신하되, 사용자가 수동 지정한 탭은 덮지 않는다.
    // manualTitles가 플래그 겸 값이고, engineTitles는 수동 해제 시 되돌릴 최신 자동 제목을 캐시한다.

    /// 새 터미널·복원 시 탭의 기본 이름.
    static let defaultTerminalTitle = "터미널"

    /// 사용자가 수동 지정한 탭 제목(tabId→제목). 존재하면 엔진 제목이 덮지 않는다.
    @ObservationIgnored private var manualTitles: [TabID: String] = [:]
    /// 엔진이 마지막으로 보낸 제목 — 수동 제목 해제 시 이 값으로 되돌린다.
    @ObservationIgnored private var engineTitles: [TabID: String] = [:]

    /// Bonsplit으로 나가는 제목의 **단일 관문** — 지속 세션(∞) 탭이면 "∞ " 접두를 단다.
    /// 왜 제목인가·왜 원본에 안 넣는가는 `TabTitle.decorate` 주석(상태 마크가 아이콘 슬롯을 차지해
    /// ∞가 안 보이는 문제의 해법). 제목을 밀어넣는 코드는 반드시 이 관문을 거친다 — 직접
    /// `controller.updateTab(title:)`을 부르면 그 경로만 접두가 빠져 표시가 깜빡인다.
    private func pushTitle(_ title: String, for tabId: TabID, hasCustomTitle: Bool? = nil) {
        let decorated = TabTitle.decorate(title, persistent: isPersistent(tabId))
        if let hasCustomTitle {
            controller.updateTab(tabId, title: decorated, hasCustomTitle: hasCustomTitle)
        } else {
            controller.updateTab(tabId, title: decorated)
        }
    }

    /// 엔진(SET_TITLE)이 보낸 제목을 탭에 반영한다 — 터미널 탭만, 수동 지정 탭은 건드리지 않는다.
    private func applyEngineTitle(_ raw: String, for tabId: TabID) {
        guard case .terminal = content(for: tabId) else { return } // 그룹 탭은 종류 제목 유지
        // 셸 기본 제목("user@host:~/path")은 탭 폭에 안 들어가 잘린다 — 마지막 폴더 이름만 남긴다.
        let title = TabTitle.shorten(raw)
        guard !title.isEmpty else { return }
        engineTitles[tabId] = title
        guard manualTitles[tabId] == nil else { return } // 수동 지정 우선
        pushTitle(title, for: tabId)
    }

    /// 사용자가 탭 이름을 수동 지정한다 — 이후 엔진 제목은 무시된다.
    func renameTab(_ tabId: TabID, to raw: String) {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        manualTitles[tabId] = title
        pushTitle(title, for: tabId, hasCustomTitle: true)
        persist()
    }

    /// 수동 제목을 해제하고 자동 명명으로 되돌린다(최신 엔진 제목 없으면 기본값).
    func clearTabName(_ tabId: TabID) {
        guard manualTitles[tabId] != nil else { return }
        manualTitles[tabId] = nil
        let fallback = engineTitles[tabId] ?? Self.defaultTerminalTitle
        pushTitle(fallback, for: tabId, hasCustomTitle: false)
        persist()
    }

    /// 탭 이름 변경 입력 시트(NSAlert + 텍스트 필드). 확정하면 renameTab.
    /// 탭바 메뉴(Bonsplit)와 칸 우클릭 메뉴(TerminalPaneMenu)가 함께 쓴다.
    func promptRenameTab(_ tabId: TabID) {
        let alert = NSAlert()
        alert.messageText = "탭 이름 변경"
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = tabTitle(tabId)
        field.placeholderString = Self.defaultTerminalTitle
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            renameTab(tabId, to: field.stringValue)
        }
    }

    /// 현재 포커스된 패인의 터미널(단축키 대상 — ⌘F 등). diff 등 비-터미널 탭이면 nil.
    var focusedTerm: TermView? {
        guard let pane = controller.focusedPaneId,
              let tab = controller.selectedTab(inPane: pane),
              case .terminal = content(for: tab.id) else { return nil }
        return term(for: tab.id)
    }

    /// 칸→탭 순서로 만나는 첫 터미널(포커스가 diff 등 비-터미널일 때의 폴백). 없으면 nil.
    private var firstTerminal: TermView? {
        for paneId in controller.allPaneIds {
            for tab in controller.tabs(inPane: paneId) where terms[tab.id] != nil {
                if case .terminal = content(for: tab.id) { return term(for: tab.id) }
            }
        }
        return nil
    }

    /// 외부 텍스트(리뷰 코멘트 등)를 에이전트 터미널에 붙여 다음 턴 지시로 되먹인다. 포커스가 diff면 첫 터미널로.
    /// 실행(Enter)은 커밋하지 않고 붙여넣기만 한다 — 사용자가 내용을 확인하고 직접 제출하게 둔다(신뢰 경계).
    /// 보낼 터미널이 없으면 false.
    @discardableResult
    func injectToTerminal(_ text: String) -> Bool {
        let body = text.hasSuffix("\n") ? String(text.dropLast()) : text // 끝 개행 = Enter 오해 방지
        guard let term = focusedTerm ?? firstTerminal, !body.isEmpty else { return false }
        term.sendText(body)
        return true
    }

    /// 탭의 내용 종류(터미널이거나 diff 등 뷰어).
    func content(for tabId: TabID) -> TabContent {
        tabContent[tabId] ?? .terminal
    }

    /// 이 프로젝트의 소유 창을 바꾼다 — 서피스를 옮기는 게 아니라 **소유권만 새긴다**(ARCHITECTURE D28).
    /// 스탬프가 바뀌면 새 창의 뷰 계층이 스스로 재부모화하고, 옛 창의 죽어가는 트리는 무동작이 된다.
    /// focusedTab의 서피스만 새 창에서 키를 받는다(원샷).
    func setOwnerWindow(_ id: WindowID, focusedTab: TabID?) {
        ownerWindowId = id.rawValue
        for (tabId, term) in terms {
            term.ownerWindowId = id.rawValue
            term.requestFocusOnAttach = tabId == focusedTab
        }
    }

    /// tabId에 대응하는 터미널 뷰(없으면 생성). 패인 내용 렌더에서 호출한다.
    func term(for tabId: TabID) -> TermView {
        if let t = terms[tabId] { return t }
        // tabId·소켓 경로를 셸 env로 주입(훅 알림용) — TermView.init에서 서피스 생성 전에 심는다.
        // 복원·상속 힌트가 있으면 그 디렉터리에서, 없으면 워크스페이스 기본 cwd에서 새 셸.
        // 지속 세션(∞ 버튼)이면 셸을 tmux 세션 안에서 띄운다 — 앱을 껐다 켜도 그 안의 프로세스가 살아남는다.
        // 그 탭에서는 스크롤백 리플레이를 하지 않는다: tmux가 화면과 프로세스를 통째로 갖고 있으므로
        // 죽은 텍스트를 덧그리면 잔상만 생긴다.
        let tabCwd = pendingCwd[tabId] ?? cwd
        let tmuxSession = tmuxSessionName(for: tabId)
        // env를 -e로 심는다 — tmux 세션의 셸은 tmux 서버 환경을 상속해서, 이걸 빼면 훅 알림이
        // 어느 탭인지 못 찾고 rc 스니펫도 안 돈다(실측).
        // ghostty `command` 필드로 직접 exec한다(초기입력 주입 아님) — tmux attach 명령이 셸에
        // 에코돼 탭이 열릴 때 번쩍이던 것을 없앤다. execCommand가 `/bin/sh -c '…; exec -l $SHELL'`로
        // 감싸 detach 후에도 셸이 남는다(탭 생존 유지).
        let command = tmuxSession.map { session in
            let env = ["MUXA_TAB_ID": tabId.uuid.uuidString,
                       "MUXA_SURFACE_ID": tabId.uuid.uuidString,
                       "MUXA_SOCK": NotifyServer.socketPath]
            let inner = TerminalSession.startCommand(tmux: TmuxService.executable ?? "tmux",
                                                     socket: TmuxService.socket,
                                                     session: session, cwd: tabCwd ?? SystemPaths.home,
                                                     env: env)
            return TerminalSession.execCommand(inner)
        }
        let t = TermView(app: app, cwd: tabCwd, tabId: tabId, sockPath: NotifyServer.socketPath,
                         restoreScrollbackFile: tmuxSession == nil ? restoredScrollbackFile[tabId] : nil,
                         command: command)
        // 나중에 만들어지는 TermView도 현재 소유 창을 물려받아야 한다 — 안 그러면 분리 창에서 새로 연
        // 탭이 "메인 소유"로 태어나 어느 창에도 안 붙는다.
        t.ownerWindowId = ownerWindowId
        // 콜백은 action_cb(메인 async)·becomeFirstResponder(메인)에서만 불린다 → assumeIsolated 안전.
        t.onSignal = { [weak self] signal in MainActor.assumeIsolated { self?.handleSignal(signal, from: tabId) } }
        t.onClearBadge = { [weak self] tid in MainActor.assumeIsolated { self?.clearTabBadge(tid) } }
        // 셸 종료 → 이 탭만 닫는다(앱 종료 아님). closeTab→didCloseTab→terms[tid]=nil→TermView deinit이
        // 서피스를 free한다. close_surface_cb는 요청일 뿐 libghostty가 직접 free하지 않아 이중 free 아님.
        t.onRequestClose = { [weak self] tid in
            MainActor.assumeIsolated { _ = self?.controller.closeTab(tid) }
        }
        t.onTitle = { [weak self] title in
            MainActor.assumeIsolated { self?.applyEngineTitle(title, for: tabId) }
        }
        t.onPwd = { [weak self] pwd in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pwds[tabId] = pwd
                // OSC 7은 **셸이 화면을 쥘 때**(프롬프트)만 나온다 — 도착 자체가 "에이전트가 물러났다"는 신호라
                // 훅 cwd 미러는 스테일로 보고 버린다(안 버리면 cc 종료 후에도 이동 배너·링크 탭이 유령으로 남는다).
                // cc가 다시 돌면 다음 훅이 다시 채운다. ∞(tmux) 탭은 바깥 OSC 7이 안 와 이 정리가 닿지 않는다(알려진 한계).
                if self.agentCwds[tabId] != nil { self.agentCwds[tabId] = nil }
                self.onPwdChange?() // cd로 새 워크트리에 들어간 세션 → AppState가 자동 승격을 판정한다
            }
        }
        terms[tabId] = t
        return t
    }

    /// 백그라운드 활동으로 이 탭에 배지(●)를 켠다 — 탭 점(Bonsplit isDirty) + 프로젝트 알림 + 인박스 이력.
    /// 같은 (tabId,kind)가 cooldown 안에 다시 오면 병합해 억제한다 — 배지는 이미 켜져 있어 시각 손실 없이
    /// 인박스·프로젝트 알림 폭주만 접는다. 주의가 해소(clearTabBadge)되면 병합기가 리셋돼 다음 신호는 통과.
    private func markBadge(_ tabId: TabID, kind: AttentionKind, tone: StatusTone, title: String) {
        let (admit, next) = badgeCoalescer.admitting(BadgeKey(tabId: tabId, kind: kind),
                                                     now: ProcessInfo.processInfo.systemUptime)
        badgeCoalescer = next
        guard admit else { return }
        badgedTabs.insert(tabId)
        controller.updateTab(tabId, isDirty: true)
        onProjectActivity?()
        onAttention?(tabId, kind, tone, title)
    }

    /// 인박스 이력에 쓸 탭 제목 — 수동 지정 > 엔진 제목 > 기본값.
    private func tabTitle(_ tabId: TabID) -> String {
        manualTitles[tabId] ?? engineTitles[tabId] ?? Self.defaultTerminalTitle
    }

    /// 훅(NotifyServer)에서 온 결정론적 알림을 이 스토어가 소유한 탭으로 라우팅한다. 소유하면 true.
    /// 셸이 도는 탭은 반드시 TermView(=terms)가 생성돼 있으므로 terms 유무로 소유를 판정한다.
    /// waiting/done은 순수 배달 게이트(NotificationGate)가 카테고리·가시성으로 배달을 가르고,
    /// working(작업 재개)은 주의 해소로 보고 배지를 끈다. resume이 실려 오면 재개 바인딩을 등록한다
    /// (state 없이 바인딩만 오는 메시지도 있어 state는 옵셔널 — 없으면 상태 신호 없이 바인딩만 등록).
    @discardableResult
    func deliverNotify(tabId incoming: TabID, state: NotifyState?, title: String, body: String,
                       category: NotifyCategory? = nil, resume: ResumeBinding? = nil) -> Bool {
        guard let tabId = resolveTab(incoming) else { return false }
        if let resume { setResumeBinding(resume, for: tabId) }
        if let state {
            // 명시 신호는 상태 추정의 ground truth — 배지 경로와 별개로 추정기에 항상 고정 반영한다(ARCHITECTURE 4.5).
            applyAgentSignal(.explicit(state), to: tabId)
            switch state {
            case .waiting, .done:
                // category 미지정이면 state에서 파생(하위호환) — 게이트가 배달 방식을 결정한다.
                fireNotification(tabId, title: title, body: body,
                                 category: category ?? state.defaultCategory, kind: .notify)
            case .working:
                clearTabBadge(tabId)
            case .idle:
                break // 유휴는 조용 — 알림도, 배지 변경도 없다(안 본 완료 배지는 "봐야 사라진다"라 그대로 둔다)
            }
        }
        return true
    }

    // MARK: 훅(Claude Code) 경로 — 원본 payload → 순수 해석 → 배달
    //
    // 추정(RENDER heartbeat + idle 타이머)과 달리 이 경로는 ground truth다. 훅이 붙은 탭은
    // 추정에 기대지 않고, 에이전트가 직접 말해주는 사실(도구 호출·배경 작업·서브에이전트)로 판단한다.

    /// 탭별 훅 세션 상태(순수 값) — 배경 작업·서브에이전트 로스터를 이벤트 사이에 유지한다.
    @ObservationIgnored private var hookSessions: [TabID: HookSessionState] = [:]
    /// 훅 신호를 한 번이라도 받은 탭 — 이 탭의 raw OSC 9/777 알림은 버린다(이중 발화 방지).
    /// Claude는 자체 OSC 알림도 쏘기 때문에, 훅 알림과 겹치면 같은 사건으로 두 번 울린다.
    @ObservationIgnored private var hookedTabs: Set<TabID> = []
    /// 보류 만료 타이머의 세대값 — 새 보류가 걸리면 이전 타이머를 무효화한다(중복 완료 방지).
    @ObservationIgnored private var deferredSeq: [TabID: Int] = [:]

    /// 훅 원본 payload를 해석해 이 스토어가 소유한 탭에 반영한다. 소유하면 true(라우팅 종료).
    ///
    /// 해석은 순수 함수(ClaudeHookInterpreter)가 하고, 여기서는 부작용만 실행한다:
    /// 상태 전이 고정(pin) · 진행 표시 갱신 · 재개 바인딩 등록 · 알림 발사.
    @discardableResult
    func deliverHook(tabId incoming: TabID, event: ClaudeHookEvent, payload: ClaudeHookPayload) -> Bool {
        guard let tabId = resolveTab(incoming) else { return false }
        hookedTabs.insert(tabId)
        // 훅이 실어 온 cwd = 에이전트의 실제 작업 폴더(EnterWorktree 반영 — 셸 OSC 7은 이걸 못 본다).
        // 워크트리 자동 승격·링크 카드의 신호라, 바뀌면 상위(AppState)에 재판정을 청한다.
        if let cwd = payload.cwd, agentCwds[tabId] != cwd {
            agentCwds[tabId] = cwd
            onPwdChange?()
        }
        // transcript 경로 미러 — hover 팝오버(첨부 이미지)가 읽는다. 세션이 바뀌면 경로도 바뀌므로 늘 최신으로.
        if let transcript = payload.transcriptPath { agentTranscripts[tabId] = transcript }

        let (outcome, next) = ClaudeHookInterpreter.interpret(
            event: event, payload: payload, state: hookSessions[tabId] ?? HookSessionState()
        )
        hookSessions[tabId] = next

        apply(outcome, to: tabId)
        return true
    }

    /// 해석 결과(순수)를 부작용으로 옮긴다 — 훅 배달과 보류 만료가 공유하는 단일 경로.
    private func apply(_ outcome: HookOutcome, to tabId: TabID) {
        if let resume = outcome.resume { setResumeBinding(resume, for: tabId) }
        updateAgentDetail(tabId, outcome: outcome)
        // 마지막 프롬프트 — 새 프롬프트만 덮는다(nil은 "변화 없음", 지우기가 아니다. 완료 후에도 남는다).
        if let prompt = outcome.prompt, agentPrompts[tabId] != prompt {
            var map = agentPrompts
            map[tabId] = prompt
            agentPrompts = map
        }

        if let state = outcome.state {
            // 훅은 ground truth — 추정기에 고정(pin)해 노이즈 RENDER가 상태를 되돌리지 못하게 한다.
            //
            // **배지는 건드리지 않는다.** working은 도구 호출마다 오는 기계 이벤트지 "사용자가 봤다"가
            // 아니다. 여기서 clearTabBadge를 부르면 (1) 사용자가 못 본 완료 배지를 배경 작업이 지워버리고
            // (2) 알림 병합 이력까지 리셋돼 폭주 방지가 무력화된다. 배지는 사용자가 탭을 볼 때만 지운다.
            applyAgentSignal(.explicit(state), to: tabId)
        }
        if outcome.deferredDone { scheduleDeferredExpiry(for: tabId) }
        guard let category = outcome.category else { return } // 상태만 갱신(알림 없음)

        // 본문이 비면 transcript 꼬리에서 "Claude가 마지막으로 한 말"을 길어 온다.
        // 파일 IO + flush 레이스 재시도가 있어 반드시 백그라운드에서 읽는다.
        guard let path = outcome.transcriptPath else {
            fireNotification(tabId, title: outcome.title, body: outcome.body, category: category, kind: .notify)
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            let message = await TranscriptTail.lastAssistantMessage(atPath: path).map(ClaudeHookInterpreter.clamp)
            await MainActor.run {
                // 읽는 사이 탭이 닫혔을 수 있다 — 재확인하지 않으면 didCloseTab이 청소한 맵에
                // 배지·인박스 항목을 다시 심는다(죽은 탭의 알림 = 클릭해도 무동작).
                guard let self, self.terms[tabId] != nil else { return }
                self.fireNotification(tabId, title: outcome.title,
                                      body: message ?? Self.turnCompleteFallbackBody,
                                      category: category, kind: .notify)
            }
        }
    }

    /// 보류된 완료의 만료 타이머 — 푸는 신호(SubagentStop·새 프롬프트)가 안 오면 강제로 완료를 낸다.
    /// 세대값으로 최신 보류만 유효하게 한다(새 Stop이 오면 이전 타이머는 무효).
    private func scheduleDeferredExpiry(for tabId: TabID) {
        let generation = (deferredSeq[tabId] ?? 0) + 1
        deferredSeq[tabId] = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ClaudeHookInterpreter.deferredTimeout * 1_000_000_000))
            guard let self, self.deferredSeq[tabId] == generation, self.terms[tabId] != nil,
                  let state = self.hookSessions[tabId],
                  let resolved = ClaudeHookInterpreter.expireDeferred(state: state) else { return }
            self.hookSessions[tabId] = resolved.state
            self.deferredSeq[tabId] = nil
            self.apply(resolved.outcome, to: tabId)
        }
    }

    /// 진행 표시 갱신 — "지우기"(턴 종료)와 "변화 없음"(알림성 이벤트)을 구분해야 표시가 안 얼어붙는다.
    private func updateAgentDetail(_ tabId: TabID, outcome: HookOutcome) {
        let next: String?
        if outcome.clearsDetail { next = nil }
        else if let detail = outcome.detail { next = detail }
        else { return } // 변화 없음 — 관측 갱신도 하지 않는다
        guard agentDetail[tabId] != next else { return }
        var map = agentDetail
        map[tabId] = next
        agentDetail = map
    }

    /// 탭의 현재 진행 표시(없으면 nil) — 푸터가 활성 탭의 값을 읽는다.
    func agentDetail(for tabId: TabID) -> String? { agentDetail[tabId] }

    /// 탭의 transcript(JSONL) 경로(없으면 nil) — hover 팝오버가 첨부 이미지를 읽을 때 쓴다.
    func agentTranscript(for tabId: TabID) -> String? { agentTranscripts[tabId] }

    /// transcript에서 마지막 메시지를 못 건졌을 때의 완료 본문(빈 본문보다 낫다).
    private static let turnCompleteFallbackBody = "턴이 끝났다"

    /// **복원** 경로 — 되살아난 탭(빈 셸)에 바인딩을 얹고 배너를 띄운다. 실행 여부는 게이트가 정한다.
    private func restoreResumeBinding(_ binding: ResumeBinding, for tabId: TabID) {
        resumeBindings[tabId] = binding
        resumeTabs.insert(tabId)
    }

    /// **훅·알림** 경로 — 에이전트가 지금 이 탭에서 돌고 있다는 신고다. 바인딩만 저장하고 **배너는 띄우지 않는다**
    /// (이어서 할 게 없다 — 이미 돌고 있다). 이 바인딩은 다음 복원 때 스냅샷에서 되살아나 그때 배너가 된다.
    ///
    /// 배너가 떠 있던 탭에서 사용자가 직접 claude를 켠 경우도 여기로 온다 — 그 배너는 이제 유효하지 않으므로 내린다.
    ///
    /// cwd가 비어 오면(구 훅·줄 프로토콜) 그 탭의 현재 셸 pwd로 채운다 — 재개를 그 폴더에 묶어 두기 위한
    /// 단일 보강 지점이다(ResumeGate가 실행 직전 이 값과 대조한다).
    func setResumeBinding(_ binding: ResumeBinding, for tabId: TabID) {
        var bound = binding
        if bound.cwd == nil { bound.cwd = pwds[tabId] }
        resumeBindings[tabId] = bound
        resumeTabs.remove(tabId)
        resumeBlocks[tabId] = nil
        persist()
    }

    /// 탭의 에이전트 재개 바인딩(없으면 nil). 재개 배너가 라벨·명령 미리보기를 읽는 접근자.
    func resumeBinding(for tabId: TabID) -> ResumeBinding? {
        resumeBindings[tabId]
    }

    /// 이 탭의 재개 전략 — 배너(ResumeOverlay)가 이 값 하나로 표시·자동 실행·강조 라벨을 정한다.
    ///
    /// **훅이 확인해 준 세션(source=.hook)만** 승인 게이트를 건너뛰고 자동 실행한다. 단 `off`는
    /// 사용자의 명시적 전면 비활성이라 존중한다.
    ///
    /// cwd 스캔으로 **추측한** 세션(.scan)은 모드+더티 판정(ResumeStrategy.decide)을 거쳐 배너로
    /// 확인받는다 — 추측이 틀리면 엉뚱한 대화를 이어받게 되므로 자동 실행하지 않는다(D2 경계).
    func resumeStrategy(for tabId: TabID) -> ResumeStrategy {
        if resumeBindings[tabId]?.trusted == true {
            return agentResumeMode == .off ? .none : .auto
        }
        return ResumeStrategy.decide(mode: agentResumeMode, wasDirty: sessionWasDirty)
    }

    /// 재개 바인딩을 소비(제거)한다 — 한 번 재개하면 중복 실행·배너 잔존을 막고, 소비를 영속에 반영해
    /// (스냅샷에서도 빠지므로) 재시작 후 이미 재개한 세션을 또 띄우지 않는다. (D2)
    func consumeResumeBinding(for tabId: TabID) {
        guard resumeBindings[tabId] != nil else { return }
        resumeBindings[tabId] = nil
        resumeTabs.remove(tabId)
        resumeBlocks[tabId] = nil
        persist()
    }

    /// 이 탭의 재개 보류 사유(없으면 nil) — 배너가 안내 문구를 읽는 접근자.
    func resumeBlock(for tabId: TabID) -> ResumeGate.Reason? { resumeBlocks[tabId] }

    /// 포그라운드가 셸 자신인가 — **모르면 nil**(pid가 아직 안 잡혔다). 재개 게이트 전용 판정.
    ///
    /// 스크롤백 캡처용 `isRunningForegroundProgram`과 데이터는 같지만 **안전 기본값이 반대**라 따로 둔다:
    /// 캡처는 모르면 해도 되지만(되돌릴 수 있다), 명령 전송은 모르면 하면 안 된다(Enter까지 커밋된다).
    /// 그 차이를 옵셔널로 드러낸다 — 호출부가 "모른다"를 무시할 수 없다.
    private func foregroundIsShell(_ term: TermView) -> Bool? {
        guard let fg = term.foregroundPid, let shell = term.shellPid else { return nil }
        return fg == shell
    }

    /// 경로 비교용 정규화 — 심링크를 해석한다(`/tmp` → `/private/tmp`, `~/dev` → 실제 볼륨).
    /// 기대 경로(claude의 물리 경로)와 셸 pwd(논리 경로)는 표기가 갈릴 수 있어, 비교 전에 같은 지반으로 내린다.
    /// 파일시스템을 만지므로 순수 판정(ResumeGate)이 아니라 이 경계가 맡는다.
    private static func resolvePath(_ path: String?) -> String? {
        guard let path else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// 복원된 에이전트 세션을 재개한다 — 재개 명령을 셸에 입력·실행하고 바인딩을 소비한다.
    ///
    /// 신뢰 경계(D28): command는 훅이 넘긴 재개 명령이다. 승인 게이트(agent_resume)가 off면 실행하지 않고,
    /// manual은 사용자가 배너 버튼으로, auto는 복원 후 자동으로 여기를 호출한다. 어느 경로든 실행은 이 한 곳뿐이고,
    /// 소비가 뒤따라 중복 실행을 막는다(auto의 지연 재호출·onAppear 재발화도 바인딩이 없으면 무동작).
    ///
    /// **보낼 대상이 맞는지는 ResumeGate가 정한다** — 포그라운드가 셸이 아니거나(TUI에 텍스트 주입) 셸이 다른
    /// 폴더에 있으면(그 폴더엔 이 세션이 없다) 보내지 않고 사유만 남긴다. 보류는 소비하지 않으므로,
    /// 사용자가 조건을 맞춘 뒤 배너를 다시 누르면 그때 실행된다. 판정을 돌려주어 auto가 `.notReady`를 재시도한다.
    @discardableResult
    func executeResume(for tabId: TabID) -> ResumeGate.Decision {
        guard agentResumeMode != .off,
              let binding = resumeBindings[tabId],
              let term = terms[tabId] else { return .hold(.notReady) }

        // pwd는 **관측된 값만** 쓴다 — pendingCwd(우리가 셸에게 부탁한 시작 폴더)는 힌트지 사실이 아니다.
        // 그걸 대신 넣으면 "모르면 안 보낸다"가 "추측으로 보낸다"가 된다(rc가 느린 셸·삭제된 폴더).
        let decision = ResumeGate.decide(expectedCwd: Self.resolvePath(binding.cwd),
                                         pwd: Self.resolvePath(term.pwd),
                                         foregroundIsShell: foregroundIsShell(term))
        guard case .send = decision else {
            if case .hold(let reason) = decision { resumeBlocks[tabId] = reason }
            return decision
        }

        resumeBlocks[tabId] = nil
        term.sendText(binding.command + "\n") // 명령 + 실행(Return). sendText가 개행을 Enter로 커밋한다.
        consumeResumeBinding(for: tabId)
        return .send
    }

    /// 알림/배지 클릭으로 이 탭을 앞으로 가져온다 — 그 칸을 선택·포커스하고 배지를 끈다.
    /// 소유(terms/groups에 존재)하지 않으면 무동작.
    func revealTab(_ tabId: TabID) {
        guard terms[tabId] != nil || groups[tabId] != nil else { return }
        controller.selectTab(tabId)
        clearTabBadge(tabId)
    }

    /// 사이드바 분포 클릭이 부른다 — 이 상태의 **다음 탭**으로 순환 선택·포커스한다(여럿이면 누를 때마다 다음).
    /// 순회는 칸→탭 순(quickSwitchTabs와 같은 순서). 현재 선택 탭 뒤의 첫 매칭으로, 없으면 처음으로 감는다.
    /// 매칭 탭이 없으면 false — 호출부(AppState)가 프로젝트 전환을 건너뛴다.
    /// **터미널 탭만** 순회한다 — 뷰어(그룹)·링크 탭은 상태가 없어 항상 idle로 판정되므로,
    /// 걸러내지 않으면 "유휴" 순환이 코드뷰어·HTML 탭까지 돈다(`projectTabStatus`와 같은 모집단).
    func revealNextTab(matching states: Set<AgentActivity>) -> Bool {
        let ordered = controller.allPaneIds.flatMap { pane in
            controller.tabs(inPane: pane).map { (pane: pane, tab: $0.id) }
        }
        let matches = ordered.indices.filter {
            guard case .terminal = content(for: ordered[$0].tab) else { return false }
            return states.contains(agentActivity(for: ordered[$0].tab))
        }
        guard !matches.isEmpty else { return false }
        let current = controller.focusedPaneId.flatMap { controller.selectedTabId(inPane: $0) }
        let currentIdx = ordered.firstIndex { $0.tab == current } ?? -1
        let targetIdx = matches.first { $0 > currentIdx } ?? matches[0] // 다음 매칭, 없으면 순환
        let target = ordered[targetIdx]
        controller.focusPane(target.pane)
        revealTab(target.tab)
        return true
    }

    /// 빠른 전환기(⌘K): 이 스토어의 모든 탭(터미널·그룹)과 그룹 서브탭을 가벼운 값으로 열거한다.
    /// 배지 여부를 함께 실어 "대기 우선" 정렬을 상위(AppState)가 판단하게 한다. 순회 순서는
    /// 칸(pane)→탭 순이라 계층(칸›탭›서브탭)이 자연스럽게 나온다.
    func quickSwitchTabs() -> [QuickTab] {
        var result: [QuickTab] = []
        for paneId in controller.allPaneIds {
            for tab in controller.tabs(inPane: paneId) {
                var subs: [QuickSubTab] = []
                if case .group = content(for: tab.id), let g = groups[tab.id] {
                    subs = g.items.map { QuickSubTab(id: $0.id, title: $0.title, icon: $0.icon) }
                }
                result.append(QuickTab(tabId: tab.id, title: tab.title, icon: tab.icon,
                                       badged: badgedTabs.contains(tab.id), subItems: subs))
            }
        }
        return result
    }

    /// 빠른 전환기: 그룹 탭 안의 특정 서브탭을 선택한다(탭 선택·포커스는 revealTab이 이미 처리).
    /// 그룹 탭이 아니거나 항목이 없으면 무동작.
    func selectGroupItem(_ tabId: TabID, itemId: String) {
        groups[tabId]?.selectedId = itemId
    }

    /// 사용자가 탭을 보면 배지를 끈다. 상시 상태 테두리(waiting/done)도 함께 해제한다("봤음").
    /// 주의가 해소됐으니 이 탭의 병합 이력도 리셋한다 — 다음 신호는 cooldown에 걸리지 않고 곧장 통과.
    func clearTabBadge(_ tabId: TabID) {
        acknowledgeAgent(tabId)
        resetCoalescers(for: tabId)
        guard badgedTabs.contains(tabId) else { return }
        badgedTabs.remove(tabId)
        controller.updateTab(tabId, isDirty: false)
    }

    /// 한 탭의 배지·알림 병합 이력을 지운다(주의 해소·탭 종료 시) — 맵 무한 성장 방지 + 오억제 방지.
    private func resetCoalescers(for tabId: TabID) {
        badgeCoalescer = badgeCoalescer.resetting { $0.tabId == tabId }
        notifyCoalescer = notifyCoalescer.resetting { $0 == tabId }
    }

    /// 사용자가 탭을 봤다 — 상시 상태 테두리를 지운다(추정기를 idle로 리셋해 고정도 푼다).
    /// **완료는 항상** 지우고(끝난 걸 확인함), **대기는 설정 조건부**(clearOnFocus), 작업중·유휴는 그대로 둔다.
    private func acknowledgeAgent(_ tabId: TabID) {
        guard let est = estimators[tabId] else { return }
        // 완료는 **보면 항상 해제**(끝난 걸 확인함). 대기는 사용자 설정 따름(기본 유지 — 다음 활동에만 바뀜).
        // 작업중·유휴는 acknowledge로 지우지 않는다(진행 중이면 계속 표시).
        let shouldClear: Bool
        switch est.state {
        case .done: shouldClear = true
        case .waiting: shouldClear = PaneIndicatorSettings.shared.clearOnFocus
        case .working, .idle: return
        }
        guard shouldClear else { return }
        estimators[tabId] = AgentActivityEstimator(idleThreshold: est.idleThreshold)
        if agentActivity[tabId] != nil {
            var map = agentActivity
            map[tabId] = nil
            agentActivity = map
        }
        // 추정 waiting이 켠 **탭 점**을 여기서 지운다 — 이 탭은 badgedTabs에 없어 clearTabBadge의 정리 경로를
        // 못 타므로(조기 반환), 상태가 idle이 됐음을 탭 점에도 반영해야 "보면 사라진다"가 성립한다.
        // (배지 탭이면 isDirty=badged로 유지 → 뒤이어 clearTabBadge가 배지를 지우며 함께 끈다.)
        reflectTabActivity(tabId, .idle)
        syncIdleTimer()
    }

    // MARK: 백그라운드 주의 신호 — 오탐 억제 후 배지/알림 (알림 신뢰도)
    //
    // TermView는 신호 종류만 넘기고, 여기서 "보이나?"·"울릴 가치가 있나?"를 판정한다.
    // 3~4분할 동시 감시에서 비포커스여도 화면에 보이는 칸(그 칸의 선택 탭)은 배지를 억제한다.

    /// 정상 종료(코드 0/미보고)면서 이 시간(ns)보다 짧게 끝난 명령은 배지를 억제한다.
    /// 짧은 `ls`·`cd` 완료로 배지가 쌓이는 오탐 방지. 기본 8초 — muxa 설정
    /// `command_finished_threshold_sec`로 덮인다(AppState가 init에 주입). (ARCHITECTURE 4.6)
    /// 설정 라이브 리로드로 갱신될 수 있어 var — AppState가 `updateCommandFinishedThreshold`로 전파한다.
    @ObservationIgnored private var commandFinishedThresholdNs: UInt64
    /// 마지막 벨로부터 이 시간(초) 안쪽 벨은 무시 — 벨 연타 오탐 억제.
    private static let bellDebounce: TimeInterval = 1.0

    /// 탭별 마지막 벨 시각(systemUptime, 단조 증가) — 디바운스용.
    @ObservationIgnored private var lastBellAt: [TabID: TimeInterval] = [:]

    // MARK: 알림 dedup/coalescing — 같은 탭 연속 신호 병합 (cmux 대조)
    //
    // auto-approve로 도구를 연타하면 같은 탭 배지·시스템 알림이 폭주한다. cooldown 안의 반복만 접고
    // 진짜 새 신호(다른 (tab,kind)·cooldown 밖)는 통과시킨다. 판정은 순수 SignalCoalescer가, 상태 소유는 store.

    /// 배지 병합 키 — 같은 탭·같은 종류의 연속 배지만 접는다(다른 종류는 별개 주의라 통과).
    private struct BadgeKey: Hashable {
        let tabId: TabID
        let kind: AttentionKind
    }
    /// 같은 (tabId,kind) 배지가 이 시간(초) 안에 다시 오면 병합(억제) — 인박스·프로젝트 알림 폭주 방지.
    private static let badgeCoalesceCooldown: TimeInterval = 2.0
    /// 같은 탭 시스템 알림이 이 시간(초) 안에 다시 오면 병합(억제) — 가장 시끄러운 채널이라 더 길게.
    private static let notifyCoalesceCooldown: TimeInterval = 3.0
    /// 배지 병합기(순수 값) — markBadge의 단일 choke point에서 태운다.
    @ObservationIgnored private var badgeCoalescer = SignalCoalescer<BadgeKey>(cooldown: TerminalStore.badgeCoalesceCooldown)
    /// 시스템 알림 병합기(순수 값, 탭 단위) — fireNotification의 systemNotification 채널에서만 태운다.
    @ObservationIgnored private var notifyCoalescer = SignalCoalescer<TabID>(cooldown: TerminalStore.notifyCoalesceCooldown)

    // MARK: 에이전트 상태 추정 (ARCHITECTURE 4.5) — 순수 추정기 + 신호 배선
    //
    // 탭별 AgentActivityEstimator(순수 값)에 신호(heartbeat·완료·명시 notify·tick)를 넣어 상태를 굴린다.
    // 명시 신호(muxa notify)가 ground truth로 우선하고, 없으면 출력 idle 타이머로 추정한다(보수적).

    /// 탭별 추정기(순수 값). agentActivity(관측 대상)는 여기서 파생한다.
    @ObservationIgnored private var estimators: [TabID: AgentActivityEstimator] = [:]
    /// working 추정 중인 탭이 있을 때만 도는 idle 점검 타이머 — 없으면 CPU를 쓰지 않게 껐다 켠다.
    @ObservationIgnored private var idleTimer: Timer?
    /// idle 추정 tick 주기(초). idleThreshold보다 촘촘해야 전이가 제때 잡힌다.
    private static let idleTickInterval: TimeInterval = 1.0

    /// 신호 하나를 탭의 추정기에 반영하고, 상태가 바뀌었으면 관측 맵을 immutable 교체 + idle 타이머를 재동기화한다.
    private func applyAgentSignal(_ signal: AgentSignal, to tabId: TabID) {
        let now = ProcessInfo.processInfo.systemUptime
        let current = estimators[tabId] ?? AgentActivityEstimator()
        let next = current.applying(signal, now: now)
        estimators[tabId] = next
        // 관측 맵은 상태가 실제로 바뀔 때만 갱신(idle은 키를 지운다) — 불필요한 SwiftUI 무효화 방지.
        if agentActivity[tabId] != next.state {
            var map = agentActivity
            if next.state == .idle { map[tabId] = nil } else { map[tabId] = next.state }
            agentActivity = map
            reflectTabActivity(tabId, next.state)
        }
        syncIdleTimer()
    }

    /// 에이전트 상태를 **탭 좌측 status 마크**로 잇는다 — 사이드바 `StatusMark`와 **같은 어휘·색·모션**
    /// (작업중 인디고 스피너 · 대기 ⏸ 로즈 펄스 · 완료 ✓ 세이지 · 유휴 무표시). `TabStatusMapping`이 매핑하고
    /// Bonsplit의 `Tab.status`가 그 슬롯에 그린다(→ 포크). 유휴는 nil이라 탭이 타입 아이콘으로 폴백한다.
    ///
    /// `isDirty`는 이제 **배지(읽지 않음)만** 진다 — 상태는 status 마크가 표현하므로 여기서 waiting을 OR하지 않는다.
    /// `isLoading`은 status(.spin)가 대신하므로 끈다.
    private func reflectTabActivity(_ tabId: TabID, _ state: AgentActivity) {
        controller.updateTab(tabId,
                             isDirty: badgedTabs.contains(tabId),
                             isLoading: false,
                             status: TabStatusMapping.status(for: state))
    }

    /// working 추정 중인 탭이 하나라도 있으면 타이머를 켜고, 없으면 끈다.
    private func syncIdleTimer() {
        let needsTick = estimators.values.contains { $0.needsIdleTick }
        if needsTick, idleTimer == nil {
            let timer = Timer(timeInterval: Self.idleTickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tickEstimators() }
            }
            RunLoop.main.add(timer, forMode: .common)
            idleTimer = timer
        } else if !needsTick, let timer = idleTimer {
            timer.invalidate()
            idleTimer = nil
        }
    }

    /// 모든 추정기에 tick을 넣어 출력이 멎은 working을 waiting으로 넘긴다(idle 추정).
    private func tickEstimators() {
        let now = ProcessInfo.processInfo.systemUptime
        var map = agentActivity
        var changed = false
        for (tabId, est) in estimators {
            let next = est.applying(.tick, now: now)
            guard next.state != est.state else { continue }
            estimators[tabId] = next
            if next.state == .idle { map[tabId] = nil } else { map[tabId] = next.state }
            reflectTabActivity(tabId, next.state)
            changed = true
        }
        if changed { agentActivity = map }
        syncIdleTimer()
    }

    /// 탭이 닫힐 때 추정기·상태를 해제한다.
    private func clearAgentActivity(_ tabId: TabID) {
        estimators[tabId] = nil
        if agentActivity[tabId] != nil {
            var map = agentActivity
            map[tabId] = nil
            agentActivity = map
        }
        syncIdleTimer()
    }

    /// 탭의 현재 추정 상태(없으면 idle).
    func agentActivity(for tabId: TabID) -> AgentActivity {
        agentActivity[tabId] ?? .idle
    }

    /// 사이드바 에이전트 목록용 — 이 스토어의 **모든 탭**을 표시 스냅샷으로 수확한다(순수 정렬은 뷰 밖 `AgentRow.ordered`).
    ///
    /// 목록은 **모든 탭**을 보인다(뷰어·링크 포함 — 무엇이 열려 있나 한눈에). 분포 pill(`projectTabStatus`)은
    /// 상태 있는 **터미널 탭만** 세므로 행 수 ≠ pill 합계일 수 있다 — 뷰어는 상태가 없어 개수에 안 낀다.
    /// 라이브 도구 한 줄은 hooked 탭에만 있어 없으면 상태 라벨로 폴백한다(계획 #3).
    /// 대기 경과는 `lastOutputAt`(단조시간) 기준으로 **수확 시점에** 계산해 값으로 넘긴다(뷰에 타이머를 두지 않는다, #1).
    func agentRows(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [AgentRow] {
        controller.allTabIds.map { tabId in
            let state = agentActivity[tabId] ?? .idle
            let waitingSeconds: TimeInterval?
            if state == .waiting, let last = estimators[tabId]?.lastOutputAt {
                waitingSeconds = now - last
            } else {
                waitingSeconds = nil
            }
            // 타입 아이콘(WHO/무엇인가) — 터미널은 terminal, 뷰어는 그 종류(문서·코드·변경…).
            let typeIcon: String
            let viewerKind: String?
            let title: String
            var subtabCount: Int?
            switch content(for: tabId) {
            case .terminal:
                typeIcon = "terminal"; viewerKind = nil
                title = tabTitle(tabId)
            case .group(let kind):
                typeIcon = kind.icon; viewerKind = kind.title
                // 그룹 행은 탭 제목(선택 서브탭명·"터미널")이 아니라 **종류가 이름**이다 — "문서·HTML·코드"로
                // 읽히게. 안에 몇 개가 열렸는지는 서브탭 개수가 말한다(행 우측 열).
                title = kind.title
                subtabCount = groups[tabId]?.items.count
            case .worktreeLink:
                typeIcon = "arrow.triangle.branch"; viewerKind = "링크"
                title = tabTitle(tabId)
            }
            return AgentRow(tabId: tabId, title: title, state: state,
                            detail: state == .working ? agentDetail[tabId] : nil,
                            waitingSeconds: waitingSeconds,
                            isAgent: hookedTabs.contains(tabId),
                            typeIcon: typeIcon, viewerKind: viewerKind,
                            subtabCount: subtabCount,
                            prompt: agentPrompts[tabId])
        }
    }

    /// 이 탭이 지금 사용자에게 보이나 — 그 뷰의 창이 실제로 눈에 들어와 있고, 자기 칸의 선택 탭일 때
    /// (줌이면 줌된 칸만). firstResponder가 아니라 selectedTab 기준이라 비포커스지만 보이는 분할 칸을 오판하지 않는다.
    ///
    /// 창 판별을 `isKeyWindow`로 하면 **창이 둘일 때 무너진다** — 분리 창에서 빤히 보고 있는 탭이
    /// 키가 아니라는 이유로 "안 보임"이 돼 알림이 뜬다. 그렇다고 키 여부를 빼면 앱이 백그라운드일 때
    /// 창은 여전히 visible이라 "보임"이 되어 **알림이 전면 억제된다**(제품 가치 소멸).
    /// 그래서 판정은 `appActive`를 포함한 순수 함수(`WindowVisibility`)가 한다.
    private func isTabVisible(_ tabId: TabID) -> Bool {
        guard let term = terms[tabId], let window = term.window,
              WindowVisibility.isVisible(appActive: NSApp.isActive,
                                         windowVisible: window.isVisible,
                                         miniaturized: window.isMiniaturized,
                                         occluded: !window.occlusionState.contains(.visible))
        else { return false }
        if let zoomed = controller.zoomedPaneId {
            return controller.selectedTab(inPane: zoomed)?.id == tabId
        }
        return controller.allPaneIds.contains { controller.selectedTab(inPane: $0)?.id == tabId }
    }

    /// 신호를 오탐 필터에 태워 배지/알림을 결정한다. 보이면 배지 억제(+테두리 훅).
    private func handleSignal(_ signal: TerminalSignal, from tabId: TabID) {
        // 출력 heartbeat는 배지/알림과 무관 — 추정기만 굴리고 끝낸다(작업 중 신호).
        if case .outputHeartbeat = signal {
            applyAgentSignal(.outputHeartbeat, to: tabId)
            return
        }
        // 복원 리플레이(`clear; cat <스크롤백>`)도 셸에겐 하나의 명령이라, 끝나면 셸 통합이
        // OSC 133 D(commandFinished)를 쏜다. 그걸 그대로 받으면 **복원 직후 모든 탭에 "완료"(초록)
        // 배지가 켜진다** — 사용자가 아무 작업도 하지 않았는데. 우리가 주입한 명령의 완료 신호이므로
        // 탭당 첫 1회를 삼킨다.
        if case .commandFinished = signal, replayPendingTabs.remove(tabId) != nil { return }
        let visible = isTabVisible(tabId)
        switch signal {
        case .commandFinished(let exitCode, let duration):
            // 명령 완료는 배지 임계값과 무관하게 상태 추정(done)엔 항상 반영한다.
            applyAgentSignal(.commandFinished, to: tabId)
            // 비정상 종료(코드 != 0)는 지속시간과 무관하게 알린다. 정상+짧은 명령은 억제.
            let abnormal = (exitCode ?? 0) != 0
            guard abnormal || duration >= commandFinishedThresholdNs else { return }
            fireActivity(tabId, kind: .done, title: tabTitle(tabId), visible: visible)
        case .bell:
            let now = ProcessInfo.processInfo.systemUptime
            if let last = lastBellAt[tabId], now - last < Self.bellDebounce { return }
            lastBellAt[tabId] = now
            fireActivity(tabId, kind: .bell, title: tabTitle(tabId), visible: visible)
        case .desktopNotification(let title, let body):
            // 훅이 붙은 탭이면 버린다 — Claude는 자체 OSC 알림도 쏘기 때문에, 훅 알림과 겹쳐 같은 사건으로
            // 두 번 울린다. 훅 payload가 더 정확하고 본문도 풍부하니 구조화된 쪽을 남긴다.
            guard !hookedTabs.contains(tabId) else { return }
            // OSC 9/777 자동 신호 — category nil로 게이트에 태운다(보이면 플래시, 안 보이면 배지+알림: 기존 동작).
            fireNotification(tabId, title: title, body: body, category: nil, kind: .notify)
        case .processExited:
            // 프로세스가 OS 레벨에서 종료 — 결정론 done(셸 통합/OSC 133 없이도 확정). 안 보이는 탭이면 배지.
            // close_surface_cb(탭 닫기)와 별개 경로다: 탭이 닫히면 didCloseTab이 추정기·배지를 정리하고,
            // 서피스가 유지되면(통합 부재 등) 이 done 테두리·배지가 유일한 종료 표식이 된다.
            applyAgentSignal(.processExited, to: tabId)
            if !visible {
                markBadge(tabId, kind: .done, tone: AttentionKind.done.tone(category: nil),
                          title: tabTitle(tabId))
            }
        case .outputHeartbeat:
            break // 위에서 이미 처리하고 반환 — 열거 완전성용.
        }
    }

    /// 안 보이면 배지(+인박스 이력). 보이면 아무것도 안 한다(상태 테두리가 이미 짚는다).
    /// 벨·명령 완료 등 시스템 알림 없는 신호용.
    private func fireActivity(_ tabId: TabID, kind: AttentionKind, title: String, visible: Bool) {
        // 벨·명령 완료는 훅 payload가 없다 — category 없이 톤을 판정한다(done=완료, bell=주의).
        if !visible { markBadge(tabId, kind: kind, tone: kind.tone(category: nil), title: title) }
    }

    /// 알림 발사의 단일 경로 — 순수 게이트(NotificationGate)로 배달 방식을 정하고 채널별로 실행한다.
    /// 자동 신호(OSC 9/777)는 category nil로, 명시 신호(muxa notify)는 실린 category로 들어온다.
    /// 시스템 알림 발사는 AppState에 위임(컨텍스트 부착) — 미배선 시엔 컨텍스트 없이 폴백.
    private func fireNotification(_ tabId: TabID, title: String, body: String,
                                 category: NotifyCategory?, kind: AttentionKind) {
        let delivery = NotificationGate.shouldDeliver(category: category, isVisibleToUser: isTabVisible(tabId))
        if delivery.systemNotification {
            // 같은 탭 연속 시스템 알림은 병합(억제) — 가장 시끄러운 채널이라 연타를 접는다. 배지·인박스는 아래에서 별도 병합.
            let (admit, next) = notifyCoalescer.admitting(tabId, now: ProcessInfo.processInfo.systemUptime)
            notifyCoalescer = next
            if admit {
                if let onNotify { onNotify(tabId, title, body) } else { NotificationService.shared.notify(title: title, body: body) }
            }
        }
        // 훅 알림은 category가 실려 온다 — 승인 대기와 턴 완료를 인박스에서도 가르는 유일한 근거다.
        if delivery.badge {
            markBadge(tabId, kind: kind, tone: kind.tone(category: category),
                      title: title.isEmpty ? tabTitle(tabId) : title)
        }
    }


    /// **분할할 때** 새 셸이 물려받을 작업 디렉터리 — 원본 칸의 현재 pwd(OSC 7). 없으면 nil.
    ///
    /// 새 터미널(⌘T·`+`)은 이걸 쓰지 않는다. 어디서 열든 **프로젝트 기본 경로에서 시작**한다 —
    /// "직전에 어디 있었는지"를 물려받으면 새 탭이 예측 불가능한 곳에서 열린다(`cd`로 잠깐 다른
    /// 디렉터리에 갔던 것뿐인데 다음 탭이 거기서 뜬다). 분할은 "옆에서 이어서 한다"는 뜻이라 다르다.
    private func inheritedCwd(inPane pane: PaneID?) -> String? {
        guard let pane, let tab = controller.selectedTab(inPane: pane) else { return nil }
        return terms[tab.id]?.pwd
    }

    /// 지금 이 스토어에서 "보고 있는" 탭 — 포커스 칸의 선택 탭.
    /// 사이드바 에이전트 목록(L1)이 활성 행(선택 채움)을 표시하는 데 쓴다.
    var currentTabId: TabID? {
        controller.focusedPaneId.flatMap { controller.selectedTabId(inPane: $0) }
    }

    /// 열려 있는 **터미널** 탭이 하나라도 있나(뷰어·정보 탭은 세션이 아니다) —
    /// 사이드바 ✕(프로젝트 닫기) 노출 판정용: 터미널이 살아 있으면 실수 클릭 한 번이 세션을 몰살한다.
    var hasTerminalTabs: Bool {
        controller.allTabIds.contains {
            if case .terminal = content(for: $0) { return true }
            return false
        }
    }

    /// 지금 포커스된 칸의 선택 탭이 있는 디렉터리 — 상태바 표시용.
    /// 터미널이 아닌 탭(문서·diff)에 포커스가 있으면 nil(보여줄 pwd가 없다).
    /// `pwds`(관측)와 `controller.focusedPaneId`(Bonsplit @Observable)를 읽으므로 포커스·cd 양쪽에 반응한다.
    var focusedPwd: String? {
        guard let pane = controller.focusedPaneId,
              let tab = controller.selectedTab(inPane: pane) else { return nil }
        if let content = tabContent[tab.id], case .group = content { return nil } // 문서·diff 탭엔 pwd가 없다
        return pwds[tab.id] ?? pendingCwd[tab.id]
    }

    /// 지금 포커스된 칸의 에이전트 진행 표시("편집 중: TermView.swift") — 푸터가 읽는다.
    /// 훅(PreToolUse/PostToolUse)이 붙은 탭에서만 값이 있다. 추정 경로는 "지금 뭘 하는지"를 알 수 없다.
    var focusedAgentDetail: String? {
        guard let pane = controller.focusedPaneId,
              let tab = controller.selectedTab(inPane: pane) else { return nil }
        return agentDetail[tab.id]
    }

    /// 백그라운드로 남겨둔 세션을 **새 탭으로 되찾는다**(복구 경로).
    ///
    /// 새 탭을 만들되 세션명을 **그대로 이어받게** 심는다 — `term(for:)`가 그 이름으로 attach하므로
    /// 안에서 돌던 프로세스와 화면이 그대로 돌아온다.
    @discardableResult
    func reattach(_ detached: DetachedSession, inPane pane: PaneID? = nil) -> TabID? {
        guard let id = controller.createTab(title: TabTitle.decorate(Self.defaultTerminalTitle,
                                                                     persistent: true),
                                            icon: Self.persistentTabIcon,
                                            inPane: pane) else { return nil }
        tmuxSessions[id] = detached.session // 새 세션을 만들지 않고 이 이름에 붙는다
        persistentIntent[id] = true
        syncAttachTimer() // 되찾은 탭도 이탈 감시 대상이다
        pendingCwd[id] = detached.cwd
        regroup(id, inPane: pane ?? controller.focusedPaneId)
        syncHasTabs()
        persist()
        return id
    }

    /// 영속(∞) 탭을 **다른 스토어로 넘기려고 이 스토어에서 놓는다** — tmux 세션을 kill/record 없이 조용히 놓고
    /// 탭을 닫는다. 세션명을 맵에서 **먼저** 떼어, `didCloseTab`의 `releaseTmuxSession`이 early-return하게 만든다
    /// (그래야 죽이지도, 이 프로젝트의 detached 목록에 남기지도 않는다). tmux 세션은 서버에 detach 상태로 살아 있어
    /// 대상 스토어가 `reattach`로 되찾는다 — **라이브 서피스를 옮기지 않아** 안전하다(프로세스는 tmux 서버에 산다).
    /// 영속 탭이 아니면 nil(일반 터미널은 프로세스가 로컬 서피스에 묶여 옮길 수 없다 — 링크 카드는 "가서 보기"만 준다).
    func handOffPersistentTab(_ tabId: TabID) -> DetachedSession? {
        guard persistentIntent[tabId] == true, let session = tmuxSessions[tabId] else { return nil }
        let detached = DetachedSession(session: session, command: tabTitle(tabId), cwd: pwds[tabId],
                                       title: tabTitle(tabId), detachedAt: Date())
        tmuxSessions[tabId] = nil        // 놓기 전에 잊는다 → releaseTmuxSession이 kill/record 없이 반환
        persistentIntent[tabId] = nil
        syncAttachTimer()
        _ = controller.closeTab(tabId)   // 서피스는 free되지만 tmux 세션은 detach 상태로 살아 있다
        return detached
    }

    /// 새 터미널 탭 생성(분할 후 빈 패인 채우기·⌘T 등).
    /// `inheritingFrom`은 작업 디렉터리를 물려받을 원본 칸(분할이면 분할된 칸). 없으면 탭이 생길 칸에서 상속한다.
    /// - Parameter persistent: 이 탭을 tmux 지속 세션(∞)으로 열지.
    ///   **nil이면 분할은 원본 칸에서 물려받고, 그 밖(`+`·⌘T·메뉴)은 tmux가 있으면 지속 세션이다.**
    ///   기본을 지속으로 두는 이유: 이 앱의 터미널은 대개 에이전트·빌드가 도는 자리라, 앱을 닫거나
    ///   실수로 탭을 닫았을 때 살아남는 쪽이 기본값이어야 손실이 없다. tmux가 없으면 일반 셸이다
    ///   (`TmuxService.isAvailable` — 설치를 강요하지 않고, ∞ 배지가 거짓말하지 않게 같은 값으로 판단).
    ///   일반 셸을 명시적으로 원하는 자리(데모 등)는 `persistent: false`를 넘긴다.
    @discardableResult
    func newTerminal(inPane pane: PaneID? = nil, inheritingFrom source: PaneID? = nil,
                     persistent: Bool? = nil) -> TabID? {
        // createTab이 새 탭을 즉시 선택하므로, 원본 칸의 pwd·지속 여부는 생성 전에 읽는다.
        // cwd는 **분할일 때만** 물려받고(새 탭은 프로젝트 기본 경로), 지속 여부는 분할이면 상속·아니면 기본값.
        let start = source.flatMap { inheritedCwd(inPane: $0) } ?? cwd
        // 일회용 스토어는 tmux가 있어도 기본이 일반 셸이다(지속을 아예 제공하지 않는다).
        let wantsPersistent = persistent
            ?? source.map { inheritedPersistence(inPane: $0) }
            ?? (ephemeral ? false : TmuxService.isAvailable)
        let id = controller.createTab(title: TabTitle.decorate(Self.defaultTerminalTitle,
                                                               persistent: wantsPersistent),
                                      icon: wantsPersistent ? Self.persistentTabIcon : Self.terminalTabIcon,
                                      inPane: pane)
        if let id {
            pendingCwd[id] = start
            // 의도는 서피스가 만들어지기 전에 정해져야 한다 — term(for:)가 이걸 보고 tmux로 띄울지 정한다.
            persistentIntent[id] = wantsPersistent
            regroup(id, inPane: pane ?? controller.focusedPaneId)
        }
        syncHasTabs() // 빈 상태에서 새 터미널을 열면 BonsplitView로 복귀(관측 갱신)
        persist()
        return id
    }

    // MARK: 탭 그룹핑 — 같은 종류끼리 묶기 (터미널 | 문서 | diff)
    //
    // 탭바에서 "문서는 문서끼리, diff는 diff끼리" 인접하도록 종류별 rank로 정렬 위치를 잡는다.
    // 복원 중엔 저장된 순서를 존중하므로 건너뛴다.

    /// 탭 종류 정렬 순위 — 터미널(0) < 문서(1) < HTML(2) < 코드(3) < 미디어(4) < 변경(5). 같은 순위는 생성 순서 유지.
    private func groupRank(_ content: TabContent) -> Int {
        switch content {
        case .terminal, .worktreeLink: return 0 // 링크 탭은 터미널과 같은 자리(맨 앞 무리)
        case .group(.documents): return 1
        case .group(.html): return 2
        case .group(.code): return 3
        case .group(.media): return 4
        case .group(.diffs): return 5
        }
    }

    /// 방금 만든 탭을 같은 종류 묶음의 끝(다음 순위 묶음 앞)으로 이동해 클러스터를 유지한다.
    private func regroup(_ tabId: TabID, inPane pane: PaneID?) {
        guard !restoring, let pane else { return }
        let rank = groupRank(content(for: tabId))
        // 자기 자신을 뺀 나머지 중 순위 ≤ 내 순위인 탭 수 = 삽입 위치(내 묶음의 끝).
        let dest = controller.tabs(inPane: pane)
            .filter { $0.id != tabId }
            .reduce(0) { $0 + (groupRank(content(for: $1.id)) <= rank ? 1 : 0) }
        _ = controller.reorderTab(tabId, toIndex: dest)
    }

    /// diff를 변경 그룹 탭의 서브탭으로 연다.
    @discardableResult
    func openDiff(_ target: GitDiffTarget) -> TabID? {
        let id = openInGroup(.diff(target)); persist(); return id
    }

    /// 파일을 종류별(문서/HTML/코드) 그룹 탭의 서브탭으로 연다.
    @discardableResult
    func openFile(_ path: String) -> TabID? {
        let id = openInGroup(.file(FileViewTarget(path: path)))
        lastOpenedFilePath = path
        revealSeq += 1 // 익스플로러 reveal 트리거(같은 파일 재-open도 반영)
        persist()
        return id
    }

    /// 그룹 탭 상태 접근 — BonsplitWorkspaceView가 .group 탭 렌더 시 사용.
    func group(for tabId: TabID) -> TabGroupState? { groups[tabId] }

    /// ⌘W — 활성 칸의 선택 탭을 닫는다. 그룹 탭(문서/변경)이면 서브탭이 둘 이상일 땐 **선택 서브탭만** 닫고,
    /// 하나뿐이면 그룹 탭째 닫는다(closeGroupItem이 빈 그룹은 탭까지 정리). 터미널 탭은 통째로 닫는다.
    func closeActiveTab() {
        guard let pane = controller.focusedPaneId, let tab = controller.selectedTab(inPane: pane) else { return }
        if case .group = content(for: tab.id), let g = group(for: tab.id), let sel = g.selected {
            closeGroupItem(tab.id, itemId: sel.id)
        } else {
            _ = controller.closeTab(tab.id, inPane: pane)
        }
    }

    /// 이 서브탭만 남기고 같은 그룹의 나머지를 닫는다(서브탭 우클릭 "다른 서브탭 모두 닫기").
    /// 하나는 반드시 남으므로 그룹 탭 자체가 사라지지 않는다.
    func closeOtherGroupItems(_ tabId: TabID, keeping itemId: String) {
        guard let state = groups[tabId] else { return }
        for other in state.items.map(\.id) where other != itemId {
            _ = state.remove(other)
        }
        persist()
    }

    /// 서브탭 닫기 → 그룹이 비면 그룹 탭 자체를 닫는다.
    func closeGroupItem(_ tabId: TabID, itemId: String) {
        guard let state = groups[tabId] else { return }
        if state.remove(itemId) {
            _ = controller.closeTab(tabId) // didCloseTab에서 groups 정리(+persist)
        } else {
            persist()
        }
    }

    // MARK: 2단 탭 — 문서/diff는 종류별 그룹 탭 하나에 서브탭으로 모은다
    //
    // 상단 탭바엔 종류별 그룹 탭([문서]/[변경])이 하나씩 서고, 그 아래에 서브탭(개별 파일/커밋)이
    // 뜬다. 같은 항목을 다시 열면 그 그룹을 선택하고 해당 서브탭으로 전환한다.

    @discardableResult
    private func openInGroup(_ item: GroupItemContent) -> TabID? {
        let kind = item.kind
        let pane = controller.focusedPaneId
        // dedup은 '포커스 패인' 기준 — 다른 패인에 같은 파일이 열려 있어도, 지금 활성 패인에 연다.
        // 1) 포커스 패인에 같은 종류 그룹 탭이 있으면 거기서 처리(add가 중복이면 선택만, 아니면 추가).
        if let pane, let tabId = groupTab(ofKind: kind, inPane: pane) {
            groups[tabId]?.add(item)
            controller.selectTab(tabId)
            return tabId
        }
        // 2) 없으면 포커스 패인에 새 그룹 탭 생성.
        guard let tabId = controller.createTab(title: kind.title, icon: kind.icon, inPane: pane) else { return nil }
        tabContent[tabId] = .group(kind)
        groups[tabId] = TabGroupState(first: item)
        regroup(tabId, inPane: pane)
        controller.selectTab(tabId)
        syncHasTabs() // 빈 상태에서 문서/diff를 열어도 메인 영역 복귀(관측 갱신)
        return tabId
    }

    /// 패인 안에서 주어진 종류의 그룹 탭을 찾는다(종류별 최대 1개).
    private func groupTab(ofKind kind: TabGroupKind, inPane pane: PaneID) -> TabID? {
        controller.tabs(inPane: pane).first { tab in
            if case .group(let k) = content(for: tab.id) { return k == kind }
            return false
        }?.id
    }

    /// 최초 표시 시: 저장된 스냅샷이 있으면 복원, 없으면 초기 터미널 1개.
    func ensureInitialTerminal() {
        guard !initialized else { return }
        initialized = true
        // Bonsplit이 컨트롤러 생성 시 자동으로 넣는 "Welcome"/star 탭. 실제 탭을 만든 뒤 이걸 닫는다.
        let bootstrap = Set(controller.allTabIds)
        if let snap = restoreSnap {
            restoreSnap = nil
            restoreLayout(snap)
        } else if initialWorktreeLink {
            // 자동 승격된 워크트리 프로젝트 — 첫 화면은 셸이 아니라 **링크 탭**("작업이 다른 탭에서 진행 중").
            _ = openWorktreeLinkTab()
        } else {
            // newTerminal 경유 — 직접 createTab하면 persistentIntent가 안 서서 첫 탭만 일반 셸이 된다.
            _ = newTerminal(inPane: nil)
        }
        // 실제 탭이 생겼으면 부트스트랩 welcome을 닫는다(복원이 이미 선택을 잡았으므로 순서 안전).
        let real = controller.allTabIds.filter { !bootstrap.contains($0) }
        if !real.isEmpty {
            for id in bootstrap { _ = controller.closeTab(id) }
        }
        if controller.allTabIds.isEmpty {
            _ = newTerminal(inPane: nil)
        }
        syncHasTabs() // 초기 탭 확정 → 빈 상태 게이트(showEmptyState) 해제
        ready = true // 이후 탭/뷰어 변경은 즉시 저장(⌘Q 없이도 복원되게)
    }

    // MARK: 세션 저장·복원 — 통합 스냅샷(트리 + 탭별 종류·payload). cmux 방식.
    //
    // PTY는 프로세스라 복원 불가 → 터미널은 워크스페이스 cwd에서 새 셸. 문서/커밋 diff는
    // 경로/해시로 재생성. 구조·순서·선택을 그대로 담아 단일 패스로 복원(선택 튐·빈 터미널 방지).

    /// 현재 레이아웃 → 저장 스냅샷. AppState.save가 사용.
    ///
    /// `captureScrollback`이 false면 서피스 리드백·파일 쓰기를 건너뛰고 **기존 스크롤백 파일 경로만**
    /// 이어 붙인다 — 패널 토글·활성 탭 전환 같은 잦은 메타 저장이 열린 모든 터미널 화면을 매번 다시
    /// 쓰지 않게 한다(무거운 IO는 종료 시 endSession에서만). 파일 경로는 `<tabId>.txt`로 결정적이라
    /// 재캡처 없이도 직전 내용을 그대로 가리킨다.
    func snapshot(captureScrollback: Bool = true) -> PaneSnapshot {
        convert(controller.treeSnapshot(), captureScrollback: captureScrollback)
    }

    /// 이 탭의 스크롤백 파일이 디스크에 있으면 그 경로(없으면 nil). 재캡처를 건너뛸 때 직전 저장을 잇는다.
    private func existingScrollbackPath(_ tabId: TabID) -> String? {
        let url = ScrollbackStore.fileURL(for: tabId)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    /// 실체화된 터미널의 화면+스크롤백을 읽어(정제·상한) 별도 파일에 쓴다. 저장된 경로(없으면 nil).
    /// 부작용(서피스 리드백·파일 쓰기)은 경계 타입(TermView·ScrollbackStore)에 격리, 정제는 순수 함수.
    ///
    /// **VT(색 포함) 우선, 실패 시 평문 폴백.** 색이 빠진 회색 평문보다는 낫지만, 없는 것보다는 평문이 낫다.
    ///
    /// TUI(vim·less·htop)가 떠 있으면 **캡처하지 않는다** — alt-screen 화면을 저장해봐야 그 프로세스는
    /// 죽어 있고, 복원하면 깨진 전체화면 위에 셸 프롬프트가 겹친다. 이때는 직전 캡처를 그대로 둔다
    /// (nil을 돌려주면 호출부가 이전 힌트를 승계한다). ghostty에 alt-screen 질의 API가 없어
    /// "포그라운드가 셸이 아니다"로 판정한다(cmux도 같은 정책).
    private func captureScrollback(from term: TermView, tabId: TabID) -> String? {
        guard !isRunningForegroundProgram(term) else { return nil }
        if let vt = term.readScreenVT() {
            return ScrollbackStore.write(ScrollbackText.sanitizeVT(vt), for: tabId)
        }
        guard let raw = term.readScreenText() else { return nil }
        return ScrollbackStore.write(ScrollbackText.sanitize(raw), for: tabId)
    }

    /// 셸이 아닌 프로그램이 포그라운드를 잡고 있는가(= TUI일 수 있다).
    private func isRunningForegroundProgram(_ term: TermView) -> Bool {
        guard let fg = term.foregroundPid, let shell = term.shellPid else { return false }
        return fg != shell
    }

    /// 저장 시점에 이 터미널에서 claude가 돌고 있으면 세션 인덱스로 자동 재개 바인딩을 만든다(제로설정, cmux식).
    /// 프로세스 트리(foreground→셸)로 claude 실행을 감지하고, OSC7 cwd로 마지막 세션을 해석한다. 없으면 nil.
    private func detectClaudeResume(from term: TermView, cwd: String?) -> ResumeBinding? {
        guard let cwd, let fg = term.foregroundPid, let shell = term.shellPid,
              AgentProcessDetector.agentRunning(commNames: ["claude"], from: fg, upTo: shell) else { return nil }
        // **스캔 결과는 짧게 캐시한다.** 스캔 1회가 `~/.claude/projects/<cwd>` 전체 stat(세션 수백 개면
        // 수백 회)인데, save()는 탭 생성·닫기·이름변경·패널 토글·창 이동마다 불린다 — 탭마다 스캔하면
        // 메인 스레드에서 stat이 천 번씩 돈다. 세션 id는 이 창(TTL) 안에서 바뀌지 않는다.
        if let hit = resumeScanCache[cwd], Date().timeIntervalSince(hit.at) < Self.resumeScanTTL {
            return hit.binding
        }
        let binding = ClaudeSessionIndex.resumeBinding(forCwd: cwd)
        resumeScanCache[cwd] = (binding, Date())
        return binding
    }

    /// cwd별 스캔 폴백 캐시(짧은 TTL) — 저장 폭주가 디스크를 갈지 않게.
    private var resumeScanCache: [String: (binding: ResumeBinding?, at: Date)] = [:]
    private static let resumeScanTTL: TimeInterval = 5

    private func convert(_ node: ExternalTreeNode, captureScrollback: Bool) -> PaneSnapshot {
        switch node {
        case .pane(let p):
            var tabs: [TabSnapshot] = []
            var selected = 0
            for (i, et) in p.tabs.enumerated() {
                guard let uuid = UUID(uuidString: et.id) else { continue }
                let tid = TabID(uuid: uuid)
                if et.id == p.selectedTabId { selected = tabs.count }
                switch content(for: tid) {
                case .terminal:
                    // 현재 셸 작업 디렉터리 기록 — TermView가 살아 있으면 그 pwd, 아직 미실체화 탭이면 복원 힌트.
                    let tabCwd = terms[tid]?.pwd ?? pendingCwd[tid]
                    // 화면+스크롤백 캡처 — 실체화된 터미널이면 서피스에서 읽어 파일에 쓰고(캡처 요청 시에만),
                    // 아니면 기존 파일 경로나 이전 복원 힌트를 그대로 이어 준다(④). 메타 저장은 재캡처를 건너뛴다.
                    let captured = captureScrollback ? terms[tid].flatMap { self.captureScrollback(from: $0, tabId: tid) } : nil
                    let scrollbackFile = captured ?? existingScrollbackPath(tid) ?? restoredScrollbackFile[tid]
                    // 재개 바인딩 — **훅이 알려준 사실이 먼저다.**
                    // 종전엔 cwd 스캔(추측)이 훅 바인딩을 덮어썼다. 훅은 "이 탭의 세션은 이것"이라고
                    // 확정해 주는데, 그걸 버리고 "이 디렉터리에서 가장 최근에 수정된 jsonl"이라는 추측으로
                    // 갈아끼운 셈이다. 스캔은 훅이 없을 때의 폴백으로만 쓴다.
                    let resume = resumeBindings[tid] ?? terms[tid].flatMap { detectClaudeResume(from: $0, cwd: tabCwd) }
                    tabs.append(TabSnapshot(group: nil, items: [], selectedItem: 0,
                                            cwd: tabCwd, resume: resume,
                                            scrollbackFile: scrollbackFile,
                                            manualTitle: manualTitles[tid],
                                            tmuxSession: tmuxSessions[tid]))
                case .group(let kind):
                    let state = groups[tid]
                    let items = (state?.items ?? []).map(itemSnapshot)
                    let sel = state.flatMap { s in s.items.firstIndex { $0.id == s.selectedId } } ?? 0
                    if items.isEmpty { continue } // 빈 그룹은 저장하지 않음
                    tabs.append(TabSnapshot(group: kind.raw, items: items, selectedItem: sel,
                                            manualTitle: manualTitles[tid]))
                case .worktreeLink:
                    continue // 링크 탭은 영속하지 않는다 — 라이브 세션 참조라 재시작 후엔 유효성을 보장 못 한다
                }
                _ = i
            }
            if tabs.isEmpty { tabs = [TabSnapshot(group: nil, items: [], selectedItem: 0)] } // 빈 패인 방지
            let focused = p.id == controller.focusedPaneId?.id.uuidString
            return .leaf(tabs: tabs, selected: min(selected, tabs.count - 1), focused: focused)
        case .split(let s):
            return .split(vertical: s.orientation == "vertical", divider: s.dividerPosition,
                          first: convert(s.first, captureScrollback: captureScrollback),
                          second: convert(s.second, captureScrollback: captureScrollback))
        }
    }

    private func itemSnapshot(_ item: GroupItemContent) -> ItemSnapshot {
        switch item {
        case .file(let t): return ItemSnapshot(file: t.path, commit: nil, commitSubject: nil)
        case .diff(let target):
            switch target {
            case .commit(let hash, let subject):
                return ItemSnapshot(file: nil, commit: hash, commitSubject: subject)
            case .commitFile(let hash, let path, let oldPath):
                // 커밋 안 파일도 불변이라 복원 대상이다(워크트리 파일 diff와 달리 내용이 안 변한다).
                return ItemSnapshot(file: nil, commit: hash, commitSubject: nil,
                                    commitFile: path, commitFileOldPath: oldPath)
            case .file, .all:
                return ItemSnapshot(file: nil, commit: nil, commitSubject: nil) // 워크트리 diff는 복원 대상 아님
            }
        }
    }

    private func itemContent(_ s: ItemSnapshot) -> GroupItemContent? {
        if let f = s.file { return .file(FileViewTarget(path: f)) }
        guard let h = s.commit else { return nil }
        // 경로가 있으면 커밋 **안 파일 하나** — 통짜 커밋 diff보다 먼저 판정해야 한다
        // (둘 다 `commit`을 쓰므로 순서가 뒤집히면 파일 서브탭이 통짜로 복원된다).
        if let path = s.commitFile {
            return .diff(.commitFile(hash: h, path: path, oldPath: s.commitFileOldPath))
        }
        return .diff(.commit(hash: h, subject: s.commitSubject ?? h))
    }

    /// 복원 중 만난 '활성 칸'과 그 칸의 선택 탭 — 재구성이 끝난 뒤 전역 포커스를 여기로 되돌린다.
    /// (realize가 리프마다 selectTab으로 포커스를 옮기므로, 마지막에 저장 시점의 활성 칸으로 복구해야 함.)
    @ObservationIgnored private var restoreFocus: (pane: PaneID, tab: TabID?)?

    /// 스냅샷을 현재 컨트롤러에 단일 패스로 재구성. 빈 패인 폴백은 ensureInitialTerminal이 담당.
    private func restoreLayout(_ snap: PaneSnapshot) {
        restoring = true
        restoreFocus = nil
        realize(snap, into: controller.allPaneIds.first)
        restoring = false
        // 활성 칸 복원 — 선택 탭이 있으면 selectTab(그 칸 포커스+탭 선택), 없으면 칸만 포커스.
        if let rf = restoreFocus {
            restoreFocus = nil
            if let tab = rf.tab { controller.selectTab(tab) } else { controller.focusPane(rf.pane) }
        }
    }

    /// 스냅샷 노드를 targetPane에 실현한다. leaf=탭들 생성+선택, split=쪼갠 뒤 양쪽 채움.
    private func realize(_ snap: PaneSnapshot, into pane: PaneID?) {
        guard let pane else { return }
        switch snap {
        case .leaf(let tabs, let selected, let focused):
            var created: [TabID] = []
            for t in tabs {
                // 방금 만든 탭만 잡는다(created.last는 생성 실패 시 직전 탭을 가리켜 이름이 엉뚱한 탭에 붙는다).
                var newTab: TabID?
                if let raw = t.group, let kind = TabGroupKind(raw: raw) {
                    newTab = realizeGroup(kind, items: t.items, selectedItem: t.selectedItem, inPane: pane)
                } else if let tid = controller.createTab(
                    // 지속 세션이었던 탭은 복원 후에도 그렇게 보여야 한다 — 아이콘 + 제목 접두(∞).
                    title: TabTitle.decorate(Self.defaultTerminalTitle, persistent: t.tmuxSession != nil),
                    icon: t.tmuxSession != nil ? Self.persistentTabIcon : Self.terminalTabIcon,
                    inPane: pane
                ) {
                    if let cwd = t.cwd { pendingCwd[tid] = cwd } // 새 셸을 저장된 작업 디렉터리에서 띄우게 힌트.
                    // 재개 바인딩 복구(+배너 표시). 실행은 게이트가.
                    //
                    // **tmux(∞) 탭은 제외한다** — 이 탭은 `tmux attach`로 복원되고, 세션 안의 claude는 **죽지 않았다**.
                    // 이어서 할 게 없는데 배너를 띄우면 살아 있는 claude 입력창에 `claude --resume …`를 꽂게 된다
                    // (게이트도 못 막는다: 포그라운드 판정이 보는 건 pty의 tmux 클라이언트지 그 안의 claude가 아니다).
                    if t.tmuxSession == nil, let resume = t.resume { restoreResumeBinding(resume, for: tid) }
                    // 신뢰 재개(claude 자동)는 곧 claude가 화면을 덮으므로 죽은 스크롤백 리플레이를 건너뛴다(잔상·중복 방지).
                    // tmux 세션명은 **저장된 이름 그대로** 이어받는다 — tabId는 방금 새로 발급됐으므로
                    // 재조립하면 엉뚱한 세션을 만들고, 돌던 프로세스는 고아가 된다.
                    if let session = t.tmuxSession {
                        tmuxSessions[tid] = session
                        persistentIntent[tid] = true // 저장된 세션이 있다 = 지속 세션으로 열었던 탭이다
                        syncAttachTimer() // 복원된 탭도 이탈 감시 대상이다
                    }
                    // tmux 탭은 스크롤백 리플레이를 하지 않는다 — tmux가 화면을 통째로 갖고 있다.
                    if t.tmuxSession == nil, let sf = t.scrollbackFile, t.resume?.trusted != true {
                        restoredScrollbackFile[tid] = sf // 새 셸에 스크롤백 파일 주입 힌트(④).
                        replayPendingTabs.insert(tid) // 이 탭의 첫 commandFinished(=리플레이 명령)는 삼킨다.
                    }
                    newTab = tid
                }
                guard let tid = newTab else { continue }
                // 수동 탭 이름 복구 — 터미널·그룹 공통. 엔진 제목이 나중에 덮지 않도록 manualTitles에도 되살린다.
                if let title = t.manualTitle {
                    manualTitles[tid] = title
                    pushTitle(title, for: tid, hasCustomTitle: true) // ∞ 탭이면 접두까지(관문 경유)
                }
                created.append(tid)
            }
            let selectedTab = selected < created.count ? created[selected] : nil
            if let selectedTab { controller.selectTab(selectedTab) }
            // 저장 시점의 활성 칸이면 재구성 후 전역 포커스를 여기로 되돌리게 기록해 둔다.
            if focused { restoreFocus = (pane, selectedTab) }
        case .split(let vertical, let divider, let first, let second):
            let orientation: SplitOrientation = vertical ? .vertical : .horizontal
            guard let newPane = controller.splitPane(pane, orientation: orientation, withTab: nil,
                                                     initialDividerPosition: CGFloat(divider)) else {
                realize(first, into: pane); realize(second, into: pane) // 분할 실패 → 평면화
                return
            }
            realize(first, into: pane)      // 기존 패인 = first
            realize(second, into: newPane)  // 새 패인 = second
        }
    }

    /// 그룹 탭 하나를 items로 재구성(첫 항목으로 생성 후 나머지 add). 선택 서브탭 복원.
    private func realizeGroup(_ kind: TabGroupKind, items: [ItemSnapshot], selectedItem: Int, inPane pane: PaneID) -> TabID? {
        var gid: TabID?
        for s in items {
            guard let content = itemContent(s) else { continue }
            if let id = gid {
                groups[id]?.add(content)
            } else if let id = controller.createTab(title: kind.title, icon: kind.icon, inPane: pane) {
                tabContent[id] = .group(kind)
                groups[id] = TabGroupState(first: content)
                gid = id
            }
        }
        if let id = gid, let state = groups[id], selectedItem < state.items.count {
            state.selectedId = state.items[selectedItem].id
        }
        return gid
    }
}

#if DEBUG
// MARK: - 데모 스크린샷 시드 (MUXA_DEMO) — 같은 파일이라 private 멤버 접근 가능
extension TerminalStore {
    /// 초기 터미널 자동 생성을 대신해 데모 레이아웃을 직접 구성한다.
    /// build 안에서 demoTerminal/demoSplit으로 칸·탭을 만들고, 끝나면 부트스트랩 welcome 탭을 닫고
    /// `initialized`를 세워 렌더 시 ensureInitialTerminal이 스킵되게 한다.
    func demoSeedLayout(_ build: () -> Void) {
        let bootstrap = Set(controller.allTabIds)
        build()
        let real = controller.allTabIds.filter { !bootstrap.contains($0) }
        if !real.isEmpty { for id in bootstrap { _ = controller.closeTab(id) } }
        if controller.allTabIds.isEmpty {
            _ = controller.createTab(title: "터미널", icon: Self.terminalTabIcon, inPane: nil)
        }
        initialized = true
        ready = true
        syncHasTabs()
    }

    /// 지정(또는 포커스) 칸에 데모 터미널 탭 하나 — 제목·트랜스크립트·에이전트 상태를 붙인다.
    @discardableResult
    func demoTerminal(inPane pane: PaneID? = nil, title: String,
                      transcript: String? = nil, status: NotifyState? = nil) -> TabID? {
        // 데모/스크린샷은 실제 tmux 세션을 만들지 않는다 — persistent를 명시해 기본값(∞)을 끈다.
        guard let id = newTerminal(inPane: pane, persistent: false) else { return nil }
        controller.updateTab(id, title: title, hasCustomTitle: true)
        demoConfigure(id, transcript: transcript, status: status)
        return id
    }

    /// 칸을 분할한다(델리게이트가 새 칸에 터미널을 자동 생성) → 그 터미널을 데모용으로 설정하고 새 PaneID 반환.
    @discardableResult
    func demoSplit(_ orientation: SplitOrientation, title: String,
                   transcript: String? = nil, status: NotifyState? = nil,
                   from pane: PaneID? = nil, divider: CGFloat? = nil) -> PaneID? {
        guard let newPane = controller.splitPane(pane, orientation: orientation,
                                                 initialDividerPosition: divider) else { return nil }
        if let tabId = controller.tabs(inPane: newPane).first?.id {
            controller.updateTab(tabId, title: title, hasCustomTitle: true)
            demoConfigure(tabId, transcript: transcript, status: status)
        }
        return newPane
    }

    /// 데모 탭에 트랜스크립트(셸이 `clear; cat`으로 표시)와 에이전트 상태(explicit pin)를 붙인다.
    func demoConfigure(_ id: TabID, transcript: String?, status: NotifyState?) {
        if let transcript { restoredScrollbackFile[id] = transcript }
        if let status { applyAgentSignal(.explicit(status), to: id) }
    }

    var demoFocusedPane: PaneID? { controller.focusedPaneId }
    func demoFocus(_ pane: PaneID) { controller.focusPane(pane) }
}
#endif
