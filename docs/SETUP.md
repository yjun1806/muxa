# muxa 개발 환경 세팅

새 macOS 머신에서 muxa를 빌드·실행하는 절차. 목표는 **머신이 바뀌어도 스크립트 하나로 동일한 환경**이 재현되는 것이다. 일상 작업은 전부 `make`로 감싸져 있다 — `make help`로 목록을 본다.

## 전제 도구

- macOS 14+ (Sonoma 이상)
- Xcode Command Line Tools — `xcode-select --install` (또는 Xcode). `xcrun`, `swift`, `ranlib` 사용
- `curl` (macOS 기본 포함)

Swift 툴체인은 Xcode/CLT에 포함된다. **zig는 필요 없다** — 터미널 코어는 소스에서 빌드하지 않고 prebuilt를 내려받는다.

## 세팅 (2단계)

```bash
make bootstrap    # 1. GhosttyKit.xcframework 설치 (최초 1회)
make dev          # 2. .app 번들로 빌드·실행 (권장 — 아이콘·시스템 알림 정상)
```

`make bootstrap`은 멱등이다 — 이미 같은 버전이 설치돼 있으면 즉시 건너뛴다. 내부적으로는 `cd macos && swift build`일 뿐이라 raw로도 된다:

```bash
make build        # = cd macos && swift build
make test         # 순수 로직 단위 테스트
```

## 앱 번들(.app)로 빌드

`.build/debug/…`를 직접 실행하면(bare) 창은 뜨지만 **번들 id가 없어 Finder/Dock 아이콘이 없고 시스템 알림이 Dock 바운스로 폴백**한다. 정식 아이콘·시스템 알림을 쓰려면 `.app` 번들로 빌드한다.

```bash
make dev          # debug 번들 빌드·실행 (개발)
make release-install      # release 번들 → /Applications 설치 (프로덕션, 재시작해야 반영)
```

`make dev`은 `scripts/build-app.sh`를 부른다. SPM은 실행파일만 내므로 이 스크립트가 `Info.plist`·`AppIcon.icns`·SPM 리소스 번들을 `.app` 구조로 조립하고 ad-hoc 서명한다.

이름·번들 id·실행파일명은 **`scripts/app-identity.sh` 단일 출처**에서 온다 — dev와 prod가 이름만 봐도 완전히 갈린다:

| | 실행파일(ps/pgrep) | 번들 id | Dock/⌘Tab |
|---|---|---|---|
| 릴리스 | `muxa` | `com.muxa.app` | `muxa` |
| 개발 | `muxa-dev-<slug>` | `com.muxa.dev.<slug>` | `Muxa Dev · <slug>` |

`<slug>`는 워크트리 디렉터리 이름(메인 체크아웃이면 브랜치명). 여러 muxa를 동시에 띄워도 안 헷갈리고, **엉뚱한 인스턴스를 죽이지 않는다**. 이 워크트리 것만 확인·종료하려면 `make whoami` / `make dev-kill`(릴리스·타 워크트리 불가침). 앱 아이콘을 바꾸려면 `scripts/build-appicon/`(Core Graphics 드로잉, SVG 래스터라이저 의존 없음)을 고치고 `make icons`를 돌린다 — `macos/AppIcon.icns` + `Resources/AppIcon.png`(런타임 Dock 아이콘)가 재생성된다.

## 워크트리에서 개발

새 개발 워크트리는 **반드시 `make worktree`로 만든다** — `git worktree add`만 쓰면 빌드가 깨진다.

```bash
make worktree BRANCH=feat/foo
```

이유: 추적되는 심링크 `macos/GhosttyKit.xcframework → ../vendor/ghostty/…`가 gitignore된 `vendor/`를 가리키는데, 새 워크트리엔 `vendor/`가 없어 심링크가 끊긴다. `make worktree`(= `scripts/new-worktree.sh`)가 메인의 `vendor/`를 심링크로 이어주거나(빠름·재다운로드 없음) 없으면 bootstrap을 돌려 곧바로 빌드되게 한다. `.build/`는 워크트리마다 따로여야 하므로 안 건드린다(첫 빌드 콜드는 정상).

## bootstrap이 하는 일

터미널 코어는 libghostty이고, muxa는 그것을 `GhosttyKit.xcframework`로 임베딩한다. 이 프레임워크는 리포에 넣지 않는다(`vendor/`는 gitignore). 대신 스크립트가 확보한다.

1. cmux fork(`manaflow-ai/ghostty`)의 GitHub 릴리스에서 **고정 SHA**의 prebuilt xcframework(universal, ReleaseFast)를 내려받는다
2. `SHA256`으로 무결성을 검증한다 — 불일치 시 중단
3. `vendor/ghostty/macos/GhosttyKit.xcframework`에 설치한다 (`macos/GhosttyKit.xcframework` 심링크가 이곳을 가리킨다)
4. 내부 정적 라이브러리를 `libghostty-internal.a`로 rename하고 `Info.plist`를 맞춘다 — SPM은 xcframework 안 라이브러리 이름이 `lib*`여야 링크한다
5. `ranlib`로 심볼 인덱스를 리프레시한다 (Xcode 26 링커 요구)

prebuilt는 self-contained라 libintl·zlib·freetype·imgui 등 C/C++ 의존성을 아카이브에 모두 포함한다. 그래서 muxa는 xcframework 하나 + 시스템 프레임워크만 링크한다.

## ghostty 버전 업그레이드

`GhosttyKit`을 새 버전으로 올리려면 `scripts/bootstrap.sh` 상단의 pin 값을 바꾼다.

| 값 | 뜻 |
|---|---|
| `GHOSTTY_SHA` | cmux fork의 ghostty 커밋 SHA |
| `GHOSTTYKIT_SHA256` | 그 SHA의 prebuilt 아카이브 SHA256 |
| `BUILD_FLAVOR` | 릴리스 태그 접미사(prebuilt 빌드 flavor) — 보통 그대로, cmux가 바꿀 때만 갱신 |

`GHOSTTY_SHA`·`GHOSTTYKIT_SHA256` 대응표는 cmux 리포 `scripts/ghosttykit-checksums.txt`(`<ghostty_sha> <sha256>`)에 있다. libghostty의 embed API는 "signatures in flux"라, 업그레이드는 muxa 소스가 새 C API와 맞는지 확인하는 의식적 이벤트로만 한다.

## 에이전트 통합 (muxa notify · 훅 · 스크롤백)

muxa는 에이전트(Claude Code 등)와 매끄럽게 물리는 세 기능을 갖췄지만, 셋 다 사용자 환경 설정이 있어야 켜진다. `make integrate`(= `scripts/integrate.sh`)가 이 세 관문을 한 번에 처리한다.

| 기능 | 무엇을 켜나 | 설정 위치 |
|---|---|---|
| **muxa-notify CLI** | 훅이 앱 소켓에 상태 신호를 쓴다 | `~/.local/bin/muxa-notify` (복사) |
| **Claude Code 훅** | 진행·권한 대기·턴 완료를 배지·알림에 반영 | `~/.claude/settings.json` |
| **스크롤백 재출력** | 세션 복원 시 이전 화면을 되살린다 | `~/.zshrc`·`~/.bashrc` |

### 사용법 — dry-run 먼저, 그다음 --apply

이 스크립트는 사용자 시스템 파일을 건드리므로 **기본이 dry-run**이다. 무엇을 바꿀지 먼저 눈으로 확인하고 `--apply`로 실제 적용한다.

```bash
make integrate                                # 1. dry-run — 무엇을 할지 출력만
./scripts/integrate.sh --apply       # 2. 실제 적용
```

- **안전** — 파일 수정 전 항상 `*.bak.<timestamp>` 백업. **멱등**이라 여러 번 돌려도 심링크·훅·스니펫이 중복되지 않는다(이미 있으면 스킵).
- **바이너리 자동 탐지** — `macos/.build/release/muxa-notify`(우선) → `.build/debug/muxa-notify` 순. 둘 다 없으면 먼저 `make build`(릴리스는 `cd macos && swift build -c release`)하라고 안내하고 멈춘다.
- **jq** — `settings.json` 병합에 **설치 시점에만** 필요하다(런타임 의존은 없다). 없으면 수동으로 붙일 JSON을 출력만 한다(`brew install jq`).

### 각 기능이 켜는 것

1. **muxa-notify 설치** — 빌드 산물을 `~/.local/bin/muxa-notify`로 **복사**한다(심링크가 아니다 — 워크트리 전환·재빌드로 원본이 사라져도 훅이 안 깨진다). 훅은 이 이름(PATH)으로 CLI를 부른다. `~/.local/bin`이 PATH에 없으면 안내가 뜬다. 소켓 경로는 앱이 각 셸 환경에 주입하므로 CLI 인자가 필요 없고, 소켓 실패해도 exit 0이라 에이전트 흐름을 막지 않는다.

2. **Claude Code 훅** — `~/.claude/settings.json`의 `hooks`에 **7개 이벤트**를 등록한다: `SessionStart` · `UserPromptSubmit` · `PreToolUse` · `Notification` · `Stop` · `SubagentStart` · `SubagentStop`. 명령은 전부 같은 꼴이다:

   ```sh
   if [ -x '<경로>/muxa-notify' ]; then '<경로>/muxa-notify' hook --event <Event>; fi
   ```

   **분류·게이팅은 전부 앱이 한다** — 훅은 stdin payload를 해석하지 않고 그대로 넘긴다(`hook --event <E>`). 그래서:
   - 훅 로직이 사용자 `settings.json`에 박히지 않아 **앱 업데이트로 고칠 수 있다**.
   - **런타임 jq 의존이 없다** — 세션 ID·배경 작업 판정 모두 앱이 payload에서 읽는다.
   - `PostToolUse`는 일부러 뺐다(PreToolUse만으로 진행 표시가 충분하고, `tool_response` 전문이 소켓 버퍼를 넘긴다).
   - **존재 가드**로 감싸므로, 바이너리를 지워도 muxa 밖 claude 세션이 매 도구 호출마다 "command not found"를 뱉지 않는다(없으면 조용히 exit 0).

   > 예전의 `--resume` 플래그는 **이제 불필요**하다 — `SessionStart` 훅이 기본으로 포함되고, 세션 재개는 앱이 payload에서 세션 ID를 읽어 처리한다. (Claude Code는 `CLAUDE_SESSION_ID`를 env로 노출하지 않고 `session_id`는 훅 stdin JSON으로만 오는데, 그 파싱을 훅이 아니라 앱이 한다.)

3. **스크롤백 재출력 스니펫** — `~/.zshrc`·`~/.bashrc`에 마커(`# >>> muxa scrollback restore >>>`)로 감싼 한 줄을 추가한다. muxa가 세션 복원 시 심는 `MUXA_RESTORE_SCROLLBACK_FILE`을 셸 시작에서 `cat`하고 지워 이전 화면을 되살린다.
