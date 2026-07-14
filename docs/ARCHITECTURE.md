# muxa 아키텍처 문서

작성일: 2026-07-08 · 상태: **v2 — 네이티브 전환 확정** (v1: Tauri/WebView 초안)

> **문서 분담** — 여기는 **왜 이렇게 만들었나**(결정 로그·아키텍처·서브시스템·마일스톤·리스크).
> **어떻게 보이나**(영역 용어·레이아웃·컬러·타이포·컴포넌트)는 [DESIGN.md](DESIGN.md).
> 현재 상태·다음 할 일은 [STATUS.md](STATUS.md).
>
> (이 문서는 원래 `DESIGN.md`였다. AI 코딩 도구 생태계에서 `DESIGN.md`가 **UI 디자인 시스템
> 컨텍스트**를 뜻하는 관례로 굳어져(designmd.co), 에이전트가 열었을 때 기대와 어긋나지 않도록
> 이름을 바꾸고 UI 스펙을 분리했다.)

> **v2 (2026-07-08): Tauri/WebView 폐기 → Swift + libghostty 전면 전환.**
> 사유는 1절 "한글 IME", 개정 결정은 D13~D17. v1 결정 중 폐기된 것은 삭제하지 않고
> "폐기(v2 →Dxx)"로 표기해 판단 이력을 보존한다.

## 1. 배경과 목표

cmux(manaflow-ai/cmux)를 쓰면서 확인한 장단점에서 출발한다.

### 실사용 워크플로 (설계의 기준점)

한 프로젝트 경로에서 코딩 에이전트(Claude Code 등) 세션을 **여러 개 동시에** 띄워두고, 그 사이를 왔다갔다 하며 작업 상황을 보고·체크하고·진행시킨다. 그러다 다른 프로젝트로 이동해 같은 일을 반복한다. 풀스택 작업이라 살아있는 세션·프로젝트 수가 많다.

이 워크플로의 병목은 터미널 **렌더링 처리량**이 아니라 **주의와 전환**이다:

- 여러 세션 중 **어느 것이 나를 기다리는가**(입력 대기·완료)를 알아야 한다 → 알림
- 세션 사이를 **빠르게 전환**해야 한다 → 전환/attach 지연이 핵심 성능 지표
- 여러 세션을 **동시에 봐야** 한다 → 자유 화면 분할
- 에이전트가 **뭘 했는지 체크**해야 한다 → 뷰어·git diff
- 프로젝트를 옮겨도 이전 세션이 **살아있어야** 한다 → 백그라운드 세션 유지

즉 muxa가 최적화해야 할 "터미널 품질"은 렌더러 충실도가 아니라 **멀티플렉싱의 질**(전환·주의·동시 감시)이다. 이 판단이 셸·엔진 선택(D2·D3)을 관통한다.

### cmux 재규정

cmux는 흔히 "탭 달린 터미널"로 보이지만, 실체는 **에이전트를 눈에 보이게 만드는 오케스트레이션 터미널**이다(알림 링, 서브에이전트 패인화, 세션 영속). 살릴 것과 버릴 것:

- **살린다**: 경로 기반 워크스페이스, 에이전트 알림, 세션 영속, 화면 분할
- **cmux에 없어서 더한다**: 파일 뷰어(에이전트 결과 문서를 VS Code 없이 본다), git 가시성(diff·히스토리·실시간 배지)
- **의도적으로 안 넣는다**: 임베디드 브라우저, SSH/원격, 모바일 — muxa 정체성 밖. 필요하면 사용자가 실제 도구를 쓴다

muxa의 차별화 축은 터미널 품질이 아니다(그건 cmux가 이미 잘한다). **에이전트 알림("언제 나를 부르는가")과 git·뷰어("무엇을 바꿨는가")를 한 화면에서 잇는 것**이다. 에디터는 넣지 않는다 — 코드 수정은 에이전트가 하고, 사람이 고칠 일이 있으면 VS Code를 쓴다.

설계 전체를 관통하는 우선순위는 전환 속도와 메모리 효율이다.

### 한글 IME — v2 전환의 결정 사유

사용자는 한국어로 에이전트와 대화한다. 터미널 한글 입력은 1급 요구사항이다. 실측(2026-07-08)으로 확인한 사실:

- **wry/WKWebView는 IME composition 이벤트(compositionstart/update/end)를 발생시키지 않는다.** xterm의 hidden textarea만이 아니라 순수 textarea에서도 동일 — xterm이 아니라 웹뷰 통합 레이어의 결손이다(xterm.js #5887, WebKit #165004 계열).
- 그 결과 xterm 내장 IME 처리가 열리지 않아 자모가 낱개로 새고, input 이벤트 기반 우회(`inputType`+`value` 재구성)를 상태기계로 완결 구현해도 실기기에서 조합·삭제·혼합 입력이 계속 어긋났다(`src/ime.ts` + 테스트 12개로 시도 보존).
- 엔진을 Chromium으로 바꿔도(Electron) xterm.js의 keydown 우선 아키텍처 탓에 CJK 엣지케이스가 구조적으로 남는다 — VS Code가 2026년 현재도 미해결(microsoft/vscode#267568).

결론: **완벽한 한글 입력은 macOS IME 프로토콜(NSTextInputClient)을 네이티브로 구현하는 스택에서만 가능하다.** 이것이 D2(Tauri) 폐기와 v2 전환의 단일 원인이다. 부수 확인: Ghostty의 macOS 앱 자체가 Swift+libghostty 구조라 NSTextInputClient의 완성된 참조 구현(MIT)이 존재한다.

## 2. 결정 로그

| # | 결정 | 선택 | 근거 |
|---|------|------|------|
| D1 | 접근 방식 | 새로 제작 (cmux 포크 아님) | cmux는 Swift/AppKit(80%) + macOS 임베딩 경로 + GPL. Swift 비숙련 → 포크는 "에이전트에 인질 잡힌 코드베이스"가 됨. 오너십·재미·라이선스 모두 신규 제작이 유리 |
| D2 | 셸 플랫폼 | **폐기(v2 →D13).** ~~Tauri 2 (Rust 백엔드 + 시스템 WebView)~~ | 폐기 사유: WKWebView IME composition 이벤트 결손 실측(1절). 원래 근거(Electron 메모리 탈락, mac 전용)는 유효했으나 한글 입력 결격이 우선 |
| D3 | 터미널 엔진 | **폐기(v2 →D14).** ~~alacritty_terminal 크레이트~~ | v1 기각 사유("libghostty는 WebView와 안 붙음")가 네이티브 전환으로 소멸 → libghostty 채택 가능해짐 |
| D4 | 터미널 렌더러 | **폐기(v2 →D14).** ~~WebView 쪽 thin view~~ | 렌더러 교체 출구로 남겨뒀던 libghostty가 본선이 됨 |
| D5 | git 백엔드 | ~~libgit2~~ → **`git` CLI 셸아웃 확정(M3)** | 의존성·벤더링 0(GhosttyKit만으로 빌드 복잡), diff·log·blame이 CLI로 간단, 워크트리(M4)가 CLI 전용이라 M3·M4 일관, cmux도 CLI. 대형 리포 성능은 FSEvents 부분갱신(M2)으로 보완. `GitService`가 백그라운드 Process로 실행 |
| D6 | 파일 워칭 | notify 크레이트 → **v2: FSEvents (macOS 네이티브)** | Swift에서 FSEvents 직접 사용이 더 단순 |
| D7 | 프론트엔드 | **폐기(v2 →D16).** ~~React + TypeScript~~ | 크롬 UI는 SwiftUI로. 읽기 전용 뷰어는 WKWebView 재사용 허용(3절 불변식 3) |
| D8 | 코드 뷰어 | CodeMirror 6 읽기 전용 | **유지 가능** — 뷰어는 입력 표면이 아니라 IME 결손이 무해. WKWebView 안에서 재사용(M2에서 네이티브 대안과 비교) |
| D9 | 상태 저장 | SQLite | 유지. Swift에서는 GRDB 경유 |
| D10 | 이름 | muxa | mux 계보 유지. GitHub·crates.io 충돌 없음 확인(2026-07) |
| D11 | 화면 분할 | **폐기(→D18).** ~~재귀 split 트리 자체 구현(`tree.ts`/`WorkspaceView` 수동 레이아웃)~~ | 자체 구현이 극도로 타이밍 민감한 AppKit Auto Layout 제약 크래시(수동 setFrame vs 자동 제약 충돌)로 이어짐. 분할·탭을 검증된 라이브러리로 대체 |
| D12 | 사용자 설정 | 파일 기반 (`~/.config/muxa/`) | 유지. **v2 보너스: libghostty라 cmux처럼 ghostty config(폰트·테마) 재사용 경로가 열림** — 직접 구축 부담 감소 |
| D13 | **셸 플랫폼 (v2)** | **Swift + SwiftUI/AppKit 네이티브 앱, macOS 전용** | WKWebView IME 결손(1절)으로 WebView 셸 자체가 결격. Electron도 xterm keydown 아키텍처 한계로 기각 — 한글 입력을 1급 요구로 두면 네이티브 NSTextInputClient만 근본 해결 |
| D14 | **터미널 엔진·렌더러 (v2)** | **libghostty (GhosttyKit macOS 임베딩)** | cmux·Kytos 검증 경로. PTY·VT·GPU 렌더·리사이즈 리플로우·스크롤백을 성숙 엔진이 담당 — v1 최대 리스크 2개(attach 지연·리플로우 버그)가 소거됨. SwiftTerm 대비: IME는 직접 구현이나 참조 구현 존재(D15), 렌더링·성숙도 우위 |
| D15 | **한글 IME (v2)** | **NSTextInputClient 직접 구현, Ghostty 업스트림 SurfaceView(MIT) 참조** | Ghostty macOS 앱이 동일 구조의 완성 구현을 가짐. cmux는 GPL — 코드 복사 금지, 구조 참고만(cmux PR #125가 한글 수정 사례) |
| D16 | **UI 프레임워크 (v2)** | **SwiftUI + AppKit 하이브리드** | cmux 패턴(@main SwiftUI + AppDelegate). 크롬(사이드바·패널)은 SwiftUI로 빠르게, 터미널 서피스·키 라우팅은 AppKit NSView |
| D17 | **마이그레이션 전략 (v2)** | **같은 리포 `macos/` 신설 + M0 IME PoC 게이트, 패리티까지 Tauri 공존** | 매몰비용 없이 전제(IME+임베딩)부터 검증. 실패 시 SwiftTerm 폴백(D14 재검토). `tree.ts` 이식, React UI는 시각 스펙으로 활용 |
| D20 | **칸 포커스를 무엇으로 말할 것인가** | **테두리를 버리고 밝기(`paneVeil`)로. 테두리는 에이전트 알림에 독점 배정.** | 포커스는 *상시* 켜지는 신호다. 그런데 같은 테두리 채널을 에이전트 알림(주황=나를 기다림)도 쓴다 — 청록 테두리가 늘 깔려 있으면 **정작 나를 부르는 주황이 그 위에서 경쟁**해야 한다. 강조가 강조를 잡아먹는 구조다. 포커스 없는 칸을 살짝 눌러(`paneVeil`) 밝기로 말하면 테두리가 비고, **"테두리가 떴다 = 무슨 일이 났다"**가 성립한다. 밝기는 덤으로 **주변시로 읽힌다** — 탭바를 안 봐도 어느 칸이 밝은지 안다. 대가: 비활성 칸의 터미널 글자가 살짝 어두워진다(칸을 나란히 놓고 대조하는 게 일상이라 **약하게** 잡았다 — 라이트 3% / 다크 12%. **다크 12%는 나중에 22%로 고쳤다 — ΔL\* 1.52로 사실상 안 보였다. → D26**). 부수 효과: 탭 카드와 칸 테두리를 하나의 윤곽으로 잇는 문제가 통째로 사라졌다(이을 선이 없다). → DESIGN "칸 상태" |
| D21 | **Bonsplit fork** | **`manaflow-ai/bonsplit` → `yjun1806/bonsplit`** (원본 `almonk`가 아님) | 탭바를 muxa 팔레트로 테마링하려면 소스 수정이 필요했다(D18의 upstream엔 훅이 없다). 원본이 아니라 manaflow fork에서 갈라진 이유: 원본 1.1.1 대비 **432커밋·+9538줄** 앞서 있고, muxa가 이미 쓰는 API 10종(`SplitActionButton`·`didRequestNewTab`·`onFileDrop`·`chromeColors` 등)이 **전부 그 fork가 추가한 것**이라 원본엔 없다. 원본에서 뜨면 탭바를 건드리기도 전에 그걸 다 재구현해야 한다. fork 변경은 **가산적**으로 유지한다(새 필드를 nil로 두면 upstream 동작 그대로) — 머지 충돌면을 최소화해 upstream을 계속 따라갈 수 있게 |
| D22 | **upstream #180 따라잡기** | 우리 SwiftUI 지시자 구현을 **버리고** upstream의 AppKit 드로잉 경로(`TabBarSelectionChromeView`)에 **의도만 재구현** | upstream이 탭 지오메트리를 SwiftUI state에서 축출했다(측정→상태→재레이아웃 피드백 루프 제거). 우리가 고쳤던 `selectedTabIndicator`·`tabBarBottomSeparator` 등 SwiftUI 오버레이 5개가 통째로 삭제되고 `ChromeNSView.draw(_:)` 하나로 합쳐졌다 — 그쪽 해법이 우리 것보다 낫다. 라인 단위로 봉합하면 '컴파일은 되는데 화면엔 없는' 좀비가 남으므로 충돌 구역은 upstream을 통째로 채택하고, 포커스별 색(`nsColorActiveIndicator(for:isFocused:)`)·두께·하단 배치만 `ChromeNSView`에 주입 프로퍼티로 다시 얹었다. 겸사겸사 유일한 비가산 변경(선택 탭 제목 semibold 고정)을 `selectedTabTitleWeight`(기본 `.regular`)로 게이팅해 fork 전체를 진짜 가산적으로 만들었다 |
| D19 | **서비스(장수 프로세스) 백엔드** | **muxa 전용 tmux 서버(`-L muxa`)에 위임. 탭 트리 밖.** | dev 서버는 muxa를 꺼도 살아야 한다. D14(libghostty가 PTY 소유)와 충돌하지 않는다 — tmux는 서비스 칸에서 도는 *프로그램*일 뿐이고 VT는 여전히 ghostty가 그린다. 얻는 것 3가지: **생존**(tmux 서버 ppid=1), **접힌 상태 감지**(서피스 렌더 없이 `list-panes`/`capture-pane`으로 상태·로그를 읽는다 — ghostty 서피스로는 불가능), **재부착 레이스 회피**(접을 때 서피스를 버려도 tmux가 프로세스를 붙잡는다). 로컬 PTY 데몬 자체 구현은 기각(DESIGN 123과 동일한 이유) — tmux가 세상에서 제일 잘하는 일을 남긴다. 대가: tmux 의존(미설치 시 안내·설치 유도), 좀비 세션(고아 정리 필수). 탭으로 두지 않는 이유: ⌘W가 dev 서버를 오살하고 세션 복원·탭 그룹핑·배지 가시성 판정이 전부 특례를 요구한다 |
| D18 | **분할·탭 엔진 (v2)** | **Bonsplit (`almonk/bonsplit`, MIT) 채택** | 분할·탭·드래그·리사이즈를 자체 구현하다 AppKit 제약 크래시에 소진(D11 폐기). cmux가 libghostty 터미널에 실전 사용하는 SwiftUI 분할 라이브러리를 채택 — 크래시·리사이즈 지터가 구조적으로 소멸. MIT라 라이선스 자유. 각 패인=`BonsplitView` content로 `TermView`(NSViewRepresentable) 호스팅. 워크스페이스별 `BonsplitController`+`TerminalStore`(`[TabID:TermView]`), 분할/닫기는 `BonsplitDelegate`로 터미널 생명주기 연결. 교훈: 검증된 라이브러리 우선(자체 구현보다) |
| D23 | **프로젝트 전환 경로** | **헤더 프로젝트 탭 폐기 → 사이드바 "워크스페이스 › 프로젝트" 2단 트리 하나로** | 전환 경로가 둘이면(상단 탭 + 사이드바) 어느 쪽이 진짜인지 매번 고민하게 되고, 상단 탭은 **활성 워크스페이스의 프로젝트만** 보여줘 "다른 워크스페이스에서 에이전트가 나를 기다린다"를 구조적으로 못 말한다. muxa의 주인공은 폴더가 아니라 **일하고 있는/기다리는 에이전트**다 — 그러면 화면에 필요한 건 탭 스트립이 아니라 **런 큐**다. 트리는 모든 워크스페이스의 프로젝트를 한 화면에 세우고, 각 행이 상태 점(유휴 5pt / 작업중 6pt / 주의 6pt)으로 자기 에이전트를 말한다. 판정은 순수 `SidebarTree`(status·rollup·펼침·firstWaiting)에 모아 테스트로 못 박고, 상태(`expandedWorkspaces`)는 `AppState`가 소유·영속한다. 상단바엔 표시 전용 **브레드크럼**만 남긴다(클릭 없음 = 경로가 둘로 갈라지지 않는다). 대가: **접힌 모드(icon 52·slim 14)도 2단이어야 한다** — 안 그러면 프로젝트 전환·닫기·워크트리 생성이 마우스로 아예 불가능해진다(탭바가 모드와 무관하게 하던 일이었다). 워크트리 생성은 워크스페이스 우클릭 메뉴에도 실어 모든 모드에서 연다 |
| D24 | **브랜드색의 자리 · 층을 무엇이 만드는가** | **앱 아이콘 teal(`2DD4BF`)은 아이콘 전용으로 격리. UI 강조는 채도를 내린 딥틸 `brand` 하나. 크롬↔콘텐츠 층은 명도차와 카드 고도가 *나눠* 진다** | 아이콘 teal은 다크 크롬(`1B1B1D`) 위에서 대비 **9.24:1** — 포커스 링에 필요한 3:1의 세 배고 보조 텍스트보다 15포인트 밝다. 그걸 UI 강조에 쓰면 **크롬에서 가장 빛나는 물체가 테두리**가 된다(VS Code `007ACC`·Zed `2472F2`·Linear `5E6AD2`는 전부 L\* 55~62). 그래서 강조 텍스트·CTA·포커스 지시선은 `brand`(라이트 5.47:1 · 다크 5.9:1, AA) 하나로 모았다. (한때 테두리 전용 `borderFocus`를 따로 뒀으나 **D20이 칸 포커스 링을 `paneVeil`로 대체**하면서 소비자가 사라졌고, 남은 포커스 강조인 선택 탭 지시선은 `bg`가 아니라 **탭바(`btnActive`) 위**라 거기서 `3B8A7F`는 2.26:1로 3:1에 미달한다 — `brand`가 3.93:1로 통과한다. 맡을 자리가 없어 토큰을 지웠다.) 함께: 크롬 회색을 중립 zinc로 통일(brand teal H≈182와 74~104° 어긋나 서로 밀어내던 청보라 gray 램프 폐기), **목록 선택은 브랜드 wash가 아니라 중립 채움(`btnActive`)** — macOS 규약이고, 색을 상태에만 남겨야 신호가 산다. **층**: "명도차로 벌린다"와 "카드 고도로 띄운다"가 정면충돌했는데 둘 다 부분적으로 옳았다 — `Elevation.Card`(그림자 + 다크 인셋 하이라이트)는 사이드바·상단바↔카드에는 닿지만 **카드 *안*의 도구 패널↔터미널에는 닿지 않는다**(거긴 `panel`/`bg`가 `border` 한 줄로 맞닿는다). 고도가 못 덮는 경계가 실재하므로 명도차를 0으로 못 내리고, 고도가 절반을 지므로 최대로 벌릴 필요도 없다 → 다크 ΔL\*를 **7.8**(10.2와 5.4의 사이)로 둔다. 제약 하나: `btnActive`는 목록 선택 채움이자 **칸 탭바의 면**이라(D21) 다크 값이 `bg` 대비 1.9:1 선에 묶인다 |
| D25 | **중간값(ΔL\* 7.8)을 떠받치려면 고도가 실제로 닿아야 한다** | **크롬 값은 그대로 두고, 고도가 *못 닿던 두 경계*를 고쳤다** — ① 콘텐츠 카드 왼쪽에 크롬 4pt를 비워 그림자가 설 자리를 준다 ② peek 사이드바에 자체 그림자(`Elevation.Peek`) | D24의 절충은 "고도가 사이드바↔카드에는 닿는다"를 전제로 명도차를 절반만 냈다. **그 전제가 코드에선 거짓이었다** — 사이드바는 카드 위에 뜨는 **불투명 오버레이**이고(peek가 콘텐츠를 안 밀려면 그래야 한다) 카드에 딱 붙어 있어, 카드 그림자의 왼쪽 번짐(~3pt)이 그 면에 통째로 가려진다. 즉 **ccb8d68이 지목한 바로 그 경계**(사이드바↔터미널)에서만 고도가 0이었고, 거기서 우리는 명도차(10.2→7.8)와 `border`(1.89→1.62)를 둘 다 낮춘 채 아무것도 안 얹은 셈이 된다. 되돌리는 길은 둘이었다 — 명도차를 main으로 복원하거나(크롬이 다시 도형이 된다), **전제를 참으로 만들거나**. 후자를 택했다: 원인이 "고도가 약하다"가 아니라 "고도가 **가려졌다**"였기 때문이다. 같은 사각지대가 peek 사이드바에도 있다(카드보다 위 레이어 → 카드 그림자가 못 비춘다). 2단 트리라 떠 있는 면적이 넓어진 만큼 남는 신호가 1px 하선뿐이면 트리가 터미널에 얹혀 보인다 → peek 중에만 오른쪽으로 그림자를 준다. **그래도 최종 판정은 화면이 한다**(STATUS ★) — 여전히 뭉개면 그때 `panel` 다크를 `303035`로 올린다(한 줄) |
| D26 | **칸 포커스를 밝기로 말한다면, 그 밝기가 실제로 보여야 한다** | **`paneVeil` 다크 알파 12% → 22%.** 두 모드의 *알파*가 아니라 **결과 ΔL\***를 맞춘다 | D20이 포커스 링을 버리고 밝기에 걸었는데, 그 밝기를 재보니 **거의 없었다** — 검정 12%를 `1B1B1D`에 곱하면 `18181A`, **ΔL\* 1.52 · 1.03:1**이다(검정 곱연산의 절대 변화량은 바탕 밝기에 비례한다 — 어두울수록 사라진다). 눈에 띄던 건 글자뿐이라 **빈 칸(프롬프트만 있는 셸)은 포커스 여부가 구분되지 않았다**. 게다가 D24가 지시선 teal을 `2DD4BF`→`5FB8AB`로 내리면서(탭바 위 4.96→3.93) 남은 단서마저 얇아졌다 — 두 결정이 각자 옳았는데 **합쳐지니 포커스가 이중으로 약해졌다**. 22%면 `151517` = **ΔL\* 3.00**으로 라이트 3%(2.77)와 같은 무게가 되고, 비포커스 칸의 터미널 글자는 8.6:1로 여전히 AAA(7:1)를 통과한다. 지시선 전용 토큰을 되살리는 대신 베일을 고친 이유: 지시선 대비는 라이트에서 `muted`(3.99:1)와 사실상 동률이라(3.77:1) **색으로는 어차피 못 가른다** — 포커스는 색이 아니라 밝기·두께·굵기로 말한다는 D20의 원안대로, 그 밝기를 보이게 만드는 게 정공법이다 |
| D27 | **재개 명령을 "어디에" 보내는가 — 배너는 제안이지 알림이 아니다** | **배너는 복원 경로에만. 실행 직전 `ResumeGate`가 대상(포그라운드=셸)과 장소(pwd=바인딩 cwd)를 검사한다. tmux(∞) 탭은 아예 제외** | 사용자 제보: "claude를 켜면 그 claude 안에 `claude --resume …`를 붙여넣는다." 원인은 **바인딩 저장과 배너 표시가 한 함수**였다는 것이다(`registerResumeBinding`). 훅(SessionStart)은 "이 탭 세션은 이것"이라는 **사실 통보**인데, 그걸 저장하면서 배너까지 띄웠고 — `.hook`은 trusted라 전략이 `.auto` — 800ms 뒤 자동 실행이 **방금 뜬 claude TUI 입력창**에 명령을 타이핑하고 Enter를 쳤다. 재개 배너는 "이어서 할래?"라는 **제안**이라 이어서 할 게 있을 때만 뜬다: 세션 복원으로 되살아난 빈 셸. 에이전트가 지금 돌고 있으면 이어서 할 게 없다. 그래서 경로를 쪼갰다(`restoreResumeBinding` = 복원·배너 / `setResumeBinding` = 훅·저장만). 2차 방어로 `ResumeGate`(순수)를 뒀다 — `sendText`는 Enter까지 커밋해 **되돌릴 수 없으므로**, 대상이 셸인지(TUI면 그 프로그램의 입력창이다)와 장소가 맞는지(`--resume`은 cwd 기준으로 세션을 찾는다 — 다른 폴더엔 그 세션이 없다)를 검사한다. 여기서 **모르는 것과 틀린 것을 가른다**: 셸 pid(250ms 폴링)·pwd(첫 프롬프트의 OSC 7)는 스폰 직후 잠시 비어 있는데, 그 구간을 "차단"으로 부르면 auto가 죽고 "통과"로 부르면 검사를 안 한 것과 같다 → `.notReady`로 따로 부르고 auto가 재시도한다(종전의 고정 800ms 단발 발사도 이걸로 대체 — 요행 대신 조건 검사). **tmux 탭은 게이트로도 못 막는다**: pty의 포그라운드는 tmux 클라이언트라 그 *안*의 claude가 안 보이고, 세션은 attach로 되살아나 claude가 죽지도 않았다 — 애초에 배너를 안 띄운다. 겸사겸사 `isSafeSessionId`를 UUID 화이트리스트로 좁혔다: 옛 문자 블랙리스트(`[A-Za-z0-9._-]`)는 `--dangerously-skip-permissions`를 **통과시킨다**(금지 문자가 하나도 없다) — session_id는 소켓으로 들어오는 외부 입력이라 플래그 주입이 성립했다. 형식을 아는 값은 형식으로 검증한다 |

### 터미널 엔진 검토 상세 (D3·D4) — v1 이력 (D14로 대체, 판단 과정 보존용)

cmux는 Swift 네이티브 앱이라 libghostty의 macOS 임베딩(GPU) 경로를 탈 수 있었다. 2026년 현재 libghostty에서 안정 공개된 건 VT 파서(libghostty-vt, C API, 알파)뿐이고, cmux가 쓰는 GPU 렌더 경로는 Ghostty 앱이 함께 배포하는 macOS 임베딩(GhosttyKit)이라 Swift 네이티브 창에 묶인다. muxa는 mac 전용이지만 셸이 Tauri(Rust 코어 + WebView 렌더)라 그 경로를 못 탄다 — 이 구성에 심을 수 있는 검증된 상태 엔진은 alacritty_terminal이 유일하다. Zed 터미널이 정확히 이 구조다(alacritty_terminal이 PTY·VTE 상태 담당, 렌더링은 GPUI가 자체 처리). muxa는 상태 소유 방식만 같고 렌더러는 WebView라는 점이 다르다.

xterm.js 단독 구성을 버린 이유: 파서와 렌더러가 JS에 묶여 패인 수만큼 JS 힙이 자란다. 상태를 Rust로 내리면 살아있는 렌더러는 화면에 보이는 패인들뿐이고, 켜두기만 한 세션은 Rust에 상태만 남아 가볍다 — "많은 세션을 띄워두고 왔다갔다"에 정확히 맞는 구조다.

**libghostty를 mac 전용인데도 안 쓰는 이유(D3 상세).** alacritty_terminal과 libghostty-vt는 둘 다 "PTY+VT 파서+그리드 상태" 역할로, 렌더러가 없다 — muxa는 어느 쪽이든 그 상태를 WebView에서 그린다. libghostty의 진짜 가치는 별도 조각인 **GPU(Metal) 렌더러**인데, 이건 NSView 안의 네이티브 서피스라 Tauri의 WKWebView와 근본적으로 안 붙는다. 억지로 붙이려면 (a) 네이티브 Swift로 전환(못 읽는 코드) (b) exotic Rust-mac 개척 (c) WebView 위 네이티브 오버레이 — 셋 다 함정이고, 특히 (c)는 자유 분할과 최악의 조합(N개 패인 좌표를 매 리사이즈마다 네이티브 뷰와 동기화)이다. 게다가 실사용이 처리량이 아닌 전환 병목이라(1절) libghostty의 렌더링 우위는 이 워크플로에서 값이 없다. D4의 렌더러 교체 출구는 libghostty가 크로스플랫폼 네이티브 위젯을 stable로 낼 때 재검토할 미래 옵션으로만 남긴다.

## 3. 아키텍처 (v2)

```
┌─ muxa.app (Swift, macOS 전용) ─────────────────────────────┐
│  ┌─ SwiftUI 크롬 ─────────────┐  ┌─ AppKit 터미널 영역 ─────┐ │
│  │ 워크스페이스 사이드바         │  │ SplitTree 컨테이너(NSView)│ │
│  │ 익스플로러 / git 패널        │  │  └ SurfaceView ×N       │ │
│  │ 뷰어(md·diff)              │  │     · NSTextInputClient │ │
│  │  └ 읽기전용은 WKWebView 허용 │  │     · GhosttyKit C API  │ │
│  └────────────────────────────┘  │       (PTY·VT·GPU 렌더) │ │
│  AppState (@Observable)          └─────────────────────────┘ │
│  StateStore (SQLite/GRDB) · Config (~/.config/muxa/)         │
└──────────────────────────────────────────────────────────────┘
```

불변식 세 가지:

1. **터미널의 진실(PTY·그리드·스크롤백)은 libghostty 서피스가 소유한다.** 앱은 서피스 핸들과 생명주기만 관리한다. v1에서 Rust 코어가 하던 역할을 성숙 엔진에 위임 — 배칭·attach 재구성·리플로우를 직접 만들지 않는다.
2. **레이아웃·워크스페이스 상태는 Swift가 소유하고 영속한다(state.v3.json).** 분할·탭 트리는 Bonsplit(D18)이 소유하고, 앱은 워크스페이스 메타 + 워크스페이스별 `treeSnapshot`을 저장한다.
3. **입력 표면은 네이티브 필수, 출력 전용 표면은 WKWebView 허용.** IME 결손은 입력에서만 치명적이다. md 렌더·diff 뷰어는 WKWebView로 기존 웹 자산(remark·CodeMirror)을 재사용할 수 있다(M2에서 네이티브 대안과 비교 결정).

## 4. 서브시스템

**3계층: 워크스페이스 ⊃ 프로젝트 ⊃ 터미널 탭** (API Dog 멘탈모델).

- **워크스페이스**(사이드바): 메인 폴더(레포) + 시작 경로. 사이드바 수직 나열, ⌘1-8 전환(cmux 방식). 배경 워크스페이스 세션도 살아있음. 사이드바에 브랜치·PR·포트·에이전트 활동 표시(M3+)
- **프로젝트**(상단 프로젝트 탭, ⌘⇧[ / ⌘⇧]): 워크스페이스 하위. 각 프로젝트 = 독립 분할 레이아웃(Bonsplit 1개) + 자체 폴더. 경로는 워크스페이스를 상속하거나 **git 워크트리면 자체 경로** — 워크트리 병렬 작업을 별도 워크스페이스로 쪼개지 않고 프로젝트 탭으로 묶는다(`git worktree add` 자동화는 M4). `Project{id,name,path?}`
- **터미널 탭/분할(4.2)**: 프로젝트 안에서 리프 패인마다 탭 N개, 각 탭이 독립 PTY(`TermView`), cwd는 프로젝트 경로. 프로젝트 전환해도 세션 유지(store를 AppState가 프로젝트 id로 보관)

### 4.2 터미널 (v2)

- **패인당** GhosttyKit 서피스 하나 — PTY·VT 상태·스크롤백·GPU 렌더를 엔진이 소유. 앱은 `TermView`(NSView)로 감싸 Bonsplit 패인에 호스팅(`TerminalRepresentable`)
- 한글 IME: `TermView`가 NSTextInputClient 구현(D15) — 조합 미리보기(marked text)가 커서 위치에 인라인 표시
- 백그라운드 세션: 서피스는 살아있되 화면 밖 — 렌더 비용은 보이는 서피스만. 메모리 상한은 ghostty 스크롤백 설정으로 제어
- **검색(Find, M1 완료)**: ⌘F. libghostty 네이티브 검색을 `ghostty_surface_binding_action("start_search"/"search:<needle>"/"navigate_search:next|previous"/"end_search")`로 구동하고, `action_cb`가 `START_SEARCH`/`SEARCH_TOTAL`/`SEARCH_SELECTED`로 되돌려주는 값을 오버레이(`SearchOverlay`, IME 안전 NSTextField)에 반영. 자체 스크롤백 덤프 불필요

**자유 재귀 분할(D18 — Bonsplit).** 각 탭의 내용은 평면 리스트가 아니라 재귀 분할 트리이며, 트리·탭·구분선은 Bonsplit(MIT, SwiftUI, cmux 검증)이 소유한다:

- 리프 패인 = 탭 N개(각 탭 = `TermView` 하나). 내부 노드 = 방향(`.horizontal` 좌우 / `.vertical` 상하) + 구분선 비율. 임의 깊이 중첩
- 분할(⌘D/⌘⇧D)·닫기(⌘W)·방향 포커스 이동·구분선 드래그 리사이즈를 Bonsplit이 처리. muxa는 `TerminalStore`(BonsplitDelegate)로 분할·닫기에 터미널 생명주기를 잇는다
- 리사이즈는 SwiftUI 레이아웃 → `TermView.setFrameSize` → ghostty `set_size` 리플로우. 수동 AppKit 프레임이 없어 D11의 제약 엔진 크래시가 소멸
- 이 분할 트리는 "터미널 영역" 안에서만. 바깥 크롬(사이드바·익스플로러·git·뷰어)은 역할 고정 접이식 패널로 별개(5절)

**세션 지속성(M1 완료, 부분).** 재시작 시 워크스페이스별 **분할 트리 구조 + 탭 수**를 복원한다 — Bonsplit엔 복원 API가 없어(1.1.1) `treeSnapshot`을 저장하고 `createTab`/`splitPane` replay로 재구성, 구분선은 lockstep 복원. **한계**: PTY는 프로세스라 복원 불가(각 탭은 워크스페이스 cwd에서 새 셸로 시작), 탭별 cwd는 OSC 7 pwd 추적으로 복원한다(구현됨). **앱을 꺼도 에이전트 세션을 유지하려면** 로컬 PTY 데몬화가 아니라 **에이전트 네이티브 resume 재부착**이 정답이다 — 돌던 에이전트를 탐지해 `--resume <sessionId>`·cwd·env를 저장하고, 복원 시 승인 게이트(auto/manual) 아래 재실행한다. (cmux 대조로 확인: cmux도 로컬은 데몬을 쓰지 않고 resume-command를 택한다 — 데몬 `cmuxd-remote`는 원격 전용. 화면 히스토리는 스크롤백 리플레이(화면 텍스트 저장→새 셸에서 재출력)로 시각 복원.) 상세 계획은 STATUS 'cmux 대조' ②·④

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

muxa 차별화의 심장. 실사용 워크플로(1절)에서 "어느 세션이 나를 기다리는가"가 최우선 pain이라 **M2로 당긴다**(구 M5).

- OSC **9/99/777** 알림 시퀀스 감지 → 에이전트 입력 대기 시 **패인 단위**로 시각 신호(패인 테두리) + 탭·워크스페이스 배지 (cmux의 알림 링에 해당). 자유 분할이라 추적 단위가 탭이 아니라 패인
- 터미널 출력 idle + 프로세스 상태로 작업 중/대기/종료 추정
- `muxa notify` CLI: 외부(스크립트·훅)에서 특정 패인에 알림을 쏘는 저비용 경로
- 알림 신뢰도가 전체 가치를 좌우 — 놓침/오탐 최소화가 M2 수용 기준

#### 훅이 1차 소스, 추정은 폴백 (2026-07 · orca·cmux 대조 후 개정)

출력 idle 추정은 **본질적으로 부정확하다**. RENDER는 "출력"이 아니라 "렌더"라 커서 깜빡임·스피너·타이핑에도 뜬다.
orca(stablyai)와 cmux가 **독립적으로 같은 결론**에 도달했다 — 에이전트 훅이 진실 원천이고, 터미널 스크래핑은 폴백이다.
muxa도 같은 계층으로 간다:

| 계층 | 소스 | 신뢰도 |
|---|---|---|
| 1차 | **Claude Code 훅** → `muxa-notify hook --event <E>` → Unix 소켓 | ground truth(pin) |
| 2차 | OSC 133 명령 완료 · 프로세스 종료(kqueue) | 결정론적이나 Claude 세션엔 안 옴 |
| 3차 | RENDER heartbeat + idle 타이머(4s) | **추정** — 훅이 없을 때만 |

설계 규칙:

- **CLI는 배관일 뿐이다.** 훅은 stdin payload를 **해석하지 않고 그대로** 소켓에 넘기고(`hook\t<tabId>\t<event>\n<원본 JSON>`),
  파싱·분류·게이팅은 전부 앱(`ClaudeHookInterpreter`, 순수)이 한다. 훅 명령줄은 사용자의 `settings.json`에 박혀 있어서,
  거기 로직을 넣으면 **앱 업데이트로 못 고친다**.
- **완료는 사실로 판정한다.** "잠깐 기다려보고 아니면 취소"하는 유예 창(orca의 1.5s quiet window)은 모든 완료를 늦추면서도
  샌다. 대신 payload가 직접 말해주는 `background_tasks[].status == "running"`·`session_crons`와 서브에이전트 로스터를 본다(cmux).
  **함정**: `Notification(idle_prompt)` payload에는 `background_tasks`가 **없다** → `Stop` 시점에 캐시해야 한다(`HookSessionState`).
- **승인 대기 ≠ 완료.** 카테고리(`needs-permission`/`turn-complete`/`idle-reminder`)를 갈라 `NotificationGate`가 각각 판단한다.
  권한 요청은 배경 작업 중에도 항상 뜬다(사용자가 막고 있는 유일한 알림).
- **알림 본문 = Claude가 마지막으로 한 말.** `Stop`의 `last_assistant_message`, 없으면 `transcript_path`(JSONL)를
  **꼬리에서 역방향**으로 읽는다(`TranscriptTail`, 256KB). "작업 완료"가 아니라 실제 요약이 배너에 뜬다.
- **진행 표시는 LLM 없이.** `PostToolUse`의 `tool_name`+`tool_input` → "편집 중: TermView.swift"(`ToolActivity`, 순수 매핑).
- **이중 발화 금지.** 훅이 붙은 탭의 raw OSC 9/777은 버린다 — Claude는 자체 OSC 알림도 쏘기 때문에 같은 사건으로 두 번 울린다.
- **정직한 상태 표시.** settings.json에 썼다 ≠ 훅이 발화한다(경로·권한·버전). 첫 훅 신호가 도착해야 "동작 중"으로 승격하고,
  그전까지는 "신호 대기 중"이라고 말한다(`HookInstallState`).
- **훅 설치는 사용자 동작으로만.** 남의 `~/.claude/settings.json`을 고치는 일이라 자동 실행하지 않는다.
  알림 인박스(벨) → "설치" 버튼. 병합은 순수 함수(`ClaudeHookSettings`), 쓰기는 백업 + 원자적 교체(`ClaudeHookInstaller`).
  **사용자 훅은 보존**하고 muxa 훅(`muxa-notify`를 부르는 모든 형식)만 멱등하게 교체한다.

### 4.6 설정 (D12)

- 파일 기반 `~/.config/muxa/` (사람이 읽고 편집). D9 SQLite(세션 상태)와 별개
- 폰트 패밀리·크기, 테마(컬러 스킴), 기본 키바인딩
- 없으면 데일리 드라이버가 못 됨 → M1 범위. cmux는 ghostty config 재사용으로 공짜였지만 muxa는 직접 구축
- 키바인딩은 앱 크롬(분할·포커스 이동·워크스페이스 전환)과 터미널(vim 등)의 키 라우팅 우선순위를 명확히 정의해야 함(7절)

### 4.7 서비스 — 장수 프로세스 (D19)

`pnpm dev` 같은 dev 서버는 **muxa를 꺼도 살아야** 하고, **접혀 있어도 죽었는지 알아야** 한다.
탭으로 두면 ⌘W가 오살하고 세션 복원·탭 그룹핑·배지 판정이 전부 특례를 요구하므로, **탭 트리 밖**에 둔다.

- **실행**: muxa 전용 tmux 서버(`-L muxa`). 세션명 `muxa__<projectId>__<serviceId>`가 소유권 표식이다.
  명령은 **로그인 셸로 감싼다**(`.app`은 PATH를 상속 안 해 `pnpm`을 못 찾는다). tmux 실행 경로도
  PATH가 아니라 절대경로로 해석한다(Finder로 연 앱은 launchd의 빈약한 PATH를 받는다).
- **상태**(`ServiceMonitor`, 2초 폴링 1개): `list-panes -a`가 모든 세션 상태를 한 번에 준다.
  **결정론적 신호는 exit code뿐**이다 — `remain-on-exit on`이 필수(없으면 죽는 순간 pane이 증발해
  exit code도 마지막 로그도 잃는다). 로그 regex로 "고장"을 추정하지 않는다(오탐 비용이 가치보다 크다).
- **표시**: 푸터 요약 칩(문제 유무만) → hover 팝오버(서비스별 상태·포트) → 클릭 시 도크(로그).
  도크는 **오버레이**다 — 레이아웃을 차지하면 여닫을 때마다 ghostty 그리드가 리플로우돼 결국 안 열게 된다.
- **로그**: 살아있으면 `tmux attach`(진짜 터미널, Ctrl+C 가능). **죽었으면 읽기 전용 텍스트**
  (`capture-pane`) — 죽는 순간 터미널을 갈아끼우면 새 서피스가 빈 화면으로 뜨는 레이스를 밟는다.
- **좀비**: tmux 생존은 이 설계의 존재 이유인 동시에 위험이다(등록이 사라져도 포트를 문다).
  시작 시 청소하되 **우리가 확실히 아는 것만** 죽인다 — muxa 인스턴스는 여럿일 수 있고 소켓을
  공유하므로, **내 state가 아는 프로젝트의 세션만** 대상이다(아니면 서로의 dev 서버를 몰살한다).
- **자동 재시작 금지**: 포트를 문 좀비나 설정 오류로 즉사하면 크래시 루프에 빠져 로그가 덮이고
  원인이 사라진다. 죽으면 그대로 두고(로그 보존) 사용자가 보고 직접 재시작한다.

## 5. UI (→ DESIGN.md)

영역 용어(SSOT)·레이아웃·컬러 토큰·타이포·컴포넌트 규칙은 **[DESIGN.md](DESIGN.md)**로 옮겼다.
AI 코딩 도구가 UI를 만들 때 그 파일 하나만 읽으면 되도록 한 곳에 모았다.

이 문서에 남는 UI 관련 **결정**은 결정 로그(2절)와 서브시스템(4절)에 있다 —
예: 분할이 두 층인 이유(4.2), 서비스 도크가 오버레이인 이유(4.7, D19).

## 6. 마일스톤 (v2)

| 단계 | 이름 | 내용 |
|------|------|------|
| **M0** | **IME·임베딩 게이트 (신규)** | 최소 Swift 앱 + GhosttyKit 서피스 1개 + NSTextInputClient(Ghostty 업스트림 참조). **통과 기준: 한글 조합 미리보기·한영 혼합·조합 중 백스페이스·스페이스·엔터·vim에서 한글 — 전부 실기기 확인.** GhosttyKit 빌드 파이프라인(zig) 확립 포함. **실패 시 SwiftTerm 폴백으로 D14 재검토** — 매몰비용 최소화가 M0의 존재 이유 |
| M1 ✅ | 터미널 코어 | 워크스페이스 + **재귀 분할 트리(Bonsplit, D18)** + ghostty config 재사용 + 터미널 Find(⌘F, libghostty 네이티브) + `treeSnapshot` replay 세션 복원(구조·탭, PTY/탭별cwd 제외). 사이드바 4모드(hover 오버레이) + 모니터 스케일 |
| M2 | 보는 눈 + 알림 | 익스플로러 + md/코드 뷰어(WKWebView 재사용 vs 네이티브 결정) + FSEvents 라이브 리로드 + **알림 최소버전(OSC 9/99/777 + 패인 단위 시각 신호)** |
| M3 | git 읽기 | status 배지, diff 뷰, 히스토리 + 사이드바 PR 번호·리스닝 포트. git 바인딩 확정(D5) |
| M4 | git 쓰기 + 워크트리 | 스테이징/커밋, 워크트리 병렬 워크플로우 |
| M5 | 인지·복구 고도화 | 알림 패널·`muxa notify` CLI·idle 추정, 세션 복구 고도화 |

v1 대비 M1이 크게 가벼워졌다 — PTY 스트리밍·리사이즈 리플로우·attach 재구성이 전부 libghostty 소관. 대신 M0이 관문이다. Tauri 앱(`src/`, `src-tauri/`)은 M1 패리티까지 공존 후 제거.

### 기존 자산 처분

| 자산 | 처분 |
|---|---|
| `src/tree.ts` (분할 트리 순수 로직) | **폐기** — Bonsplit(D18)이 분할·탭 트리를 대체(자체 구현이 D11 크래시 유발) |
| React UI (사이드바 4모드·상단바·검색) | 시각·동작 **스펙으로 활용** 후 폐기 |
| `src-tauri/` (pty.rs 등 Rust 코어) | 폐기 — GhosttyKit이 대체 |
| `src/ime.ts` + 테스트 12개 | 커밋으로 **기록 보존** — 웹뷰를 버린 이유의 실측 증거 |
| `docs/DESIGN.md` 결정 로그 | 유지 — v1 판단 이력 포함 |

## 7. 리스크 (v2)

- **libghostty embed API 유동 (1순위)**: 공식적으로 "API signatures in flux, breaking changes expected". GhosttyKit 버전을 핀 고정하고 업그레이드는 의식적 이벤트로만. 심하게 흔들리면 SwiftTerm 폴백(D14 재검토) — M0에서 조기 감지
- **Swift 비숙련 (D1에서 지적했던 리스크의 귀환)**: v1이 Tauri를 고른 이유 중 하나였다. 완화: Ghostty·cmux라는 동형 구조의 참조가 있고, 순수 로직(트리)은 테스트로 방어. 그래도 리뷰 능력 저하는 실재 — 코드를 작게, 패턴을 참조 구현에 붙여서 간다
- **NSTextInputClient 구현 품질**: 한글 조합 엣지케이스(조합 중 삭제·한영 전환·marked text 위치)가 승부처. Ghostty 업스트림 SurfaceView를 최대한 그대로 따르고, M0 통과 기준에 명시
- **GPL 오염**: cmux는 GPL — 코드 복사 금지, 구조·이슈(PR #125) 참고만. 코드 수준 참조는 Ghostty(MIT)만
- **zig 빌드 체인**: GhosttyKit 빌드에 zig 필요. 빌드 파이프라인 복잡도 — M0에서 확립하고 문서화
- **재작성 기간 기능 동결**: M1 패리티까지 신규 기능 없음. Tauri 앱 공존으로 데일리 사용은 유지
- **키 라우팅 충돌**: 분할·포커스 이동·워크스페이스 전환 키와 터미널 안 vim의 hjkl 충돌. 앱 크롬 vs 터미널 키 우선순위 규칙 정의(4.6) — AppKit responder chain 설계로 해결
- **대형 리포 git status 비용**: libgit2 status가 느릴 수 있어 FSEvents 기반 부분 갱신 전제. 부족하면 `git status --porcelain` 폴백

## 참고 링크

- cmux: https://github.com/manaflow-ai/cmux (GPL — 구조 참고만)
- cmux 한글 IME 수정 사례: https://github.com/manaflow-ai/cmux/pull/125
- Ghostty (macOS 앱 = Swift + libghostty, MIT — 코드 수준 참조): https://github.com/ghostty-org/ghostty
- libghostty 로드맵: https://mitchellh.com/writing/libghostty-is-coming
- Kytos (libghostty 기반 서드파티 터미널 사례): https://jwintz.gitlabpages.inria.fr/jwintz/blog/2026-03-14-kytos-terminal-on-ghostty/
- WKWebView IME 결손 (v2 전환 근거): https://github.com/xtermjs/xterm.js/issues/5887
- xterm.js CJK 구조 한계 (Electron 기각 근거): https://github.com/microsoft/vscode/issues/267568
- v1 참고: Zed 터미널 구현 https://github.com/zed-industries/zed/blob/main/crates/terminal/src/terminal.rs · alacritty_terminal https://crates.io/crates/alacritty_terminal
