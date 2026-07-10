# muxa

터미널 기반 에이전틱 개발 환경. 코딩 에이전트를 워크스페이스별 터미널에서 돌리고, 에이전트가 만든 결과물 — 문서, 코드, git 변경사항 — 을 앱 안에서 바로 본다.

**mux + a(gent)**. cmux의 계보를 잇되, 터미널 멀티플렉서에 "보는 눈"을 더한다.

## 상태

구현 중. 터미널 코어(분할·탭·검색·세션 복원)와 git 읽기(상태·diff·히스토리)까지 동작한다.
설계는 [docs/DESIGN.md](docs/DESIGN.md), 현재 상태·다음 할 일은 [docs/STATUS.md](docs/STATUS.md).

## 핵심 아이디어

- 경로 기반 워크스페이스 + 자유 화면 분할(세로/가로·임의 중첩) — 여러 에이전트 세션을 동시에 감시
- 에이전트 알림: OSC 감지로 "어느 세션이 나를 기다리는가"를 패인 단위로 표시
- 파일 익스플로러, 렌더링되는 Markdown 뷰어, 코드 뷰어 — 에디터는 없다, 읽기 전용
- git 가시성: 에이전트가 뭘 바꿨는지 diff·히스토리·실시간 배지로 바로 확인
- git worktree 기반 에이전트 병렬 실행

## 스택

Swift/SwiftUI + AppKit (macOS 14+). 터미널 코어는 libghostty 임베딩(`GhosttyKit.xcframework`),
분할·탭은 Bonsplit, git은 CLI 셸아웃. 근거는 설계 문서 참고.
