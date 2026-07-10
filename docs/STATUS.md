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

## 다음 할 일 (우선순위: C→B→A 중 **C 끝, 다음 B**)

### B. 익스플로러 + md/코드 뷰어 (다음)
- **탭 메커니즘 이미 준비됨**: `TabContent`(터미널 | diff)에 `.markdown(path)` · `.code(path)` 추가하면 됨.
- 파일 트리(익스플로러) → 파일 클릭 → **뷰어 탭**으로 열기(diff 탭과 동일 패턴, `store.openXxx(...)`).
- md 렌더·코드 하이라이트: DESIGN.md는 WKWebView(remark/CodeMirror) vs 네이티브 미정 — B에서 결정.
- FSEvents 라이브 리로드(파일 변경 시 갱신) — git 패널 자동갱신도 여기서.

### A. 알림 / 완료 감지 (그 다음)
- **`GhosttyRuntime.action_cb`에 케이스만 추가**(⌘F 검색 때 이미 깔림): `GHOSTTY_ACTION_DESKTOP_NOTIFICATION`(OSC 9/777) · `RING_BELL` · `COMMAND_FINISHED`(OSC 133) · `PROGRESS_REPORT`.
- 결과: 백그라운드 탭·프로젝트에 **배지(●)** + (옵션) macOS 알림. "에이전트 끝남"을 안 쳐다봐도 앎.

### M4. 프로젝트 = git 워크트리 자동화
- 지금 "폴더 선택"은 자리표시자. `git worktree list --porcelain` 자동 로드 + `git worktree add`로 생성.
- `Project.path`가 이미 토대 → 재작업 0. git CLI(`GitService`) 확장.
- **gh(GitHub CLI)는 별개 레이어** — PR 번호·CI 상태용(레포가 GitHub + `gh` 로그인 시). 현재 `gh` 설치·인증됨(account: youngjunkim-aha).

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
