# 세션 복원 설계 (Session Restore)

muxa의 세션 복원 전체 설계. [DESIGN.md](DESIGN.md) §4.2의 "세션 지속성"을 대체·확장한다.
현재 상태·진행은 [STATUS.md](STATUS.md).

---

## 1. 문제 정의

지금 muxa의 복원은 **레이아웃은 촘촘한데 화면은 재현극**이다. 분할 트리·탭·서브탭·활성 칸까지
픽셀 단위로 되살리지만, 정작 터미널 안에는 색이 다 빠진 회색 평문이 `cat`으로 뿌려지고,
돌던 프로세스는 전부 죽어 있다.

cmux·Orca 코드베이스 대조로 확인한 격차:

| 축 | muxa | cmux | Orca |
|---|---|---|---|
| 화면 내용 | 평문 (SGR 전부 strip) | **VT/ANSI 보존** | **직렬화 ANSI + 모드/OSC8** |
| 프로세스 연속성 | 없음 | 없음 (원격만 데몬) | **PTY 데몬 상주 → warm reattach** |
| 창 지오메트리 | 없음 | 디스플레이 구성별 기억 | 있음 |
| 상태 파일 내구성 | 백업 없음, 디코드 실패 시 전량 유실 | `-previous` 폴백 | `.bak.0~4` 로테이션 |
| 에이전트 재개 근거 | cwd + **mtime 최신 jsonl 추측** | 훅이 준 session_id ↔ surfaceId 바인딩 | 훅이 준 session_id + transcriptPath |
| 저장 비용 | 매 이벤트 전 터미널 리드백(메인 스레드) | 8초 autosave(스크롤백 제외) | 1s 디바운스 + 데몬 5초 증분 |
| 크래시 시 화면 | **남음** | 날아감 | 남음 (cold restore) |

우리가 앞선 칸은 마지막 하나뿐이고, 그것도 "매 클릭마다 전 터미널을 디스크에 쓴다"는 값을
치르고 얻은 것이다.

### 목표

1. 복원된 화면이 **끄기 직전과 시각적으로 같다** — 색·굵기·하이퍼링크 포함
2. 앱을 껐다 켜도 **돌던 작업이 이어진다** (opt-in)
3. 저장이 **UI를 막지 않는다**
4. 상태 파일이 깨져도 **조용히 전부 잃지 않는다**

### 비목표

- 다른 머신으로 세션을 옮기는 것(원격/동기화)
- 재부팅을 건너뛰는 프로세스 부활 — 재부팅하면 프로세스는 죽는 게 맞다
- 셸 히스토리·환경변수·job 테이블 복원 — 셸의 영역이다

---

## 2. 복원 계층 (3단)

복원을 **하나의 기능이 아니라 세 겹**으로 본다. 아래 층이 실패해도 위 층은 살아남는다.

```
L3  프로세스 연속성   tmux 백엔드 (opt-in)      ── 돌던 작업이 그대로 이어짐
    ↓ 실패/비활성이면
L2  화면 충실도       VT 스크롤백 리플레이       ── 색까지 같은 화면, 새 셸
    ↓ 실패/비활성이면
L1  구조 + 재개       레이아웃 + 에이전트 resume ── 빈 셸이지만 배치·에이전트는 복귀
```

**L1이 마지막 방어선이다.** 스크롤백 파일이 없어도, tmux가 없어도, 레이아웃과 에이전트 재개는
항상 동작해야 한다. 지금 코드의 최대 위험(§5.3 `layouts` 통째 nil)은 이 원칙을 깬다.

---

## 3. L1 — 구조 · 에이전트 재개

### 3.1 상태 파일 내구성 (D-R1)

**결정: 백업 1세대 + 필드 단위 격리 디코드.**

- `state.v4.json` 저장 성공 시 직전 내용을 `state.v4-previous.json`으로 복사(cmux 방식).
  Orca처럼 5세대까지 돌릴 이유는 없다 — 우리 상태 파일은 작고, 1세대면 "직전 정상 실행"을 되찾는다.
- 로드 실패 시 `-previous` 폴백. 그것도 실패하면 빈 상태로 시작하되 **알림 인박스에 시스템 항목**을
  남긴다("이전 세션을 불러오지 못했습니다"). 지금은 조용히 사라진다.
- **부분 실패 격리**: 현재 `layouts`는 `try?` 한 방으로 디코드해서, 프로젝트 하나의 스냅샷이
  깨지면 **전 프로젝트 레이아웃이 통째로 사라진다**. 프로젝트별로 개별 디코드해 실패한 것만 버린다.
  Orca가 zod `.catch(default)`로 필드 단위 격리를 하는 이유와 같다 — 미지의 enum 값 하나가
  모든 탭을 날리면 안 된다.

```swift
// AppState.load() — 프로젝트별 격리
var layouts: [String: PaneSnapshot] = [:]
for (pid, raw) in persisted.rawLayouts ?? [:] {
    if let snap = try? decoder.decode(PaneSnapshot.self, from: raw) { layouts[pid] = snap }
    else { restoreWarnings.append(.layoutDropped(projectId: pid)) }
}
```

- `version` 필드는 지금 읽고 버려진다. **읽으면 분기하거나, 아니면 필드를 빼라.** 유지한다면
  `version < currentVersion`일 때 마이그레이션 함수 테이블을 태우고, `>`면 백업으로 폴백한다
  (미래 버전의 파일을 구버전 앱이 덮어써 파괴하는 걸 막는다).

### 3.2 창 지오메트리 (D-R2)

**결정: `setFrameAutosaveName` + 디스플레이 구성 키.**

1단계는 `NSWindow.setFrameAutosaveName("muxa.main")` 한 줄이면 끝난다(현재 1000×680 하드코딩).
2단계로 cmux처럼 **디스플레이 구성별 프레임**을 기억한다 — 외장 모니터를 뽑았다 꽂을 때
창이 화면 밖으로 나가는 문제를 막는다. 구성 키 = 연결된 스크린들의 `displayID`+해상도 해시,
LRU 4개 유지. 복원 시 해당 구성의 프레임이 없거나 현재 스크린 밖이면 `constrainFrameRect`로 보정.

### 3.3 스키마 확장 (D-R3)

`TabSnapshot`에 지금 없어서 매 재시작 유실되는 것들을 넣는다:

```swift
struct TabSnapshot: Codable {
    // 기존
    var group: String?
    var items: [ItemSnapshot]
    var selectedItem: Int
    var cwd: String?
    var resume: ResumeBinding?
    var scrollbackFile: String?
    // 추가
    var manualTitle: String?      // 사용자가 손으로 붙인 탭 이름 (지금 저장은 하는데 필드가 없어 유실)
    var fontSizeDelta: Int?       // ⌘+/− 조정값
}
```

알림 인박스 이력(`AttentionLog`)은 `TabSnapshot`이 아니라 별도 파일(`attention.json`)로 뺀다 —
탭 스냅샷과 수명이 다르고(탭이 닫혀도 이력은 남아야 함) 레이아웃 저장 경로를 무겁게 하지 않는다.

### 3.4 에이전트 재개 — 추측에서 사실로 (D-R4)

**문제**: 지금은 `~/.claude/projects/<encoded-cwd>/`에서 **mtime이 가장 최근인 `.jsonl`**을 고른다.
백그라운드에서 다른 claude가 파일을 건드리면 엉뚱한 세션을 물고, 그게 `trusted=true`라
manual 게이트를 우회해 **자동 실행된다.** 잘못된 세션을 자동으로 이어받는다는 뜻이다.

**결정: 훅이 알려준 사실을 1순위, 스캔은 폴백.**

cmux·Orca 둘 다 훅이 넘겨준 `session_id`를 **서피스/패인에 바인딩**해 저장한다. 우리도
`ClaudeHookInterpreter`가 이미 `session_id`를 받고 있다. 이걸 신뢰 경로로 승격한다.

```
1순위  훅 바인딩      SessionStart/Stop 훅이 (session_id, transcript_path, cwd)를
                     MUXA_SURFACE_ID와 함께 보고 → tabId에 직접 바인딩. trusted = true
2순위  프로세스 감지  claude가 돌고 있는데 훅 기록이 없음 → cwd 스캔으로 추정.
                     trusted = false → 배너로 사용자에게 확인받는다 (자동 실행 금지)
3순위  없음          재개 배너 없음
```

핵심은 **trusted의 정의를 바꾸는 것**이다. 지금은 "claude면 trusted", 앞으로는
"훅이 이 탭의 세션이라고 말해줬으면 trusted". 추측은 절대 자동 실행하지 않는다.

이를 위해 `MUXA_SURFACE_ID` env를 **실제로 배선**한다(현재 슬롯만 있고 라우팅 미배선,
STATUS.md:89). 훅 스크립트가 이 값을 그대로 되돌려주면 cwd 추측이 불필요해진다.

**에이전트 다변화 — argv 테이블은 만들지 않는다.** 훅이 `--resume-command`로 **명령 문자열을 통째로**
넘기므로 muxa가 에이전트별 argv를 조립할 일이 없다. codex든 gemini든 자기 훅에서 자기 명령을
보내면 그대로 저장·복원된다. 우리가 아는 것은 "이 탭에서 이 명령을 다시 실행하면 된다"뿐이면 충분하다.
(스캔 폴백만 claude 전용으로 남는다 — `~/.claude/projects` 인덱스가 claude 고유이므로.)

세션 ID 검증은 유지(`isSafeSessionId` — 파일명·셸 주입 방어).

### 3.5 재개 실행 타이밍 (D-R5)

현재 auto 모드는 **0.8초 고정 지연** 후 명령을 보낸다. `ResumeBanner` 스스로 "프롬프트 감지는
과설계라 고정 지연으로 완화"라고 인정한다. 느린 rc(nvm/oh-my-zsh)면 프롬프트 준비 전에
텍스트가 날아가 명령이 반쯤 먹힌다.

**결정: 셸 통합의 프롬프트 마크(OSC 133)를 기다린다.** 우리는 이미 셸 통합 스크립트를
설치한다(`install-integration.sh`). OSC 133 `A`(프롬프트 시작)를 한 번 받으면 그때 보낸다.
2초 안에 안 오면 기존 고정 지연으로 폴백. 마법 상수를 지우는 게 아니라 **정상 경로에서는
쓰지 않게** 만든다.

---

## 4. L2 — 화면 충실도

### 4.1 캡처: VT 보존 덤프 (D-R6)

**결정: `ghostty_surface_binding_action("write_screen_file:copy,vt")` 로 교체.**

현재 `ghostty_surface_read_text` + `strip()`은 설계상 색을 되살릴 수 없다 — read_text가
평문을 주고, strip이 잔여 CSI까지 걷어낸다. cmux는 **같은 libghostty에서** 바인딩 액션으로
VT 시퀀스를 포함한 파일을 export 받는다. 우리도 ⌘F 검색을 바인딩 액션으로 구동하고 있으니
경로는 이미 있다.

```
write_screen_file:copy,vt   → ghostty가 임시파일에 VT 포함 덤프, 경로를 클립보드로 반환
                            → 파일 읽고 삭제 → 상한 적용 후 scrollback/<tabId>.txt 에 저장
```

- 실패 시 기존 `read_text` 평문 경로로 폴백(무색이지만 없는 것보단 낫다)
- 상한(4000줄 / 400KB)은 유지하되, **꼬리 자르기가 CSI 시퀀스 중간을 끊지 않도록** 보정한다.
  끊긴 이스케이프는 재주입 시 화면을 오염시킨다.

### 4.2 재주입: rc 훅 (D-R7)

**결정: `initial_input`을 버리고 셸 통합 rc 훅으로 되돌린다.**

지금은 `config.initial_input = "clear; cat <file>\n"`으로 셸 stdin에 명령을 넣는다. 동작은
하지만 두 가지가 나쁘다:

1. **셸 히스토리 오염** — 사용자가 위 화살표를 누르면 `clear; cat /...scrollback/xxx.txt`가 나온다
2. 프롬프트가 뜨기 전 타이밍에 의존한다

cmux는 rc 스니펫이 첫 프롬프트 **직전에** 파일을 `cat`하고 `unset`한다 — 히스토리에 남지 않는다.
아이러니하게 우리 `install-integration.sh`는 **아직도 그 스니펫을 심고 있는데**(env를 더 이상
주입하지 않아 no-op) — 코드를 문서 쪽으로 되돌리면 양쪽이 맞는다.

```zsh
_muxa_restore_scrollback_once() {
    local path="${MUXA_RESTORE_SCROLLBACK_FILE:-}"
    [[ -n "$path" ]] || return 0
    unset MUXA_RESTORE_SCROLLBACK_FILE
    [[ -r "$path" ]] && /bin/cat -- "$path" 2>/dev/null
}
```

**단, `rm -f`는 하지 않는다.** 현재 스니펫은 cat 후 파일을 지우는데, 그러면 그 세션에서
크래시가 나면 다음 복원은 빈 파일을 만난다. 삭제는 앱의 GC(`ScrollbackStore.collectGarbage`,
1시간 유예)에 맡긴다 — 삭제 책임을 한 곳에 둔다.

### 4.3 테마 오염 방지 (D-R8)

**cmux가 이슈 #5165로 배운 함정을 미리 피한다.** VT 덤프에는 캡처 당시 테마가 구워져 있다
(OSC 4 팔레트, OSC 10/11 fg/bg). 라이트→다크로 테마를 바꾸고 복원하면 **흰 배경에 흰 글자**가 된다.

재주입 전 위생 처리:
- **제거**: OSC 4/5, 10–19, 104/105, 110–119 (색상 정의 시퀀스)
- **보존**: SGR(`ESC[...m`), OSC 8(하이퍼링크), OSC 133(프롬프트 마크)
- 덤프 앞뒤를 `ESC[0m`으로 감싼다 (잔여 속성 누출 차단)

### 4.4 alt-screen 처리 (D-R9)

vim·less·htop이 떠 있는 상태로 종료하면 어떻게 되는가? 지금 코드에는 **alt-screen 분기가 아예 없다.**
read_text가 primary를 주는지 alt를 주는지 확인조차 안 했다.

**결정: alt-screen 활성 중이면 스크롤백을 캡처하지 않는다.** Orca처럼 모드를 저장했다가
`rehydrateSequences`로 재적용하는 건 우리 L2(새 셸) 모델에서 의미가 없다 — vim 화면을 그려봐야
그 vim은 죽어 있고, 아무 키나 누르면 깨진 화면과 셸 프롬프트가 섞인다. **alt-screen 상태는
L3(tmux)의 영역이다.** L2에서는 primary 스크린만 저장하고, alt-screen이면 직전 primary 내용을
보존한다(캡처 실패 시 이전 파일 유지 — cmux의 fallback 전략).

### 4.5 클립보드 보호 (D-R10)

`write_screen_file:copy,vt`의 `copy`는 **덤프 파일 경로를 클립보드에 쓴다**는 뜻이다. 캡처할
때마다 사용자 클립보드가 덮인다 — 그대로 쓰면 복사해둔 내용이 조용히 사라지는 최악의 회귀다.

**결정: 캡처 구간 동안 `write_clipboard_cb`를 가로챈다.** 콜백은 이미 배선돼 있다
(`GhosttyRuntime.swift:126`). 캡처 시작 전 "다음 write를 삼키고 값만 넘겨라" 플래그를 세우고,
경로를 받은 뒤 해제한다. cmux가 `captureNextStandardClipboardWrite`로 하는 것과 같다.
NSPasteboard에는 아무것도 쓰지 않으므로 복구할 것도 없다.

### 4.6 저장 경로 분리 — **하지 않는다** (D-R11)

당초 "매 클릭마다 열린 터미널 전부를 리드백해 디스크에 쓴다"를 문제로 보고, 레이아웃 저장(즉시)과
스크롤백 캡처(디바운스·백그라운드)를 분리하려 했다. **실측 결과 근거가 없어 폐기한다.**

```
~/Library/Application Support/muxa/
  state.v4.json      4 KB
  scrollback/       108 KB  (27개 파일 전체 합, 최대 파일 3.4 KB)
```

상한은 탭당 400KB지만 실사용은 **탭당 수 KB**다. "터미널 8개 × 400KB = 3MB"는 도달하지 않는
이론적 최악치였다. 여기서 얻을 성능 이득은 없고, 대가로 크래시 시 스크롤백 손실 창이
0 → 5초가 된다.

**즉시 저장(손실 창 0)은 cmux(정상 종료 때만 스크롤백 저장 → 강제 종료 시 화면 전량 유실) 대비
우리의 유일한 우위다. 근거 없이 버리지 않는다.**

재검토 조건: 프로파일링에서 `AppState.save()`가 메인 스레드를 16ms 이상 막는 것이 관측되면
그때 다시 연다. 그 전까지는 현행 유지.

---

## 5. L3 — 프로세스 연속성 (tmux 백엔드, opt-in)

### 5.1 왜 PTY 데몬을 만들지 않는가 (D-R12)

Orca는 데몬 프로세스 안에서 **headless xterm**을 돌리고 `SerializeAddon`으로 체크포인트한다.
앱을 껐다 켜면 살아있는 PTY에 다시 붙는다(warm reattach). 이게 진짜 해답이다.

하지만 **우리는 이 구조를 복제할 수 없다.** libghostty는 서피스가 PTY·VT 파서·그리드를 전부
소유한다(DESIGN.md 불변식 1). PTY를 데몬으로 빼면 서피스는 껍데기가 되고, VT 파싱·리플로우·
스크롤백을 우리가 다시 구현해야 한다 — v1에서 Rust 코어를 버리고 libghostty로 간 이유를
정면으로 되돌리는 일이다.

**결정: 셸 대신 tmux를 띄운다. 그리고 그 인프라는 이미 있다.**

`218e9c5`/`c22c1e3`에서 dev 서버 같은 장수 프로세스를 위해 **muxa 전용 tmux 백엔드**를 이미
들여왔다(`TmuxService.swift`, `Service.swift`). L3는 새 인프라를 만드는 일이 아니라 **이걸
터미널 탭으로 확장하는 일**이다. 이미 갖춰진 것:

| 자산 | 위치 | L3에서 그대로 쓴다 |
|---|---|---|
| 전용 소켓 격리 (`-L muxa`) | `TmuxService.socket` | 사용자의 기본 tmux 서버를 절대 건드리지 않는다 |
| 설치 여부 가드 | `TmuxService.isAvailable` | 미설치 시 조용히 L2로 폴백 |
| 멱등 기동 / attach 명령 | `start()` / `attachCommand()` | 탭 spawn·복원에 동일 패턴 |
| 세션명 규약 + 소유권 표식 | `ServiceSession.name` (`muxa__<projectId>__<serviceId>`) | 터미널용 네임스페이스만 추가 |
| 고아 GC (순수 판정 + 셸아웃 분리) | `ServiceSession.orphans` / `collectGarbage` | 등록 없는 세션만 죽인다. 남의 세션은 판정에서 배제 |
| 로그인 셸 래핑 (`$SHELL -l -c`) | `TmuxService.start` | `.app` 번들의 PATH 결손 문제가 이미 해결돼 있다 |

**생존성은 이미 실측 검증됐다** — 커밋 메시지: "tmux 서버는 ppid=1(launchd) — muxa를 꺼도
프로세스가 살아남는다".

터미널 탭 확장:

```swift
// 세션명: 서비스와 네임스페이스를 분리한다
// 서비스  muxa__<projectId>__<serviceId>
// 터미널  muxa__<projectId>__term__<tabId>
let session = ServiceSession.terminalName(projectId: pid, tabId: tid)
command = "tmux -L muxa new-session -A -s \(session) -c \(cwd)"
```

`-A`(있으면 attach, 없으면 create) 하나로 최초 실행과 복원이 같은 명령이 된다. tmux가 PTY·
프로세스·스크롤백·alt-screen·모드를 전부 보존하므로, L3가 켜진 탭에서는 **L2(스크롤백 리플레이)도
에이전트 resume도 불필요하다.** 재부팅하면 tmux 서버도 죽고 자동으로 L2로 강등된다.

### 5.2 서비스 코드와의 충돌 지점 (필수 확인)

기존 서비스 백엔드를 그대로 쓰면 **깨지는 것이 하나 있다.**

`applyServerOptions()`가 `remain-on-exit on`을 **서버 전역(`-g`)** 으로 건다. 서비스에는 필수다
(프로세스가 죽어도 pane이 남아야 exit code·마지막 로그를 읽는다). 하지만 터미널 탭에 그대로
적용되면 **사용자가 `exit`를 쳐도 pane이 죽은 채 남아** 탭이 닫히지 않고 좀비 세션이 쌓인다.

**결정: 터미널 세션에는 `remain-on-exit off`를 세션 단위로 덮어쓴다.**

```swift
// 터미널 세션 생성 직후
await run(["set-option", "-t", "=\(session)", "remain-on-exit", "off"])
```

전역 옵션은 서비스를 위해 그대로 두고, 터미널 세션만 예외로 뺀다. 반대로 하면(전역 off + 서비스만 on)
서비스 알림의 유일한 결정론적 신호가 깨진다.

고아 GC도 갈라야 한다. 현재 `ServiceSession.orphans`는 "등록(`Project.services`)에 없는 muxa
세션 = 고아"로 판정한다. 터미널 세션(`__term__`)이 생기면 **등록이 services에 없으므로 전부
고아로 몰려 죽는다.** 판정 입력에 스냅샷의 살아있는 tabId를 함께 넘기거나, 네임스페이스별로
GC를 분리해야 한다. **이건 기존 테스트가 잡아주지 않는다 — L3 착수 시 첫 번째로 처리할 것.**

### 5.3 스파이크 결과 (실측 완료)

터미널 탭을 실제로 `tmux -L muxa attach`에 붙여 확인했다.

| 항목 | 결과 |
|---|---|
| **한글 IME** | ✅ 정상 — 최대 리스크였는데 통과했다 |
| 색·프롬프트 렌더 | ✅ 정상 |
| **OSC 7 (cwd 추적)** | ❌ **막힌다** — tmux가 안쪽 OSC를 자체 소비한다. 푸터 경로가 안 바뀐다 |
| **OSC 133 (완료 신호)** | ❌ 같은 이유로 막힌다 → 배지·알림·에이전트 상태가 전부 죽는다 |
| 탭 자동 명명 | ❌ tmux가 자기 제목(= `tmux ... attach ...` 명령줄)을 내보내 탭 이름이 그걸로 굳는다 |
| **tmux passthrough** | ✅ **동작한다** — `allow-passthrough on` + `\ePtmux;…\e\\` 래핑으로 OSC가 바깥까지 나온다 |

**결론: 살릴 수 있다. 단, 셸 통합을 우리가 제공해야 한다.**

OSC가 막히는 건 치명적이었다 — cwd 추적·완료 알림은 muxa의 핵심이고, 그게 죽으면 "프로세스는
살아남지만 알림이 안 오는 탭"이 된다. 프로세스 연속성보다 알림이 더 값질 수 있어 R4 자체가
무의미해질 뻔했다. passthrough가 동작하므로 우회로가 있다.

다만 **ghostty의 셸 통합은 tmux 안에서 자동 실행되지 않고**(업스트림 주석에 명시), 실행되더라도
passthrough 래핑을 하지 않는다. 그래서 tmux 세션용 OSC 통합은 muxa가 직접 제공해야 한다.

### 5.4 R4 작업 목록 (확정)

| # | 할 일 | 근거 |
|---|---|---|
| A | tmux 세션 옵션: `allow-passthrough on`, 터미널 세션만 `remain-on-exit off`, `set-titles-string` | §5.2·스파이크. remain-on-exit은 서비스엔 필수지만 터미널에선 `exit` 후 pane이 죽은 채 남는다 |
| B | **tmux용 셸 통합 스니펫** — `$TMUX`면 OSC 7/133을 `\ePtmux;…\e\\`로 감싸 쏜다 | 스파이크. 이게 없으면 cwd·완료 신호가 죽는다. R4의 절반이 여기다 |
| C | `TabSnapshot.tmuxSession` 저장 + 복원 시 그 이름으로 `new-session -A` | **복원 때 tabId가 새로 발급된다**(realize→createTab). 세션명을 tabId로 지으면 자기 세션을 못 찾는다 — 스크롤백이 파일 경로를 저장해 푼 것과 같은 문제 |
| D | 탭 수명: ⌘W → `kill-session` / 앱 종료 → 살려둠 | 앱 종료 후 생존이 목적이지만, 사용자가 탭을 닫은 건 "끝냈다"는 뜻이다 |
| E | L3 탭은 스크롤백 캡처·에이전트 재개를 **끈다** | tmux가 화면과 프로세스를 소유한다. 이중 관리는 잔상만 만든다 |
| F | opt-in — `[session] persistent = false`(기본) | tmux 의존을 기본값으로 강제하지 않는다 |
| G | 터미널 세션 고아 GC | `ServiceSession.parse`가 3파트만 인정해 터미널 세션(`muxa__<pid>__term__<tabId>`, 4파트)은 서비스 GC에서 자동 제외된다(우연히 안전). 전용 GC를 따로 붙인다 |

미검증으로 남는 것: ⌘F 검색, 마우스 리포팅, 대량 출력 성능. 구현 중 확인한다(폐기 사유는 아니다).

### 5.3 왜 opt-in인가

기본값 off. 이유:
- tmux 의존을 기본값으로 강제하면 "설치 없이 바로 쓰는 터미널"이라는 성질을 잃는다
- 위 표의 ★ 두 항목(OSC 7 통과, 성능)이 실측 전이다
- L2가 충분히 좋아지면(색 복원) 많은 사용자에게 L3가 불필요할 수 있다

설정: `~/.config/muxa/config.toml` → `[session] persistent = false` (기본), `true`면 L3 활성.

---

## 6. 스키마 변경 요약

```swift
// state.v5.json  (version: 2)
struct Persisted: Codable {
    var version: Int                    // 2 — 이제 실제로 분기한다
    var workspaces: [Workspace]
    var activeId: String
    var sidebarMode: SidebarMode
    var layouts: [String: PaneSnapshot]?
    var explorerWidth, gitPanelWidth: Double?
    var showExplorer, showGitPanel: Bool?
    var windowFrames: [String: SessionRect]?   // NEW — 디스플레이 구성 키 → 프레임 (LRU 4)
}

struct TabSnapshot: Codable {
    // ... 기존
    var manualTitle: String?            // NEW
    var fontSizeDelta: Int?             // NEW
    var tmuxSession: String?            // NEW — L3 활성 시 "muxa-<tabId>"
}

struct ResumeBinding: Codable {
    var command: String
    var agentId: String?                // CHANGED — agentLabel → AgentSpec.id
    var sessionId: String?              // NEW — 훅이 준 값 (재구성 대신 그대로 사용)
    var transcriptPath: String?         // NEW — 훅이 준 경로
    var cwd: String?
    var trusted: Bool                   // 의미 변경: "훅이 확인해줌" (추측 ≠ trusted)
}
```

**마이그레이션**: `version 1 → 2`는 필드 추가뿐이라 무손실. v1 파일을 읽으면 새 필드는 nil,
저장 시 v2로 승격. `version > 2`를 만나면 백업으로 폴백하고 사용자에게 알린다.

---

## 7. 구현 순서

각 단계는 **독립 출하 가능**하고, 앞 단계가 뒤 단계의 전제가 되지 않는다.

| 단계 | 내용 | 검증 기준 |
|---|---|---|
| **R1** ✅ | 창 프레임 복원 · state 백업/부분 폴백 · manualTitle 스키마 (§3.1–3.3) | 완료. 손상된 state로도 백업에서 터미널 3개 복원(대조군 1개). 화면 밖 프레임은 가운데로 되돌림 |
| **R2** ✅ | VT 스크롤백 (§4.1–4.5) — 캡처·클립보드 가로채기·테마 위생·TUI 가드 | 완료. 색은 인덱스 색까지 보존된다(ghostty가 팔레트를 RGB로 풀어 뱉는다). 클립보드도 안전. 앞서 "인덱스 색 누락"이라 한 것은 오진 — §8 |
| **R3** ✅ | 에이전트 재개 신뢰 경계 뒤집기 (§3.4) | 완료. 훅(사실) 우선, 스캔(추측)은 배너 확인 |
| **R4** | tmux 백엔드 (§5) — opt-in | `persistent = true` + `sleep 300` 실행 → 앱 재시작 → sleep이 **계속 돌고 있다** |

**중간에 드러나 함께 고친 것** (계획에 없던 실기기 발견):
- **흰 패인** — 복원 시 일부 칸이 빈 화면으로 굳고 클릭해도 안 살아났다. 근인 셋: ①ghostty의
  `Surface.focused` 기본값이 `true`인데 muxa는 `false`로 시작해 `set_focus`가 no-op이 됨(클릭이
  복구 신호를 못 만듦) ②`updateNSView`가 소유권 검사 없이 TermView를 강탈해 죽어가는 계층으로
  끌고 감 ③`ghostty_surface_new` 실패 무가드. 8회 재시작 무재현이지만 **완치 증명은 아님**.
- **완료 오탐** — 복원 리플레이(`clear; cat`)가 끝나며 OSC 133 D를 쏴 모든 탭에 "완료" 배지가
  켜졌다. 리플레이 탭의 첫 완료 신호를 삼킨다.

**폐기·보류된 계획**:
- ~~AgentSpec argv 테이블~~ — 훅이 재개 명령을 통째로 주므로 muxa가 argv를 조립할 일이 없다(YAGNI).
- ~~저장 경로 분리~~ — 실측 결과 비용이 없어 폐기(§4.6).
- OSC 133 프롬프트 대기(0.8초 마법 상수 제거) — `TerminalSignal`에 프롬프트 시작 신호가 없어
  인프라 추가가 선행돼야 한다. auto 모드에서만 쓰이는 값이라 급하지 않다.

---

## 8. 리스크

**해소됨 (착수 전 확인 완료)**

- ~~`write_screen_file:copy,vt`가 우리 빌드에 없을 수 있다~~ → **있다.** `libghostty-internal.a`에
  `write_screen_file:copy,{plain,html,vt}` 전 변형이 노출돼 있다. R2 GO.
- ~~저장 비용이 커서 경로 분리가 필요하다~~ → **아니다.** 실측 108KB (§4.6). R3(당초) 폐기.

**남은 리스크**

1. **캡처가 클립보드를 덮어쓴다.** `copy` 옵션의 본질적 부작용. `write_clipboard_cb` 가로채기
   (§4.5)가 R2의 필수 구성요소이며, 이게 새면 "복사해둔 게 사라진다"는 최악의 회귀가 된다.
   **가로채기 없이 캡처를 붙이면 안 된다.**
2. **tmux의 OSC 7 통과 여부.** 안 되면 L3에서 cwd 추적이 죽고, 에이전트 재개의 cwd 근거가
   사라진다. `allow-passthrough` 설정으로 되는지 R4 착수 전 5분이면 확인 가능하다.
3. **trusted 재정의가 기존 흐름을 바꾼다.** 지금 "claude면 자동 재개"에 익숙한 상태에서,
   훅이 없으면 갑자기 버튼을 눌러야 한다. 훅 설치 안내(`install-integration.sh`)가 확실히
   동작하는지가 전제다.
4. **tmux를 넣는 순간 터미널 안의 터미널이 된다.** 키 입력·마우스·리사이즈·색 지원이
   한 겹 더 거친다. 미묘한 회귀(⌘F, 한글 IME, 마우스 리포팅)가 나올 수 있고, 그건
   "복원 기능이 평상시 사용성을 갉아먹는" 최악의 형태다. opt-in인 이유이자, 기본값을
   절대 바꾸지 말아야 하는 이유다.
5. **VT 덤프가 평문보다 훨씬 크다.** SGR·OSC가 들어가면 같은 화면도 2~5배 부푼다. 400KB
   상한은 유지하되, 꼬리 자르기가 이스케이프 시퀀스 중간을 끊지 않도록 보정한다(§4.1, 구현됨).

6. ~~인덱스 색이 덤프에서 누락된다~~ — **오진이었다. 색은 온전히 보존된다.**

   `grep 31m`으로 찾다가 못 찾고 "누락"이라 결론냈는데, 애초에 `31m` 형태로 나올 리가 없었다.
   ghostty의 `ScreenFormatter`는 팔레트를 받아 **인덱스 색을 RGB로 풀어서** 뱉는다:

   ```
   원본 덤프:  \e[38;2;210;15;57m IDX_RED     ← 팔레트 1(빨강)이 트루컬러로 변환됨
   저장 파일:  \e[38;2;210;15;57m IDX_RED     ← 그대로 보존
   ```

   덤프에 실려오는 OSC는 `10`(fg)·`11`(bg) 둘뿐이고, `stripThemeOSC`가 그 둘만 걷어낸다 —
   정확히 의도대로다. 이걸 재주입하면 캡처 당시 테마의 fg/bg가 강제돼 다크로 바꾼 뒤 복원할 때
   흰 배경에 흰 글자가 된다. 셀 색은 이미 RGB로 해석돼 있어 영향받지 않는다.

   **R2는 인덱스 색까지 완전히 동작한다.**

**정리 대상 (조사 중 발견)**

- `~/Library/Application Support/muxa/`에 `state.v1/v2/v3.json` 잔재가 남아 있다. v5 도입 시 정리.
- `docs/DESIGN.md:98`이 아직 `state.v3.json`이라고 적혀 있다(실제 v4).
- `scripts/install-integration.sh:202`가 심는 rc 스니펫은 현재 no-op이다(env 미주입).
  R2에서 되살아나지만, 스니펫 안의 `rm -f`는 제거해야 한다 (§4.2).
