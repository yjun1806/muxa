# muxa 진행 상태 · 인수인계 (2026-07-10 · rev11)

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
- **M4 git 쓰기** ✅ — 스테이징/언스테이지/커밋(GitPanel 변경사항 탭 = 커밋박스 + 스테이지됨/변경 2섹션)
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
  있었다. 판정은 순수(`WorktreeOrphans.projectIds`), 닫기는 기존 파괴 동선(`closeProject` → 서비스·tmux 종료).

### ★ 육안 검증 필요 (이 수정)
- Finder/Dock에서 새 사용자 상태로 첫 실행 → 워크스페이스가 **홈**에 생기는가(더 이상 `/`가 아닌가).
- 메뉴바 `명령` 메뉴의 항목이 실제로 동작하는가 · 시트가 떠 있을 때 ⌘W가 뒤 탭을 닫지 않는가.
- 워크트리 시트에서 휴지통/병합 후 정리 → 그 워크트리를 쓰던 프로젝트 탭이 닫히고 dev 서버가 죽는가.
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

### ★ 육안 검증 필요 (이 기능 — `make relaunch`)

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
  **레거시 `muxa-notify --state` 훅도 흡수**해 교체한다(안 그러면 Stop에서 이중 발화). `scripts/install-integration.sh`도 새 형식으로 갱신(jq 의존 제거).
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
- **에이전트 통합 설치 스크립트** `scripts/install-integration.sh`(dry-run 기본, `--apply`로만 실수정·백업·멱등) — muxa-notify PATH 심링크 + Claude Code 훅(`~/.claude/settings.json`, jq 병합) + 스크롤백 rc 스니펫. **훅 스키마 검증**: `session_id`는 env 아닌 stdin JSON이라 재개 프리셋을 `jq -r .session_id`로. docs/SETUP.md에 안내.
- **진단·크래시 UI 표면화**: 키 재정의 진단(`KeymapDiagnostic`)·직전 비정상 종료를 알림 인박스(`AttentionKind.system`, 제목 dedup)에 노출. 크래시 마커→`ResumeStrategy`(none/manual/manualDirty/auto) 배선 — 더티 종료면 재개 배너 강조.
- **discard 보강**: hunk 단위 버리기(`DiffPatch`+`git apply --reverse`) + 스테이지된 리네임(R) 안전 3단계(`DiscardPlan` 순수 로직, 실제 git 검증).
- **위생·UX**: 스크롤백 파일 GC(`ScrollbackStore.orphans` 순수 판정 + 1h 유예로 활성 파일 절대 보존) + 마지막 탭 닫힘 시 빈 상태 뷰(`EmptyProjectView`, ⌘T).

### 미완·후속 (남은 것)

- **상태머신 튜닝 미검증**: RENDER가 포커스 칸 커서 깜빡임에도 오는지 실기기 확인(오면 포커스 칸 idle 추정 불가·비포커스는 정상). `idleThreshold`(4s)·throttle(1s) 실사용 조정.
- **세션 미영속**: 수동 탭 이름(`manualTitles`)·알림 인박스 이력은 재시작 시 비워짐 — 영속하려면 `TabSnapshot` 스키마 확장.
- **저심각 잔여**: dedup cooldown·`MUXA_SURFACE_ID` 실 라우팅은 설정/구조 확장 시 · discard `--cached` hunk unstage · 전체 diff 파일 헤더 클릭 점프 · 탭 순환 ⌃Tab 이론적 충돌 · rename NSAlert 모달(인라인 아님) · 탭 점 색 상태화(Bonsplit `isDirty`가 bool뿐) · 종료 감지 foreground_pid 휘발성(셸 종료 위주).

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

- **① 구조화 훅으로 상태 추정 제거 [M·상]** — 방금 만든 상태머신의 최대 약점이 `idleThreshold`(4s) 출력 추정(4초 생각만 해도 waiting 오탐). cmux는 **추정을 안 한다**: Claude Code 훅 `PreToolUse/PostToolUse→working`·`PermissionRequest/AskUserQuestion/Notification→waiting`·`Stop→idle`·`SessionEnd→ended`를 결정론 매핑. muxa notify `--state`를 세분(+훅 프리셋)하면 출력추정 거의 불필요. `AgentActivityEstimator`에 pin 인프라 이미 있음.
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
