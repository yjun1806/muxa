# muxa 프로젝트 규칙

muxa는 macOS 전용 터미널 기반 에이전틱 개발 환경 (Swift/SwiftUI + AppKit, libghostty 임베딩).
설계·결정의 단일 진실 원천은 [docs/DESIGN.md](docs/DESIGN.md), 현재 상태·다음 할 일은 [docs/STATUS.md](docs/STATUS.md). 아키텍처를 바꾸면 두 문서도 갱신한다.

## 코딩 원칙 — 클린코드 + 높은 재사용성 (CRITICAL)

새 코드를 짜기 전에 **"이미 있는 걸 재사용하거나 공통화할 수 있나?"**를 먼저 묻는다.
모든 코드는 재사용 가능하고 읽기 쉽게.

- **로직은 순수 함수/값 타입으로 분리한다.** 상태 모델·파싱 같은 순수 로직은 뷰가 아니라
  값 타입·순수 함수로 둔다 (예: `Workspace`/`Project` 값 타입, `GitService`의 출력 파싱).
  부작용(PTY·이벤트·창)은 경계 타입에만 격리한다.
- **상태는 위, 표현은 아래 (controlled).** 상태 소유는 상위(`AppState`·`TerminalStore`)가,
  SwiftUI 뷰는 바인딩으로 받아 렌더한다 (예: `BonsplitWorkspaceView`는 트리를 소유하지 않고 store에 위임).
- **중복이 3번이면 추출한다.** 같은 로직이 세 번째 나오면 즉시 공통 함수/타입으로.
- **타입은 단일 책임.** 하나가 커지면 쪼갠다 (예: 패인 = `TermView`(ghostty surface) + 상단바 컨트롤 분리).
- **하드코딩·매직값 금지, 값은 한 곳에.** 색은 `Palette.swift`, 상수는 명명된 `let`.
  같은 hex·숫자를 여러 곳에 흩뿌리지 않는다.
- **작은 파일 여러 개 > 큰 파일 하나.** 도메인·기능별로 분리, 파일당 200~300줄 유지.

기존 패턴을 먼저 읽고 따른다 (`macos/Sources/muxa/`):
- 상태 모델(값 타입) → `Workspace.swift`
- 앱 전역 상태 소유 → `AppState.swift`
- 다형 탭·분할 델리게이트(상태 소유) → `TerminalStore.swift`
- controlled 렌더 뷰 → `BonsplitWorkspaceView.swift`
- 네이티브 리소스 캡슐화(ghostty surface) → `TermView.swift` · `GhosttyRuntime.swift`
- git CLI 셸아웃 → `GitService.swift`

## 패키지 매니저 · 의존성

**SPM** (`macos/Package.swift`). 분할·탭은 Bonsplit(MIT, 1.1.1).
터미널 코어는 libghostty — `vendor/ghostty`에서 zig로 빌드한 `GhosttyKit.xcframework`를 임베딩한다
(`vendor/`는 gitignore, 리포에 안 넣음. 새 머신은 vendor 빌드부터).

## 검증 · 빌드

```bash
cd macos
swift build            # 빌드
.build/debug/muxa      # 실행 (창 뜸)
```

- UI·PTY 변경은 재빌드+재실행으로 확인. 인터랙티브 동작은 실제 창에서 확인한다.
- 커밋 자유(private), push만 승인. 커밋 트레일러 금지. 응답은 한국어.
