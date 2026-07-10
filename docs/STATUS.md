# muxa 진행 상태 · 인수인계 (2026-07-10 · rev4)

> 다음 세션이 여기서 이어간다. 설계 원천은 [DESIGN.md](DESIGN.md), 이 문서는 **현재 상태·다음 할 일**만.

## 재개 방법

```bash
./scripts/bootstrap.sh      # (새 머신 최초 1회) GhosttyKit 설치 — docs/SETUP.md
cd macos
swift build                 # 빌드 (SPM)
.build/debug/muxa           # 실행 (창 뜸)
# UI 변경은 재빌드+재실행. pkill로 죽이면 세션 저장(applicationWillTerminate) 안 됨 — ⌘Q로 정상 종료해야 복원됨.
```

커밋 자유(private), push만 승인. 커밋 트레일러 금지. 응답은 한국어.

## 마일스톤 진행

- **M0 IME·임베딩** ✅ · **M1 터미널 코어** ✅ (워크스페이스·Bonsplit 분할/탭·⌘F·세션복원·사이드바 4모드·모니터 스케일)
- **M2 보는 눈 + 알림** ✅ — 익스플로러 + md/코드 뷰어 + FSEvents + 알림 배지 (아래 상세)
- **M3 git 읽기(C)** ✅ — 상태 패널·diff 탭·히스토리
- **M4 워크트리** ✅ (완결) — list/add/**remove UI**·WorktreePicker·`.worktrees/<branch>`+exclude
- **M4 git 쓰기** ✅ — 스테이징/언스테이지/커밋(GitPanel 변경사항 탭 = 커밋박스 + 스테이지됨/변경 2섹션)
- **뷰어 라이브러리** ✅ — **md/HTML = WKWebView + markdown-it·highlight.js·mermaid**(`Resources/mdviewer`), **코드 = Shiki**(VSCode 문법)
- **익스플로러 VSCode급 1단계** ✅ — **NSOutlineView 전환** + git색·컨텍스트메뉴(여기서 터미널 열기)·선택 하이라이트·키보드 네비
- **파일 아이콘 Material** ✅ — Material Icon Theme(MIT) 슬림 번들(828 SVG·`Resources/fileicons`), `IconTheme`가 확장자/파일명/폴더명 매핑
- **탭 추가 버튼(탭바)** ✅ — **bonsplit fork(manaflow) 전환** + `splitButtons=[.newTerminal,.splitRight,.splitDown]`로 분할 버튼 옆
- **탭 그룹핑** ✅ — 종류별 rank(터미널0<문서1<diff2) 클러스터(`TerminalStore.regroup`)
- **2단 서브탭** ✅ — 상단 그룹 탭(`[문서]`/`[변경]`) + 하위 서브탭. 터미널은 개별 탭(분할). `TabGroup`·`TabGroupView`. 문서/커밋 diff 재시작 복원(`SavedViewer`).
- **코드/diff 뷰어 = WKWebView(HTML)** ✅ — NSTextView가 fork keepAllAlive에서 본문 미합성 → Shiki 토큰→HTML→`CodeWebView`. md와 같은 WKWebView.
- **익스플로러 VSCode급 2단계** ✅ — 파일 조작(새파일/폴더·이름변경·삭제[휴지통])·확장 보존 reload·FSEvents 자동 트리갱신·인덴트 가이드
- **뷰어 라이브 리로드** ✅ — 열린 코드/md가 디스크에서 바뀌면 자동 재로드
- **세션 복원 정합성** ✅ — 트리는 터미널만(`layoutSnapshot`), 문서/diff는 `SavedViewer`로 별도 복원

## 최근 완료 (ultracode 워크플로 + 적대적 리뷰 수정)

- **서브탭·활성 칸 완전 복원** ✅ — `PaneSnapshot.leaf.focused`(커스텀 Codable 하위호환), 복원 후 활성 칸+선택탭 복구
- **익스플로러 reveal + 인라인 이름변경** ✅ — 파일 열면 트리 펼침+선택+스크롤; 셀 인라인 편집(편집 중 리로드 보류로 데이터손실 방지)
- **git 브랜치 전환 + pull/push** ✅ — `GitService+Branch`; Git 헤더 브랜치 메뉴 + pull/push 버튼
- **diff 인라인 스테이지** ✅ — hunk 단위(WKWebView→Swift 메시지 + `git apply --cached`) + 파일 전체 스테이지/언스테이지 도구줄; 스테이지 후 최신 status 재조회
- **gh 배지** ✅ — `GitService+GH`; Git 헤더에 PR#·상태색·CI 롤업(gh 미설치/미인증 전경로 가드)
- **에이전트 상태 추정** ✅ (Tier3, DESIGN 4.5) — 순수 값 `AgentActivityEstimator`(idle/working/waiting/done) + 신호 배선. RENDER 액션을 `TermView`가 초당 1회로 다운샘플→`.outputHeartbeat`, OSC 133 완료→done, muxa notify 명시신호(waiting/done/working)를 ground truth로 고정(pin). 출력이 `idleThreshold`(4s) 넘게 멎으면 working→waiting 추정(working 탭 있을 때만 1s idle 타이머). 표시=패인 상시 테두리(waiting 주황·done 초록, working/idle 없음), 그 칸을 보면 해제. **튜닝 미검증**(아래 주의).

## 다음 할 일 (백로그) — ultracode 검토 재구성 (2026-07-10)

검토 결론: 조각(배지·git·diff·뷰어)은 완성됐으나 **정체성 동선("알림으로 언제 부르는지 → git·뷰어로 뭘 바꿨는지 체크")이 엔드투엔드로 끊겨 있다.** 조각을 더 만들기보다 이미 만든 조각을 잇는 게 최대 레버리지. 아래는 fable 3렌즈 + 직접 코드 검증(파일:라인)으로 확정한 우선순위.

### Tier 0 — 부채 청산 (기능 이전에 고칠 것)

- **B1 셸 종료 = 앱 종료 [치명·S]** — `GhosttyRuntime.swift:111` `close_surface_cb`가 `NSApp.terminate(nil)`("M0" 잔재). 셸에서 `exit` 한 번이 앱 전체 종료. surface→TermView→tabId 복원(read_clipboard_cb 패턴) 후 `controller.closeTab`로. 마지막 탭이면 빈 상태 뷰.
- **B2 도구 패널 상태 승격 [S]** — `showGitPanel`/`showExplorer`가 `ContentView` 로컬 `@State`(:8-9)라 알림·단축키·프로그램이 패널을 못 연다. `AppState`로 올려야 함 — 이후 모든 "알림→패널" 연결의 선행조건. ⌘⇧G 토글도 공짜.

### Tier 1 — 정체성 동선 완성 (알림 → 체크 → 판정)

- **알림 신뢰도 패스 [S~M]** — (a) `isVisibleToUser`가 `firstResponder && isKeyWindow` 판정(`TermView.swift:239`)이라 3~4분할 동시 감시 시 보이는 비포커스 칸에 배지 누적 → 보이는 칸은 배지 대신 **패인 테두리 플래시**. (b) `onCommandFinished`가 `duration`·`exitCode`를 버리고 무조건 배지(:249) → 임계값 필터(장시간·비정상종료만). (c) **워크스페이스 ●**(SidebarSUI에 렌더 부재, DESIGN 5절 표 위반) + **Dock 배지 카운트**. (d) 패인 테두리 = DESIGN 4.5 미이행 약속.
- **muxa notify CLI + env 주입 [M]** — `ghostty_env_var_s`·`surface_config.env_vars`(ghostty.h:446,484) 확인. `TermView.init`에서 `MUXA_TAB_ID` 주입 + Unix 소켓 리스너(`NotifyServer.swift` 신설) → tabId 라우팅은 `markBadge` 재사용. Claude Code hooks(Notification/Stop)에 한 줄 → **결정론적 대기/완료 신호**(장수명 TUI라 COMMAND_FINISHED가 0회인 무신호 구간 해소). cmux 대비 차별화.
- **알림 → 원클릭 검토 [S~M]** — 탭/프로젝트 배지·시스템 알림 클릭 → 프로젝트 활성 + git 패널 자동 오픈(+세션 diff). B2 위에 얹음. `UNUserNotificationCenterDelegate` + userInfo(ids).
- **세션 기준선 diff [M]** — `Project`에 `sessionBaseHead: String?`(Codable 영속), 최초 터미널 생성 시 `rev-parse HEAD` 기록. git 패널에 "이번 세션" 필터(기준선 이후 커밋 + 워크트리 변경 누적 diff). DESIGN 4.4 #2 명문 미구현. 에이전트 자율 커밋 워크플로에서 "워크트리 diff만 보기"가 무력화되므로 시급.
- **Discard [S]** — 파일 단위 변경 버리기(`git restore` / untracked는 `FileManager.trashItem`), `GitService+Write`에 추가. 체크 동선의 "거부" 반쪽(DESIGN 4.4 #4). hunk discard는 기존 `DiffPatch` + `git apply --reverse` 재사용.

### Tier 2 — 데일리 드라이버 기본기

- **설정 파일 `~/.config/muxa/config` + 키바인딩 테이블 [M]** — DESIGN 4.6 미구현("없으면 데일리 드라이버 못 됨"). ghostty config는 폰트·테마만 재사용 중, muxa 고유 설정 표면은 0. `MuxaConfig` 값 타입 + 순수 파서(테스트 가능), `main.swift:75` `handleShortcut` switch를 `KeymapResolver`로 데이터화. 빠진 칸 포커스 이동·탭 순환 키도 여기서 추가.
- **탭별 cwd 추적 [S]** — `GHOSTTY_ACTION_PWD`(ghostty.h:941) 배선만: `action_cb` 케이스 → `TermView.onPwdChange` → `TabSnapshot.cwd`(옵셔널 하위호환). 복원 시 그 경로에서 새 셸. DESIGN 4.2가 예약한 항목.
- **탭 자동 명명 [S]** — `GHOSTTY_ACTION_SET_TITLE`(:938) → `controller.updateTab(title:)`. 전부 "터미널"인 탭 식별 문제(감시의 전제). 수동 rename 우선 플래그.
- **⌘⇧A 다음 대기 세션 점프 [S]** — 워크스페이스 경계 넘어 배지 칸 순환 이동. 알림→소비 동선의 마지막 조각.

### Tier 3 — 심화

~~에이전트 상태머신(RENDER heartbeat + idle 추정, DESIGN 4.5 · M~L)~~ ✅(위) — **잔여 튜닝**: RENDER가 포커스 칸 커서 깜빡임에도 오는지 실기기 확인(그렇다면 포커스 칸은 idle 추정이 안 됨 — 비포커스 칸은 정상). idleThreshold(4s)·throttle(1s) 실사용 조정. muxa notify 훅 미설치 시 추정 정확도 한계. 탭 점 색 상태화(현재는 배지 dot만; Bonsplit isDirty가 bool뿐이라 미구현) · 알림 인박스(놓친 이력 큐 + 점프, M5 · M) · ⌘K 빠른 전환기(계층 5단 퍼지 탐색, M) · diff 탭 라이브 리로드(md 뷰어 패턴 이식, S~M) · 전체 변경 통합 diff 서브탭(M) · 워크트리 merge·정리 원액션(M~L) · side-by-side diff(후순위).

### 기타 (기존 백로그 · 저심각)

- 실기기 검증: 세션복원(활성칸)·2단 서브탭·문서영속 — 눈으로 아직
- pull/push 타임아웃·취소, diff 도구줄 stale 배너 clear, 원격 트래킹 브랜치 체크아웃, hunk 언스테이지, PR 배지 폴링, runResult 대량출력 파이프(실위험 낮음)
- 붙여넣기 무조건 승인(`confirm_read_clipboard_cb` "M0" 잔재 — Tier 0과 함께 정리 가능)
- git status 부분 재계산(FSEvents 이벤트마다 status+log+branch 전부 재실행, `FileWatcher.lastPaths` 미사용) — Tier 1/2 착수 시 성능 부채로 정리

## 핵심 아키텍처

- **3계층**: `Workspace{path,projects[]}` ⊃ `Project{name,path?}` ⊃ Bonsplit 탭/분할. `AppState.stores`는 프로젝트 id 키잉.
- **2단 탭**: `TabContent = .terminal | .group(TabGroupKind)`. 터미널=개별 탭, 문서·diff=종류별 그룹 탭 하나에 서브탭으로. `groups: [TabID: TabGroupState]`(@Observable). `openFile`/`openDiff`→`openInGroup`(같은 종류 그룹에 서브탭 추가·dedup). `BonsplitWorkspaceView`가 `.group`→`TabGroupView`(서브탭 바 + ZStack opacity로 서브탭 유지). `closeGroupItem`(비면 그룹 탭 닫기).
- **Bonsplit**(**manaflow-ai fork**, revision 고정 — 태그 없음). almonk 상위집합(API 동일 + SplitActionButton 등). `TerminalStore`(BonsplitDelegate). **config `keepAllAlive`** — 탭 전환 시 뷰 유지(재렌더 방지). **탭바 내장 버튼** = `appearance.splitButtons`(새터미널 `+` → `didRequestNewTab`, 분할 → `didSplitPane`). 초기 "Welcome" 탭 → `ensureInitialTerminal`이 정리. **탭 그룹핑** = `regroup`이 `tabs(inPane:)`+`reorderTab`로 종류별 클러스터.
- **파일 아이콘**: `IconTheme`(Material Icon Theme 슬림 번들). `Resources/fileicons/icons.json`(fileExtensions/fileNames/folderNames→아이콘명) + 828 SVG. NSImage가 SVG 직접 렌더(macOS 14). 매칭: 파일명(원본→소문자)→확장자(복합 최장 우선)→기본. `FileIcon`이 Material 우선, 실패 시 NSWorkspace 폴백. 재번들 = `scripts/build-fileicons/build.py`.
- **git 쓰기**: `GitService+Write`(add/restore --staged/reset/commit CLI). `GitPanel` 변경사항 = `GitCommitBox` + staged/unstaged 2섹션(행별 +/− ). `GitStatus.staged/unstaged`, `GitFileChange.opPath`(리네임 안전).
- **세션 저장**: `TerminalStore.layoutSnapshot()`이 뷰어/diff 탭 프루닝(터미널만). `AppState.save`가 이걸 저장.
- **코드/diff 뷰어(표시=WKWebView)**: `ShikiHighlighter`(싱글턴, 오프스크린 WKWebView 1개가 shiki `codeToTokens` 계산) → `CodeHTML`(토큰/diff줄 → 정적 HTML: 줄번호 sticky·가로스크롤·테마색) → `CodeWebView`(loadHTMLString). **NSTextView는 fork keepAllAlive(ZStack+opacity)에서 본문이 합성 안 돼 폐기**, md와 같은 WKWebView로 통일. shiki는 **JS RegExp 엔진(wasm 없음)** esbuild IIFE 단일 번들(`Resources/codeviewer/shiki.bundle.js`, 재번들 scratchpad `shiki-build`). 뷰어는 `chrome:false`면 자체 헤더 숨김(서브탭 바가 대신).
- **md/HTML 뷰어**: `MarkdownWebView`(WKWebView) + `Resources/mdviewer/shell.html`. `.html`은 raw 렌더. 코드·md 모두 `FileWatcher`로 라이브 리로드.
- **익스플로러**: `FileExplorerOutline`(NSOutlineView Representable+Coordinator) + `FileCellView`/`FileRowView`(인덴트 가이드·선택 하이라이트). `FileNode`는 class(참조 동일성). **확장 보존 reload**(`expandedPaths` 경로 추적). 파일 조작(새파일/폴더·이름변경·삭제[휴지통]) 컨텍스트 메뉴. FSEvents→`reloadToken` 자동 트리갱신. git색 = `GitService.statusMap`. 아이콘 = `FileIcon`(Material 우선).
- **git = CLI 셸아웃**. `GitService`(+`GitService+Worktree`, `+Explorer`). `repoRoot`는 `--git-common-dir`(링크 워크트리 안전).
- **터미널 테마**: `GhosttyRuntime`가 시스템 외관 기반 배경/전경 폴백을 `config_load_string`으로 주입(사용자 config 있으면 덮음) + `set_color_scheme`. (사용자 config는 `~/.config/ghostty/config` — 확장자 없는 파일이어야 ghostty가 읽음)
- **알림 배지(A)**: `action_cb` 4케이스 → `TermView`(tabId 보유)가 `isVisibleToUser`(**firstResponder+key창**) 아니면 배지. 탭 점=Bonsplit isDirty, 프로젝트 ●=`AppState.badgedProjects`. 알림=`NotificationService`(번들 가드).
- **영속**: `state.v4.json`. ⌘Q(applicationWillTerminate) 시 저장.

## 사용자 검증 상태

- **눈으로 확인됨** ✅ — 코드 뷰어(WKWebView 하이라이트·줄번호·간격), 탭 추가 버튼(탭바), 익스플로러 컬러 아이콘
- **아직 미검증 ★** — 2단 서브탭(그룹+서브탭 전환·유지), 문서 재시작 복원, 파일 조작(새파일/폴더·이름변경·삭제), 인덴트 가이드, 자동 트리갱신, 뷰어 라이브 리로드, git 쓰기(스테이징·커밋), 워크트리 제거, 탭 그룹핑, 세션 복원(터미널+문서), md 뷰어(표·mermaid), 알림 배지, ⌘F

## 이번 세션 함정 (재발 방지)

- **NSTextView 본문 미합성** = manaflow fork의 `keepAllAlive`는 모든 탭을 `ZStack{opacity}`로 동시에 얹는데, 그 안에서 NSTextView 본문이 안 그려짐(줄번호 ruler는 NSScrollView 소속이라 보임 → "줄번호만" 착시). **로그로 확정: tokens·storage·layout 다 정상, 글자만 미합성.** → 코드/diff 표시를 WKWebView(HTML)로 전환(md와 동일, 정상 합성). 교훈: 이 ZStack에선 뷰어를 WKWebView로.
- **코드뷰어 굼뜸** = 파일마다 새 WKWebView가 shiki를 재로드. 해결: 오프스크린 하이라이터 1개가 토큰만 계산 → 표시 WKWebView는 정적 HTML(loadHTMLString, shiki 없음).
- **탭 전환 재렌더** = Bonsplit 기본 `.recreateOnSwitch`. → `keepAllAlive`(서브탭도 ZStack+opacity로 동일 처리).
- **배지 무력화** = `TermView.isFocused`가 어디서도 대입 안 돼 항상 false. → `isVisibleToUser`를 `window?.firstResponder === self`로.
- **세션 복원 터미널 안 뜸** = welcome 탭이 selected인 채 닫혀 선택 사라짐. → 복원 탭 먼저 selectTab 후 welcome 닫기.
- **Shiki 오프라인** = esm.sh ?bundle은 동적 import라 file:// 실패. JS RegExp 엔진(wasm 제거) + esbuild IIFE 단일 파일이 정답.
- (기존) 모니터 스케일=layer.contentsScale, 빈 타이틀바=본문 상단바, 상단바 두 줄=safeAreaRegions=[], ⌘Q=메인 메뉴, 복원 replay=restoring 플래그.

## 참조 (scratchpad, 커밋 금지)

- `cmux-ref`(GPL) — 익스플로러 NSOutlineView·git 상태 전파 구조 참고.
- `bonsplit-mf` — 이제 실제 의존성(manaflow fork). API 확인용 클론.
- `shiki-build` — shiki 번들 재생성(code-entry.js + esbuild).
- 파일 아이콘 재번들 = `scripts/build-fileicons/build.py`(npm pack material-icon-theme → 프루닝).
