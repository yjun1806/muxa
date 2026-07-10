# muxa 진행 상태 · 인수인계 (2026-07-10)

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
- **M4 워크트리** ✅ — 워크트리 list/add/remove·WorktreePicker·`.worktrees/<branch>`+exclude. **git 쓰기(스테이징/커밋)는 남음**
- **뷰어 라이브러리** ✅ — **md/HTML = WKWebView + markdown-it·highlight.js·mermaid**(`Resources/mdviewer`), **코드 = Shiki**(VSCode 문법)
- **익스플로러 VSCode급 1단계** ✅ — **NSOutlineView 전환** + git색·컨텍스트메뉴(여기서 터미널 열기)·선택 하이라이트·키보드 네비

## 다음 할 일

- **탭 추가 버튼 위치** — 지금 상단바에 있음. 분할 버튼 옆(탭바)이 정위치. Bonsplit이 탭바를 그려서 못 끼움 → `manaflow-ai/bonsplit` fork(`SplitActionButton` config 있음)로 전환하면 가능. **의존성 교체(almonk→manaflow) 리스크 검토 필요.**
- **파일 아이콘 Material** — 지금 NSWorkspace 시스템 아이콘(밋밋). Material Icon Theme(MIT SVG) 번들 + 매핑 코드젠. `FileIcon.image` 한 함수만 교체하면 됨(격리).
- **탭 그룹핑** — 문서 탭끼리·diff 탭끼리 묶기.
- **git 쓰기(M4 나머지)** — 스테이징/커밋 UI(GitPanel에 변경 파일 목록 있음).
- **익스플로러 VSCode급 2단계** — 인덴트 가이드·호버·reveal·인라인 이름변경·새파일/삭제·트리 구조 라이브 갱신(reloadItem).
- **뷰어 탭 라이브 리로드**·**gh 배지**·**세션복원 시 뷰어/diff 탭 제외**·**워크트리 제거 UI**.

## 핵심 아키텍처

- **3계층**: `Workspace{path,projects[]}` ⊃ `Project{name,path?}` ⊃ Bonsplit 탭/분할. `AppState.stores`는 프로젝트 id 키잉.
- **다형 탭**: `TabContent = .terminal | .diff(GitDiffTarget) | .file(FileViewTarget)`. `BonsplitWorkspaceView`가 렌더 분기. `store.openFile`/`openDiff`로 탭 생성(경로 dedup).
- **Bonsplit**(almonk, SPM 1.1.1). `TerminalStore`(BonsplitDelegate). **config `keepAllAlive`** — 탭 전환 시 뷰 유지(재렌더 방지). Bonsplit이 초기 "Welcome"/star 탭을 자동 생성 → `ensureInitialTerminal`이 복원/신규 탭 만든 뒤 selected 옮기고 welcome 닫음.
- **코드 뷰어**: `ShikiHighlighter`(싱글턴, 오프스크린 WKWebView 1개가 shiki `codeToTokens` 계산) → `CodeTextView`(NSTextView)가 토큰을 attributed로 네이티브 렌더 + 줄번호 ruler. shiki는 **JS RegExp 엔진(wasm 없음)** esbuild IIFE 단일 번들(`Resources/codeviewer/shiki.bundle.js`, 재번들은 scratchpad `shiki-build`: npm shiki@4 + esbuild).
- **md/HTML 뷰어**: `MarkdownWebView`(WKWebView) + `Resources/mdviewer/shell.html`. `.html`은 raw 렌더.
- **익스플로러**: `FileExplorerOutline`(NSOutlineView Representable+Coordinator) + `FileCellView`/`FileRowView`. `FileNode`는 class(참조 동일성). git색 = `GitService.statusMap`(porcelain -z + 조상 폴더 전파). `FileIcon`(NSWorkspace 1차).
- **git = CLI 셸아웃**. `GitService`(+`GitService+Worktree`, `+Explorer`). `repoRoot`는 `--git-common-dir`(링크 워크트리 안전).
- **터미널 테마**: `GhosttyRuntime`가 시스템 외관 기반 배경/전경 폴백을 `config_load_string`으로 주입(사용자 config 있으면 덮음) + `set_color_scheme`. (사용자 config는 `~/.config/ghostty/config` — 확장자 없는 파일이어야 ghostty가 읽음)
- **알림 배지(A)**: `action_cb` 4케이스 → `TermView`(tabId 보유)가 `isVisibleToUser`(**firstResponder+key창**) 아니면 배지. 탭 점=Bonsplit isDirty, 프로젝트 ●=`AppState.badgedProjects`. 알림=`NotificationService`(번들 가드).
- **영속**: `state.v4.json`. ⌘Q(applicationWillTerminate) 시 저장.

## 사용자 미검증 항목 (빌드·크래시0, 눈으로는 아직)

1. **코드뷰어** Shiki 하이라이트·줄번호·파일 열기 속도(네이티브 전환 후)
2. **md 뷰어** 표·mermaid·코드블록·다크테마
3. **익스플로러** 트리·아이콘·git색·우클릭 메뉴(터미널 열기)·선택·키보드
4. **세션 복원** ⌘Q 종료 후 재시작 시 탭/분할 유지
5. **알림 배지** 백그라운드 완료/벨 시 탭·프로젝트 ● + 억제/해제
6. **M4 워크트리** 시트 생성·프로젝트 열림
7. 터미널 라이트 테마·탭 제목·⌘F·모니터 스케일

## 이번 세션 함정 (재발 방지)

- **NSTextView 본문 clip** = `isHorizontallyResizable=true`인데 `maxSize` 안 줌 → 줄번호만 보이고 텍스트 안 뜸. minSize/maxSize 필수.
- **코드뷰어 굼뜸** = 파일마다 새 WKWebView(web 프로세스 스폰). 해결: 오프스크린 하이라이터 1개 공유 + 네이티브 NSTextView 표시.
- **탭 전환 재렌더** = Bonsplit 기본 `.recreateOnSwitch`. → `keepAllAlive`.
- **배지 무력화** = `TermView.isFocused`가 어디서도 대입 안 돼 항상 false. → `isVisibleToUser`를 `window?.firstResponder === self`로.
- **세션 복원 터미널 안 뜸** = welcome 탭이 selected인 채 닫혀 선택 사라짐. → 복원 탭 먼저 selectTab 후 welcome 닫기.
- **Shiki 오프라인** = esm.sh ?bundle은 동적 import라 file:// 실패. JS RegExp 엔진(wasm 제거) + esbuild IIFE 단일 파일이 정답.
- (기존) 모니터 스케일=layer.contentsScale, 빈 타이틀바=본문 상단바, 상단바 두 줄=safeAreaRegions=[], ⌘Q=메인 메뉴, 복원 replay=restoring 플래그.

## 참조 (scratchpad, 커밋 금지)

- `cmux-ref`(GPL) — 익스플로러 NSOutlineView·git 상태 전파 구조 참고. `bonsplit-mf`(manaflow fork) — SplitActionButton 등 풍부한 API.
- `shiki-build` — shiki 번들 재생성(code-entry.js + esbuild).
