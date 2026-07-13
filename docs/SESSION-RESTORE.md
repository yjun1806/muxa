# 세션 복원 설계 (Session Restore)

muxa의 세션 복원 전체 설계. [ARCHITECTURE.md](ARCHITECTURE.md) §4.2의 "세션 지속성"을 대체·확장한다.
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

**에이전트 다변화**: `commNames: ["claude"]`, `~/.claude/projects` 하드코딩을 테이블로 뺀다.

```swift
struct AgentSpec {
    let id: String              // "claude" | "codex" | "gemini" | ...
    let commNames: [String]     // 프로세스 감지용
    let resumeArgv: (String) -> [String]   // sessionId -> argv
}
// claude → ["claude", "--resume", id]      codex → ["codex", "resume", id]
// gemini → ["gemini", "--resume", id]      opencode → ["opencode", "--session", id]
```

세션 ID 검증은 유지·강화(길이 상한, `-` 시작 금지, 제어문자 금지 — argv 인젝션 방어).

**cwd 네임스페이싱**: `claude --resume`은 프로젝트 디렉터리 기준으로 트랜스크립트를 찾으므로,
재개 명령 앞에 `cd`를 붙여야 한다. cmux가 fish 호환까지 고려해 쓰는 형태를 따른다:

```
cd -- '<cwd>' 2>/dev/null || [ ! -d '<cwd>' ] && <resume-cmd>
```

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
소유한다(ARCHITECTURE.md 불변식 1). PTY를 데몬으로 빼면 서피스는 껍데기가 되고, VT 파싱·리플로우·
스크롤백을 우리가 다시 구현해야 한다 — v1에서 Rust 코어를 버리고 libghostty로 간 이유를 정면으로 되돌리는 일이다.

**결정: 셸 대신 `tmux`를 띄운다.** 같은 효과를 아키텍처를 건드리지 않고 얻는다.

```swift
// 탭 spawn 시 (persistentSessions = true 일 때)
command = "tmux new-session -A -s muxa-\(tabId) -c \(cwd)"
```

- `-A` = 있으면 attach, 없으면 create. **앱을 껐다 켜도 같은 명령이 그대로 재부착된다**
- tmux가 PTY·프로세스·스크롤백·alt-screen·모드를 전부 보존한다 — 우리가 만들 필요가 없다
- 돌던 빌드도, `claude`도, `tail -f`도 **그대로 이어진다.** 재개 명령도 스크롤백 리플레이도 불필요
- 재부팅하면 tmux 서버도 죽는다 → 자동으로 L2로 강등(스크롤백 리플레이)

### 5.2 대가 (정직하게)

| 문제 | 대응 |
|---|---|
| tmux 미설치 | 실행 시 `which tmux` 확인, 없으면 조용히 L2로 폴백 |
| prefix 키(`C-b`) 충돌 | muxa 전용 `-f` 설정 파일 제공: prefix 해제, status bar off, mouse on |
| 스크롤백 이중 관리 | tmux 세션에서는 muxa 스크롤백 캡처를 **끈다**(tmux가 소유) |
| ⌘F 검색 | ghostty 네이티브 검색은 뷰포트/스크롤백 기준 — tmux copy-mode와 별개로 그대로 동작 |
| OSC 7 cwd 추적 | tmux가 OSC 7을 통과시킨다(`set -g allow-passthrough`), 검증 필요 ★ |
| 고아 세션 누적 | 앱 시작 시 `tmux ls`로 `muxa-*` 스캔 → 스냅샷에 없는 세션은 kill (GC) |
| 성능 | tmux가 VT를 한 번 더 파싱 → 대량 출력 시 오버헤드. 실측 필요 ★ |

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
| **R1** | 창 프레임 복원 · state 백업/부분 폴백 · manualTitle 스키마 (§3.1–3.3) | 창을 옮기고 재시작 → 같은 위치. state.json을 손상시켜도 워크스페이스는 남고 경고가 뜬다 |
| **R2** | VT 스크롤백 (§4.1–4.5) — 캡처·클립보드 가로채기·rc 훅 재주입·테마 위생·alt-screen 가드 | `git diff` 출력 후 재시작 → 초록/빨강이 그대로. 다크↔라이트 전환 후 복원해도 안 깨짐. 캡처 전후로 **클립보드 내용이 그대로다** |
| **R3** | 에이전트 재개 신뢰도 (§3.4–3.5) — 훅 바인딩 1순위, AgentSpec 테이블, OSC 133 대기 | 두 프로젝트에서 claude 동시 실행 → 각 탭이 **자기** 세션으로 재개. 훅 없는 codex는 배너로 확인받음 |
| **R4** | tmux 백엔드 (§5) — opt-in | `persistent = true` + `sleep 300` 실행 → 앱 재시작 → sleep이 **계속 돌고 있다** |

R1은 하루 안쪽, R2는 1~2일, R3은 이틀, R4는 실측(★)에 따라 달라진다.
(당초 "저장 경로 분리"를 R3으로 뒀으나 실측 결과 폐기 — §4.6)

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
   상한은 유지하되, **꼬리 자르기가 이스케이프 시퀀스 중간을 끊지 않도록** 하는 보정(§4.1)이
   없으면 복원 화면이 깨진다. 지금 `capBytes`는 바이트 단위로 무작정 자른다.

**정리 대상 (조사 중 발견)**

- `~/Library/Application Support/muxa/`에 `state.v1/v2/v3.json` 잔재가 남아 있다. v5 도입 시 정리.
- `docs/ARCHITECTURE.md:98`이 아직 `state.v3.json`이라고 적혀 있다(실제 v4).
- `scripts/install-integration.sh:202`가 심는 rc 스니펫은 현재 no-op이다(env 미주입).
  R2에서 되살아나지만, 스니펫 안의 `rm -f`는 제거해야 한다 (§4.2).
