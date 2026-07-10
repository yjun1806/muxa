# muxa 진행 상태 · 인수인계 (2026-07-10 · rev10)

> 다음 세션이 여기서 이어간다. 설계 원천은 [DESIGN.md](DESIGN.md), 이 문서는 **현재 상태·다음 할 일**만.

## 재개 방법

```bash
./scripts/bootstrap.sh      # (새 머신 최초 1회) GhosttyKit 설치 — docs/SETUP.md
cd macos
swift build                 # 빌드 (SPM)
swift test                  # 순수 로직 단위 테스트 (68개, GhosttyKit 링크 포함)
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
- **diff 리뷰 코멘트 + 제출 풀** ✅ (cmux 대조 ③) — diff 줄 hover '＋'로 코멘트, `lineText` 재앵커링(anchored/moved/outdated)으로 라이브 리로드 드리프트 방지, Git 패널 "N개 보내기"로 포커스 터미널에 붙여 다음 턴 지시로 되먹임. 순수 로직 분리(`ReviewComment`·`ReviewCommentAnchor`·`ReviewCommentFormat`) + 영속 경계(`ReviewCommentStore`, 리포키=canonical root SHA256) + WKWebView 코멘트 브리지 채널(`muxaComment`). 붙여넣기는 Enter 미커밋(사용자 확인 후 제출).
- **에이전트 상태 추정** ✅ (Tier3, DESIGN 4.5) — 순수 값 `AgentActivityEstimator`(idle/working/waiting/done) + 신호 배선. RENDER 액션을 `TermView`가 초당 1회로 다운샘플→`.outputHeartbeat`, OSC 133 완료→done, muxa notify 명시신호(waiting/done/working)를 ground truth로 고정(pin). 출력이 `idleThreshold`(4s) 넘게 멎으면 working→waiting 추정(working 탭 있을 때만 1s idle 타이머). 표시=패인 상시 테두리(waiting 주황·done 초록, working/idle 없음), 그 칸을 보면 해제. **튜닝 미검증**(아래 주의).

## Tier 0~3 백로그 20개 — 구현 완료 (2026-07-10 · ultracode 순차 워크플로)

fable 3렌즈 검토로 도출한 백로그를 순차 파이프라인(각 단계 구현→`swift build`→커밋)으로 20개 전부 구현. 최종 빌드 green + 실행 init 크래시 없음(3초 스모크) 확인. 커밋 `a85fcaf`(B1) ~ `5da0433`(상태머신), +2654줄. **전부 GUI 동작이라 실기기 육안 검증은 미수행(★).**

- **Tier 0** — B1 셸 종료 시 해당 탭만 닫기(앱 종료 결함 제거, `close_surface_cb`) · B2 도구 패널 표시를 `AppState`로 승격 + ⌘⇧E/⌘⇧G 토글.
- **Tier 1** — 배지 오탐 억제(보이는 칸/짧은 명령[8s]/벨 디바운스 필터, 명명 상수 `shortCommandThresholdNs`·`bellDebounce`) · 워크스페이스 ● + Dock 배지 카운트 · 패인 활동 테두리(`flashingTabs`, 1.2s 페이드) · muxa notify CLI + env 주입(별 바이너리 `muxa-notify` + `NotifyServer` Unix 소켓) · 알림/배지 클릭→프로젝트 활성+Git 패널(`revealActivity`) · 세션 기준선 diff(`Project.sessionBaseHead`, 영속) · 변경 버리기(discard, 파일 단위·untracked는 휴지통).
- **Tier 2** — 설정 파일 `~/.config/muxa/config`(`MuxaConfig` 순수 파서, 시작 시 1회 로드) · 키바인딩 테이블화(`KeymapResolver` + 칸 포커스 이동 ⌘⌥방향·탭 순환 ⌃Tab) · 탭별 cwd 추적(OSC 7, `TermView.pwd` 진실원천) · 탭 자동 명명(SET_TITLE) + 수동 rename · ⌘⇧A 다음 대기 세션 전역 점프.
- **Tier 3** — diff 탭 라이브 리로드(FileWatcher + 스크롤 보존) · 전체 변경 통합 diff 서브탭(`.all`) · 알림 인박스(`AttentionLog` + 팝오버) · ⌘K 빠른 전환기(`FuzzyMatch` 퍼지·대기 우선 정렬) · 워크트리 merge 후 정리 원액션 · 에이전트 상태 추정(`AgentActivityEstimator` idle/working/waiting/done, RENDER 초당 1회 다운샘플, muxa notify 명시신호 pin, 패인 테두리 waiting=주황·done=초록).

신규 파일: `NotifyServer` · `MuxaConfig` · `KeymapResolver` · `QuickSwitcher`/`QuickSwitchItem` · `FuzzyMatch` · `TerminalSignal` · `DiscardConfirm` · `WorktreeMergeConfirm`.

## 다음 할 일 (백로그) — 잔여·후속

### 실기기 검증 (최우선 ★)

20개 전부 GUI 동작이라 육안 미확인: 패인 테두리 플래시·상태 테두리색(주황/초록)·Dock 배지·사이드바 ●·알림 클릭 라우팅·⌘K 오버레이·rename 시트·칸 포커스 이동/탭 순환 키·discard·워크트리 merge. **`.app` 번들 실행이어야 시스템 알림 동작**(bare `.build/debug/muxa`는 Dock 바운스 폴백).

### 미완·후속 (구현 중 남긴 것 — 각 커밋 notes)

- **muxa notify 설치 경로**: `muxa-notify` 바이너리를 PATH 심볼릭 링크 또는 훅에서 절대경로 참조해야 함(자동 설치 미구현). Claude Code 훅 예시 — Notification→`muxa notify --state waiting`, Stop→`--state done`, 재개→`--state working`(배지 클리어).
- **상태머신 튜닝 미검증**: RENDER가 포커스 칸 커서 깜빡임에도 오는지 실기기 확인(오면 포커스 칸 idle 추정 불가·비포커스는 정상). `idleThreshold`(4s)·throttle(1s) 실사용 조정. 훅 미설치 시 추정 정확도 한계.
- **세션 미영속**: 수동 탭 이름(`manualTitles`)·알림 인박스 이력은 재시작 시 비워짐 — 영속하려면 `TabSnapshot` 스키마 확장.
- **세부 미완**: 마지막 탭 닫힘 시 빈 상태 뷰(B1은 `controller.closeTab` 기본 동작에 위임) · discard의 스테이지된 리네임(R) 실패 가능·hunk discard 미구현 · 설정 라이브 리로드(FSEvents) 미구현 · 전체 diff 파일 헤더 클릭 점프 미구현 · 탭 순환 ⌃Tab 이론적 충돌 가능성 · rename이 인라인 아닌 NSAlert 모달 · 탭 점 색 상태화(Bonsplit `isDirty`가 bool뿐).

## cmux 대조 — 흡수할 개선 (2026-07-10 · GPL이라 구조·아이디어만)

cmux(4333 swift·상용급: SSH·모바일·브라우저·데몬·135 키액션·nucleo FFI·AI 자동명명) 4영역 대조. **muxa의 "작고 순수"는 옳았다** — 즉시저장(유실 창 0, cmux는 8초 autosave+별도 크래시 스토어)·단일 패스 realize·`selectedTab` 가시성 판정(분할 감시에 더 정확)·의존성 0·값타입 분리. 아래는 규모가 아니라 **정체성 심화**로 가져올 것. 난이도(S/M/L)·가치(상/중/하).

> **진행 (2026-07-10 rev9): cmux 대조 배울점 전부(①~⑧ + 추가 후보 7) 구현·커밋 완료.** 매 단계 빌드 green + 실행 init 크래시 없음. **GUI·훅 의존이라 실기기 육안 검증은 미수행(★).**
> - **저비용 즉효**: ⑦ `GIT_OPTIONAL_LOCKS=0` · ⑥ 순수 `NotificationGate` · ① 훅 카테고리(muxa notify `--category`) · ⑤ 팔레트 액션 실행(`AppState.perform` 추출) · ⑧ 설정 라이브 리로드(`ConfigWatcher`) + DESIGN 4.2 정정.
> - **정체성 심화**: ② resume 재부착(`ResumeBinding`·`ResumeBanner`·승인 게이트 `agent_resume`·`TermView.sendText` bracketed-paste 회피) · **③ diff 리뷰 코멘트 + 제출 풀**(`ReviewComment`·`ReviewCommentAnchor` 재앵커링·`ReviewCommentStore` 리포키 SHA256·`ReviewCommentSheet`·WKWebView `muxaComment` 브리지·"N개 보내기"로 터미널 되먹임) · **④ 스크롤백 리플레이**(`ghostty_surface_read_text`로 화면+스크롤백 캡처→`ScrollbackStore` 별도 파일→복원 시 env `MUXA_RESTORE_SCROLLBACK_FILE` 재출력).
> - **추가 후보 7**: 프로세스 종료 감지(`DispatchSourceProcess.exit`, foreground_pid) · 스냅샷 `version` + 크래시 마커(`CrashMarker` running-lock) · notify CLI 견고성(소켓 실패 exit 0) · `MUXA_SURFACE_ID`(env 슬롯만 — 탭=서피스 1:1이라 최소) · 알림 dedup/coalescing(cooldown) · 키 충돌·예약키 감지(`KeymapDiagnostic`) · side-by-side diff 토글(`SideBySideDiff` 순수 2열).
>
> **남음 — 실기기 검증 + 잔여:**
> - **실기기 검증 ★**: ② 재개 배너·명령 주입 타이밍(auto 0.8s 지연 유실 여부) · ③ diff 코멘트 브리지·터미널 되먹임 · ④ 스크롤백은 **사용자가 `~/.zshrc`에 `[ -n "$MUXA_RESTORE_SCROLLBACK_FILE" ] && [ -f "$MUXA_RESTORE_SCROLLBACK_FILE" ] && { cat "$MUXA_RESTORE_SCROLLBACK_FILE"; rm -f "$MUXA_RESTORE_SCROLLBACK_FILE"; }` 추가해야 시각 복원 동작**(인프라만 제공) · side-by-side.
> - **잔여 미완**: ④ 스크롤백 파일 GC(복원 시 tabId 변경으로 고아 1회 가능 — 앱 시작 시 디렉터리 GC 후속) · ③ 재앵커링 파일 전체 스코프(hunk 아님)·다중줄/커밋 diff 코멘트 미지원 · 종료 감지 foreground_pid 휘발성(셸 종료 위주, '셸 생존+에이전트만 크래시'는 OSC133과 중복 회피로 미포착) · dedup cooldown·키 진단·크래시 마커 판정값이 로그만(UI 미노출) · `MUXA_SURFACE_ID` 실 라우팅 미배선(env만).
> - **✅ 테스트 타깃 신설 완료** (2026-07-10 rev10) — `Tests/muxaTests/`(`swift test`, **68 테스트 0 실패**). 순수 로직 11종 커버: `FuzzyMatch`·`NotificationGate`·`DiffPatch`·`MuxaConfig`·`SideBySideDiff`·`GitService`(parseStatus/parseLog)·`GitService+GH`(parseGHStatus)·`ReviewCommentAnchor`(anchored/moved/outdated)·`KeymapResolver`(resolve+진단)·`AgentActivityEstimator`(상태 전이·pin)·`Workspace`. Package.swift에 `testTarget(muxaTests, deps:[muxa])` — executable 모듈 `@testable import`(GhosttyKit 링크 정상).
> - **다음 마일스톤 후보**: 실기기 검증 통과 후 — 상태머신 튜닝 실사용 · 크래시 마커→auto resume 연동 · 진단(키 충돌·크래시)의 상단바/인박스 표면화 · 통합/E2E 테스트(GUI 상호작용이라 단위 테스트와 별도 — Playwright류 불가, XCUITest 검토).

### 정체성 심화 (가치 상)

- **① 구조화 훅으로 상태 추정 제거 [M·상]** — 방금 만든 상태머신의 최대 약점이 `idleThreshold`(4s) 출력 추정(4초 생각만 해도 waiting 오탐). cmux는 **추정을 안 한다**: Claude Code 훅 `PreToolUse/PostToolUse→working`·`PermissionRequest/AskUserQuestion/Notification→waiting`·`Stop→idle`·`SessionEnd→ended`를 결정론 매핑. muxa notify `--state`를 세분(+훅 프리셋)하면 출력추정 거의 불필요. `AgentActivityEstimator`에 pin 인프라 이미 있음.
- **② 에이전트 resume 재부착 [M~L·상]** — "앱 꺼도 에이전트 세션 유지"의 실제 정답. **로컬 PTY 데몬화가 아니다**(cmux 데몬 `cmuxd-remote`는 원격 전용, 로컬은 resume-command). 돌던 에이전트 탐지→`claude/codex --resume <sessionId>` 명령+cwd+env 저장(`TabSnapshot` 확장)→복원 시 재실행, 승인 게이트(auto/manual)로 자동실행 통제. OSC7 cwd 인프라 확장. **DESIGN 4.2 "데몬화" 표현을 이 방향으로 대체 검토.**
- **③ diff 리뷰 코멘트 + 제출 풀 [L·상]** ✅ 구현 — 에이전트 diff에 줄 단위 인라인 코멘트→"N개 코멘트 보내기"로 포커스 터미널에 붙여 다음 턴 지시로 되먹임(에이전틱 루프 닫기). 편집이 아니라 메타데이터라 "에디터 없음" 비목표 무저촉. 기존 hunk 스테이지 WKWebView postMessage 브리지 재사용. `lineText` 재앵커링(anchored/moved/outdated)으로 라이브 리로드 diff 드리프트 방지. 리포키 = canonical root SHA256. (재앵커링 uniqueness는 hunk 스코프 아닌 파일 전체 스코프로 MVP 단순화; 다중 선택 코멘트·commit diff 코멘트는 미지원.)
- **④ 스크롤백 리플레이 [M·상]** — PTY 화면 복원 갭 메움. ghostty surface 텍스트 readback→저장(색 OSC 스트립·용량 상한)→env로 새 셸 시작 시 재출력. libghostty 텍스트 readback API 확보가 M 요인.

### 저비용 즉효 (S~M)

- **⑤ 팔레트 액션 실행 통합 [M·상]** — ⌘K 점프 전용 → 명령 실행. `QuickSwitchItem`에 `.command(KeymapAction)` 케이스 얹어 기존 `perform` 재사용. GitService 동작(브랜치 전환·워크트리 생성)도 흡수.
- **⑥ 알림 카테고리 + 배달 게이트 [S·상]** — "안 보이면 무조건 알림" → category(turn-complete/needs-permission/idle)×pending×설정 순수 `shouldDeliver` 게이트. muxa notify에 category 인자 추가. muxa "순수 값타입 분리" 철학과 일치.
- **⑦ `GIT_OPTIONAL_LOCKS=0` 비잠금 status [S·중상]** — 에이전트가 같은 리포에서 git 동시 실행 중 인덱스 락 경합 제거. `GitService.run`/`runResult` 프로세스 env에 한 줄.
- **⑧ 설정 라이브 리로드 [S·중]** — `MuxaConfig.parse`가 순수라 로더 경계에 `DispatchSource` 파일워처만. 저장 시 재파싱 + `KeymapResolver` 재빌드. 재시작 불필요.

### 추가 후보 (중~하)

알림 dedup/coalescing(같은 tabId+kind 연속 배지 last-write 병합+cooldown, S·중) · `DispatchSourceProcess(.exit)` 종료 감지(크래시·강제종료 결정론, M·중) · side-by-side diff 토글(`CodeHTML` 좌/우 순수 렌더, M·중) · 스냅샷 `version` 필드+용량 상한+크래시 마커(S·중) · 키 재정의 충돌·예약키 감지 리포트(현재 무음 무시→경고, M·중) · notify CLI 견고성(소켓 실패해도 exit 0으로 에이전트 흐름 안 막기, S·중) · 이중 주소 `MUXA_SURFACE_ID`(칸 단위 라우팅, M·중).

### 배제 권고 (muxa 소형·MIT 지향에 과잉)

cmux `GitMetadataService`(수제 git 온디스크 파서 — CLI 셸아웃 일관성에 배치, L·하) · nucleo FFI(무의존성 원칙 상충 — 자체 `FuzzyMatch`에 갭 패널티·최근성 boost·매치 하이라이트만 더하는 게 muxa답다) · `@pierre/diffs` 통짜 도입 · 135액션·2500줄 설정 시스템.

### 기타 (기존 백로그 · 저심각)

- 실기기 검증(기존): 세션복원(활성칸)·2단 서브탭·문서영속 — 눈으로 아직
- pull/push 타임아웃·취소, diff 도구줄 stale 배너 clear, 원격 트래킹 브랜치 체크아웃, hunk 언스테이지, PR 배지 폴링, runResult 대량출력 파이프(실위험 낮음)
- 붙여넣기 무조건 승인(`confirm_read_clipboard_cb` "M0" 잔재)
- git status 부분 재계산(FSEvents 이벤트마다 status+log+branch 전량 재실행, `FileWatcher.lastPaths` 미사용) — 성능 부채

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
