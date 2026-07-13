# muxa 프로젝트 규칙

muxa는 macOS 전용 터미널 기반 에이전틱 개발 환경 (Swift/SwiftUI + AppKit, libghostty 임베딩).

**문서 3종 — 바꾸면 함께 갱신한다.**
| 문서 | 무엇 | 언제 읽나 |
|---|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | **왜 이렇게 만들었나** — 결정 로그(D1~D19)·아키텍처·서브시스템·마일스톤·리스크 | 구조를 바꾸기 전 |
| [docs/DESIGN.md](docs/DESIGN.md) | **어떻게 보이나** — 색·타이포·간격·컴포넌트·레이아웃·영역 용어(SSOT) | **UI를 만들거나 고치기 전** |
| [docs/STATUS.md](docs/STATUS.md) | 현재 상태·다음 할 일·미검증 항목(★) | 세션 시작 시 |

## 코딩 원칙 — 클린코드 + 높은 재사용성 (CRITICAL)

새 코드를 짜기 전에 **"이미 있는 걸 재사용하거나 공통화할 수 있나?"**를 먼저 묻는다.
모든 코드는 재사용 가능하고 읽기 쉽게.

- **로직은 순수 함수/값 타입으로 분리한다.** 상태 모델·파싱 같은 순수 로직은 뷰가 아니라
  값 타입·순수 함수로 둔다 (예: `Workspace`/`Project` 값 타입, `GitService`·`ServiceSession`의 출력 파싱).
  부작용(PTY·셸아웃·이벤트·창)은 경계 타입에만 격리한다 (`GitService`·`TmuxService`).
- **상태는 위, 표현은 아래 (controlled).** 상태 소유는 상위(`AppState`·`TerminalStore`)가,
  SwiftUI 뷰는 바인딩으로 받아 렌더한다 (예: `BonsplitWorkspaceView`는 트리를 소유하지 않고 store에 위임).
- **중복이 3번이면 추출한다.** 같은 로직이 세 번째 나오면 즉시 공통 함수/타입으로
  (예: 서비스 상태 색·글리프가 칩·도크·팝오버에 세 번 → `ServiceStatusStyle`).
- **타입은 단일 책임.** 하나가 커지면 쪼갠다 (예: 칸 = `TermView`(ghostty surface) + 상단바 컨트롤 분리).
- **하드코딩·매직값 금지, 값은 한 곳에.** 색은 `Palette.swift`, 크기·간격은 `Design/Tokens.swift`,
  그 밖의 상수는 명명된 `let`. 같은 hex·숫자를 여러 곳에 흩뿌리지 않는다. → [DESIGN.md](docs/DESIGN.md)
- **작은 파일 여러 개 > 큰 파일 하나.** 도메인·기능별로 분리, 파일당 200~300줄 유지.
- **파괴적 동작은 판정을 좁게, 보존을 넓게.** 지우는 판정은 순수 함수로 뽑아 테스트하고,
  삭제 자체는 경계에만 둔다. **의심되면 안 지운다** (`ScrollbackStore.orphans`·`ServiceSession.orphans`).

기존 패턴을 먼저 읽고 따른다 (`macos/Sources/muxa/`):
- 상태 모델(값 타입) → `Workspace.swift` · `Service.swift`
- 앱 전역 상태 소유 → `AppState.swift`
- 다형 탭·분할 델리게이트(상태 소유) → `TerminalStore.swift`
- controlled 렌더 뷰 → `BonsplitWorkspaceView.swift`
- 네이티브 리소스 캡슐화(ghostty surface) → `TermView.swift` · `GhosttyRuntime.swift`
- **CLI 셸아웃 경계** → `GitService.swift` · `TmuxService.swift`
- 폴링 관측(@Observable) → `ServiceMonitor.swift`
- 디자인 토큰·공용 컴포넌트 → `Palette.swift` · `Design/`

## 외부 CLI에 의존할 때 (git · tmux)

`.app` 번들은 **로그인 셸의 PATH를 상속하지 않는다**(launchd가 띄우므로 `/usr/bin:/bin:...`뿐).
실사용자는 Finder·Dock에서 앱을 연다 — 터미널에서 띄운 개발 빌드에서만 되는 코드를 쓰면 안 된다.

- **실행 파일은 절대경로로 해석한다** — 로그인 셸에 물어보고(`$SHELL -l -c 'command -v X'`),
  실패하면 알려진 경로를 훑는다 (`TmuxService.executable`).
- **사용자 명령은 로그인 셸로 감싼다** — 안 그러면 `pnpm`이 `command not found`로 즉사한다.
- **미설치는 숨기지 말고 안내한다** — 기능을 감추면 있는지도 모른다. 설치 명령은 터미널에
  **주입만** 하고 Enter는 사용자가 누른다(앱이 직접 `brew install` 하지 않는다).

## 패키지 매니저 · 의존성

**SPM** (`macos/Package.swift`). 분할·탭은 Bonsplit(MIT, 1.1.1).
터미널 코어는 libghostty — cmux fork가 배포하는 prebuilt `GhosttyKit.xcframework`(universal, self-contained)를
임베딩한다. `vendor/`는 gitignore(리포에 안 넣음)이고, **새 머신은 `./scripts/bootstrap.sh`가 SHA 고정으로
내려받아 설치**한다(zig 불필요). 세팅 절차는 [docs/SETUP.md](docs/SETUP.md).

**런타임 외부 의존**: `git`(필수) · `tmux`(서비스 기능, 없으면 안내) · `gh`(PR 배지, 선택).

## 검증 · 빌드

```bash
./scripts/bootstrap.sh   # (최초 1회) GhosttyKit 설치 — docs/SETUP.md
cd macos
swift build            # 빌드
swift test             # 순수 로직 단위 테스트
.build/debug/muxa      # 실행 (창 뜸)
```

- **순수 로직은 테스트로 못 박는다.** 파싱·판정·정리 같은 순수 함수는 UI 없이 검증된다 — 먼저 여기까지 끝낸다.
- **UI·PTY 변경은 재빌드+재실행으로 확인한다.** 자동 검증을 통과해도 실제 화면에서 깨지는 게 있다
  (셸을 거치는 명령의 인용, 뷰 교체 시 서피스 레이스 등). 육안 확인이 안 된 것은 STATUS에 **★로 남긴다**.
- **muxa 인스턴스는 하나만 띄우고 검증한다.** 여러 개가 뜨면 같은 `state.v4.json`·tmux 소켓을 공유해
  서로 덮어쓴다. 죽일 때는 **경로를 정확히 지정**한다(다른 워크트리의 앱을 죽이지 않게).
- 커밋 자유(private), push만 승인. 커밋 트레일러 금지. 응답은 한국어.
