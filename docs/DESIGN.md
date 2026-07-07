# muxa 설계 문서

작성일: 2026-07-08 · 상태: 초안 (구현 전)

## 1. 배경과 목표

cmux(manaflow-ai/cmux)를 쓰면서 확인한 장단점에서 출발한다.

좋았던 것:

- 경로 기반 워크스페이스를 여러 개 만들 수 있다
- 워크스페이스 안에 터미널 탭 여러 개가 유지된다

아쉬웠던 것:

- 파일 뷰어가 없다. 에이전트가 결과 문서를 만들어도 보려면 VS Code를 열거나 명령어를 쳐야 했다
- git 이력을 보기 힘들다. 에이전트가 파일을 여러 개 바꿔도 뭘 바꿨는지 별도 git 도구로 확인해야 했다

muxa는 터미널 멀티플렉서에 "보는 눈"을 더한 물건이다. 익스플로러, Markdown/코드 뷰어, git diff·히스토리가 터미널 옆에 산다. 에디터는 넣지 않는다. 코드 수정은 에이전트가 하고, 사람이 고칠 일이 있으면 VS Code를 쓰면 된다.

설계 전체를 관통하는 우선순위는 속도와 메모리 효율이다.

## 2. 결정 로그

| # | 결정 | 선택 | 근거 |
|---|------|------|------|
| D1 | 접근 방식 | 새로 제작 (cmux 포크 아님) | 아키텍처 자유도. cmux는 Swift/AppKit + GPL |
| D2 | 셸 플랫폼 | Tauri 2 (Rust 백엔드 + 시스템 WebView) | Electron은 메모리 기준 탈락. 네이티브 Swift는 macOS 전용 + 뷰어에 결국 WKWebView 필요 |
| D3 | 터미널 엔진 | alacritty_terminal 크레이트 | Zed가 프로덕션 검증. libghostty는 파서(-vt)만 알파 공개, 렌더러·위젯은 로드맵 단계 |
| D4 | 터미널 렌더러 | WebView 쪽 thin view (xterm.js 또는 셀 스트림 canvas) | 상태는 Rust가 소유하므로 렌더러는 교체 가능. libghostty-gpu가 성숙하면 갈아끼울 출구 유지 |
| D5 | git 백엔드 | git2 (libgit2 바인딩) | status/diff/log/stage/commit/worktree 전부 커버, gitoxide보다 성숙 |
| D6 | 파일 워칭 | notify 크레이트 + 디바운싱 | 익스플로러 배지·뷰어 리로드·git status 갱신을 워처 하나로 트리거 |
| D7 | 프론트엔드 | React + TypeScript | xterm/CodeMirror 생태계. 프레임워크 간 메모리 차이는 WebView 대비 오차 범위 |
| D8 | 코드 뷰어 | CodeMirror 6 읽기 전용 | 가볍고 대용량 파일에 강함 |
| D9 | 상태 저장 | SQLite | 워크스페이스·탭 레이아웃·세션 복구 |
| D10 | 이름 | muxa | mux 계보 유지. GitHub·crates.io 충돌 없음 확인(2026-07) |

### 터미널 엔진 검토 상세 (D3·D4)

cmux는 Swift 네이티브 앱이라 libghostty의 macOS 임베딩 경로를 탈 수 있었다. 2026년 현재 libghostty에서 공개된 건 VT 파서(libghostty-vt, C API, 알파)뿐이고 GPU 렌더러와 터미널 뷰 위젯은 로드맵에 있다. 크로스플랫폼 Rust 코어에 심을 수 있는 검증된 엔진은 alacritty_terminal이 유일하다 — Zed 터미널이 정확히 이 구조다(alacritty_terminal이 PTY·VTE 상태 담당, 렌더링은 GPUI가 자체 처리).

xterm.js 단독 구성을 버린 이유: 파서와 렌더러가 JS에 묶여 탭 수만큼 JS 힙이 자란다. 상태를 Rust로 내리면 살아있는 렌더러는 화면에 보이는 패인뿐이다.

## 3. 아키텍처

```
┌─ Tauri App ─────────────────────────────────────────────┐
│  ┌─ Rust Core (상태의 진실) ─────────┐   ┌─ WebView ────┐ │
│  │ WorkspaceManager                 │   │ React UI     │ │
│  │  └ Workspace (path 기반)          │   │  워크스페이스   │ │
│  │     ├ TerminalSession ×N         │◄──┤  사이드바      │ │
│  │     │   PTY + alacritty_terminal │   │  터미널 탭     │ │
│  │     ├ GitEngine (git2)           │──►│  익스플로러    │ │
│  │     ├ FileWatcher (notify)       │   │  뷰어 / diff  │ │
│  │     └ WorktreeManager            │   │  git 패널     │ │
│  │ StateStore (SQLite)              │   └──────────────┘ │
│  └──────────────────────────────────┘                    │
│    IPC: Tauri command(요청/응답) + event(스트림, 배칭)       │
└──────────────────────────────────────────────────────────┘
```

불변식 두 가지:

1. **모든 상태는 Rust 코어가 소유한다.** 터미널 그리드·스크롤백, git 상태, 파일 트리의 진실은 항상 Rust에 있고 WebView는 구독만 한다. 메모리 효율과 렌더러 교체 가능성이 여기서 나온다.
2. **단방향 데이터 흐름.** 에이전트가 파일을 바꾸면 `FileWatcher → GitEngine 부분 갱신 → 이벤트 → UI(배지·뷰어 리로드)` 한 파이프라인으로 흐른다. 프론트에 별도 캐시를 두지 않는다.

PTY 출력은 Rust에서 ~16ms 단위로 배칭해 이벤트로 푸시한다(프레임당 1회, IPC 오버헤드 최소화). 비활성 탭은 렌더러를 붙이지 않고 Rust 쪽 상태만 갱신한다.

## 4. 서브시스템

### 4.1 워크스페이스

- 경로 기반. 사이드바에 수직 나열, ⌘1-8 전환 (cmux 방식)
- 워크스페이스별 터미널 탭 N개, 각 탭은 독립 PTY
- 사이드바에 브랜치·에이전트 활동·알림 표시

### 4.2 터미널

- 탭당 `portable-pty` + `alacritty_terminal::Term` 인스턴스, tokio 이벤트 루프
- 스크롤백은 Rust 버퍼 (상한 설정 가능)
- 렌더러는 활성 패인에만 attach — attach 시 Rust 상태에서 화면 재구성
- 세션 지속성 1단계: 앱 생존 동안 유지 + 재시작 시 레이아웃·cwd 복원. PTY 호스트를 분리 가능한 모듈로 설계해 나중에 데몬화(앱 꺼도 에이전트 유지)로 확장

### 4.3 익스플로러와 뷰어

- 익스플로러: lazy 트리, notify 기반 갱신, git status 배지
- Markdown 뷰어: unified/remark 렌더링, mermaid 지원. 파일 워처와 연동해 에이전트가 문서를 쓰는 동안 실시간 갱신 — 이 동선이 "결과 문서 보려고 VS Code 열기"를 대체한다
- 코드 뷰어: CodeMirror 6 읽기 전용, 신택스 하이라이팅
- 편집 기능은 의도적으로 제외

### 4.4 git

요구 수준: 작업 트리 diff, 커밋 히스토리, 실시간 감지, 스테이징/커밋, 워크트리 전부.

1. **작업 트리 diff**: git 패널에서 파일 클릭 → 뷰어 패널에 side-by-side/unified diff. 워처 덕에 에이전트 작업 중에도 실시간
2. **히스토리**: 커밋 타임라인 + 커밋별 diff. 세션 시작 시점 HEAD를 기록해 "에이전트가 이번 세션에 만든 커밋" 필터 제공
3. **실시간 감지**: 워처 이벤트 → 변경 경로만 status 부분 재계산 → 배지 갱신. 대형 리포에서 전체 status 재계산을 피하는 게 핵심
4. **쓰기**: 파일/헝크 단위 스테이징(diff 뷰에 체크박스), 커밋, discard
5. **워크트리**: "새 워크트리 + 터미널 탭"을 한 동작으로 생성 → 브랜치별 에이전트 병렬 실행. 탭에 워크트리·브랜치 뱃지, 작업 후 merge와 워크트리 정리까지 UI에서 처리

### 4.5 에이전트 인지

- OSC 9/777 알림 시퀀스 감지 → 에이전트 입력 대기 시 탭·워크스페이스에 표시 (cmux의 알림 링에 해당)
- 터미널 출력 idle + 프로세스 상태로 작업 중/대기/종료 추정

## 5. UI 레이아웃

```
┌──────┬──────────────────────────────┬───────────────┐
│ WS   │ ▶ agent  build  logs   [+]   │ EXPLORER      │
│ ● A  │                              │ ▸ src/    M   │
│   B  │  $ claude                    │ ▾ docs/       │
│   C  │  ⏺ Writing report.md...      │    report.md ●│
│      │  █                           ├───────────────┤
│      │                              │ GIT  ⎇ main   │
│      │                              │ M src/api.ts  │
│  [+] │                              │ A docs/rep..  │
├──────┴──────────────────────────────┴───────────────┤
│ VIEWER: report.md (rendered) ⟷ api.ts (diff)         │
└──────────────────────────────────────────────────────┘
```

- 좌: 워크스페이스 사이드바 / 중앙: 터미널 탭 / 우: 익스플로러 + git 패널 / 하단: 뷰어(md 렌더링·diff 탭)
- 모든 패널은 접을 수 있다. 다 접으면 그냥 터미널 앱
- 뷰어 위치(하단 vs 우측 분할)는 M2에서 실사용으로 결정

## 6. 마일스톤

| 단계 | 이름 | 내용 |
|------|------|------|
| M1 | 뼈대 | 워크스페이스 + 터미널 탭 + PTY 스트리밍 (cmux 기본기 재현) |
| M2 | 보는 눈 | 익스플로러 + md/코드 뷰어 + 파일 워처 라이브 리로드 |
| M3 | git 읽기 | status 배지, diff 뷰, 히스토리 |
| M4 | git 쓰기 + 워크트리 | 스테이징/커밋, 워크트리 병렬 워크플로우 |
| M5 | 에이전트 인지 | OSC 알림, 상태 표시, 세션 복구 고도화 |

## 7. 리스크

- **터미널 체감 성능**: WebView 렌더러는 libghostty·Kitty급 처리량이 안 나온다. 에이전트 출력(사람이 읽는 속도)에는 충분하다는 판단이나, `cat 대용량` 같은 극단 케이스는 M1에서 벤치마크로 확인. 상태-렌더러 분리 덕에 최악의 경우 렌더러만 교체하면 된다
- **대형 리포 git status 비용**: libgit2 status가 느릴 수 있어 워처 기반 부분 갱신을 처음부터 전제. 그래도 느리면 `git status --porcelain` 서브프로세스 폴백 검토
- **alacritty_terminal 업스트림**: Alacritty 본체 개발이 느려질 경우를 대비해 Zed 포크(zed-industries/alacritty)를 대안으로 인지
- **Tauri IPC 처리량**: PTY 스트림 배칭으로 완화. 부족하면 로컬 WebSocket 채널로 우회 가능

## 참고 링크

- cmux: https://github.com/manaflow-ai/cmux
- libghostty 로드맵: https://mitchellh.com/writing/libghostty-is-coming
- Zed 터미널 구현: https://github.com/zed-industries/zed/blob/main/crates/terminal/src/terminal.rs
- alacritty_terminal: https://crates.io/crates/alacritty_terminal
