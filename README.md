# muxa

터미널 기반 에이전틱 개발 환경. 코딩 에이전트를 워크스페이스별 터미널에서 돌리고, 에이전트가 만든 결과물 — 문서, 코드, git 변경사항 — 을 앱 안에서 바로 본다.

**mux + a(gent)**. cmux의 계보를 잇되, 터미널 멀티플렉서에 "보는 눈"을 더한다.

## 상태

설계 단계. 코드는 아직 없다. 설계 문서는 [docs/DESIGN.md](docs/DESIGN.md)에 있다.

## 핵심 아이디어

- 경로 기반 워크스페이스 + 워크스페이스별 터미널 탭 (cmux에서 살린 것)
- 파일 익스플로러, 렌더링되는 Markdown 뷰어, 코드 뷰어 — 에디터는 없다, 읽기 전용
- git 가시성: 에이전트가 뭘 바꿨는지 diff·히스토리·실시간 배지로 바로 확인
- git worktree 기반 에이전트 병렬 실행

## 스택

Tauri 2 + Rust 코어(alacritty_terminal, git2, notify) + React/TypeScript. 근거는 설계 문서 참고.
