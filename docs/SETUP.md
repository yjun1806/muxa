# muxa 개발 환경 세팅

새 macOS 머신에서 muxa를 빌드·실행하는 절차. 목표는 **머신이 바뀌어도 스크립트 하나로 동일한 환경**이 재현되는 것이다.

## 전제 도구

- macOS 14+ (Sonoma 이상)
- Xcode Command Line Tools — `xcode-select --install` (또는 Xcode). `xcrun`, `swift`, `ranlib` 사용
- `curl` (macOS 기본 포함)

Swift 툴체인은 Xcode/CLT에 포함된다. **zig는 필요 없다** — 터미널 코어는 소스에서 빌드하지 않고 prebuilt를 내려받는다.

## 세팅 (3단계)

```bash
./scripts/bootstrap.sh    # 1. GhosttyKit.xcframework 설치 (최초 1회)
cd macos
swift build               # 2. 빌드
.build/debug/muxa         # 3. 실행 (창이 뜬다)
```

`bootstrap.sh`는 멱등이다 — 이미 같은 버전이 설치돼 있으면 즉시 건너뛴다.

## 앱 번들(.app)로 빌드

`.build/debug/muxa` bare 실행은 창은 뜨지만 **Finder/Dock 아이콘이 없고 시스템 알림이 Dock 바운스로 폴백**한다(번들 id가 없어서). 정식 아이콘·시스템 알림을 쓰려면 `.app` 번들로 빌드한다.

```bash
./scripts/build-app.sh              # debug 번들 → macos/.build/debug/muxa.app
./scripts/build-app.sh release      # release 번들
open macos/.build/debug/muxa.app
```

SPM은 실행파일만 내므로 이 스크립트가 `Info.plist`(bundleId `com.muxa.app`)·`AppIcon.icns`·SPM 리소스 번들을 `.app` 구조로 조립하고 ad-hoc 서명한다. 앱 아이콘을 바꾸려면 `scripts/build-appicon/icon-gen.swift`(Core Graphics 드로잉, SVG 래스터라이저 의존 없음)를 고치고 `scripts/build-appicon/build.sh`를 돌린다 — `macos/AppIcon.icns` + `Resources/AppIcon.png`(런타임 Dock 아이콘)가 재생성된다.

## bootstrap.sh가 하는 일

터미널 코어는 libghostty이고, muxa는 그것을 `GhosttyKit.xcframework`로 임베딩한다. 이 프레임워크는 리포에 넣지 않는다(`vendor/`는 gitignore). 대신 스크립트가 확보한다.

1. cmux fork(`manaflow-ai/ghostty`)의 GitHub 릴리스에서 **고정 SHA**의 prebuilt xcframework(universal, ReleaseFast)를 내려받는다
2. `SHA256`으로 무결성을 검증한다 — 불일치 시 중단
3. `vendor/ghostty/macos/GhosttyKit.xcframework`에 설치한다 (`macos/GhosttyKit.xcframework` 심링크가 이곳을 가리킨다)
4. 내부 정적 라이브러리를 `libghostty-internal.a`로 rename하고 `Info.plist`를 맞춘다 — SPM은 xcframework 안 라이브러리 이름이 `lib*`여야 링크한다
5. `ranlib`로 심볼 인덱스를 리프레시한다 (Xcode 26 링커 요구)

prebuilt는 self-contained라 libintl·zlib·freetype·imgui 등 C/C++ 의존성을 아카이브에 모두 포함한다. 그래서 muxa는 xcframework 하나 + 시스템 프레임워크만 링크한다.

## ghostty 버전 업그레이드

`GhosttyKit`을 새 버전으로 올리려면 `scripts/bootstrap.sh` 상단의 두 값을 **함께** 바꾼다.

| 값 | 뜻 |
|---|---|
| `GHOSTTY_SHA` | cmux fork의 ghostty 커밋 SHA |
| `GHOSTTYKIT_SHA256` | 그 SHA의 prebuilt 아카이브 SHA256 |

두 값의 대응표는 cmux 리포 `scripts/ghosttykit-checksums.txt`(`<ghostty_sha> <sha256>`)에 있다. libghostty의 embed API는 "signatures in flux"라, 업그레이드는 muxa 소스가 새 C API와 맞는지 확인하는 의식적 이벤트로만 한다.

## 에이전트 통합 (muxa notify · 훅 · 스크롤백)

muxa는 에이전트(Claude Code 등)와 매끄럽게 물리는 세 기능을 갖췄지만, 셋 다 사용자 환경 설정이 있어야 켜진다. `scripts/install-integration.sh`가 이 세 관문을 한 번에 처리한다.

| 기능 | 무엇을 켜나 | 설정 위치 |
|---|---|---|
| **muxa-notify CLI** | 훅이 앱 소켓에 상태/재개 신호를 쓴다 | `~/.local/bin/muxa-notify` 심링크 |
| **Claude Code 훅** | 권한 대기·턴 완료를 결정론적으로 배지·알림에 반영 | `~/.claude/settings.json` |
| **스크롤백 재출력** | 세션 복원 시 이전 화면을 되살린다 | `~/.zshrc`·`~/.bashrc` |

### 사용법 — dry-run 먼저, 그다음 --apply

이 스크립트는 사용자 시스템 파일을 건드리므로 **기본이 dry-run**이다. 무엇을 바꿀지 먼저 눈으로 확인하고 `--apply`로 실제 적용한다.

```bash
./scripts/install-integration.sh              # 1. dry-run — 무엇을 할지 출력만
./scripts/install-integration.sh --apply       # 2. 실제 적용
./scripts/install-integration.sh --apply --resume   # (선택) 재개 훅까지
```

- **안전** — 파일 수정 전 항상 `*.bak.<timestamp>` 백업. **멱등**이라 여러 번 돌려도 심링크·훅·스니펫이 중복되지 않는다(이미 있으면 스킵).
- **바이너리 자동 탐지** — `macos/.build/release/muxa-notify`(우선) → `.build/debug/muxa-notify` 순. 둘 다 없으면 먼저 `cd macos && swift build`(릴리스는 `-c release`)하라고 안내하고 멈춘다.
- **jq** — `settings.json`은 jq가 있으면 기존 설정을 보존한 채 병합한다. 없으면 수동으로 붙일 JSON을 출력만 한다(`brew install jq`).

### 각 기능이 켜는 것

1. **muxa-notify 심링크** — 빌드 산물을 `~/.local/bin/muxa-notify`로 심링크한다. 훅은 이 이름(PATH)으로 CLI를 부른다. `~/.local/bin`이 PATH에 없으면 안내가 뜬다. 소켓 경로는 앱이 각 셸에 `MUXA_SOCK` env로 주입하므로 CLI 인자가 필요 없다. muxa-notify는 소켓 실패해도 exit 0이라 에이전트 흐름을 막지 않는다.

2. **Claude Code 훅** — `~/.claude/settings.json`의 `hooks`에 프리셋을 등록한다.
   - `Notification` → `muxa-notify --state waiting --category needs-permission` (권한/알림 대기)
   - `Stop` → `muxa-notify --state done --category turn-complete` (턴 완료)
   - `--resume` 시 `SessionStart`(matcher `resume`) → 세션 ID를 stdin JSON에서 뽑아 재개 명령을 탭에 바인딩

   > **주의(스키마 검증됨, 2026-07 기준 `code.claude.com/docs/en/hooks`)**: Claude Code는 `CLAUDE_SESSION_ID`를 env로 노출하지 **않는다**. `session_id`는 훅 stdin의 JSON으로만 온다. 그래서 재개 훅은 `jq -r .session_id`로 파싱해 `--resume-command`에 넣는다(런타임에 `jq` 필요). Notification/Stop 프리셋은 env·인자 의존이 없어 그대로 동작한다.

3. **스크롤백 재출력 스니펫** — `~/.zshrc`·`~/.bashrc`에 마커(`# >>> muxa scrollback restore >>>`)로 감싼 한 줄을 추가한다. muxa가 세션 복원 시 심는 `MUXA_RESTORE_SCROLLBACK_FILE`을 셸 시작에서 `cat`하고 지워 이전 화면을 되살린다.
