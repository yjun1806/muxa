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
