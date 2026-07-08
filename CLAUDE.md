# muxa 프로젝트 규칙

muxa는 macOS 전용 터미널 기반 에이전틱 개발 환경 (Tauri 2 + Rust 코어 + React/TS).
설계·결정의 단일 진실 원천은 [docs/DESIGN.md](docs/DESIGN.md) — 아키텍처를 바꾸면 이 문서도 갱신한다.

## 코딩 원칙 — 클린코드 + 높은 재사용성 (CRITICAL)

새 코드를 짜기 전에 **"이미 있는 걸 재사용하거나 공통화할 수 있나?"**를 먼저 묻는다.
모든 코드는 재사용 가능하고 읽기 쉽게.

- **로직은 순수 함수로 분리한다.** 트리 조작·레이아웃 계산 같은 순수 로직은 컴포넌트가 아니라
  순수 함수로 둔다 (예: `src/tree.ts` — `splitPane`/`closePane`/`computeLayout`). 부작용(PTY·이벤트·DOM)은
  경계 컴포넌트에만 격리한다.
- **상태는 위, 표현은 아래 (controlled).** 상태 소유는 상위 컴포넌트가, 하위는 props로 받아 렌더한다
  (예: `WorkspaceView`는 tree/focusedId를 소유하지 않고 `onChange`로 위임). 재사용·테스트가 쉬워진다.
- **중복이 3번이면 추출한다.** 같은 로직이 세 번째 나오면 즉시 공통 함수/훅/모듈로.
- **컴포넌트는 단일 책임.** 하나가 커지면 쪼갠다 (예: 패인 = `TerminalPane`(PTY·xterm) + `PaneHeader`(버튼)).
- **하드코딩·매직값 금지, 값은 한 곳에.** 색은 CSS 변수(`src/index.css`의 팔레트), 상수는 명명된 `const`.
  같은 hex·숫자를 여러 곳에 흩뿌리지 않는다.
- **작은 파일 여러 개 > 큰 파일 하나.** 도메인·기능별로 분리, 파일당 200~300줄 유지.

기존 패턴을 먼저 읽고 따른다:
- 순수 로직 → `src/tree.ts`
- 네이티브 리소스 캡슐화 컴포넌트 → `src/TerminalPane.tsx`
- controlled 컴포넌트 분리 → `src/WorkspaceView.tsx`
- Rust 커맨드·상태 소유 → `src-tauri/src/pty.rs`

## 패키지 매니저

**pnpm** (루트 `pnpm-lock.yaml`). npm/yarn 섞지 않는다.

## 검증

프론트 타입: `pnpm exec tsc --noEmit` · Rust: `cd src-tauri && cargo check`.
UI·PTY 변경은 실행 중 `pnpm tauri dev`가 HMR/재빌드로 반영 — 인터랙티브 동작은 실제 창에서 확인한다.
