# muxa 진행 상태 · 인수인계 (2026-07-17 · rev15)

> 다음 세션이 여기서 이어간다. 아키텍처·결정은 [ARCHITECTURE.md](ARCHITECTURE.md), UI 디자인 시스템은
> [DESIGN.md](DESIGN.md). 이 문서는 **현재 상태·다음 할 일**만.

## 재개 방법

```bash
./scripts/bootstrap.sh      # (새 머신 최초 1회) GhosttyKit 설치 — docs/SETUP.md
cd macos
swift build                 # 빌드 (SPM)
swift test                  # 순수 로직 단위 테스트 (94개, GhosttyKit 링크 포함)
.build/debug/muxa           # bare 실행 (창 뜸, 아이콘 런타임 적용·시스템 알림은 Dock 바운스 폴백)
# 정식 아이콘·시스템 알림: ./scripts/build-app.sh && open macos/.build/debug/muxa.app  (.app 번들 = bundleId 생김)
# UI 변경은 재빌드+재실행. pkill로 죽이면 세션 저장(applicationWillTerminate) 안 됨 — ⌘Q로 정상 종료해야 복원됨.
```

커밋 자유(private), push만 승인. 커밋 트레일러 금지. 응답은 한국어.

## 마일스톤 진행

- **M0 IME·임베딩** ✅ · **M1 터미널 코어** ✅ (워크스페이스·Bonsplit 분할/탭·⌘F·세션복원·사이드바 4모드·모니터 스케일)
- **M2 보는 눈 + 알림** ✅ — 익스플로러 + md/코드 뷰어 + FSEvents + 알림 배지 (아래 상세)
- **M3 git 읽기(C)** ✅ — 상태 패널·diff 탭·히스토리
- **M4 워크트리** ✅ (완결) — list/add/**remove UI**·WorktreePicker·`.worktrees/<branch>`+exclude
- **M4 git 쓰기** ✅ → **D37에서 축소** — 스테이징·커밋은 **삭제**, 남은 쓰기는 **거부(파일 버리기·헝크 되돌리기)**뿐
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
- **Git 패널 = 리뷰 창구 재편** ✅(로직) / ★(육안) — 아래 상세

### Git 패널 재편 (커밋별 파일 내역 + 2탭 + 리뷰 상태)

**왜** — Git 패널이 "SourceTree 축소판"으로 흘렀고, 정작 **커밋이 어떤 파일을 건드렸는지 패널에서 볼 수 없었다**
(`commitDiff`의 `show --stat -p` 통짜 텍스트를 서브탭에 던지는 게 전부). 변경사항 탭만 파일 단위 밀도를 갖는 비대칭.

**한 것**
- **커밋·스테이징 삭제(D37)** — 커밋박스·스테이지 버튼·헝크 스테이지 + `GitService`의 쓰기 API 6개 제거.
  변경 목록은 스테이지됨/변경 구분 없이 **한 목록**. muxa는 편집을 에이전트에게 맡기므로 사람이 커밋을 조립하지 않는다.
  **버리기·되돌리기는 남는다**(저작이 아니라 리뷰 판정의 "거부"). 사람이 굳이 커밋하려면 옆 칸 터미널에서.
- **일반 뷰어로 열기** — 미커밋 파일을 ⌥클릭·우클릭 메뉴로 md 렌더링/코드 하이라이트 뷰어에(`store.openFile` 재사용,
  탐색기와 같은 경로). 삭제된 파일은 제외(디스크에 없다). **커밋 안 파일은 diff만** — 그 시점 내용을 보려면
  `FileViewTarget`을 "경로를 읽는" 타입에서 "내용을 받는" 타입으로 넓혀야 해서 이번 범위 밖.
- **커밋별 파일 내역** — `GitCommitFile` 값 타입 + `GitService.commitFiles`(`--name-status` ∥ `--numstat`, 경로로 결합).
  커밋 행 클릭 = **펼침**(아코디언 1개·해시 캐시), 파일 행 클릭 = `.commitFile` 서브탭. 통짜 diff는 우측 `⧉`.
- **2탭 재편** `[리뷰 | 히스토리]` — 예전 3탭은 `이번 세션 ⊂ 히스토리` 포함관계라 같은 커밋이 중복 렌더됐다.
  세그먼티드 `Picker` → `PanelTabSwitcher` 알약(앱 유일 이탈이었고 시스템 accent가 새어 들어왔다).
- **"세션" → "이번 작업"**(UI 문구만) — tmux 백그라운드 세션·Claude Code 세션과 3중 충돌. **코드 필드명(`sessionBase`)은 유지**(스냅샷 하위호환).
- **파일별 "봤음"은 만들었다가 걷어냈다** — 워킹트리가 살아 있어 표식이 대부분 지워진 채였고, 값은 얇은데
  비용(행마다 아이콘 + 갱신마다 파일별 `git hash-object`)이 두꺼웠다. 대신 **변경 시각**(`GitFileTime`) —
  클릭 없이 얻어지고 "방금 만진 게 뭐지"라는 실제 첫 질문에 답한다.
- **파일 상태는 GitHub식 diff 글리프** — 문자(A/M/D) → 사각형 안 `+`·`·`·`−`·`→`.
- **D-3 리뷰 코멘트 커밋 앵커** — `ReviewComment.commit`(옵셔널·하위호환). 없을 땐 커밋 코멘트가 워크트리 diff로
  **새어나왔다**(스토어는 리포 키, 앵커는 file+side+lineText만 봤다). 지시문에 짧은 해시가 실린다.
- **SSOT 추출** — `GitStatusStyle`(git 축)·`PRStatusStyle`. 죽은 `GitFileStatus.badge` 제거(untracked를 `U`,
  conflict를 `C`로 내보내 git 원문과 **정반대**였다 — 소비처가 없어 화면엔 안 떴지만 지뢰였다).
- **시각 정합** — 커밋 버튼 `Color.accentColor`+`Color.white` → `pBrand`/`pOnBrand`, `SectionLabel`의
  `.opacity(0.7)` 제거(공용이라 사이드바까지 전파됐다), 파일·커밋 행 `ListRowFill`, 에러에 글리프 추가.
- **파일 분해** — `GitPanel.swift` 552 → 324줄 + 신규 8파일.

**테스트** — swift-testing 307 + XCTest 1116, 실패 0. 신규 36개: 파서 21(머지 결합 diff 비대칭·리네임 브레이스
압축 경로·바이너리 `-`는 0이 아니라 nil), 리뷰 상태 9, 코멘트 스코프 6.

**★ 육안 미검증** — 커밋박스·버리기 사라진 리뷰 탭 · GitHub식 상태 글리프 · 변경 시각 · 뷰어 아이콘(미커밋·커밋 양쪽) · 커밋 펼침/접힘·lazy 로드 · 파일 행 → 그 파일만의 diff 서브탭 · **재시작 후 `.commitFile`
서브탭 복원**(`ItemSnapshot.commitFile`) · 머지 커밋 "파일을 바꾸지 않았습니다" 라벨 · 알약 스위처 렌더 ·
`lane` 면 동심원 · "봤음" 체크와 자동 해제 · 180pt 최소 폭에서의 행 조판.

**안 한 것(의도)** — 커밋 그래프·rebase/cherry-pick/revert 버튼·blame·패널 안 diff 렌더링.
되돌림도 "리뷰 코멘트로 에이전트에게 지시"가 muxa의 경로다.

## 다음 후보 (미구현) — 사이드바 에이전트 목록 (Orca 대조 완료)

프로젝트 행의 **분포 pill**(리딩 헤드라인 + 접힘/확장 pill, 커밋 `8e34b9b`)을 Orca식 **에이전트 목록**으로
확장하는 방향. Orca 실제 코드(`../orca` Electron 클론 — [[orca-cmux-reference-clones]])로 대조해
"베낄 것 / 이길 것"을 좁혔다. **결론: "Orca 약점" 프레임은 절반 틀렸다** — 아래처럼 흡수 3 + 개선 4.

**Orca 컴포넌트(대조 SSOT)** — `orca/src/renderer/src/components/sidebar/`:
- 접힘 pill·트리 `worktree-card-compact-agents.tsx` · 개별 행 `worktree-card-compact-agent-row.tsx`
- 상태 그룹핑·요약 `worktree-card-agent-summary.ts` · 행 데이터·**agent 판정** `worktree-agent-rows.ts` +
  `worktree-title-derived-agent-rows.ts` · 정렬 `worktree-agent-row-order.ts` · full 행 `dashboard/DashboardAgentRow.tsx`
- 본문 텍스트 파생 `lib/agent-row-primary-text.ts`. 기본 모드 `compact`(`src/shared/constants.ts:51`).

**Orca가 이미 잘함 → 흡수(개선 아님):**
- **상태 인지형 본문** — working이면 라이브 도구 호출("Bash: pnpm test"), done이면 마지막 메시지
  (`worktree-card-compact-agent-row.tsx:52`). primary는 부트스트랩 preamble 절대 노출 안 함.
- **에이전트만 분류** — 훅 리포트 + CLI 타이틀 매칭(Claude/Codex/Gemini…)만 행 생성, 순수 셸 제외
  (`worktree-title-derived-agent-rows.ts:128`). muxa는 `hookedTabs`로 같은 판정 가능.
- **성능** — per-워크트리 구독 + **카드당 relative-time 타이머 1개**(빈 카드는 0). muxa 폴링·칩 갱신에 참고.
- **파괴 판정 보수** — 훅이 조용해지면 working→`idle`로 낮추되 **삭제 안 함**(`worktree-agent-rows.ts:237`). muxa 원칙과 동일.

**muxa가 이길 지점(진짜 개선):**
- (3) **활성 우선 정렬 + 유휴 접기** — Orca는 `startedAt` 오름차순 평면 나열이라 유휴가 섞여 소음
  (`worktree-agent-row-order.ts:17`). muxa는 대기→작업중→완료→유휴 정렬, 유휴는 "○ N" 한 줄로 접기.
- (4) **상태 한정 시간** — Orca는 맨숫자 "19m"이라 "시작? 완료?" 모호. muxa는 "입력 대기 19m째"·"완료 23h 전".
- (5) **접힘에서 바로 점프** — Orca 다중 pill은 확장 토글만(내부 아이콘 `aria-hidden`). muxa는 접힘 칩 클릭=순환 점프(이미 있음).
- (1) **명시적 카운트** — Orca 접힘은 색 dot로만(숫자 없음, aria-label에만). muxa는 상태별 숫자 표기(색맹+즉독).

**데이터 준비(전부 있음):** 라이브 활동 = `ToolActivity`(편집/실행/검색) + 탭 제목(Claude OSC) · 경과/대기시간 =
추정기 `lastOutputAt`(systemUptime 경과) · 에이전트 판정 = `hookedTabs`. **경량 가드**: 접힘 기본 + 유휴 접기로 절제
(muxa 우위=가벼움, [[muxa-vs-orca-positioning]]).

## 최근 완료 (2026-07-23) — 문서 뷰어 원본/미리보기 토글 (SRC-TOGGLE, v0.2.0)

md/HTML 뷰어에 렌더 ↔ 원문 텍스트 전환. 새 웹뷰 없이 `shell.html`의 `render()`에 `source` 파라미터 추가
(escape 후 `<pre>`, md=markdown·html=xml 하이라이트). 버튼은 뷰어 우상단 오버레이 — 그룹 서브탭(`chrome:false`)엔
자체 헤더가 없어 오버레이가 유일한 자리. `MarkdownWebView.Coordinator`의 dedupe 키에 source 포함(안 넣으면 토글 무반응).

- **코드**: `shell.html`(render+source CSS) · `MarkdownWebView`(showSource+키) · `MarkdownView`(@State+오버레이 버튼)
- **버전**: CHANGELOG 0.2.0 준비 완료. 태그(`git tag v0.2.0`)는 사용자 승인 후.

### ★ 육안 검증 필요 (SRC-TOGGLE — `make dev-relaunch`)
1. ★ **토글 표시·동작**: 문서 뷰어 우상단 "원본" 버튼 → 원문 텍스트(pre), "미리보기"로 되돌림. 그룹 서브탭에서도 뜨는지.
2. ★ **md/html 양쪽**: .md는 markdown 하이라이트, .html은 xml 하이라이트로 원문이 보이는지.
3. ★ **다크/라이트·긴 줄**: 테마 따라가고 긴 줄이 접히는지(pre-wrap). 전환 시 스크롤 top 리셋.

## 최근 완료 (2026-07-21) — 명령 탭 재설계 v2: 실행→즐겨찾기·실행내역·로그영속 (CMD-V2)

CMD-UNIFY를 사용자 요구 재정의로 갈아엎었다. **등록 폼 폐기 → 실행 후 ★즐겨찾기=등록.** 명령당 실행
내역(로그 영속·10개)·cwd 칩(NSOpenPanel).

- **모델**(커밋 ea238d5): `CommandEntry`(command·name?·cwd?·favorite·executions[≤10]) + `CommandExecution`
  + `CommandStore`(순수: recordStart/Finish·toggleFavorite·setCwd·remove·sections·migrate). 테스트 12개.
- **배선·로그 영속**(aa93446): `Project.commands` + `CommandLogStore`(execId별 파일) + launchScript→recordStart,
  완료 관측→recordFinish + `TmuxService.capture`로 pane 로그를 파일로 굳힘.
- **UI**(7fcdf48·4814683): 즐겨찾기 섹션(전부·스크롤·▶즉시실행·★해제) + 히스토리(명령당·클릭 펼침→
  실행내역 ✓/✗·시각·소요·exit, 클릭→저장 로그) + **cwd 칩**(제안·NSOpenPanel[숨김·루트 자유]·직접입력).
- **마이그레이션**: 로드 후 `migrateCommandsIfNeeded` — 기존 scripts→즐겨찾기, commandHistory→히스토리.

**정리 잔여(dead code, 빌드 무해)**: v1 `CommandHistory`(record/sections/runState) · AppState v1
(commandSections·recordCommandRun·removeCommandHistory·clearCommandHistory·requestScriptAdd·commandHistory(of)) ·
`Project.scripts`/`commandHistory`·관련 CRUD(addScript·runScript…) — 마이그레이션 소스라 일부는 유지, 나머지는 후속 제거.

### ★ 육안 검증 필요 (CMD-V2 — `make dev-relaunch`)
1. ★ **즐겨찾기·실행**: 즐겨찾기가 전부 노출·스크롤되고 ▶로 즉시 실행. ★로 해제되는지. 마이그레이션(기존 등록 스크립트가 즐겨찾기로 뜸).
2. ★ **실행→즐겨찾기**: 입력창 실행 → 히스토리에 남고, ☆로 즐겨찾기 추가(=등록).
3. ★ **실행 내역**: 히스토리 명령 클릭 → 과거 실행들(✓/✗·시각·소요·exit) 펼침. 실행 클릭 → 저장 로그(재시작 후에도).
4. ★ **cwd 칩**: 📁 클릭 → 제안 경로·'폴더 선택…'(숨김·루트 탐색)·직접입력. 그 cwd로 실행되는지.
5. ★ **로그 영속·용량**: 명령당 실행 11번째부터 오래된 로그 삭제(`command-logs/`).

## 최근 완료 (2026-07-21) — 스크립트+일회용을 '명령'으로 통합 (CMD-UNIFY)

도크 3탭 `[서비스|스크립트|일회용]`에서 스크립트·일회용이 겹쳤다(둘 다 끝있는 명령, 차이는 등록 여부뿐 —
이미 같은 `Script`·tmux·`ScriptRun`). **`[서비스|명령]` 2탭**으로 합쳤다. 등록 여부는 축이 아니라 저장 위치.

- **명령 이력**(영속): `CommandHistory`(순수) — `record`(병합·**100개** 상한)·`sections`(등록/미등록)·`runState`
  (command→실행 인스턴스 매칭). `Project.commandHistory` 영속. `launchScript` 공통 지점에서 기록(등록·즉석).
- **명령 탭**: 입력창 + 등록 섹션(꺼냄, lastRun) + 최근 실행 히스토리(lastRun·횟수, 재실행·등록·삭제).
  `CommandRow.swift`(등록·히스토리 행 + `CommandRelativeTime` 'N분 전').
- **DockTab** 2탭, **ScriptStrip** → 명령 칩(즉석 실행도 요약, `commandRuns`), **⌘K** "명령 실행(한 번)".
- 정리: `oneOffHistoryHeader`·`oneOffHistory`·`OneOffRow`·`clearOneOffHistory` 제거(commandsColumn이 대체).
- 테스트 440개(이력 8·매칭 포함). 커밋 718e87f·50aec3c·d80c418 등.

### ★ 육안 검증 필요 (CMD-UNIFY — `make dev-relaunch`)
1. ★ **명령 탭**: ⌘J → `[서비스|명령]` 2탭. 명령 탭에 입력창 + 등록 섹션 + 최근 실행. 각 행 lastRun('N분 전').
2. ★ **즉석 실행→히스토리**: 입력창에 `sleep 2 && echo hi` → 실행 → 히스토리에 남고 재시작 후에도 lastRun 유지(영속).
3. ★ **행 액션**: 히스토리 행 hover → ▶재실행·⊞등록(시트 프리필)·🗑삭제. 등록 행 hover ▶실행. 비우기(미등록만).
4. ★ **푸터 명령 칩**: 등록·즉석 실행 중/잔류가 칩에 반영되는지. 클릭=명령 탭.
5. ★ **상세**: 등록/히스토리 행 클릭 → 우측 로그/터미널(실행 중 attach·종료 로그).

## 최근 완료 (2026-07-21) — 사용량 A-1 소스: statusLine sink로 429 회피 (USAGE-A1)

사용량 칩이 `/api/oauth/usage`(A-2)를 15분 폴링해 **429를 자주 맞았다**(엔드포인트 자체가 빡빡 —
"9%에서도 폴링만으로 제한" 실측). A-1(Claude Code statusLine stdin의 `rate_limits`)을 1순위 소스로 얹었다.
claude가 코딩하며 받은 값을 재활용하므로 **사용량용 요청 0회 → 429 원천 차단**. A-2는 폴백으로 그대로 유지
(A-1 없음·낡음·만료창이면 넘어감), A-3(PTY)도 최후 폴백으로 살아 있다("셋 다" 보완).

- **순수 로직**(커밋 d8dd8a1): `ClaudeUsage.parseStatusLine`(rate_limits→UsageLimit) · `UsageSourceSelector`
  (신선하면 사용+API스킵) · `ClaudeStatusLineSettings`(settings.json statusLine 멱등 병합·래핑·제거).
- **배선**(커밋 dd827f7): `muxa-notify statusline` 서브커맨드(stdin→`muxa-shared/statusline/latest.json`
  원자적 쓰기 + 사용자 statusLine pass-through) · `StatusLineUsageStore` · `ClaudeUsageService` A-1 우선
  (`UsagePolicy.statusLineFresh=600s`) · `ClaudeHookInstaller` install/uninstall이 훅+statusLine 함께 처리.
- **리뷰·실사용 반영**(커밋 c80b77f·9dc7bfc·e2e5793·1b9c0cd):
  - uninstall 유실 수정(래핑 파일 삭제를 write 성공 이후로) · sink SIGPIPE 방어(`SIG_IGN`+`write(contentsOf:)`).
  - **Fable 보존**: A-1은 five_hour/seven_day만 줘 Fable이 사라지던 회귀 → A-2 캐시의 모델 스코프 한도 병합.
  - **칩 tick 60s→2s**: A-1은 파일 읽기라 싸서 실시간에 가깝게(더 낮추면 같은 값 재읽기만 늚).
  - **훅 설치 유도를 전역 푸터로**(`HookInstallChip`): 인박스 안에만 있던 설치 버튼을 상시 보이는 푸터로.
    미설치·실패일 때만 뜨고 설치되면 사라진다. Swift6 경고 2건(liveFetch·Date.init)도 제거.
- 테스트 432개 통과. 헬퍼 sink는 **CLI e2e로 persist·보존·pass-through·EPIPE 방어 실측**.

**실사용 확인됨**: A-1 실제 작동(`latest.json` 갱신 관측) · ccstatusline 래핑 보존 확인 · 데스크탑 앱과 1% 차이는
소스 차이(statusLine=Claude Code 기준 vs 웹 집계)라 버그 아님(`/usage`와 일치).

### ★ 육안 검증 필요 (USAGE-A1 — `make dev-relaunch`)
1. ★ **훅 칩 표시**: 미설치·실패일 때 푸터 왼쪽에 "⚡ 훅 설치" 칩이 뜨고, 설치되면 사라지는지. 클릭 1번에 설치되는지.
   (지금은 이미 설치돼 안 보임 — "제거" 후 확인. **이 김에 `main` 빌드에서 재설치하면 slug가 main 헬퍼로 갱신**.)
2. ★ **동의/문구**: 설치 UI·툴팁이 "알림 + 사용량 추적"임을 알리는지 — 상태 라벨은 아직 "훅"만 말함(조정 후보).
3. ★ **전역 영향**: muxa 밖 터미널 claude도 statusLine sink를 매 렌더 실행 — 렌더가 느려지거나 깨지지 않는지.

**개발빌드 함정**: statusLine이 심은 워크트리(`muxa-dev-<slug>`)의 헬퍼를 가리킨다 — 그 워크트리를 지우면
sink가 죽어 ccstatusline까지 빈다. 켠 빌드에서 재설치하면 그 빌드 헬퍼로 갱신된다(릴리스는 `muxa/bin` 고정이라 무관).

## 최근 완료 (2026-07-20) — 사이드바 에이전트 목록: 터미널 / 뷰어 분리 (LIST-SPLIT)

프로젝트를 펼치면 터미널과 뷰어(문서·코드·변경)가 한 줄기로 섞여 나와, 실행 중인 것을 훑을 때마다
정적인 파일 이름을 건너뛰어야 했다. 시안 4안(정렬만 / 소제목 / 여백+선 / 접이식) 중 **C2**(여백+목록 폭 선) 채택.

- `AgentRow.sections` — 순수 함수. `viewerKind == nil`로 터미널/뷰어를 가르고, 유휴 터미널 수와
  **구분선 표시 여부**(양쪽 다 있을 때만)를 함께 낸다. 뷰에 있던 `visible`/`idleCount` 필터도 여기로 흡수.
- `SidebarProjectRow.agentList()` — 터미널 → "유휴 N" 폴드 → 구분선 → 뷰어 순서. 폴드는 **선 위**(터미널 쪽).
- 구분선은 `pBorder` 1pt, **행 들여쓰기 안에 가둔다**(레인 전폭 금지 — 상위 경계보다 세 보이면 위계 역전).
- DESIGN.md: "가로 구분선 없다"에 **목록 안 종류 경계** 예외 명문화 + 에이전트 목록 절에 두 덩어리 규칙 추가.

**검증**: 단위 테스트 6개 추가(분리·유휴 접기·빈 그룹 4경우) — 307개 전부 통과.

### ★ 육안 검증 필요 (LIST-SPLIT — `make dev-relaunch`)
1. ★ **선 세기**: 라이트/다크 양쪽에서 선이 보이되 튀지 않는지. 다크의 `pBorder`(423F3A)가 `lane`(23211E)과
   가까워 **너무 옅을 위험** — 안 보이면 다크만 별도 값이 필요하다.
2. ★ **빈 그룹**: 뷰어 0개(가장 흔함)일 때 선이 안 그려지고 **지금과 똑같이** 보이는지. 문서만 연 프로젝트도 선 없음.
3. ★ **유휴 폴드 위치**: "유휴 N"이 선 **위**에 남는지(아래로 가면 뷰어를 접는다는 오해).
4. ★ **간격**: 선 위아래 `Space.xs`(총 13pt 간격)가 과하지 않은지 — 프로젝트가 여럿일 때 목록이 길어 보이면 줄인다.

## 최근 완료 (2026-07-17) — 도크 리뷰 반영: 삭제 안전·로그 보존·서비스 중단 (DOCK-REFINE)

DOCK-TABS 실사용 4건 불만 + 시니어 UX·UI·디자인시스템 3인 검수를 시안(아티팩트 v3)으로 종합해 반영.

- **① 등록 해제 2단계 확인** (`Design/DeleteConfirmButton.swift`) — 아이콘 전용 관례 유지, 삭제만 예외로
  트래시→인라인 확인(정직한 문구 "실행 중인 web을 종료하고 등록·로그를 지웁니다"·취소가 오른쪽·취소 기본 포커스).
  서비스·스크립트 상세 헤더가 공유. 일회용은 저위험(등록 아님)이라 확인 없이. 용어 통일: 등록 축=**등록 해제**, 일회용=**기록 삭제**.
- **② 툴바 정리 + 추가 위치** — 툴바에서 ＋·비우기 제거(탭+닫기만, "탭 추가" 오독 제거). 추가는 **현재
  워크스페이스 카드 안**(`AddInCardRow`, 활성 프로젝트 대상·`→ 이름` 명시, 창 전체 목록에서 대상 모호성 제거),
  현재 카드는 비어도 항상 렌더. 일회용 비우기는 "최근 실행" 헤더로.
- **③ 종료 로그 스냅샷 보존** — dead pane capture 의존을 버리고 **종료 전이 순간 in-memory 스냅샷**
  (`AppState.finalLogs[id]`, `@ObservationIgnored` 아님·값 타입 밖). 스크립트=merge `exits`에서 캡처,
  서비스=중단 직전 캡처. `ServiceLogView.fallback` — 라이브 캡처가 비면 스냅샷 사용(재실행·중단·tmux 사망에도 로그 생존).
  remove/축출 시 정리. cross-restart 보존은 범위 밖.
- **④ 서비스 중단/재실행** — 새 `ServiceState` case가 아니라 **`userStoppedServiceIds` 오버레이 + 세션 kill**
  (`stopService`). 표시는 `ServiceDisplay`(순수 SSOT 위 한 겹): `.missing`+stopped → **중단됨**(stop.circle 무채),
  "실행 전"과 갈림. 순진한 프로세스 kill의 **exit 143 거짓 실패 알림·빨간 배지를 원천 차단**(isFailure 불변).
  상세 헤더 상태별: 실행중=중단·재실행 / 중단됨·실행전=시작 / 비정상종료=재시작. 서비스 행 hover=중단/시작.
  restart/remove 시 오버레이 정리.
- 검증: `swift build` green · 305 테스트 green.

### ★ 육안 검증 필요 (DOCK-REFINE — `make dev-relaunch`)
1. ★ **추가 위치**: 도크 툴바에 ＋ 없음. 현재 워크스페이스 카드 안 `＋ 서비스/스크립트 추가 → muxa`. 다른 워크스페이스엔 추가 없음.
2. ★ **2단계 삭제**: 상세 헤더 🗑 → "…등록·로그를 지웁니다" 확인 → 취소/등록 해제. 취소가 오른쪽·기본 포커스.
3. ★ **서비스 중단**: 실행 중 서비스 상세/행 hover에 중단 → 프로세스 종료·**등록 유지**·"중단됨" 표시. **실패 알림·빨간 배지 안 뜸**. 시작으로 재기동.
4. ★ **로그 보존**: 스크립트 실행→종료 후 재실행해도 이전 종료 로그가 상세에 남는지(스냅샷 폴백). 서비스 중단 후 로그 보임.
5. ★ **일회용 비우기**: 일회용 "최근 실행" 헤더 오른쪽 비우기(완료분만). 툴바엔 없음.

## 최근 완료 (2026-07-17) — 서비스 도크 3탭 + 일회용 명령 러너 (DOCK-TABS)

서비스 도크를 **3탭 허브**로 재편: `[서비스 | 스크립트 | 일회용]`. 축은 셋 — **서비스**(끝없는·등록·자동기동) /
**스크립트**(끝있는·등록·반복) / **일회용**(끝있는·즉석·1회). UX·UI를 서브에이전트 2인(플로우/시각)으로
설계한 뒤 구현.

- **스크립트 팝오버 제거** — `ScriptPopover.swift`·`ScriptRow`(struct) 삭제, `ScriptStrip`의 `.muxaPopover` 제거.
  스크립트 칩 클릭 = **도크 스크립트 탭 토글**(서비스 칩과 대칭 — `ServiceStrip.toggleDock` 계약). running 앞
  세그먼트=출력 보기 유지, 팝오버 세그먼트=삭제(단일 클릭). 스크립트 추가 시트가 **도크 호스팅**으로 이전
  (StatusBar의 `showAddScript`/`scriptAddSheet` 삭제 — "팝오버는 시트 못 띄움" 제약 소멸).
- **탭 스위처** — FooterChip 알약 재사용(선택=`pBtnActive`), 축 글리프(원형/사각형/`terminal`). 목록 열 하한
  150이라 좁으면 `ViewThatFits`로 라벨 접어 글리프만. 실패 있을 때만 탭에 빨간 롤업 점. `scopeItems`는 활성 탭
  종류로 필터(`groupByWorkspace`에 한쪽만 전달), 이전 세션의 `sectionLabel`/`mixed`는 제거.
- **일회용 러너** — `runScript` 코어를 `launchScript(_:in:cwd:)`로 추출 → 등록 스크립트·일회용 공유. 일회용은
  `Project.scripts`에 저장 안 함(세션 한정 `oneOffScripts`, 상한 20 LRU·완료분만 축출). `ScriptRun`/`ScriptSession`/
  tmux/`ScriptStatusStyle`(사각형 축) **전면 재사용**. 탭 UI = 입력창+[실행](Return·brand CTA) / 역시간순 flat 기록
  (`OneOffRow`, 제목=명령 mono) / 빈 상태는 입력창 유지 + 프로젝트 감지 채움 칩(클릭=입력, 실행 아님) /
  hover=재실행·등록(승격)·삭제. ⌘K "일회용 명령 실행"(`KeymapAction.runOneOff`)이 탭+입력창 포커스.
- **불변식(테스트로 못 박음)** — ① `mergeScriptObservation`·`syncServiceMonitor`가 `trackedLocatedScripts`(등록+일회용)를
  넘겨 일회용 run이 증발하지 않음(ScriptRunTests 2건 신규) ② 푸터 스크립트 칩 feed(`scriptRuns(of:)`)를 **등록 id로
  필터** — 일회용이 칩에 안 샘. GC 입력(`collectLiveScriptIds`)엔 일회용 제외 → 다음 세션 자동 청소.
- 검증: `swift build` green · `swift test --filter ScriptRunTests` 16개 green.

### ★ 육안 검증 필요 (DOCK-TABS — `make dev-relaunch`)
1. ★ **탭 전환**: ⌘J → 도크 상단 `[서비스|스크립트|일회용]` 탭. 클릭 시 목록·상세·＋대상이 바뀌는지. 좁힐 때 라벨→글리프.
2. ★ **스크립트 칩**: 등록 0개 [스크립트] 클릭 → 도크 스크립트 탭(빈 상태 + [스크립트 추가]). 실행 중 칩 클릭 → 라이브 출력. 잔류 클릭 → acknowledge+로그.
3. ★ **스크립트 추가**: 스크립트 탭 ＋ → 시트(도크 호스팅, 팝오버 없음) → 등록 → 목록. hover ▶ 1클릭 실행.
4. ★ **일회용 실행**: 일회용 탭 입력창에 `sleep 2 && echo done` → Return → 기록에 `⟳ … 2s` → `✓ … 2s`, 우측 상세에 로그.
5. ★ **일회용 칩 격리**: 등록 0개 + 일회용 실행 중 → **푸터 스크립트 칩은 여전히 [스크립트] 플레이스홀더**(일회용이 안 샘).
6. ★ **일회용 재실행·승격·삭제**: 기록 hover → ⟳(새 기록)·⊞등록(승격 시트 프리필)·🗑. 비우기(🗑 툴바)는 완료분만.
7. ★ **⌘K 일회용**: ⌘K "일회용 명령 실행" → 일회용 탭 + 입력창 포커스.
8. ★ **실패 롤업 점**: 서비스/스크립트/일회용 중 실패가 있으면 그 탭 라벨 뒤 빨간 점(다른 탭 보는 중에도).

## 최근 완료 (2026-07-19) — 서비스 도크 터미널의 스크롤·드래그 복구

실사용 버그: 도크의 서비스 터미널에서 휠이 아무 반응이 없고, 텍스트를 끌어 선택하려 하면 **앱 창이 통째로 움직였다.**
원인이 둘로 갈렸다.

- **창 이동 가로채기**: 창이 `isMovableByWindowBackground`인데 `NSView.mouseDownCanMoveWindow` 기본값이
  true라, AppKit이 mouseDown을 뷰에 넘기기 **전에** 창 이동으로 가져갔다 → `TermView`·`TermHostView`에서 false로.
- **스크롤할 것이 양쪽 다 없음**: attach는 alternate screen이라 지난 출력이 ghostty 스크롤백에 안 쌓이고,
  tmux는 `mouse off`면 휠을 처리하지 않는다 → `startArgs`에 `set -g mouse on`(전용 소켓 `-L`이라 사용자
  tmux에는 영향 없음). 세션 생성 경로에만 두면 **이미 돌고 있는 서비스에서는 영영 안 고쳐지므로**
  (tmux 서버가 앱보다 오래 산다) 도크를 열 때 `TmuxService.applyDockViewingOptions`로 다시 건다.
- 테스트: mouse 옵션이 `new-session` 앞에 `on`으로 온다 — 전체 307개 통과.

### ★ 육안 검증 필요 (`make dev-relaunch`)
1. ★ **이미 돌고 있던** 서비스의 도크에서 휠 스크롤 — 앱만 재실행하고 서비스는 그대로 둔 채 확인
   (`applyDockViewingOptions` 경로. 서비스를 재시작하면 `startArgs` 경로라 다른 검증이다).
2. ★ 도크 터미널에서 드래그 → 창이 움직이지 않고 tmux 선택이 되는지. 메인 칸의 드래그 선택도 회귀 없는지.
3. ★ **회귀 우려**: `mouse on`이면 `ghostty_surface_mouse_captured`가 true라 도크에서 **우클릭이 tmux로 간다**
   — muxa 컨텍스트 메뉴(복사)가 안 뜬다. 이 교환이 받아들일 만한지 실사용에서 판단 필요.

## 최근 완료 (2026-07-17) — 서비스 셸 환경 일치 + 실행 폴더 지정 (SVC-CWD) → D35·D36

실사용 버그에서 출발: xames-admin에서 `pnpm dev:local` 서비스가 corepack 서명 오류(exit 1)로 즉사.
원인은 **로그인 비인터랙티브 셸**(`-l -c`)이 `.zshrc`(nvm·`PNPM_HOME`)를 안 읽어, 탭에서는 잡히던
pnpm 대신 homebrew 구버전 corepack shim이 잡힌 것. 함께 "서비스가 프로젝트 하위 폴더에서 돌아야
한다"는 요구도 해결.

- **D35**: `TmuxService.startArgs` 셸 래핑 `-l -c` → `-l -i -c` — 서비스·스크립트가 탭(인터랙티브)과
  같은 PATH를 보게. tmux **탐지**는 `-l -c` 유지(앱 기동 경로에 rc 부작용 금지).
- **D36**: `Service.cwd`·`Script.cwd`(옵셔널, nil = 상속) — 해석 사슬 자체지정 → 프로젝트 경로 →
  워크스페이스 경로를 `collectAllServices`/`collectAllScripts` 한 곳에서. 추가 시트 "실행 경로"가
  편집 필드로(placeholder = 프로젝트 경로, `~` 확장·존재 검증, 기본값과 같으면 저장 안 함 —
  `runCwdOverride` 순수 함수). 워크스페이스 경로 변경 자동 재시작은 자체 지정 서비스를 건너뜀.
- 테스트: startArgs `-i` 포함·cwd 해석 사슬·override 정규화(빈 값·동일 값·`~`·뒤 슬래시) — 전체 303개 통과.

### ★ 육안 검증 필요 (SVC-CWD — `make dev-relaunch`)
1. ★ 서비스 추가 시트: 실행 경로 필드에 하위 폴더(`apps/…`) 입력 → 스크립트 후보가 그 폴더 기준으로
   다시 스캔되는지 → 등록 후 그 폴더에서 도는지(`tmux -L muxa-services-* list-panes -a -F '#{pane_start_path}'`).
2. ★ 없는 폴더 입력 → 앰버 경고("폴더를 찾을 수 없습니다") + "추가" 비활성.
3. ★ 비워두면 기존과 동일(프로젝트 경로) — 기존 서비스 재시작·자동기동 회귀 없음.
4. ★ nvm/PNPM_HOME 환경에서 `pnpm dev` 서비스가 즉사 없이 뜨는지(-i 효과 — 실제 xames-admin에서 재현 확인).
5. ★ rc가 느린 환경에서 서비스 기동 지연이 체감되는지 관찰.

## 최근 완료 (2026-07-17) — 지속 세션(∞) 탭 제목 접두 (INF-TITLE)

에이전트가 작업 중이면 탭 좌측 슬롯을 상태 마크(스피너·⏸·✓)가 차지해 **∞ 아이콘이 안 보였다**
(에이전트 탭은 대부분 그 상태 — "어느 탭이 tmux 안인가"가 실사용에서 사라짐, 사용자 불만).
제목을 상태와 경쟁하지 않는 채널로 써서 **"∞ muxa"처럼 접두**를 단다. → DESIGN §4.

- `TabTitle.decorate(_:persistent:)` (순수·멱등 — "∞ " 이중 접두 방지) + XCTest 2건.
- Bonsplit으로 나가는 제목의 **단일 관문** `TerminalStore.pushTitle` 신설 — 엔진 제목(OSC)·수동
  이름·해제 폴백·복원 경로가 전부 경유. 원본 저장소(manualTitles·engineTitles)·스냅샷·detached
  기록은 무장식 유지(tabTitle 로직 오염 없음).
- 생성(newTerminal·reattach·복원 createTab)은 초기 제목부터 접두, `releaseDetachedTab`(tmux 이탈
  확정)은 아이콘과 함께 접두도 뗀다.
- 검토한 대안: 탭 우측 트레일링 ∞ 슬롯(Bonsplit fork 수정) — 더 깔끔하지만 fork 리비전 절차가
  필요해 사용자가 제목 접두를 선택. fork 슬롯은 후속 후보로 남음.

### ★ 육안 검증 필요 (INF-TITLE — `make dev-relaunch`)
1. ★ ∞ 탭에서 claude 작업 중(스피너) — 제목이 "∞ <이름>"으로 구분되는지.
2. ★ 일반 탭엔 접두 없음 · ∞ 탭 수동 이름 변경 후에도 접두 유지 · 이름 해제 시에도 유지.
3. ★ `⌃b d`로 tmux 이탈 → 아이콘·접두 둘 다 떨어지는지.
4. ★ 재시작 복원된 ∞ 탭 — 처음부터 접두가 붙어 있는지(엔진 제목 도착 전 "∞ 터미널").

## 최근 완료 (2026-07-17) — 스크립트 백그라운드 실행 (SCRIPT-BG) → D34

SCRIPT-TAB(아래, 07-16)의 **탭 실행 경로를 통째로 대체**했다: 스크립트는 이제 탭을 띄우지 않고
**서비스와 같은 전용 tmux 소켓의 백그라운드 세션**(`muxa__<proj>__script__<id>`)에서 돈다.
`remain-on-exit` 덕에 끝나도 pane이 남아 **exit code·종료 로그가 보존**되고, 출력은 **서비스 도크**에서
본다(실행 중 = attach 라이브 터미널 / 종료 = capture-pane 읽기 전용 로그). 사용자 요구 3건이 출발점:
실행 버튼 상시 노출·탭 없는 백그라운드 실행·종료 후에도 로그 보존.

- **세션 규약** — `ScriptSession`(순수): 4조각 `script` marker — 서비스(3조각)·터미널(`term`) 파서/GC와
  상호 불가침(테스트로 고정). 고아 GC는 **등록 해제된 것만**(종료 로그 pane은 등록이 살아 있는 한 보존).
- **관측·전이** — `ServiceMonitor`의 같은 2초 폴링이 스크립트 세션도 배달(`onScriptsPoll`, 빈 관측도 발화).
  전이는 순수 `ScriptRun.merging`: running 유지(startedAt 보존)·exited 확정(+실패만 attention·배지)·
  **재시작 후 채택**(startedAt/duration nil — 경과를 지어내지 않음, 옛 결과는 acknowledged로 조용히)·
  유예(10s) 지난 세션 소멸 = "결과 미상"(✓/✗ 안 지어냄). 레지스트리는 AppState 전역(`scriptRuns`).
- **실행** — `AppState.runScript`: dedup(도는 중이면 도크 출력 reveal), 재실행은 세션 갈아엎기
  (이전 로그 수명 = 다음 실행 전까지), 시작 실패는 attention + 엔트리 제거. tmux 미설치 = 도크 설치 안내.
- **도크 통합** — 그룹핑(`groupServices`/`groupByWorkspace`)에 scripts 동승(스크립트뿐인 프로젝트도 목록에),
  `ScriptDockRow`(선택 알약) + 상세(헤더: 글리프·경과·재실행·등록해제 / 본문: attach 터미널·로그·실행 전 안내),
  접힌 워크스페이스 롤업에 스크립트 실패 포함. `ServiceLogView`는 세션명 기반으로 일반화.
- **푸터 칩 4모드** — `.hidden` → **`.empty` 플레이스홀더**(상시 — 서비스 칩과 같은 발견성 철학).
  실행 중 클릭 = 도크 출력, 잔류(✓/✗) 클릭 = **acknowledge + 도크 로그**(칩만 내려가고 결과·세션·로그는 남음).
- **삭제** — 탭 실행 경로 전부: `ScriptRunCommand` 래퍼, `script-exit` 소켓 프레임(NotifyServer·muxa-notify),
  TerminalStore의 scriptCommands/runScript/deliverScriptExit, 스냅샷 강등 특례.
- 검증: `swift build` green · **테스트 301개** green(재작성: ScriptRun merge 14·Chip 12 / 신설: ScriptSession 7·
  Script collect 2·Monitor 스크립트 2 / 삭제: 래퍼·프레임·와이어 e2e).

### ★ 육안 검증 필요 (SCRIPT-BG — `make dev-relaunch`)
1. ★ **빈 칩**: 스크립트 0개에서 푸터에 [▶ 스크립트] 플레이스홀더 상시 → 클릭 → **도크 스크립트 탭**(빈 상태 + ＋) → 시트 → 등록. (DOCK-TABS로 팝오버 대체)
2. ★ **성공 경로**: `sleep 2 && true`류 실행 → 탭이 안 뜨고 칩 `⟳ 이름 · 2s` → `✓ 이름 2s` 잔류 → 클릭 → 도크에 종료 로그 + 칩 내려감.
3. ★ **실패 경로**: `exit 2`류 → 칩 `✗ 이름 exit 2` + 인박스 "이름 실패 (exit 2)" → 클릭 → 도크 로그에 에러 보임.
4. ★ **실행 중 출력**: 긴 명령(`sleep 30`) 실행 → 칩 클릭 → 도크에 라이브 터미널(attach) → Ctrl+C로 중단 가능.
5. ★ **dedup**: 도는 중 도크 스크립트 탭에서 같은 스크립트 hover ▶ 재클릭 → 새 실행 없이 도크 출력만 열림. (DOCK-TABS로 팝오버 대체)
6. ★ **재시작 생존**: 긴 명령 실행 중 muxa 재시작 → 칩이 running으로 복원(경과 없음 — 채택), 끝나면 결과 확정.
   끝난 뒤 재시작 → 잔류 칩은 안 뜨되(acknowledged 채택) 도크에서 로그는 보임.
7. ★ **등록 해제**: 도는 스크립트 삭제 → 프로세스·세션 함께 종료(`tmux -L muxa-services-* ls`로 확인).
8. ★ **.app 번들에서** attach·로그가 뜨는지(tmux 절대경로 해석 — bare 빌드만 되는 함정 재확인).
9. ★ **도크 상세 열어둔 채 ⟳ 재실행**: attach 터미널이 새 세션으로 갈아 끼워져 라이브 출력이 보이는지
   (기동 완료 후 dropDockTerm + restartSeq id — 빈 화면이면 리뷰 지적 경합의 재발).

**남은 것(범위 밖)**: 도크 스크립트 상세의 stdout 스트리밍 뷰(현재 attach/캡처로 충분), 스크립트 단축키 바인딩.

## 최근 완료 (2026-07-17) — 파일 드롭 첨부 수리 (FILE-DROP)

터미널 칸에 이미지·파일을 드래그해 경로를 삽입하는 기능(7/13 `35f9883`)이 사실상 죽어 있었다.
Bonsplit·muxa 코드 모두 구현 당시와 동일 — **처음부터 플레이키**였고 검증 때 우연히 통과한 것.

- **원인**: 레거시 `controller.onFileDrop`은 center zone에서만 드롭을 받는데(`acceptsFileDrop`),
  `validateDrop`의 zone 판정은 드래그가 칸에 **진입한 순간의 좌표**다. 가장자리 zone이 각 변
  25%(최소 80pt)라 진입 좌표는 거의 항상 edge → **세션 전체가 조용히 거부**(마우스를 빠르게 넣어
  첫 hover 이벤트가 중앙에서 잡힐 때만 통과). 증거: 디버그 로그에 `pane.dropExited`만 남고
  `validateDrop`/`dropEntered`/`drop`이 없음.
- **수정**: `controller.onExternalFileDrop`으로 전환(`TerminalStore.init`) — 이 핸들러가 있으면
  모든 zone에서 파일 드롭이 유효. destination(insert/split)과 무관하게 targetPane만 뽑아
  `insertDroppedPaths`로 라우팅(muxa 의미론 = "그 칸 터미널에 경로 삽입", zone 무관).

### ★ 육안 검증 필요 (FILE-DROP — `make dev-relaunch`)
1. ★ Finder에서 이미지를 터미널 칸에 **천천히** 드래그(가장자리로 진입) → 경로가 프롬프트에 삽입되는지. 이전엔 이 경로가 실패.
2. ★ 드롭한 경로를 claude code가 이미지 첨부로 인식하는지(백슬래시 이스케이프 형식 유지 확인).
3. ★ 여러 파일 동시 드롭 → 공백으로 이어진 경로들. 뷰어 탭(diff·문서)엔 드롭이 거부되는지.
4. ★ 파일을 가장자리 zone 위에서 hover할 때 분할 하이라이트가 떠도 드롭 결과는 "경로 삽입"(분할 아님) — 어포던스 불일치가 거슬리는 수준인지 관찰.

## 최근 완료 (2026-07-17) — 마지막 프롬프트 노출 (LAST-PROMPT)

사이드바 에이전트 목록과 백그라운드 터미널 팝오버에 **"내가 마지막에 뭘 시켰나"**를 노출.
지금까지 두 곳 모두 에이전트 쪽 사정(라이브 도구·상태·마지막 답변)만 말했다.

- **데이터**: `UserPromptSubmit` 훅 payload의 `prompt` 필드(기존에 버리던 것)를 파싱(`AgentPrompt.parse` —
  "[Image #N]" 마커는 개수로 접고 본문 500자 클램프). `TerminalStore.agentPrompts`(관측 맵)에 탭별 저장 —
  진행 표시와 달리 **턴이 끝나도 남는다**. transcript 경로도 미러(`agentTranscripts`, hover 이미지용).
- **사이드바 행(B+C 합침)**: 프롬프트가 있으면 **2줄** — 첫 줄 제목=프롬프트(승격), 아랫줄=`탭 이름 – 상태/라이브 도구`.
  이미지 첨부는 칩(`PromptImageChip`), 잘린 전문·이미지는 **hover 카드**(`PromptHoverCard`, 0.5s 지연).
  프롬프트 없으면(일반 셸·훅 이전) 현행 1줄 폴백. 뷰어 행은 승격 안 함(종류가 이름).
- **백그라운드 팝오버(문답 페어)**: `❯ 내 지시`(진하게, transcript 마지막 user 메시지 — tool_result·
  isMeta·사이드체인·슬래시 명령 배관은 건너뜀) + `↳ 마지막 답변`(흐리게). 이미지 칩 + hover 카드 동일.
  비 claude 세션은 tmux 화면 꼬리 폴백(현행).
- **인프라**: `HoverTip`을 일반화 — `TipHostView`/`TipWindow`가 칩·리치 카드 공용(`muxaHoverCard`).
  `TranscriptTail`에 `lastUserMessage`/`lastUserImages`(base64 디코딩) 추가, 재시도 루프는 `retryingTail`로 공통화.
- **테스트**: `AgentPromptTests`(파싱·훅 전달·제목 승격) + `TranscriptUserTailTests`(오염 차단·이미지) 등
  신규 2파일 — 전체 스위트 통과.

### ★ 육안 검증 필요 (LAST-PROMPT — `make dev-relaunch`)
1. ★ claude 탭에 프롬프트 입력 → 사이드바 행이 2줄(제목=프롬프트, 아랫줄=상태)로 바뀌는지. 다음 프롬프트에서 갱신되는지.
2. ★ 긴 프롬프트 행 hover 0.5s → 카드에 전문. 이미지 붙인 프롬프트 → 행에 `photo N` 칩 + 카드에 썸네일.
3. ★ 일반 zsh 탭·훅 이전 세션은 현행 1줄 그대로(2줄 오염 없음). 뷰어 행 불변.
4. ★ 2줄 행 높이·hover/선택 채움·시작선 정렬이 목록 리듬을 깨지 않는지(유휴 접기 행과 나란히).
5. ★ 백그라운드 팝오버: claude 세션에 `❯ 지시` + `↳ 답변` 페어, 이미지 칩 hover 카드. tmux 폴백 세션은 현행.
6. ★ hover 카드가 클릭·스크롤·키 입력에 즉시 접히는지(TipWindow 규칙 상속 확인).

## 최근 완료 (2026-07-17) — 주의 큐 헤더 → 주의 큐 카드 (QUEUE-CARD)

한 줄 헤더("메인 가 입력을 기다립니다")가 ① 어느 워크스페이스의 "메인"인지 침묵하고
② 여럿이면 "N개 프로젝트"로 뭉개던 걸 **카드**로 재설계했다. 시안 3안(레일·틴트·펄스 링) 중
사용자가 **C안(펄스 링)** 채택 — 칸 테두리의 대기 어휘("전체 링 + 펄스")를 카드가 공유한다.
→ DESIGN 용어표·컴포넌트 갱신.

- **순수 판정** — `SidebarTree.allWaiting`(배지 전부, ⌘⇧A 순회와 같은 순서) + `WaitingRef.workspaceName`.
  `firstWaiting`은 `allWaiting().first`로 축소. 테스트 2개 추가(순서·이름 적재, 306개 green).
- **경계 수확** — `AppState.waitingQueue`(`WaitingQueueEntry` = ref + `usesMonoName` + 대기 경과 초).
  경과는 그 프로젝트 대기 탭 중 최장(`agentRows`의 `waitingSeconds` 재사용) — **못 재면 nil**(지어내지 않는다).
  행 클릭용 `jumpToWaiting(projectId:)` = 대기 탭 지목(`revealNextTab`) → `revealActivity` 폴백.
- **카드 뷰** — `SidebarQueueHeader.swift` → `SidebarQueueCard.swift`(rename). bg 면 + **로즈 링 펄스**
  (`TimelineView` 시간구동 사인, reduce-motion이면 정적 링). 행 = ⏸(첫 행만 펄스) + **워크스페이스 › 프로젝트**
  (워크트리는 모노) + 경과(모노, 첫 행만 로즈). 2곳부터 머리글 "입력 대기 N"+⌘⇧A, 4행 초과는 "그 외 N곳"
  (클릭=순환 점프). 경과 갱신은 카드 로컬 1초 tick(ScriptStrip 규칙).
- **공용화** — `ListRowFill`(hover·선택 채움)을 `SidebarProjectRow` private → `Design/ListRowFill.swift`로 추출.

### ★ 육안 검증 필요 (QUEUE-CARD — `make dev-relaunch`)
1. ★ 단일 대기: 카드에 행 하나(머리글 없음), 링 펄스가 거슬리지 않는 밝기·주기인지(라이트/다크 둘 다).
2. ★ 다수 대기: 머리글 "입력 대기 N" + 행별 `워크스페이스 › 프로젝트` + 경과가 1초마다 갱신되는지.
3. ★ 행 클릭 → **그 프로젝트의 대기 탭**이 실제 선택되는지(배지만 남은 프로젝트는 프로젝트 이동만).
4. ★ 5곳 이상 대기 시 "그 외 N곳" 행 + 클릭 순환. 좁은 사이드바에서 워크스페이스명이 먼저 잘리는지(주어 보존).
5. ★ 링 펄스(TimelineView)가 사이드바 hover·트리 리렌더와 간섭 없는지, reduce-motion에서 정적 링인지.

## 최근 완료 (2026-07-17) — 사용량 조회 인스턴스 간 공유 캐시·백오프

429가 계속 재발하던 뿌리: muxa가 여러 개 동시에 뜨는데(워크트리별 개발빌드 + 릴리스) **각자
`/api/oauth/usage`를 따로 두드렸다**. A가 retry-after 백오프 중일 때 B의 프로브가 리밋 창을
연장시켜 아무도 못 빠져나오는 핑퐁. 게다가 개발빌드는 `make dev-relaunch`마다 시작 직후 1회 프로브(idle).
실측: 사용량은 5h 53%·주간 20%로 한도 소진이 아닌데도 429 + retry-after 2733초.

- **공유 스냅샷 파일** — `MuxaSupportDir.sharedURL`(`~/Library/Application Support/muxa-shared`,
  빌드 불문 단일 경로. `url`은 빌드별로 갈려 공유가 안 됨 — 이게 문제의 절반이었다). 모든 인스턴스가
  백오프(`blockedUntil`)·성공 캐시(`updatedAt`+limits)·single-flight(`inflight` 창)를 한 파일로 본다.
- **순수/경계 분리** — `UsageSnapshot`(Codable 값) · `UsageCoordinator`(plan/reduce/resolve 판정) ·
  `UsageCacheStore`(원자적 파일 IO). `ClaudeUsageService`는 인메모리 타이머를 버리고 공유 스냅샷을
  단일 출처로 참조. 한 인스턴스가 성공하면 나머지는 **네트워크 없이 캐시 값을 화면에 얹는다**.
- XCTest 3개 추가(캐시 공유 서빙·백오프 공유·갓 뜬 인스턴스가 제한 중 캐시값 표시). 기존 10개 유지, 303 green.
- ★ 육안 검증 필요: 릴리스+개발빌드 동시에 띄운 뒤 `muxa-shared/usage-cache.json`이 생기고
  두 인스턴스가 한 백오프 창을 공유하는지(재실행 버스트가 사라지는지).

## 최근 완료 (2026-07-17) — 사용량 429 레이트리밋 존중 + 오진 수정

상태바 Claude 사용량이 안 뜨는데 팝오버는 "로그인 필요"라고 오진하던 문제. 실측 진단:
토큰·키체인은 정상, 서버가 `/api/oauth/usage`에 **429 + retry-after 3068초**를 주고 있었다.
muxa는 429를 일반 실패로 뭉개 **45초마다 재시도** → 리밋 창이 계속 연장되는 자충수.
(의심했던 oh-my-hud statusline은 무죄 — stdin의 context_window만 읽고 API를 안 때린다.)

- `UsageFetch.rateLimited(retryAfter:)` + `UsageState.rateLimited` 신설 — 429는 retry-after만큼
  물러난다(헤더 없으면 15분, 상한 1시간). 수동 새로고침은 백오프 무시. 이전 값 유지는 실패와 동일.
- 팝오버: "로그인 필요" 대신 "요청 제한 중(로그인 문제 아님) · 약 N분 후 자동 재시도".
  칩 경고 삼각형 툴팁도 구분. XCTest 5개 추가(retry-after 존중·기본 15분·1시간 상한·값 유지·수동 우회).

## 최근 완료 (2026-07-17) — Shift+Enter 줄바꿈 (tmux extended-keys)

터미널 탭에서 Claude Code 등 안쪽 TUI에 **Shift+Enter가 그냥 Enter로 뭉개지던** 문제.
단독 Ghostty에선 kitty 키보드 프로토콜로 구분되지만, muxa 탭은 tmux를 경유하는데 tmux 기본값이
`extended-keys off`라 안쪽 요청이 무시됐다. `TerminalSession.startCommand`에 두 줄 추가:
`set-option -s extended-keys on`(안쪽 요청 수용) + `set-option -sa terminal-features 'xterm*:extkeys'`
(바깥 ghostty에 modifyOtherKeys 요청). 서버 옵션이라 서비스·스크립트 세션에도 함께 적용.
테스트 `extended_keys를_켠다` + 기존 1024바이트 길이 가드 통과(305개 green).

**육안 검증 완료(2026-07-17)** — 릴리스 재설치 후 Claude Code 입력창에서 Shift+Enter 줄바꿈 확인.
기본 키(Enter·한글 입력) 회귀 없음. 주의: 기존 tmux 서버가 살아있으면 새 탭을 열어 옵션이 박힌 뒤부터 적용된다.

## 최근 완료 (2026-07-16) — 일회용 스크립트 터미널 (SCRIPT-TAB) — **실행 경로는 SCRIPT-BG(D34)로 대체됨**

> 아래 탭 실행·래퍼·script-exit 프레임·★ 목록은 2026-07-17 SCRIPT-BG가 **삭제·대체**했다(이력 보존용).
> 모델(Script/Project.scripts)·표시 SSOT(ScriptStatusStyle)·시트 재사용은 그대로 살아 있다.

**끝이 있는 명령**(`make build` 등)을 원클릭 실행하는 스크립트 축 신설 → ARCHITECTURE **D33**, DESIGN 어휘표.
**서비스 = 끝이 없는 프로세스(tmux·도크·▶ 원형) / 스크립트 = 끝이 있는 명령(일반 탭·사각형 가족)**.
성공(exit 0) → 프로세스 종료 → `close_surface_cb` → **탭 자동 닫힘** / 실패 → `exec -l $SHELL`로 **셸 잔류**(에러를 그 자리에서).

- **모델** — `Script { id, name, command }` + `Project.scripts: [Script]?`(Persisted 자동 편승, 하위호환).
  CRUD는 `AppState.scripts(of:)/addScript/removeScript` — 서비스 미러이되 tmux 없음.
- **래퍼(순수·테스트)** — `ScriptRunCommand.wrap`: `/bin/sh -c '<로그인셸 -l -c 명령>; s=$?; muxa-notify script-exit --code $s; 실패 시만 exec -l $SHELL'`.
  **exit code는 소켓 프레임이 유일한 진실** — 워처는 exec pid 승계로 무음, OSC 133은 직접 exec에선 안 뜸(D33 근거).
- **프레임** — `script-exit\t<tabId>\t<code>`(NotifyServer 신규 파싱·`onScriptExit`) + muxa-notify `script-exit --code` 서브커맨드.
  와이어 계약은 **실물 e2e 테스트**(임시 소켓에 NotifyServer + 빌드된 muxa-notify spawn)로 못 박음.
- **실행 경로** — `TerminalStore.runScript`: dedup(실행 중이면 기존 탭 포커스) → createTab(`play.square`) → `scriptCommands` 심기.
  결과 레지스트리 `scriptRuns`는 **scriptId 키**(성공 프레임 vs 탭 닫힘 레이스 해소). ⌘W·프레임 유실은 `code nil` = **"결과 미상"**(✓를 지어내지 않음, `questionmark.square`). 재시작 스냅샷에선 일반 터미널로 강등.
- **푸터 칩 3모드**(`ScriptStrip`, DetachedStrip↔ServiceStrip 사이) — 평시: 개수+팝오버(목록·실행·trash 삭제·＋추가) /
  실행 중: `⟳ 이름 · 12s`(1초 tick은 칩 로컬) 클릭=탭 포커스 / 잔류: `✓ 이름 8s`(무채)·`✗ 이름 exit 2`(빨강) — 클릭 시 해제.
  **등록 0개면 칩 숨김** — 부트스트랩은 ⌘K/명령 메뉴 **"스크립트 추가"**(`KeymapAction.addScript`)와 StatusBar 상주 시트가 담당.
- **표시 SSOT** — `ScriptStatusStyle`(제3 축, 사각형 가족) + 순수 칩 판정 `ScriptChipMode.judge`. 시트는 `ServiceAddSheet` 파라미터화 재사용(ProjectScripts 스캔 그대로).
- **리뷰 마감** — 5차원 리뷰+적대적 검증에서 확정 6건 전부 수정: 부트스트랩 데드락(critical — 0개면 등록 진입점까지 숨었음),
  removeScript 죽은 코드, `frame(maxWidth:)` 탐욕 확장(`fixedSize` 상한화), runScript YAGNI 시그니처, 셸 테스트 밀폐(HOME 임시화), 와이어 e2e.
- 검증: `swift build` green · **테스트 297개** green(신규 32: Script 14·ScriptRun 7·ScriptChip 10·와이어 e2e 1).

### ★ 육안 검증 필요 (SCRIPT-TAB — `make dev-relaunch`)
1. ★ **부트스트랩**: 스크립트 0개 상태에서 ⌘K "스크립트 추가" → 시트 → 등록 → 푸터에 칩 등장.
2. ★ **성공 경로**: 짧은 성공 명령(`true` 등) 실행 → 탭이 스스로 닫히고 칩에 `✓ 이름 시간` 잔류. **마지막 탭이었으면** 빈 상태 뷰 전환이 놀랍지 않은지.
3. ★ **실패 경로**: `exit 2`류 실행 → 탭이 셸로 남아 로그 보임 + 칩 `✗ 이름 exit 2` + 클릭 → 그 탭 포커스.
4. ★ **exit code 보고가 .app 번들에서도** 도는지 — muxa-notify를 번들 옆 절대경로로 부른다(PATH 미의존). bare 빌드·`.app` 둘 다.
5. ★ **dedup**: 도는 중 팝오버에서 같은 스크립트 재클릭 → 새 탭 대신 기존 탭 포커스.
6. ★ **칩 폭**: 짧은 이름(`bd`)에서 칩이 내용만큼만(120pt로 안 부풂 — fixedSize 수정), 긴 이름은 120pt에서 잘림. 1초 tick이 푸터 전체를 리렌더하지 않는지(느낌: 다른 칩 hover 상태 유지).
7. ★ **⌘W 중단**: 실행 중 탭을 ⌘W → 칩이 "결과 미상"(`?` 무채)으로 남고 ✓로 속이지 않는지.
8. ★ 앱 재시작 → 스크립트 탭이 있던 자리가 일반 터미널로 복원(cwd 유지), 칩 잔류는 사라짐(비영속 의도).

**남은 것(범위 밖)**: 스크립트 단축키 바인딩(`named("add_script")`만 예약됨), 여러 실행 동시 표시의 팝오버 상세 UX 다듬기.

## 최근 완료 (2026-07-16) — 사이드바 트리 v2: orca 헤더 × 레인 × 목록형 에이전트 (SIDEBAR-V2)

시안 2라운드(아티팩트)에서 사용자가 확정한 조합을 구현했다: **워크스페이스 = orca식 그룹 헤더 ·
프로젝트 묶음 = 레인(면) · 에이전트 목록 = L1(풀폭 목록 행)**. orca 참조는 실제 소스
(`../orca` `WorktreeList.tsx`·`worktree-card-compact-agent-row.tsx`)로 대조했다. → DESIGN §2·§3·§5 갱신.

- **워크스페이스 헤더(orca식)** — 선행 디스클로저 제거, **행 전체가 접기/펼치기 토글**. 셰브론은
  오른쪽·hover에서만(접히면 −90° 회전). 이름 옆 **프로젝트 개수 배지**(캡슐). 이름은 대문자·자간
  (`muxaLabel`) 폐기 → **일반 케이스 body semibold**(한글엔 대문자가 없어 반쪽이던 규칙 정리).
- **프로젝트 레인(D안)** — 세로 가이드선(`guide` 토큰 삭제)·들여쓰기(`treeIndent` 토큰 삭제)를
  **`lane` 면**(bg 55%+panel 45%, `Radius.lg` 동심원)으로 대체. 긴 워크트리 이름에 가로 공간 확보.
- **프로젝트 롤업 = 점** — 리딩 슬롯이 `StatusMark`(스피너·펄스)에서 **점**(`StatusStyle` 색·크기)으로.
  살아있는 글리프는 펼친 에이전트 행만 — 개요(점)와 실체(글리프)의 위계. 유휴는 빈 슬롯 유지.
- **에이전트 목록 L1** — 행이 프로젝트 행과 같은 문법(풀폭 hover 채움 `ListRowFill`·`RowHeight.tight`).
  **"지금 보고 있는 탭"은 선택 채움**(신규 `TerminalStore.currentTabId`→`AppState.selectedTabId`).
  본문·시간 분리: `AgentRow.bodyLabel`(상태 본문) + `timeLabel`(**대기 경과만** 우측 mono 열 — working/done은
  시각 미저장이라 침묵). 구분자 "·"→"–", 제목/본문 caption(10)→label(11). 셰브론은 hover에서만(▼→▶).
- **완료 글리프 ✓ 맨 체크** — `StatusStyle.success`를 `checkmark.circle.fill`→`checkmark`로(시안 채택).
  `TabStatusMapping`이 글리프를 `StatusStyle`에서 파생하게 고쳐 탭 마크도 자동 동기(드리프트 제거).
- 검증: `make build` green · 테스트 271개 green(`AgentRowTests`에 bodyLabel/timeLabel 3케이스 신규).

### ★ 육안 검증 필요 (SIDEBAR-V2 — `make dev-relaunch`)
- **레인 명도**: `lane`(라이트 F7F5F3·다크 23211E)이 ghostty 실화면에서 **떠 보이지 않는지**(카드처럼 읽히면 실패 — 값 조정).
- 워크스페이스 헤더: 행 아무 데나 클릭=토글 · hover에만 ⌘n·`+`·셰브론 · 배지+롤업 점이 좁은 폭에서 이름을 안 잘라먹는지.
- 에이전트 행: hover 채움·클릭 이동 · **지금 보고 있는 탭에 선택 채움**이 정확히 붙는지(칸 포커스 바꿔가며).
- 대기 행 우측 **시간 열**("19m")이 갱신되는지(수확 시점 계산이라 리렌더 주기 확인).
- 탭 마크 완료가 **맨 ✓**로 바뀌었는지(사이드바·탭 동일). 접힌 icon(52)·slim(14) 모드 회귀 없는지(이번에 안 건드림).
- **후속(같은 날)**: 유휴 = 작은 무채 점(빈 슬롯 폐기) · 25pt 시작선 리듬 · 채움을 이름 줄로 한정(리뷰 C1) ·
  행 채움 안쪽 패딩(leading xs·trailing sm — ✕가 모서리에 붙지 않게) · **✕는 열린 터미널 0일 때만**(hover) ·
  분리 창 스트립도 점 문법(리뷰 R2).
- **팝오버 툴팁(muxaTip)**: 탭바 스플릿 버튼·탭 제목 hover 0.5s 후 칩이 앵커 아래 뜨는지 · 클릭·키 입력에 접히는지 ·
  화면 가장자리에서 클램프되는지 · 전역 즉시 툴팁(NSInitialToolTipDelay 해킹)이 사라져 나머지 툴팁이 시스템 기본 지연인지.
  **bonsplit 포크 `ceee247` push + Package.swift SHA 핀 복원 필요**(지금은 임시 path 의존 — 커밋 금지 상태).

## 최근 완료 (2026-07-16) — 칸 상태 표시 2축 + 어휘 통일 + 유휴 구분 (PANE-STATUS)

STATUS-UNIFY(07-15)가 표시 어휘를 SSOT로 모았다면, 이번엔 그 어휘를 **세 곳(사이드바·탭·칸)에서 같은 모양·색·모션으로**
그리고, 칸 테두리를 **형태×모션 2축**으로 재설계하고, **유휴를 대기와 갈랐다**. → ARCHITECTURE **D32**, DESIGN "칸 상태".

- **칸 상태 표시 2축** — 형태 6종(링·상단/하단 바·좌측 레일·브래킷·코너) × 모션 4종(없음·펄스·흐름·글로우)을
  **상태별(작업중·대기·완료)로 각각** 설정(설정 패널 아코디언, `PaneIndicatorSettings`·순수·테스트). 두께·글로우 번짐·
  브래킷 여백·속도 슬라이더. 모션은 `TimelineView` 시간구동이라 테두리 순간이동 원칙과 안 싸운다. 글로우=이너(분할 안전).
- **어휘 통일(세 곳)** — 작업중 인디고 스피너·대기 로즈 ⏸·완료 세이지 ✓를 **사이드바 점(`StatusMark`)·탭 좌측 마크·
  칸 테두리**가 공유. 탭은 Bonsplit 포크에 **`Tab.status` API** 신설(핀 `3c090c3`, `TabStatusMapping`이 매핑). 옛 Bonsplit
  내장 스피너/더티점 대신 우리 어휘로.
- **상태색 재배정** — 작업중 **틸→인디고**(`3A5FD0`/`7C9BF0`, 완료 세이지와 너무 가까웠다), 대기 글리프 **…→⏸**(`pause.fill`),
  완료 아이콘 **`checkmark.circle`→`.fill`**(대기 ⏸과 같은 솔리드 무게). 세 색은 `Palette.StatusHex` **단일 출처**(드리프트 0).
- **작업중 지속 표시** — 예전엔 "작업 중엔 조용히"라 안 그렸으나, 진행 중이면 칸 테두리가 계속 켜지게(`borderColor` working→인디고).
- **유휴 ≠ 대기** — Claude `idle_prompt`(끝나고 프롬프트에 앉음)를 waiting으로 뭉개던 걸 **`NotifyState.idle` 신설**로 갈랐다.
  유휴는 표시·알림·배지 없이 조용. "입력 대기"(⏸)는 권한·질문 등 **사람이 결정해야 나아가는** 것만.
- **활동 플래시 제거** — 앰버 순간 테두리(`flashPane`)와 `NotificationGate` 플래시 채널을 걷어냈다(상태 테두리와 중복·소음).
- **완료 포커스 해제** — 완료 칸을 보면 항상 해제, 대기는 `clearOnFocus` 조건부(기본 유지). **칸 사이 틈 제거**(divider 0).
  글로우 3겹 강화.
- **리뷰 반영** — 상태색 hex SSOT·`explicit(.idle)` 추정기 테스트·낡은 주석 정정(코드리뷰 5축 후).

### ★ 육안 검증 필요 (PANE-STATUS)
- 사이드바·탭·칸이 **같은 마크**로 뜨는지 — 작업중 인디고 스피너 회전, 대기 ⏸ 펄스, 완료 ✓, 유휴 무표시.
- **작업중** 칸에 인디고 진행바(흐름)가 계속 흐르는지. **완료** 칸 포커스하면 마크가 사라지는지.
- **유휴 구분**: Claude 세션이 끝나고 프롬프트에 앉으면 더는 **대기(⏸)로 안 뜨고 무표시**인지.
- **분할**에서 글로우·흐름이 옆 칸으로 안 새는지(이너 글로우·clipShape). **divider 0**이어도 칸 경계 드래그 리사이즈 되는지.
- 빨간(앰버) 활동 플래시가 더는 안 번쩍이는지.

### 마무리 남음
- **push** — `main`이 `origin/main`보다 앞섬(이번 세션 커밋들). push 승인 필요.
- `status-indigo` 브랜치는 `main`과 동일 — 정리 가능. 포크(`yjun1806/bonsplit muxa`)는 `3c090c3` push 완료.

## 최근 완료 (2026-07-15) — 상태값 통일 (STATUS-UNIFY)

에이전트·서비스 상태가 **5개 어휘·4개 매핑 테이블에 흩어져** 한 사실이 화면마다 다른 색·모양으로 그려지던 걸,
**표시 어휘를 `StatusTone`/`StatusStyle` 한 곳(SSOT)으로** 모았다. 도메인 타입 3층(`AgentActivity`(탭)·
`SidebarTree.ProjectStatus`(롤업)·`ServiceState`(서비스))은 의미가 달라 그대로 두고, "화면에 어떤 톤으로
그릴까"만 통일했다. 감사·계획은 세션 중 Fable 아키텍트가 낸 status-unification-plan(C1~C3·I1~I6).

- **SSOT 신설** — `StatusTone`(quiet·active·attention·success·failure·inert) + `StatusStyle`(톤→색·글리프·
  점크기·라벨 단일 매핑). `ProjectStatusStyle`은 그 위 **얇은 어댑터**로 축소. 회귀 앵커
  `StatusMappingSnapshotTests`가 매핑을 못 박아, 이후 단계의 **의도된 변경만 diff로** 드러난다.
- **완료의 3중 인격 해소** (C2) — 같은 done 탭이 패인 테두리=초록·분포=유휴 링·롤업=호박으로 셋이 달랐다.
  분포에 **완료 = 초록 체크(success)**를 별도 표기 → 패인 테두리 초록과 일치. done 탭은 보면 acknowledge로 사라짐.
- **글리프 충돌 해소** (I1) — 작업중 ●(틸)과 서비스 실행중 ●(초록)이 한 행에 같은 `circle.fill`. 서비스 실행중을
  **▶(`play.circle.fill`)**로 분리(정상종료 `stop.circle`과 play/stop 짝). active 색은 **틸 유지** 결정.
- **두 초록 겹침 해소** — 에이전트 완료 ✓(초록)와 서비스 실행중 ▶이 둘 다 초록 → 서비스 실행중을 **파랑**(`serviceRunning`
  =`gitRenamed`)으로. 완료=초록 유지(`StatusStyle.success`=신설 `pGitAdded`). 서비스 팔레트: 파랑=live·빨강=죽음·무채=정상종료.
- **주의(attention)가 에러처럼 빨갛던 문제** — 글리프 느낌표→**…(`ellipsis.circle.fill`)**, 색 `B45309`(적갈색)→
  **`A16207`(앰버, 4.9:1)**. 느낌표는 이제 **failure(죽은 서비스)에만** — "느낌표=실패, …=대기"로 갈림.
- **추정 waiting 탭 전파** (C1) — 훅 없는 에이전트 대기가 사이드바만 호박이고 탭엔 무표식이던 걸, `reflectTabActivity`가
  **탭 점(isDirty)**도 켜서 어느 탭인지 탭바에 보이게. `markBadge`는 안 부름(추정 오탐은 인박스·알림 없이 탭 점만, 보면 사라짐).
- **⌘K 대기 판정 일원화** (C3) — ⌘K가 배지만 보던 걸 사이드바와 같은 `projectStatus/workspaceStatus == .attention`로.
  죽은 `badgedWorkspaces` 제거.
- **우회 3곳 흡수** — 큐 헤더 생 색, ⌘K **7×7 하드코딩**, 분리창 스트립 점을 전부 `StatusStyle` 글리프로. notify 색 틸→앰버.
- **탭 제목·클릭 점프** (Q1·Q2) — 작업중이면 Bonsplit 스피너(`isLoading`), 분포 아이콘 클릭 = 그 상태 다음 탭으로 순환 점프.
- **tmux 상태 죽던 버그** — notify 소켓이 `muxa-<pid>.sock`(재시작마다 바뀜)이라 재시작을 넘긴 tmux 영속 세션의
  `MUXA_SOCK`이 죽은 소켓을 가리켜 상태·알림이 전멸했다. **`notify.sock` 고정 경로**로(인스턴스 격리는 지원 디렉터리가 함).

**최종 톤→표시:** quiet ○muted · active ●틸 · attention …앰버 · success ✓초록 · failure ⚠▲빨강 · inert ◌muted.
서비스 실행중은 ▶파랑(별도). **색+모양 둘 다**로 갈려 색맹 안전.

### ★ 육안 검증 필요 (상태값 통일)
- 서비스 실행중 **▶파랑** vs 완료 **✓초록** 구분 · 죽은 서비스 **빨간 ⚠▲** 확실
- 주의가 **차분한 앰버 …**(빨강·에러 아님) · 패인 테두리도 앰버
- 훅 없는 명령 조용해지면 **탭 점**, 그 탭 보면 사라짐 · 탭 점이 **너무 자주** 뜨진 않는지(오탐)
- 앞으로 상태 색·글리프는 **`Design/StatusStyle.swift` 한 곳**만 고치면 전 화면 전파

**남은 별건:** I6(안 보이는 탭의 working 미감지 — 렌더 heartbeat가 가시 서피스만; 포그라운드 프로세스 폴링 필요)·
S2(푸터 전역 waiting/working 카운트 칩). ServiceStatusStyle 완전 흡수(어댑터→StatusStyle)는 선택.

## 최근 완료 (2026-07-14) — 서비스 코드 리뷰 마감 (SERVICE-REVIEW)

서비스(장수 프로세스) 기능 전체 리뷰의 **Critical·Required·Nit 전부와 Optional 대부분을 해결**했다.
남은 둘(기동 지연 · state 파일 0600)과 별건(AppState 분해)만 [SERVICE-REVIEW.md](SERVICE-REVIEW.md)에 남겼다.

- **설치했는데 화면이 안 살아났다** (R9) — 뷰 7곳이 `TmuxService.isAvailable`(**static = 비관측**)을 직접 읽어,
  tmux를 깔고 재탐지에 성공해도 SwiftUI가 무효화를 못 봐 칩·도크가 "tmux 없음"으로 굳었다. 관측 가능한
  `AppState.servicesAvailable` + `retryTmuxDetection()` 한 벌로 모으고, 뷰가 직접 하던 셸아웃(`refresh`)·
  전역 동작(`startServices`)을 상태로 걷어올렸다.
- **"web 종료됨"을 누르면 Git 패널이 열렸다** (R7) — 죽음 알림은 `tabId` 자리에 **서비스 id**를 담는데
  서비스는 탭 트리 밖(D19)이라 탭을 못 찾고 프로젝트 이동 + Git 패널로 흘렀다. **죽은 서버의 사인을
  보러 가는 유일한 동선이 엉뚱한 패널을 여는 셈.** `locateService`(순수)로 분기해 도크로 보낸다.
  배지 해제·탭 선택을 창 분기보다 먼저 하는 기존 계약(§5.3)은 그대로.
- **판정·조회 중복 제거** — "비정상 종료란 무엇인가"가 네 곳에 흩어져 있던 걸 `ServiceState.isFailure`로,
  `states[id] ?? .missing`은 `ServiceMonitor.state(of:)`로 모았다(한 곳만 고쳐져 배지는 뜨는데 알림은
  안 오는 갈라짐을 막는다). 트리 순회도 `collectAllServices` 하나로.
- **죽은 코드**(R12) — `ScriptSource.justfile`: 파서도 discover 분기도 없는데 목록에 "just" 라벨만 렌더해
  **"just가 지원되나 보다"라는 거짓 신호**를 줬다. 삭제(되살릴 땐 파서와 함께).
- **Makefile `::=` 오인** — `foo::=bar`(POSIX 즉시 대입)를 타깃으로 읽었다. 이중 콜론 **규칙**(`clean::`)은
  진짜 타깃이라 살려두고 대입만 걸러낸다. 테스트로 못 박음.

### ★ 육안 검증 필요 (이 수정 + 앞선 서비스 수정들)
- tmux 없는 상태에서 도크 → "설치했습니다 — 다시 확인" → **푸터 칩·도크가 즉시 살아나는가**(R9의 핵심).
- 서비스를 죽여(`kill`) 인박스에 "종료됨"이 뜨면 → 클릭 시 **도크(로그)**가 열리는가(Git 패널이 아니라).
- App Nap 폴링 감속(비활성 30초) · pane 0 타겟(attach 후 화면 분할해도 상태·로그가 서비스 pane) ·
  도크 행 글리프(색맹 안전 — 죽으면 모양 자체가 바뀌는가).

## 최근 완료 (2026-07-14) — 상용 감사: 인프라·배포

- **첫 화면이 `/`였다** — `.app`을 Finder/Dock에서 열면 cwd가 `/`라 첫 워크스페이스가 파일시스템 루트로
  생겼다(터미널에서 띄운 개발 빌드에서만 멀쩡했다). 판정을 순수 함수로 뽑았다: `InitialWorkspacePath.resolve`
  (설정값 > **bare 개발 실행일 때만** cwd > 홈). 테스트로 못 박음.
- **메뉴바에 앱 명령이 없었다** → `명령` 메뉴 신설. 목록·단축키는 `QuickCommandCatalog` 단일 출처를 그대로
  구워 쓴다(`MenuShortcut.parse`가 "⌘⇧D" → 키 등가물). 키 등가물은 **우리 창이 키일 때만** 먹는다
  (`validateMenuItem` — 시트가 떠 있을 때 ⌘W가 뒤 화면을 닫지 않게).
- **버전·About·설정 진입점** — 버전은 `scripts/app-identity.sh`가 git 태그·커밋 수에서 파생(APP_VERSION/APP_BUILD,
  더는 `0.1.0 (1)` 고정 아님). 앱 메뉴에 `정보`·`설정 파일 열기…`(⌘,) 추가 — 설정 파일이 없으면 주석 달린
  기본본(`MuxaConfig.template`)을 만들어 연다.
- **서명 파이프라인** — `--deep` 제거(안쪽→바깥쪽 순차 서명), `CODESIGN_ID`로 Developer ID 파라미터화,
  실 식별자면 `--options runtime --timestamp`(공증 필수 조건), **릴리스는 서명 실패 시 hard fail + `--verify --strict` 게이트**.
  `build-dmg.sh`는 `NOTARY_PROFILE`이 있으면 `notarytool submit --wait` + `stapler staple`. README에 설치·Gatekeeper 우회 절차.
- **워크트리 제거가 프로젝트를 고아로 남겼다** — 폴더를 지워도 그 경로를 쓰던 프로젝트·dev 서버가 그대로 살아
  있었다. 당시엔 자동 닫기(`WorktreeOrphans` → `closeProject`)로 풀었으나, **이후 배지 정책으로 대체·삭제됨**
  (살아있는 cc 보호 — 아래 "스텝 3 제거 배지" 참조).

### ★ 육안 검증 필요 (이 수정)
- Finder/Dock에서 새 사용자 상태로 첫 실행 → 워크스페이스가 **홈**에 생기는가(더 이상 `/`가 아닌가).
- 메뉴바 `명령` 메뉴의 항목이 실제로 동작하는가 · 시트가 떠 있을 때 ⌘W가 뒤 탭을 닫지 않는가.
- ~~워크트리 시트에서 휴지통/병합 후 정리 → 그 워크트리를 쓰던 프로젝트 탭이 닫히고 dev 서버가 죽는가.~~
  (폐기 — 이제 닫지 않고 **취소선 배지**만 단다. "스텝 3 제거 배지" 육안 항목으로 대체)
- `Developer ID`로 서명·공증한 DMG의 첫 실행(계정 필요 — 미검증).

## 최근 완료 (2026-07-14) — 창 분리·재합치기 (D28~D30)

프로젝트를 **별도 창으로 분리**하고(우클릭 · ⌘K "새 창으로 분리" · 워크스페이스 단위), 창을 닫으면
**메인으로 무손실 재합치기**된다. 서피스는 아무도 옮기지 않는다 — 소유 창(`WindowID`)을 값으로 스탬프하고
뷰 계층이 스스로 재부모화한다(D28). 배치의 원자는 프로젝트, 메인 창은 **여집합**(D29) — 분리 창 목록만 저장한다.

- 순수 로직: `WindowLayout`(owner/move/normalize/visibleActiveProjects/nextMainProject/nextProject) ·
  `WindowVisibility` · `ProjectCloseDecision` · `TermAttach` · `WindowFrame.restore`. **전부 테스트로 못 박음**.
- 여러 프로젝트를 품은 분리 창은 상단바의 **프로젝트 스트립**(`WindowProjectStrip`)으로 그 안에서 전환한다
  (사이드바는 여전히 메인에만 — 분리 창은 탐색하는 창이 아니다). ⌘⇧[ / ⌘⇧]도 **그 창의 목록 안에서** 돈다.
- 배지 게이트(`visibleActiveProjectIds`)가 알림 게이트와 **같은 판정**을 쓴다 — 최소화·가려짐·앱 비활성인
  창의 활성 프로젝트에도 배지가 붙는다(`WindowHost.visibleWindowIds` → `WindowVisibility.isVisible`).
- 분리 창의 **제목 = 그 창의 프로젝트 이름**(크롬엔 안 보이고 '창' 메뉴에만) — 동명 항목이면 창을 되찾을 수 없다.
- 경계: `WindowHost`(모델⇄NSWindow 단일 reconcile) · `MuxaWindowController`(창별 포커스 계약·프레임 보고).
- 알림 가시성 판정이 `isKeyWindow` → `WindowVisibility.isVisible(appActive:…)`로 바뀌었다.
  **앱이 백그라운드면 언제나 "안 보임"** — 이게 깨지면 에이전트 완료 알림이 전면 억제된다(제품 가치 소멸).
- 분리 창 프레임은 `state.v4.json`에, 메인 창 프레임은 기존 UserDefaults autosave에 — **비대칭은 의도**다.
- **부채(의도적)**: 크롬 토글 상태가 비대칭이다(메인 = `AppState` 필드, 분리 창 = `ProjectWindow` 필드).
  뷰 18개를 `WindowState`로 파라미터화하는 리팩터는 창 분리와 **독립적인 회귀 표면**이라 분리했다.
  서비스 도크·⌘K 오버레이는 **v1에서 메인 전용**(`dockTerms`가 전역 맵이라 두 창이 같은 도크를 열면 TermView 쟁탈).

### ★ 육안 검증 필요 (이 기능 — `make dev-relaunch`)

1. ★ **분리 전후 셸 PID 동일** — 분리할 터미널에 `echo $$`를 남기고 분리 후 재확인(터미널이 죽으면 기능 자체가 무의미).
2. ★ **ghostty Metal 렌더가 창 경계를 넘어 살아남는가** — libghostty가 surface config의 `nsview`에서
   window/CAMetalLayer를 캐시하는지는 **코드로 판정 불가**(prebuilt). **여기서 깨지면 설계가 성립하지 않는다.**
3. ★ 배율이 다른 두 모니터 사이로 분리 창 이동 — 흐려지거나 멈추지 않는가.
4. ★ 분리 창에서 **한글 IME**(조합·후보창 좌표).
5. ★ 분리 창의 ⌘T/⌘D/⌘W/⌘F가 **그 창의** 스토어에만 적용(메인 오라우팅 없음).
6. ★ 분리 창 빨간 버튼 → 종료 시트 없이 메인으로 재합치기, 셸 PID 그대로.
7. ★ 메인 사이드바 ✕로 **분리 창에 있는** 프로젝트를 닫으면 확인 시트 → 취소하면 창·세션 그대로.
8. ★ **알림**: 분리 창에서 **보고 있는** 탭의 완료엔 알림이 안 뜬다. 단 앱을 백그라운드로 보내면 **뜬다**(회귀 방지).
9. ★ 알림 클릭/⌘⇧A/⌘K가 분리 창을 앞으로 올리고 **그 탭이 실제로 선택**된다(배지 해제·탭 선택은 창과 무관하게 항상).
10. ★ 분리 창 2개를 각 모니터에 두고 재시작 → 위치·소속 복원. 외장 모니터를 뽑고 재시작 → 화면 밖 창 없이 cascade.
11. ★ Bonsplit `keepAllAlive`가 창 간 이동에서 호스팅 뷰를 어떻게 다루는지 — **미확인**(소스 미열람).
12. ★ 워크스페이스를 통째로 분리 → 그 창 상단바의 **프로젝트 스트립**으로 두 번째 프로젝트가 실제로 그려지는가.
13. ★ 분리 창을 ⌘M으로 최소화 → 그 창 프로젝트의 대기 신호에 사이드바 ●·Dock 배지가 붙는가.
    알림 클릭·사이드바 클릭이 **최소화된 창을 되살리는가**(deminiaturize).
14. ★ 분리 창 드래그가 끊기지 않는가(프레임은 저장 직전에만 모델에 병합 — 드래그 중 재렌더 없음).

## 최근 완료 (2026-07-14) — 상용 감사: 뷰·접근성

- **TerminalStore ↔ TermView 순환 참조 끊김** — `BonsplitWorkspaceView`의 `onFocus`가 store를 강하게
  되잡아, 프로젝트를 닫아도(`stores[id]=nil`) 스토어·서피스가 해제되지 않았다 → 자식 셸(PTY)·idle
  타이머·Dock 배지가 영원히 살아남았다. `[weak store]`로 끊었다(바로 아래 `onContextMenu`와 같은 패턴).
- **커스텀 메뉴 키보드 네비** — 직접 그린 메뉴(`MuxaMenuView`)에 ↑↓·Return을 붙였다. 이동 판정은
  순수 타입 `MuxaMenuNav`(구분선·비활성 건너뜀 + 순환), 테스트로 못 박음. Esc는 기존대로 패널이 처리.
- **VoiceOver 진입점** — 조작면이 `Button`이 아니라 `onTapGesture`라 접근성 트리에 아예 없었다.
  공용 모디파이어 `accessibilityRow(label:selected:activate:)`(→ `Design/AccessibleRow.swift`)로
  사이드바 4행·주의 큐 헤더·그룹 서브탭·⌘K 팔레트 행에 라벨·버튼 트레이트·기본 액션을 달았다.
- **hover에서만 "존재"하던 컨트롤** — 사이드바 `+`(새 프로젝트)·프로젝트 ✕가 hover 아니면 뷰 트리에서
  사라져 키보드·VO로는 도달 불가였다. 이제 항상 렌더하고 `opacity`로만 감춘다(마우스 히트만 hover로 가름).

### ★ 육안 검증 필요 (이 수정 — 접근성은 VoiceOver ⌘F5로 본다)

1. ★ 프로젝트 닫기 → `ps`로 그 프로젝트 셸(`sleep 9999` 등)이 **실제로 죽는지**(순환 참조 해소의 유일한 증거).
2. ★ 우클릭 메뉴에서 ↑↓·Return·Esc — 구분선/비활성 항목을 건너뛰고, hover와 키보드 강조가 겹치지 않는지.
3. ★ 메뉴가 열릴 때 키 포커스를 받는지(`.focusable()` + nonactivating 패널 조합 — 코드로 판정 불가).
4. ★ 사이드바 행에 안 보이는 `+`·✕가 **마우스로 눌리지 않는지**(hover 밖 클릭 = 행 선택이어야 한다).
5. ★ VO 커서가 사이드바 행에 착지하고 이름·선택 상태를 읽는지, 행의 보조 액션(닫기·추가)이 나오는지.
6. ★ **메뉴를 여는 키보드 경로는 여전히 없다** — 아래 미해결 참조.

### 미해결(이번 범위 밖)

- 터미널 포커스에서 **크롬으로 나가는 키보드 경로**가 없다(`KeymapResolver`에 크롬 포커스 액션 부재).
  착지점(`@FocusState`)·복귀 키를 4개 패널에 설계해야 하는 별건 — 실행 검증 없이 넣으면 터미널 키를 뺏는다.
- `GitPanel`·`FileExplorerPanel`이 같은 폴더에 **FSEventStream을 2개** 건다(프로젝트당 1개로 공유해야).

## 최근 완료 (2026-07-14) — 재개(resume)가 **살아 있는 claude에 명령을 꽂던** 버그

사용자 제보: "claude가 시작되면 거기에 `claude --resume …`를 붙여넣어 버린다."

원인은 두 겹이었다.
1. **배너를 훅 경로가 띄웠다.** `registerResumeBinding`이 저장과 배너 표시를 동시에 했고, 훅(SessionStart)
   경로도 그걸 썼다. 훅 바인딩은 `.hook`이라 `trusted` → `resumeStrategy`가 `.auto` → 배너 `onAppear`가
   800ms 뒤 자동 실행 → **방금 뜬 claude TUI 입력창**에 명령을 타이핑하고 Enter까지 쳤다.
2. **보낼 대상을 아무도 검사하지 않았다.** `executeResume`은 "이 탭은 셸 프롬프트"라고 가정하고 `sendText`했다.
   `ResumeBinding.cwd`는 필드만 있고 **읽는 코드가 없는 죽은 필드**였다(훅 경로는 채우지도 않았다).

고친 것 (결정: [ARCHITECTURE D27](ARCHITECTURE.md)):
- **배너는 복원 경로만** 띄운다(`restoreResumeBinding`). 훅·알림 경로(`setResumeBinding`)는 바인딩만 저장하고
  배너를 **내린다** — 에이전트가 지금 돌고 있으면 "이어서 할" 게 없다.
- **`ResumeGate`(신규·순수)** 가 실행 직전 판정한다: 포그라운드가 **셸일 때만** + 셸의 pwd가 **바인딩 cwd와
  같을 때만** 보낸다. 보류면 바인딩을 소비하지 않고 배너에 사유를 띄운다("폴더가 다릅니다 — …에서만 재개됩니다").
- **모르는 것과 틀린 것을 가른다** — 셸 pid·pwd가 아직 안 잡힌 구간은 `.notReady`고, auto는 이걸 **재시도**한다
  (300ms×16). 종전의 고정 800ms 단발 발사는 늦게 뜬 셸에서 입력이 유실됐다 — 요행 대신 조건을 검사한다.
- **cwd를 실제로 싣는다** — 훅 payload의 `cwd`를 파싱해 바인딩에 묶고, 없으면 등록 시점 탭 pwd로 보강.
  비교 전 심링크 해석(`/tmp`→`/private/tmp`) + 대소문자 무시(APFS 기본 case-insensitive).

리뷰(code-reviewer)가 잡아낸 것 — 전부 반영:
- **tmux(∞) 탭은 배너에서 제외**. 게이트로도 못 막는다(pty 포그라운드는 tmux 클라이언트라 그 안의 claude가
  안 보인다) + attach로 복원되니 claude가 죽지도 않았다. 원래 버그가 그대로 재현되는 경로였다.
- **`pendingCwd` 폴백 제거** — "우리가 셸에게 부탁한 시작 폴더"는 힌트지 사실이 아니다. 그걸 pwd 대신 넣으면
  "모르면 안 보낸다"가 "추측으로 보낸다"가 된다.
- **포그라운드 판정을 3-값(`Bool?`)으로** — 스크롤백 캡처(`isRunningForegroundProgram`)는 "모르면 한다"가
  안전하지만 명령 전송은 정반대다. 같은 함수를 재사용하며 안전 기본값까지 상속했던 걸 끊었다.
- **보안: `isSafeSessionId`를 UUID 화이트리스트로** — 옛 문자 블랙리스트는 `--dangerously-skip-permissions`를
  통과시켰다(금지 문자가 없다). session_id는 소켓 외부 입력이라 플래그 주입이 성립했다.

검증: `swift build` green · **swift-testing 110 + XCTest 242** green(`ResumeGate` 스위트 9개 신규).

### ★ 육안 검증 필요 (이 수정)
1. **claude를 켠 탭에 배너가 안 뜬다** — 터미널에서 `claude` 실행 → SessionStart 훅 발화 → 배너 없음,
   입력창에 아무것도 안 꽂힘. (기존 증상 재현 안 됨)
2. **복원 후 배너는 정상** — claude 돌던 탭을 두고 ⌘Q → 재실행 → 빈 셸 위에 배너 → 누르면 셸에 명령이 쳐진다.
   `agent_resume=auto`면 셸이 준비되는 대로 자동 실행(재시도 루프가 실제로 무는지).
3. **경로 게이트** — 배너가 뜬 상태에서 `cd /tmp` 후 배너 클릭 → 실행 대신 "폴더가 다릅니다 — <원래경로>" 표시.
   다시 원래 폴더로 `cd` → 클릭 → 정상 재개.
4. **TUI 게이트** — 배너가 뜬 탭에서 `vim`(또는 `less`) 실행 후 배너 클릭 → "다른 프로그램 실행 중" 표시, vim에 텍스트 미주입.
5. **tmux(∞) 탭** — claude를 ∞ 탭에서 돌리고 ⌘Q → 재실행 → attach로 claude가 그대로 살아 있고 **배너가 없다**.
6. **경로 표기** — 공백·한글이 든 폴더에서 재개가 정상 동작하는지(OSC 7 pwd가 URL 디코드돼 오는지 실측 필요).

## 최근 완료 (2026-07-14) — main 머지: "층을 무엇이 만드는가" 논쟁 해소

`main`(크롬 층 대비 강화 · Bonsplit fork 탭바 · dev/prod 정체성 · fork upstream 추격)을 이 브랜치에 머지했다.
**핵심 충돌은 `panel`/`border` 다크 값이었다 — 같은 줄, 정반대 방향.**
main은 "크롬↔콘텐츠가 뭉갠다"며 명도차를 벌렸고(ΔL\*≈10), 이 브랜치는 "층은 카드 고도가 만든다"며 좁혔다(≈4).

**판정: 둘 다 부분적으로 옳아서 중간을 택했다(ΔL\*≈7.8).** 근거 —
카드 고도(`Elevation.Card`)가 층의 절반을 지되, **고도가 못 닿는 경계가 실재한다**
(카드 *안*의 도구 패널↔터미널: `panel`/`bg`가 `border` 선 하나를 두고 직접 맞닿는다). 그래서
명도차를 0으로 되돌릴 수 없고, 고도가 절반을 지므로 10까지 벌릴 필요도 없다. 값·수치는 [DESIGN 2절](DESIGN.md).

**머지 후 검증에서 그 전제가 절반 거짓이었음이 드러나 고쳤다(D25·D26)** — 크롬 값은 그대로 두고 고도·베일을 고쳤다:

- **사이드바↔터미널 경계에선 고도가 0이었다.** 사이드바는 카드 위에 뜨는 **불투명 오버레이**라
  카드 그림자(왼쪽 ~3pt 번짐)를 통째로 가린다 — 하필 ccb8d68이 지목한 그 경계다.
  카드 왼쪽에 크롬 4pt(`Space.xs`)를 비워 그림자가 설 자리를 줬다(`ContentView.contentCard`).
- **peek 사이드바도 사각지대다**(카드보다 위 레이어) → peek 중에만 오른쪽 그림자(`Elevation.Peek`).
  도킹 상태엔 0이라 크롬끼리 이어지는 자리엔 그늘이 안 진다.
- **`paneVeil` 다크 12% → 22%.** 12%는 `1B1B1D`→`18181A`, **ΔL\* 1.52 · 1.03:1**로 사실상 아무 말도 안 했다
  (검정 곱연산은 어두운 바탕에서 사라진다). 게다가 지시선 teal이 `2DD4BF`→`5FB8AB`로 내려가(탭바 위 4.96→3.93)
  포커스 단서가 이중으로 얇아진 상태였다. 22% = `151517`, **ΔL\* 3.00**(라이트 3%의 2.77과 같은 무게),
  비포커스 칸 글자는 8.6:1로 AAA 유지.

- **`btnActive` 다크는 `47474C`로 되돌렸다** — c713cd5가 이 토큰에 **칸 탭바의 면**이라는 새 역할을 줬다.
  이 브랜치의 `3C3C41`은 `bg` 대비 1.57:1로 그 측정 지표(1.9:1)를 절반쯤 무효화한다. `47474C`는 1.86:1이고
  r≈g의 무채라 zinc 원칙과 충돌하지 않는다. `panel`을 올린 만큼 `btnHover`도 한 칸 올려 사다리를 유지.
- **`borderFocus` 토큰은 삭제했다** — 유일한 소비자였던 칸 포커스 링이 `paneVeil`로 대체됐고(D20),
  남은 포커스 강조인 선택 탭 지시선은 탭바(`btnActive`) 위라 `3B8A7F`가 **2.26:1**로 3:1에 미달한다
  (`brand`는 3.93:1). 맡을 자리가 없어졌다. main의 `activeIndicator = brand`가 옳다 — 그대로 뒀다.
- **main의 기능은 전부 살렸다** — `paneVeil`·`BonsplitChrome`·dev/prod 정체성·`TerminalStore` 주입 무손실.
- 검증: `swift build` green · **99 tests / 12 suites** green. **화면은 육안 미검증(★ 아래).**

### ★ 이 머지가 만든 육안 검증 항목 (다크 모드부터 본다)
1. **사이드바↔터미널 경계** — 4pt 홈 + 카드 그림자로 카드가 "떠 있게" 보이는가.
   여기가 이번 판정의 급소다. 안 갈리면 `panel` 다크를 `303035`로 올린다(`Palette.swift` 한 줄).
   반대로 홈이 **틈처럼** 보이거나 크롬이 도형으로 튀면 `Space.xs` 패딩을 빼고 `panel`을 올리는 쪽으로 간다.
2. **칸 포커스** — 분할해서 **빈 셸 두 칸**을 나란히 두고, 포커스를 옮겨 어느 칸이 밝은지 즉시 읽히는가
   (베일 22%, ΔL\* 3.0). 글자가 있는 칸 말고 **빈 칸**으로 봐야 한다 — 12%가 실패한 지점이 정확히 거기다.
   너무 어두워 대조가 힘들면 18%로 내린다.
3. **카드 *안*: 익스플로러/git 패널 ↔ 터미널** — 고도가 못 닿는 유일한 경계. `border`(`3E3E44`)만으로 갈리는가.
4. **hover 모드에서 사이드바 peek** — 트리가 터미널 **위에 뜬 판**으로 보이는가(오른쪽 그림자).
   접힌 상태(도킹)에서 크롬 위아래에 그늘 얼룩이 지지 않는지도 함께 본다.
5. **탭바(`47474C`) 위 활성 탭(`bg`)이 면으로 보이는가** — 1.86:1.
6. **라이트 모드** — 카드 그림자가 0.06이라 거의 없다. 사이드바↔터미널이 `panel`(ΔL\* 5.5)+`border`만으로 갈리는가.

## 최근 완료 (2026-07-14) — 사이드바 "런 큐" 2단 트리 + 팔레트 수술

프로젝트 전환을 **헤더 탭 → 사이드바 트리**로 옮기고(D23), 브랜드 teal을 **아이콘 전용으로 격리**했다(D24).
근거·수치는 [ARCHITECTURE 2절 D23·D24](ARCHITECTURE.md), 값·규칙은 [DESIGN.md](DESIGN.md).
순수 로직 테스트 16개 추가. **화면은 육안 미검증(★).**

- **사이드바 = 워크스페이스 › 프로젝트 2단 트리** — `SidebarTree`(순수: status/rollup/펼침/firstWaiting) +
  `SidebarWorkspaceRow`(소섹션 머리글) · `SidebarProjectRow`(주인공) · `SidebarQueueHeader`(주의 큐 한 줄) ·
  `SidebarIconItem`/`SidebarProjectIcon`(접힌 모드도 2단) · `SidebarRow`(공통 hover·우클릭·이름 칩).
  **`ProjectTabBar` 삭제**, 상단바엔 표시 전용 `Breadcrumb`만.
- **펼침 상태 영속** — `AppState.expandedWorkspaces`(+`state.v4.json`, 옵셔널 필드라 구 저장분 무손실).
  활성 워크스페이스는 **접히지 않는다**(규칙은 `SidebarTree` 한 곳).
- **에이전트 상태를 색이 아니라 모양으로** — 유휴 5pt 무채 / 작업중 6pt 딥틸 / 주의 6pt 호박(`ProjectStatusStyle`).
- **팔레트** — 중립 zinc 통일, **목록 선택은 중립 채움**(탐색기 행·서비스 목록의 브랜드 wash 제거),
  AA 미달값 수리(borderActivity 라이트 2.15:1 → 5.05:1 등), 카드 고도(`Elevation.Card`)로 층을 만든다.
  (당시 도입한 `borderFocus` 토큰은 위 머지에서 삭제됐다 — 포커스는 `paneVeil`이 말한다.)
- **접힌 모드 회귀 방지** — icon/slim에서도 프로젝트 항목을 그리고, 워크트리 생성을 워크스페이스
  우클릭 메뉴(`ProjectAddMenu`)에도 실었다. 안 그러면 그 모드에서 프로젝트 관리가 통째로 사라진다.

### 실기기 검증 필요 (★ 이 기능)
1. **비활성 워크스페이스의 프로젝트** 클릭·✕·우클릭 닫기·`+`가 실제로 동작하는가(새로 생긴 경로).
2. **접힌 모드(아이콘 52 / 슬림 14)** — 프로젝트 점이 보이고 hover 시 이름 칩이 뜨는가, 우클릭 메뉴로
   워크트리를 만들 수 있는가, 슬림 막대의 3색(주의 호박 > 작업중 딥틸 > 유휴 무채)이 14pt에서 읽히는가.
3. **워크트리 시트** — hover 사이드바에서 `+` → "워크트리…" → 사이드바가 접혀도 시트가 살아 있는가.
4. **상태 점 갱신 전파** — 백그라운드 프로젝트가 working → attention으로 바뀔 때 행이 다시 그려지는가.
5. **카드 그림자·인셋 하이라이트**가 라이트/다크에서 보이는가(ghostty 서피스 리렌더 이상 없이).
   함께: **카드 *안쪽* 헤어라인**(인덴트 가이드·패널 헤더 구분선)은 고도 보상이 닿지 않는 영역이다 —
   위 머지에서 `border`를 한 단계 올렸으니(`34343A`→`3E3E44`) 이제 충분한지 본다.
6. 세션 복원 직후엔 스토어가 없어 **모든 프로젝트가 유휴 점**이다("안 연 프로젝트"와 구분되지 않음 — 의도된 절제).

## 최근 완료 (2026-07-14) — Bonsplit fork를 upstream main(#180)에 따라잡히기

fork(`yjun1806/bonsplit`) `muxa` 브랜치에 upstream `main`(46def98)을 머지·push했고,
`macos/Package.swift`의 revision을 새 SHA(`7754f46`)로 고정했다. → [D22](ARCHITECTURE.md)

- upstream이 탭 지시자·구분선을 SwiftUI → AppKit(`TabBarSelectionChromeView`)으로 옮겼다. 우리 SwiftUI 구현은 버리고
  포커스별 색·두께·하단 배치만 그 경로에 재구현했다.
- fork가 진짜 **가산적**이 됐다 — 선택 탭 제목 굵기가 `selectedTabTitleWeight`(기본 `.regular`)로 게이팅됐다.
  muxa 쪽 변경은 `BonsplitChrome.selectedTabTitleWeight`(+`TerminalStore` 1줄)뿐.
- 검증: bonsplit `swift test` 194개 green · muxa `swift build` + `swift test` green.

### ★ 실기기 육안 검증 필요 (이 머지)
- 포커스된 칸의 선택 탭 = 하단 teal 2pt / 포커스 잃으면 회색 1pt (색·두께 **둘 다** 바뀌는지).
- 라이트↔다크 토글 시 탭바 면·활성 탭 면·지시자 색이 즉시 따라오는지.
- 탭을 많이 열어 스크롤 — 탭이 분할 버튼 레인 아래로 페이드되고, 지시자는 레인 아래로 새어들지 않는지.
- 다른 칸 보고 돌아왔을 때 선택 탭이 뷰포트로 스크롤되는지(`keepsSelectedTabVisible`).
- 선택 탭 제목이 포커스 시 semibold인지.
- 기본 `BonsplitConfiguration()`(다른 host) 렌더가 upstream과 동일한지 — 가산성 회귀.

## 최근 완료 (2026-07-14) — 탭바 테마링 + 칸 포커스 반전 (Bonsplit fork)

Bonsplit을 **우리 fork로 갈아타고**(`yjun1806/bonsplit`, → [ARCHITECTURE D21](ARCHITECTURE.md)) 탭바를 muxa 팔레트로 테마링했다.
그 과정에서 **칸 포커스 표현을 뒤집었다** — 테두리 → 밝기(→ [D20](ARCHITECTURE.md), [DESIGN "칸 상태"](DESIGN.md)).

**고친 것 (전부 실측으로 드러난 문제):**
- **활성 탭 대비가 1.00:1이었다** — Bonsplit이 시스템 색을 쓰는데 `windowBackground == controlBackground`라 **선택 탭 배경과 탭바 배경의 픽셀이 동일**했다. 활성 탭의 면이 시각적으로 존재하지 않았다. hover도 같은 이유로 변화량 0.
- **`chromeColors`가 다크에서 안 먹었다** — `layer.backgroundColor = color.cgColor`가 drawing scope 밖에서 **조용히 라이트 값으로 폴백**한다. fork의 존재 이유가 무력화돼 있었다. scope 안에서 resolve + `viewDidChangeEffectiveAppearance` 재적용으로 수정.
- **활성 지시자가 시스템 강조색**이었다(사용자가 accent를 바꾸면 muxa 크롬만 색이 변함) → `brand`.
- 분할 시 **비포커스 칸의 선택 탭을 읽을 수 없었다**(지시선 대비 1.46:1) → 색 + 굵기 2중 인코딩.

**지금 활성 탭이 말하는 방식:** 면(`bg`, 아래 터미널과 같은 hex) + 위 2면 라운드 + 하단 선(포커스 teal 2pt / 비포커스 회색 1pt) + 아이콘 teal + 굵은 제목. 탭바는 `btnActive`(면을 띄우려면 아래가 눌려야 한다).

**검증:** `swift build` green · **83 tests / 10 suites** (신규 `BonsplitChromeTests` 5개 — 팔레트→hex 변환은 틀려도 조용해서 못 박음).

### ★ 실기기 육안 검증 필요 (이 기능)
- **다크 모드 탭바 색** — 위 `cgColor` 버그를 고쳤으나 눈으로 확인 안 됨. 라이트↔다크 전환 시 탭바가 따라오는지.
- **분할 버튼 레인** — `splitButtonBackdrop: "#00000000"`이 레인 면만 끄고 **탭 페이드는 살리는지**. 뚝 잘려 보이면 실패.
- **베일 강도** — 라이트 3% / 다크 **22%**(12%는 ΔL\* 1.52로 사실상 안 보여 상향, D26)가 적정한지
  (두 칸을 나란히 대조하는 데 지장 없는지). → 위 "★ 이 머지가 만든 육안 검증 항목" 2번.
- **하단 지시선 vs 탭바 바텀 구분선** — 같은 픽셀을 다툰다. z-order로 한쪽이 가려질 수 있음.
- **탭 상단 3pt** — 클릭·hover는 되는데 배경이 안 칠해진다(`tabTopInset`이 배경에만 적용). hover 시 눈에 띄면 조정.

## 최근 완료 (2026-07-13) — 알림 파이프라인 개편: 훅이 1차 소스

orca(stablyai)·cmux 구현을 대조해 **추정 1차 → 훅 1차**로 뒤집었다. 설계 근거는 [ARCHITECTURE 4.5](ARCHITECTURE.md) 참조.
신규 순수 로직 + 테스트 76개(전체 168개 green). **GUI 동작은 실기기 육안 검증 미수행(★).**

- **훅 원본 payload 경로** — `muxa-notify hook --event <E>`가 stdin JSON을 **해석 없이** 소켓에 전달
  (`hook\t<tabId>\t<event>\n<원본 JSON>`). 파싱·분류는 앱이 한다(훅에 로직을 넣으면 앱 업데이트로 못 고침).
  신규: `ClaudeHookPayload`·`ClaudeHookInterpreter`(순수)·`HookSessionState`.
- **가짜 완료 차단** — `background_tasks`/`session_crons`(cmux `pending`) + 서브에이전트 로스터가 남으면 Stop이어도 done이 아니다.
  `idle_prompt` payload엔 `background_tasks`가 없어 **Stop 시점 캐시**가 유일한 근거.
- **알림 본문 = Claude가 마지막으로 한 말** — `last_assistant_message`, 없으면 `transcript_path` 꼬리 역방향 파싱(`TranscriptTail`, 재시도 5×50ms).
- **진행 표시** — `PostToolUse` → "편집 중: TermView.swift"(`ToolActivity`, LLM 없음). 푸터에 표시(`focusedAgentDetail`).
- **인앱 훅 설치** — 알림 벨 → "설치" 버튼. 백업 + 원자적 교체, 사용자 훅 보존, 멱등(`ClaudeHookSettings`/`ClaudeHookInstaller`).
  **레거시 `muxa-notify --state` 훅도 흡수**해 교체한다(안 그러면 Stop에서 이중 발화). `scripts/integrate.sh`도 새 형식으로 갱신(jq 의존 제거).
- **정직한 상태 표시** — 설치됨 ≠ 동작 중. 첫 훅 신호가 와야 "동작 중"으로 승격(`HookInstallState`).
- **이중 발화 억제** — 훅이 붙은 탭의 raw OSC 9/777은 폐기.

### 실기기 검증 필요 (★ 이 기능)
1. 벨 → "설치" 누르고 `~/.claude/settings.json` 확인(기존 훅 보존·백업 생성).
2. 앱 안에서 claude 실행 → 푸터에 "편집 중: …" 뜨는지, 벨 상태가 "훅 동작 중"으로 바뀌는지.
3. 턴 완료 시 알림 본문에 **Claude의 마지막 말**이 뜨는지(다른 앱에 포커스 둔 채로).
4. 백그라운드 작업(`&`)이 도는 채로 턴이 끝나면 완료 알림이 **안 뜨는지**.

## 최근 완료 (ultracode 워크플로 + 적대적 리뷰 수정)

- **서브탭·활성 칸 완전 복원** ✅ — `PaneSnapshot.leaf.focused`(커스텀 Codable 하위호환), 복원 후 활성 칸+선택탭 복구
- **익스플로러 reveal + 인라인 이름변경** ✅ — 파일 열면 트리 펼침+선택+스크롤; 셀 인라인 편집(편집 중 리로드 보류로 데이터손실 방지)
- **git 브랜치 전환 + pull/push** ✅ — `GitService+Branch`; Git 헤더 브랜치 메뉴 + pull/push 버튼
- **diff 인라인 스테이지** ✅ — hunk 단위(WKWebView→Swift 메시지 + `git apply --cached`) + 파일 전체 스테이지/언스테이지 도구줄; 스테이지 후 최신 status 재조회
- **gh 배지** ✅ — `GitService+GH`; Git 헤더에 PR#·상태색·CI 롤업(gh 미설치/미인증 전경로 가드)
- **diff 리뷰 코멘트 + 제출 풀** ✅ (cmux 대조 ③) — diff 줄 hover '＋'로 코멘트, `lineText` 재앵커링(anchored/moved/outdated)으로 라이브 리로드 드리프트 방지, Git 패널 "N개 보내기"로 포커스 터미널에 붙여 다음 턴 지시로 되먹임. 순수 로직 분리(`ReviewComment`·`ReviewCommentAnchor`·`ReviewCommentFormat`) + 영속 경계(`ReviewCommentStore`, 리포키=canonical root SHA256) + WKWebView 코멘트 브리지 채널(`muxaComment`). 붙여넣기는 Enter 미커밋(사용자 확인 후 제출).
- **에이전트 상태 추정** ✅ (Tier3, ARCHITECTURE 4.5) — 순수 값 `AgentActivityEstimator`(idle/working/waiting/done) + 신호 배선. RENDER 액션을 `TermView`가 초당 1회로 다운샘플→`.outputHeartbeat`, OSC 133 완료→done, muxa notify 명시신호(waiting/done/working)를 ground truth로 고정(pin). 출력이 `idleThreshold`(4s) 넘게 멎으면 working→waiting 추정(working 탭 있을 때만 1s idle 타이머). 표시=패인 상시 테두리(waiting 주황·done 초록, working/idle 없음), 그 칸을 보면 해제. **튜닝 미검증**(아래 주의).

## Tier 0~3 백로그 20개 — 구현 완료 (2026-07-10 · ultracode 순차 워크플로)

fable 3렌즈 검토로 도출한 백로그를 순차 파이프라인(각 단계 구현→`swift build`→커밋)으로 20개 전부 구현. 최종 빌드 green + 실행 init 크래시 없음(3초 스모크) 확인. 커밋 `a85fcaf`(B1) ~ `5da0433`(상태머신), +2654줄. **전부 GUI 동작이라 실기기 육안 검증은 미수행(★).**

- **Tier 0** — B1 셸 종료 시 해당 탭만 닫기(앱 종료 결함 제거, `close_surface_cb`) · B2 도구 패널 표시를 `AppState`로 승격 + ⌘⇧E/⌘⇧G 토글.
- **Tier 1** — 배지 오탐 억제(보이는 칸/짧은 명령[8s]/벨 디바운스 필터, 명명 상수 `shortCommandThresholdNs`·`bellDebounce`) · 워크스페이스 ● + Dock 배지 카운트 · 패인 활동 테두리(`flashingTabs`, 1.2s 페이드) · muxa notify CLI + env 주입(별 바이너리 `muxa-notify` + `NotifyServer` Unix 소켓) · 알림/배지 클릭→프로젝트 활성+Git 패널(`revealActivity`) · 세션 기준선 diff(`Project.sessionBaseHead`, 영속) · 변경 버리기(discard, 파일 단위·untracked는 휴지통).
- **Tier 2** — 설정 파일 `~/.config/muxa/config`(`MuxaConfig` 순수 파서, 시작 시 1회 로드) · 키바인딩 테이블화(`KeymapResolver` + 칸 포커스 이동 ⌘⌥방향·탭 순환 ⌃Tab) · 탭별 cwd 추적(OSC 7, `TermView.pwd` 진실원천) · 탭 자동 명명(SET_TITLE) + 수동 rename · ⌘⇧A 다음 대기 세션 전역 점프.
- **Tier 3** — diff 탭 라이브 리로드(FileWatcher + 스크롤 보존) · 전체 변경 통합 diff 서브탭(`.all`) · 알림 인박스(`AttentionLog` + 팝오버) · ⌘K 빠른 전환기(`FuzzyMatch` 퍼지·대기 우선 정렬) · 워크트리 merge 후 정리 원액션 · 에이전트 상태 추정(`AgentActivityEstimator` idle/working/waiting/done, RENDER 초당 1회 다운샘플, muxa notify 명시신호 pin, 패인 테두리 waiting=주황·done=초록).

신규 파일: `NotifyServer` · `MuxaConfig` · `KeymapResolver` · `QuickSwitcher`/`QuickSwitchItem` · `FuzzyMatch` · `TerminalSignal` · `DiscardConfirm` · `WorktreeMergeConfirm`.

## 서비스(장수 프로세스) — 기능 완성, **코드 리뷰 미반영** (2026-07-13)

dev 서버를 **탭 트리 밖 "서비스"**로 두고 실행을 muxa 전용 tmux 서버에 위임. 설계 근거는
[ARCHITECTURE D19 · 4.7](ARCHITECTURE.md). **238개 통과** + 실기기 육안 확인 완료.

> ⚠️ **리뷰에서 Critical 3 + Required 12 발견 — 미수정.** 목록·수정안·진행 체크는
> **[SERVICE-REVIEW.md](SERVICE-REVIEW.md)**. 특히 C1(`remain-on-exit`를 new-session *뒤에* 걸어
> 첫 서비스가 즉사하면 exit code·로그·알림이 통째로 소실 — 아래 "생존/감지" 주장이 이 경우엔 거짓)과
> C3(중복 serviceId → 부팅 크래시)은 데이터 소실·크래시라 다음 세션 최우선. 육안 검증은 서버가
> 살아있는 동안만 이뤄져 이들을 놓쳤다.

- **생존** — tmux 서버는 ppid=1(launchd). muxa를 꺼도 dev 서버가 산다(실측). 재실행 시 세션 생성
  시각 불변 = 중복 기동 없음(`start` 멱등).
- **접힌 상태 감지** — 서피스 렌더 없이 `list-panes`/`capture-pane`으로 상태·로그를 읽는다.
  `remain-on-exit on` **필수**(없으면 죽는 순간 pane이 증발해 exit code·로그를 잃는다).
- **UI** — 푸터 칩(사용량 오른쪽)이 **두 세그먼트**: [지금 이 프로젝트] | [창 전체]. 앞은 클릭 시
  도크(도크가 보여주는 것과 같은 집합), 뒤는 전역 목록. 전역과 현재가 같으면 뒤는 숨긴다.
  hover → 팝오버(프로젝트별 그룹, 다른 프로젝트 것을 클릭하면 **거기로 데려간다**).
  클릭/⌘J → 하단 **오버레이** 도크(여닫아도 ghostty 리플로우 0). 살아있으면 attach(진짜 터미널),
  죽었으면 읽기 전용 로그(`ServiceLogView` — 죽은 pane에 attach하면 리사이즈로 사인이 날아간다).
- **스크립트 선택** — `package.json`(패키지 매니저는 **lock 파일로 판별**, 없으면 사용자가 고른다)·
  `Makefile`(`## 주석`)·`scripts/*.sh`(상단 주석)에서 실행 명령을 골라 넣는다. 직접 입력도 가능.
- **정리** — 프로젝트·워크스페이스를 닫으면 그 서비스 프로세스도 함께 죽인다(등록만 지우면 포트를 문다).
- **tmux 미설치** — 숨기지 않고 안내한다. `brew install tmux`를 터미널에 **주입만** 하고 Enter는
  사용자가 누른다(앱이 직접 설치하지 않는다).

**개발빌드 격리 (CRITICAL — `AppInfo.devKey`)**: 워크트리마다 muxa를 띄우면 예전엔 같은
`state.v4.json`과 같은 tmux 소켓을 공유해 **서로의 세션을 덮어쓰고 서로의 tmux 세션을 죽였다**
(세션 복원의 `term__…` 세션까지 서비스 청소가 죽이는 경로가 열려 있었다 — 실측 확인). 지금은
저장소(`muxa-dev-<워크트리>-<해시>`)와 소켓(`muxa-services-<key>`)이 **물리적으로 분리**된다.
워크트리를 지우면 저장소도 GC로 사라진다(`.origin`에 워크트리 루트 기록 + 7일 유예).

실측으로 잡은 함정: `.app`은 PATH를 상속 안 해 `pnpm`·`tmux`를 못 찾는다(로그인 셸 래핑 + 절대경로
해석) · zsh의 `=word` 확장이 `attach -t =세션`을 삼킨다(인용 필수) · `capture-pane` 타겟은 `=<세션>:` ·
`IconButton`(14×14 고정)을 안 쓰면 HStack이 버튼을 0폭으로 압축해 **닫기 버튼이 사라진다**.

> **개발 시 주의**: muxa 프로세스는 전부 이름이 `muxa`라 `pkill -f 'debug/muxa'`가 **다른 워크트리의
> 앱까지 죽인다**. AppleScript `System Events`도 둘을 구분 못 한다. 개발빌드를 여러 개 띄웠다면
> **pid로 관리**할 것.

## 다음 할 일 (백로그) — 잔여·후속

### 실기기 검증 (최우선 ★)

20개 전부 GUI 동작이라 육안 미확인: 패인 테두리 플래시·상태 테두리색(주황/초록)·Dock 배지·사이드바 ●·알림 클릭 라우팅·⌘K 오버레이·rename 시트·칸 포커스 이동/탭 순환 키·discard·워크트리 merge. **`.app` 번들 실행이어야 시스템 알림 동작**(bare `.build/debug/muxa`는 Dock 바운스 폴백).

### 마무리 완료 (2026-07-10 rev11 · "알아서 완벽하게")

실사용 관문·완성도·위생을 마무리. 빌드 green + `swift test` **92/92** + 실행 스모크 통과.
- **에이전트 통합 설치 스크립트** `scripts/integrate.sh`(dry-run 기본, `--apply`로만 실수정·백업·멱등) — muxa-notify PATH 심링크 + Claude Code 훅(`~/.claude/settings.json`, jq 병합) + 스크롤백 rc 스니펫. **훅 스키마 검증**: `session_id`는 env 아닌 stdin JSON이라 재개 프리셋을 `jq -r .session_id`로. docs/SETUP.md에 안내.
- **진단·크래시 UI 표면화**: 키 재정의 진단(`KeymapDiagnostic`)·직전 비정상 종료를 알림 인박스(`AttentionKind.system`, 제목 dedup)에 노출. 크래시 마커→`ResumeStrategy`(none/manual/manualDirty/auto) 배선 — 더티 종료면 재개 배너 강조.
- **discard 보강**: hunk 단위 버리기(`DiffPatch`+`git apply --reverse`) + 스테이지된 리네임(R) 안전 3단계(`DiscardPlan` 순수 로직, 실제 git 검증).
- **위생·UX**: 스크롤백 파일 GC(`ScrollbackStore.orphans` 순수 판정 + 1h 유예로 활성 파일 절대 보존) + 마지막 탭 닫힘 시 빈 상태 뷰(`EmptyProjectView`, ⌘T).

### 미완·후속 (남은 것)

- **상태머신 튜닝 — 훅 없는 세션 한정 미검증**: 훅 있는 Claude 세션의 "입력 대기" 오탐(조용한 도구 실행/생각 중)은 working 훅 pin으로 **해소·dev 빌드 육안 검증됨**(2026-07-16, `f8bc261`·`cd074ca` — 아래 "정체성 심화 ①"). 남은 건 **훅 없는(추정 전용)** 세션뿐: RENDER가 포커스 칸 커서 깜빡임에도 오는지(오면 포커스 칸 idle 추정 불가·비포커스는 정상)·`idleThreshold`(4s)·throttle(1s) 실사용 조정.
- **세션 미영속**: 수동 탭 이름(`manualTitles`)·알림 인박스 이력은 재시작 시 비워짐 — 영속하려면 `TabSnapshot` 스키마 확장.
- **저심각 잔여**: dedup cooldown·`MUXA_SURFACE_ID` 실 라우팅은 설정/구조 확장 시 · discard `--cached` hunk unstage · 전체 diff 파일 헤더 클릭 점프 · 탭 순환 ⌃Tab 이론적 충돌 · rename NSAlert 모달(인라인 아님) · 탭 점 색 상태화(Bonsplit `isDirty`가 bool뿐) · 종료 감지 foreground_pid 휘발성(셸 종료 위주).
- **워크트리 세션 귀속 (M4 후속 · 계획·근거 = [ARCHITECTURE D31](ARCHITECTURE.md) · orca 대조 반영)**: 에이전트에게 "워크트리 만들어 작업해"를 시키면 cc가 옛 탭 안에서 `git worktree add` 후 그 안으로 cd한다 → **워크트리가 사이드바에 안 뜨고 살아있는 cc가 옛 탭에 갇힌다**. orca(`../orca`)는 이걸 **외부 워크트리 인박스 + 영속 baseline**으로 풀며 자동 승격하지 않는다 — muxa는 그 원리만 경량으로. 진행:
  - ✅ **순수 코어**(`WorktreeMembership.swift` + 14 테스트): `pending`/`offers`(pending − baseline) · `WorktreeMove.target`. `GitWorktree.isMain`(파서 첫 레코드) · `Workspace.acknowledgedWorktreePaths`(영속 baseline) · `normalizePath` 공통화.
  - ✅ **스텝 1 감지** — `WorktreeMonitor`(@MainActor @Observable): 워크스페이스별 공통 `.git`을 FSEvents(`FileWatcher.onFlush`) 감시 → `worktreeList` → `detected` 갱신. transient 빈 목록 방어. `GitService.gitCommonDir`. AppState가 `syncWorktreeMonitor()`로 소유(add/remove/ensureInitial/`ContentView.onAppear`). **★ 육안 미검증**(실제 워크트리 add 시 감지되는가).
  - ✅ **스텝 2 제안 UI** — `AttentionInbox` 상단 "새 워크트리 감지" 섹션 + `offerRow`(추가=`importWorktree` 승격 / 무시=`dismissWorktree` baseline). 벨 배지에 offer 수. **★ 육안 미검증**.
  - ✅ **스텝 2.5 자동 승격 (D31 보완)** — **muxa 세션이 안에 있는 워크트리는 인박스 없이 자동으로 프로젝트가 된다**: 신규 워크트리(offer 후보) 안에 라이브 세션 cwd(OSC 7)가 있으면(에이전트가 만들고 들어간 것 = 의도된 행동) `autoImportWorktrees`가 조용히 `importWorktree`. 신호 없으면(외부 생성) 기존 offer 유지 — D31의 놀람·노이즈 반론은 외부 생성에만 해당. baseline 적재로 부활 방지. **신호 = 실효 cwd(`effectiveCwds` = 훅 cwd 우선 ?? 셸 OSC 7 pwd)** — 셸 pwd만으론 안 된다(실측): cc의 EnterWorktree는 셸을 cd하지 않고, ∞(tmux) 탭은 안쪽 OSC 7이 바깥 pty로 통과 안 됨. 훅 페이로드의 cwd(`deliverHook` → `agentCwds` 미러)가 ground truth. 트리거 = `worktreeMonitor.onChange` + `onPwdChange`(셸 cd·훅 cwd 변화 겸용). 판정 순수 헬퍼 `pathIsInside`(중복 3회 → 추출). 링크 카드(`externalLiveSession`)도 같은 실효 cwd를 본다. **★ 육안 미검증**. 한계: 훅은 cc **활동 시**에만 오므로, 이미 들어가 앉아 있는 idle cc는 다음 턴에야 잡힌다.
  - ✅ **적대 리뷰(ultracode Workflow, 5차원×발견별 검증)** — critical 0. important 3 고침: `duplicateWorkspace`/`setWorkspacePath`에 `syncWorktreeMonitor()` 추가 + `WorktreeMonitor.sync`가 **경로 변경 시 재attach**(id만 보던 것 → sourceDir 비교). 저심각 fold: offer 복합키(공유 repo 충돌) · offer 스크롤 · orphan watcher 방어(`wanted`) · branch 변경 반영 · baseline 정규화.
  - **리뷰 후속(보류·저심각)**: (a) 심링크 — folder picker로 미resolve 경로(`/tmp/…`) 프로젝트를 추가하면 git의 real path와 안 맞아 offer 오탐 가능(경계 resolve 필요, I2와 동일). (b) `FileWatcher` FSEvents 콜백 use-after-free 창(동적 생성/파괴로 노출↑, 기존 문제). (c) `rescan`이 `worktreeList` 내부 repoRoot rev-parse 중복(미세 성능).
  - ✅ **스텝 3 제거 배지 (닫지 않고 표시)** — 정책 전환: 워크트리 폴더가 사라져도 **자동으로 안 닫는다**(안에 살아있는 cc·미저장 작업 보호). `DeadWorktree.projectIds`(순수, 존재확인 주입) + `AppState.deadWorktreeProjectIds`(런타임 Set) + `reconcileDeadWorktrees`(FileManager 경계). 트리거 = `WorktreeMonitor.onChange`(FSEvents)·startup·피커 제거. 사이드바 프로젝트 행에 **이름 취소선 + `questionmark.folder` 글리프(참조 유실 관례 — badge.minus는 '제거 동작'으로 오독)**(서비스-빨강·에이전트-앰버와 무충돌). `closeProjects(underPath:)`·`WorktreeOrphans`(+테스트)는 정책 폐기로 **삭제**. **★ 육안 미검증**.
  - ✅ **스텝 4 링크 탭 (D31 이동 배지의 실현)** — 워크트리에서 도는 작업이 **다른 프로젝트 탭에 갇혔을 때**(cc가 옛 탭에서 worktree add 후 진입) 자동 승격된 프로젝트의 **첫 화면 = 전용 링크 탭**(`TabContent.worktreeLink` + `WorktreeLinkPane` — 셸 스폰 없음, 스냅샷 영속 안 함, 오버레이 배너는 폐기·사용자 피드백). 대상/액션은 스토어 위임(`worktreeLink`/`onWorktreeLinkAction`)으로 AppState가 맡는다. 가져오기 후 링크 탭 자동 닫힘.
  - ✅ **스텝 5 이동 배너 (D31 이동 배지의 원본 쪽)** — 진행 중인 **∞ 세션**이 다른 프로젝트의 워크트리 안에서 작업 중이면 그 칸 상단에 "‘이름’ 워크트리에서 작업 중 — [프로젝트로 옮기기][여기 둠]" 배너(`WorktreeMoveOverlay`, CloseConfirm 배너와 같은 문법). 판정 `AppState.worktreeMoveSuggestion`(= `WorktreeLink.owner`, 영속 탭만), 실행 = `bringPersistentTab`(이식 후 대상의 링크 탭 자동 정리). "여기 둠"은 같은 대상 한정 무시(`dismissedMove`, 세션 한정). 옛 준비물 `WorktreeMove.target`(+테스트)은 superseded로 **삭제**. **★ 육안 미검증**. `WorktreeLink.owner`(순수 임자 판정 — 레포 루트가 하위 워크트리 세션 가로채는 것 방지) + `AppState.externalLiveSession`(다른 store들 OSC7 `pwds` 스캔). **[가서 보기]**=`focusAgentTab`(원본 탭 점프). **[가져오기]**=**영속(∞ tmux) 탭만** — `handOffPersistentTab`(A에서 세션 맵 먼저 떼어 kill/record 없이 detach) → `store.reattach`(B에서 같은 세션 attach). **라이브 서피스 이식 안 함**(프로세스는 tmux 서버에 산다) — cross-store 서피스 수술 회피. 일반 터미널은 가서 보기만(프로세스가 로컬 서피스에 묶임). **★ 육안 미검증**(핵심: 실제 워크트리 add→배너 표시, 가져오기 후 cc 생존, 제거→취소선 배지).

## cmux 대조 — 흡수할 개선 (2026-07-10 · GPL이라 구조·아이디어만)

cmux(4333 swift·상용급: SSH·모바일·브라우저·데몬·135 키액션·nucleo FFI·AI 자동명명) 4영역 대조. **muxa의 "작고 순수"는 옳았다** — 즉시저장(유실 창 0, cmux는 8초 autosave+별도 크래시 스토어)·단일 패스 realize·`selectedTab` 가시성 판정(분할 감시에 더 정확)·의존성 0·값타입 분리. 아래는 규모가 아니라 **정체성 심화**로 가져올 것. 난이도(S/M/L)·가치(상/중/하).

> **진행 (2026-07-10 rev9): cmux 대조 배울점 전부(①~⑧ + 추가 후보 7) 구현·커밋 완료.** 매 단계 빌드 green + 실행 init 크래시 없음. **GUI·훅 의존이라 실기기 육안 검증은 미수행(★).**
> - **저비용 즉효**: ⑦ `GIT_OPTIONAL_LOCKS=0` · ⑥ 순수 `NotificationGate` · ① 훅 카테고리(muxa notify `--category`) · ⑤ 팔레트 액션 실행(`AppState.perform` 추출) · ⑧ 설정 라이브 리로드(`ConfigWatcher`) + ARCHITECTURE 4.2 정정.
> - **정체성 심화**: ② resume 재부착(`ResumeBinding`·`ResumeBanner`·승인 게이트 `agent_resume`·`TermView.sendText` bracketed-paste 회피) · **③ diff 리뷰 코멘트 + 제출 풀**(`ReviewComment`·`ReviewCommentAnchor` 재앵커링·`ReviewCommentStore` 리포키 SHA256·`ReviewCommentSheet`·WKWebView `muxaComment` 브리지·"N개 보내기"로 터미널 되먹임) · **④ 스크롤백 리플레이**(`ghostty_surface_read_text`로 화면+스크롤백 캡처→`ScrollbackStore` 별도 파일→복원 시 env `MUXA_RESTORE_SCROLLBACK_FILE` 재출력).
> - **추가 후보 7**: 프로세스 종료 감지(`DispatchSourceProcess.exit`, foreground_pid) · 스냅샷 `version` + 크래시 마커(`CrashMarker` running-lock) · notify CLI 견고성(소켓 실패 exit 0) · `MUXA_SURFACE_ID`(env 슬롯만 — 탭=서피스 1:1이라 최소) · 알림 dedup/coalescing(cooldown) · 키 충돌·예약키 감지(`KeymapDiagnostic`) · side-by-side diff 토글(`SideBySideDiff` 순수 2열).
>
> **남음 — 실기기 검증 + 잔여:**
> - **실기기 검증 ★**: ② 재개 배너·명령 주입 타이밍(auto 0.8s 지연 유실 여부) · ③ diff 코멘트 브리지·터미널 되먹임 · ④ 스크롤백은 **사용자가 `~/.zshrc`에 `[ -n "$MUXA_RESTORE_SCROLLBACK_FILE" ] && [ -f "$MUXA_RESTORE_SCROLLBACK_FILE" ] && { cat "$MUXA_RESTORE_SCROLLBACK_FILE"; rm -f "$MUXA_RESTORE_SCROLLBACK_FILE"; }` 추가해야 시각 복원 동작**(인프라만 제공) · side-by-side.
> - **잔여 미완**: ④ 스크롤백 파일 GC(복원 시 tabId 변경으로 고아 1회 가능 — 앱 시작 시 디렉터리 GC 후속) · ③ 재앵커링 파일 전체 스코프(hunk 아님)·다중줄/커밋 diff 코멘트 미지원 · 종료 감지 foreground_pid 휘발성(셸 종료 위주, '셸 생존+에이전트만 크래시'는 OSC133과 중복 회피로 미포착) · dedup cooldown·키 진단·크래시 마커 판정값이 로그만(UI 미노출) · `MUXA_SURFACE_ID` 실 라우팅 미배선(env만).
> - **✅ 테스트 타깃 신설 완료** (rev10, 이후 92로 확대) — `Tests/muxaTests/`(`swift test`, **92 테스트 0 실패**). 순수 로직 커버: `FuzzyMatch`·`NotificationGate`·`DiffPatch`·`MuxaConfig`·`SideBySideDiff`·`GitService`(parseStatus/parseLog)·`GitService+GH`·`ReviewCommentAnchor`·`KeymapResolver`(resolve+진단)·`AgentActivityEstimator`·`Workspace`·`DiscardPlan`·`ResumeStrategy`·`AttentionLog`·`ScrollbackStore.orphans`. Package.swift에 `testTarget(muxaTests, deps:[muxa])` — executable 모듈 `@testable import`(GhosttyKit 링크 정상).
> - **✅ 마무리 완료** (rev11) — 설치 스크립트·진단/크래시 표면화·discard 보강·스크롤백 GC·빈 상태 뷰(위 "마무리 완료" 섹션).
> - **다음 마일스톤 후보**: 실기기 검증 통과 후 — 상태머신 튜닝 실사용 · 통합/E2E 테스트(GUI 상호작용이라 단위 테스트와 별도 — Playwright류 불가, XCUITest 검토).

### 정체성 심화 (가치 상)

- **① 구조화 훅으로 상태 추정 제거 [M·상]** ✅ **구현·육안 검증(2026-07-16, `f8bc261`·`cd074ca`)** — 상태머신의 최대 약점이던 `idleThreshold`(4s) 출력 추정 오탐(조용한 도구 실행/생각 중을 "입력 대기"로 오판, orca 대조로 확인). `ClaudeHookInterpreter`가 Claude 훅을 결정론 매핑(`UserPromptSubmit/PreToolUse/PostToolUse→working`·`AskUserQuestion/permission_prompt/idle_prompt→waiting`·`Stop→done`)하고, **working 훅이 pin**하여 조용한 구간에도 tick이 상태를 못 뒤집는다. 두 증상(오탐 "입력 대기"·그 탭 포커스 시 "유휴") 모두 dev 빌드에서 사라짐 확인. 불변식(working pin돼도 다음 훅은 상태를 바꾼다)은 `testHooksOverrideWorkingPin`으로 못 박음. **남음**: 훅 없는(notify 미설치) 세션은 여전히 출력추정 의존(위 "상태머신 튜닝").
- **② 에이전트 resume 재부착 [M~L·상]** ✅ **claude 제로설정 자동 재개 구현** — "앱 꺼도 에이전트 세션 유지". **로컬 PTY 데몬화가 아니다**(cmux 데몬 `cmuxd-remote`는 원격 전용). cmux식 제로설정: 저장 시 각 칸의 프로세스 트리(foreground→셸)를 훑어 claude 실행을 감지(`AgentProcessDetector`, `proc_pidinfo` 부모 사슬 — claude 자식 comm이 `2.1.207`이라 단일 pid 검사론 부족)→OSC7 cwd로 `~/.claude/projects/<인코딩된-cwd>/`의 최신 `.jsonl`=세션 UUID 해석(`ClaudeSessionIndex`, 인코딩 `/`·`.`→`-`)→`claude --resume <UUID>`를 **muxa가 자가구성**해 `ResumeBinding`으로 저장·복원. **신뢰는 출처가 정한다(D27)** — 훅이 알려준 세션(`.hook`)만 사실이라 자동 실행 대상이고, cwd 스캔으로 **추측한** 세션(`.scan`)은 배너 확인을 거친다(옛 문서는 이게 정반대였다). 실행 직전 `ResumeGate`가 포그라운드가 셸인지·폴더가 맞는지 대조한다. 훅 불필요·설치 불필요. 스크롤백 리플레이는 trusted 칸에선 생략(claude가 화면 덮음). **미구현: codex 등 타 에이전트(현재 claude 전용), OSC7 미방출 셸에선 cwd 폴백 정확도.**
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
