# 서비스 기능 코드 리뷰 — 남은 항목

리뷰 대상: 서비스(장수 프로세스) 기능 전체. 세 관점(정확성·엣지케이스 / 아키텍처·중복 / 보안·성능)
병렬 리뷰로 시작해 **C1~C3 · R1~R12 · Nit 전부와 Optional 대부분을 코드로 해결**했다(2026-07-14).

> **이 문서는 할 일 목록이다.** 고친 항목은 지운다. 다 비면 이 문서를 지운다.
> 설계 근거는 [ARCHITECTURE.md](ARCHITECTURE.md) D19·§4.7, 현재 상태는 [STATUS.md](STATUS.md).

## 남은 것

### [ ] R4-② — 기동이 여전히 첫 창보다 앞에서 tmux 경로를 해석한다
`main.swift:63,76,79`. **영구 정지는 막혔다** — `TmuxService.capture`에 2초 워치독(`resolveTimeout`)이
붙어 `nvm use`가 네트워크를 때려도 포기하고 fallback 경로 훑기로 넘어간다.
남은 절반은 **지연**이다: `AppState` 초기화(`servicesAvailable`)·`collectServiceGarbage`·`startServices`가
창 생성(`:98~`)보다 먼저 로그인 셸을 동기로 띄워, 무거운 rc에서 최대 2초만큼 **첫 페인트가 늦는다.**
**수정**: 셋을 첫 프레임 뒤 `DispatchQueue.main.async`로 미룬다(스크롤백 GC가 이미 쓰는 패턴 — `main.swift:151`).
순서(청소 → 재기동)는 같은 블록 안에서 유지해야 방금 지운 세션을 되살리지 않는다.

### [ ] Optional — `service.command` 평문 저장(0644)
`AppState.swift:1401` — `data.write(to:options: .atomic)`에 파일 보호가 없다. `API_KEY=… pnpm dev`를
등록하면 state.v4.json에 평문으로 남는다. 안내문("토큰은 .env로")은 이미 `ServiceAddSheet.swift:80`에 있다.
**수정**: 저장 시 `.completeFileProtection`(0600). (알림 본문엔 name+exit code만 넣은 건 잘한 부분 — 유지.)

## 아키텍처 — 별건 (이 리뷰 범위 밖)

`AppState.swift`는 여전히 1000줄대다(프로젝트 규칙 200~300). **서비스만 빼서는 못 맞춘다** —
AppState는 영속·빠른 전환기·크롬 액션·배지·창 배치까지 껴안은 god object이고 서비스는 최근 입주자일 뿐이다.

- [ ] **영속 안 되는 런타임 상태만 `ServiceDockStore`로**(약 70줄): `showServiceDock`·`selectedServiceId`·
  `serviceAddRequested`·`dockTerms`·`serviceRestartSeq`·`dockTerm`·`open/closeServiceDock`·`requestAddService`·
  `dropDockTerm`. `app: ghostty_app_t`만 필요해 백레퍼런스 없이 깨끗이 떨어진다(TerminalStore 패턴과 동형).
  CRUD(`addService`/`removeService`/…)는 workspaces(값 타입) 편집+`save()`라 AppState에 남긴다 —
  **통짜 `ServiceStore`는 만들지 말 것(복잡도 이동일 뿐).**
- [ ] `SessionPersistence`(save/load/Persisted) 추출 — 또 다른 별건.

## 해결된 것 (기록)

C1 remain-on-exit 순서(`startArgs` 순수 함수+테스트) · C2 포트 조회 백오프(`PortProbe`) · C3 중복 serviceId
crash(`ServiceMonitor.index`) · R1 빈 `.origin`(보존) · R2 셸 인용+id 화이트리스트(`ShellQuote.single`·
`isValidId`) · R3 refresh 세대 카운터 · R4-① capture 워치독 · R5 `brew` 캐시 · R6 start 실패 표면화
(`reportServiceStart`) · R7 인박스→서비스 라우팅(`locateService`) · R8 도크 행 글리프(`ServiceRow` 공용) ·
R9 관측 가능한 `AppState.servicesAvailable`+`retryTmuxDetection` · R10 `groupServices`(분할, 순수) ·
R11 GC 유령(`worktreeRoot ?? bundlePath`) · R12 죽은 코드(`logCommand`·`ScriptSource.justfile`) ·
판정 중복(`ServiceState.isFailure`) · `states[id] ?? .missing`(`ServiceMonitor.state(of:)`) · 포트 캐시
재시작 무효화 · runCommand 정책을 뷰 밖으로(`ProjectScripts.command(for:manager:)`) · pane 0 타겟 고정 ·
악성 package.json UI 은폐(`.tail` truncation·이름 화이트리스트·`sanitize`) · 하드코딩 토큰화 ·
`EmptyState` 재사용 · `projectId(of:in:)` 제거 · Makefile `::=` 오인 · App Nap 폴링 감속 ·
WHY 주석 3중 복붙 → D19 포인터 · 테스트 공백(ServiceMonitor·startArgs·빈 origin·중복 id).
