# muxa 진행 상태 · 인수인계 (2026-07-09)

> 다음 세션이 여기서 이어간다. 설계 원천은 [DESIGN.md](DESIGN.md), 이 문서는 **현재 상태·다음 할 일**만.

## 재개 방법

```bash
./scripts/bootstrap.sh      # (새 머신 최초 1회) GhosttyKit 설치 — docs/SETUP.md
cd macos
swift build                 # 빌드 (SPM)
.build/debug/muxa           # 실행 (창 뜸)
# UI/PTY 변경은 재빌드+재실행으로 확인. 인터랙티브 동작은 실제 창에서.
```

커밋 자유(private), push만 승인. 커밋 트레일러 금지. 응답은 한국어.

## 마일스톤 진행

- **M0 (IME·임베딩 게이트)** ✅ — 한글 IME 검증 완료.
- **M1 (터미널 코어)** ✅ — 워크스페이스 · Bonsplit 분할/탭 · ⌘F 검색 · 세션 복원 · 사이드바 4모드(hover 오버레이) · 모니터 스케일 · ghostty config 재사용.
- **추가 (M1 범위 밖)** ✅ — **프로젝트 계층**(워크스페이스⊃프로젝트⊃탭), 상단바 한 줄 통합, ⌘Q 메뉴+종료 확인, 접힌 사이드바 호버 이름.
- **M3 (git 읽기) — "C"** ✅ 읽기 부분 완성 — Git 상태 패널(브랜치·↑↓·변경파일) + diff 뷰 + 히스토리(커밋). **diff는 모달 아니라 활성 패인의 탭**으로 뜸.
- **B (익스플로러 + md/코드 뷰어)** ✅ — 우측 접이식 파일 트리(GitPanel 형제) → 파일 클릭 → 뷰어 탭. 다형 탭에 `.file(FileViewTarget)` 추가. md는 네이티브 렌더(블록 파서 + AttributedString 인라인), 코드는 monospace+줄번호. 대형/바이너리 가드. FSEvents 라이브 리로드는 B-2로 남김.
- **A (알림/완료 감지)** ✅ — `action_cb` 4케이스(DESKTOP_NOTIFICATION·COMMAND_FINISHED·RING_BELL·PROGRESS_REPORT). 백그라운드 탭 배지(Bonsplit `isDirty`)·프로젝트 ● 배지·macOS 알림(번들일 때만, bare 바이너리는 Dock 바운스). 보고 있는 탭(first responder+key창)은 억제.
- **M4 (git 워크트리 자동화)** ✅ — `GitService` worktree list/add/remove, `WorktreePicker` 시트(기존 목록+생성 폼), `.worktrees/<branch>` + info/exclude 등록. repoRoot는 `--git-common-dir`(링크 워크트리 안전). gh 레이어는 후속.

## 다음 할 일

### B-2. FSEvents 라이브 리로드 (다음)
- `FileWatcher`(FSEventStream, 디바운스) — 익스플로러 트리 갱신 · 열린 뷰어 탭 리로드 · git 패널 자동갱신을 하나로 공유. 무시 경로(.git·node_modules)는 `FileTree.ignored` 재사용.

### 후속 (백로그)
- **md 고급 렌더**(mermaid·표·이미지) → WKWebView 경로. `MarkdownView`만 교체하면 됨(뷰 격리). WebKit 링크 + 번들 JS 에셋 필요.
- **코드 신택스 하이라이트** — 현재 monospace 평문. `DiffView`의 라인 렌더와 공통화 여지.
- **gh 레이어**(PR 번호·CI 배지) — `GhService`로 격리 예정. 레포가 GitHub + `gh` 로그인 시. 현재 `gh` 설치·인증됨(account: youngjunkim-aha).
- **세션 복원 시 뷰어/diff 탭 제외** — 현재 복원 replay가 모든 탭을 터미널로 되살림(뷰어·diff는 임시라 제외 TODO).
- **워크트리 제거 UI** — `GitService.worktreeRemove`는 있으나 확인 다이얼로그 액션 미연결(비파괴 기본).

## 핵심 아키텍처 (재개에 필요)

- **3계층**: `Workspace{path,projects[]}` ⊃ `Project{name,path?}`(path nil=워크스페이스 상속, 워크트리면 자체) ⊃ Bonsplit 탭/분할. `AppState.stores`는 **프로젝트 id로 키잉**.
- **다형 탭**: `TabContent = .terminal | .diff(GitDiffTarget)`. `TerminalStore.content(for:)`로 분기, `BonsplitWorkspaceView`가 렌더. 뷰어는 `openDiff`처럼 `store.openXxx`로 탭 생성.
- **분할·탭 = Bonsplit**(MIT, SPM 1.1.1). 자체 tree.ts 폐기(크래시). `TerminalStore`(BonsplitDelegate) + `TerminalRepresentable`.
- **git = CLI 셸아웃**(D5 확정). `GitService`(백그라운드 Process): status/diff/log/show. libgit2 안 씀.
- **상단바**: `fullSizeContentView` + `NSHostingView.safeAreaRegions=[]`(안 그러면 신호등과 두 줄로 갈라짐). ContentView 최상단 한 줄에 사이드바컨트롤·프로젝트탭·경로·git토글.
- **영속**: `state.v4.json`(App Support/muxa). 워크스페이스·프로젝트·사이드바모드 + 프로젝트별 `treeSnapshot`. ⌘Q(applicationWillTerminate) 시 저장.

## 사용자 미검증 항목 (구현·빌드·크래시0 확인, 눈으로는 아직)

작업자가 화면 녹화 권한이 없어 못 본 것 — 다음 세션에서 사용자가 확인 필요:
1. ⌘F 검색 오버레이 실제 동작(한글 검색·카운터·Enter 이동)
2. hover 사이드바 모드 오버레이 시각
3. 세션 복원(분할 만들고 ⌘Q→재실행)
4. 모니터 이동 시 글자 크기
5. git 패널·diff 탭·히스토리 실제 표시
6. **B** 익스플로러: 폴더 토글 아이콘(상단바)·트리 펼침·파일 클릭→뷰어 탭·md 렌더·코드 줄번호·중복 클릭 dedup
7. **A** 배지: 백그라운드 터미널에서 명령 완료/벨 시 탭 점·프로젝트 ● 표시, 보고 있는 탭은 억제, 탭/프로젝트 보면 해제. (알림은 .app 번들 전엔 Dock 바운스만)
8. **M4** 워크트리: `+`→워크트리… 시트에서 기존 목록·새 워크트리 생성, 생성 후 프로젝트 탭으로 열림

## 이번 세션에서 밝힌 함정 (재발 방지)

- 모니터 변경 글자 작아짐 = `layer.contentsScale=window.backingScaleFactor`(CATransaction) 누락. `set_content_scale`만으론 부족(cmux 대조).
- 빈 타이틀바 = NSTitlebarAccessoryViewController 렌더 불안정 → 본문 상단바 + fullSizeContentView.
- 상단바 두 줄 = SwiftUI safe-area → `safeAreaRegions=[]`.
- ⌘Q 안 됨 = 메인 메뉴 부재 → App 메뉴 추가. Edit 메뉴 ⌘C/⌘V는 터미널 복사/붙여넣기(ghostty) 가로채니 넣지 말 것.
- 세션 복원 replay: `splitPane(withTab:nil)`=빈 패인, `restoring` 플래그로 delegate 자동생성 억제.

## 알려진 한계 (백로그)

- 세션 복원 시 옛 diff 탭이 터미널로 되살아남(diff는 임시라 복원 대상 아님 — 복원 때 제외 처리 TODO).
- git 패널 자동 갱신 없음(프로젝트 전환·수동 버튼만) → B의 FSEvents에서.

## 참조 (scratchpad, 커밋 금지)

- `cmux-ref` (GPL) — 검색·스케일·Bonsplit 사용 원본. `bonsplit-ref` (MIT main) — 풍부한 API.
- ghostty 헤더: `macos/vendor/ghostty/include/ghostty.h`.
