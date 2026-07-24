#!/usr/bin/env bash
# muxa.app 번들 조립 — SPM은 실행파일만 내므로 .app 구조를 손으로 만든다.
# bare 실행과 달리 번들이면 (1) Finder/Dock에 .icns 아이콘, (2) bundleIdentifier가 생겨
# UNUserNotificationCenter 시스템 알림이 동작한다(NotificationService의 번들 가드).
#
#   ./scripts/build-app.sh            # debug 번들
#   ./scripts/build-app.sh release    # release 번들
#   open macos/.build/<config>/muxa-dev-<slug>.app   (개발)  ·  muxa.app (릴리스)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../macos"

CONFIG="${1:-debug}"

# ── 빌드 식별자 — 이름 규칙은 app-identity.sh 한 곳에서만 정한다(단일 출처) ────────────
# dev/prod가 이름만 봐도 완전히 갈린다: 릴리스 `muxa`, 개발 `muxa-dev-<slug>`.
# 번들 id도 갈려(com.muxa.app vs com.muxa.dev.<slug>) 알림 권한·LaunchServices 등록이 각각이라
# 창·프로세스가 서로 섞이지 않는다. → docs/SETUP.md, 종료는 `make dev-kill`(이 워크트리 것만).
# shellcheck source=app-identity.sh
source "$SCRIPT_DIR/app-identity.sh" "$CONFIG"
BIN="$APP_BIN"

# 자기-업데이트가 되돌아올 소스 저장소 루트 — 워크트리·커스텀 MUXA_DIR도 정확히 잡게 git에 묻는다.
SOURCE_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"

if [ "$CONFIG" = "release" ]; then
  swift build -c release
else
  swift build
fi

APP="$BIN/$APP_FILE.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 실행파일 + 앱 아이콘(.icns)
# 실행 파일명이 곧 Dock·⌘Tab·ps에 뜨는 이름이다(CFBundleName이 아니라). 빌드별로 갈라야 구분된다.
cp "$BIN/muxa" "$APP/Contents/MacOS/$APP_FILE"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 훅 CLI — 앱이 실행 파일 옆에서 찾아 Application Support로 복사한다(ClaudeHookInstaller).
# 번들에 없으면 인앱 훅 설치가 "muxa-notify를 찾을 수 없다"로 실패한다.
cp "$BIN/muxa-notify" "$APP/Contents/MacOS/muxa-notify"

# SPM 리소스 번들(muxa_muxa·Bonsplit_Bonsplit) — Bundle.module이 Contents/Resources에서 찾는다.
for b in "$BIN"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_FILE</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
    <key>CFBundleVersion</key><string>$APP_BUILD</string>
    <!-- 자기-업데이트가 pull·재빌드할 소스 저장소 루트 — 릴리스 앱은 /Applications에 있어
         번들 경로만으론 소스 위치를 모른다. 여기 구워두면 AppInfo.sourceRoot가 그대로 읽는다. -->
    <key>MUXASourceRoot</key><string>$SOURCE_ROOT</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>muxa</string>
    <!-- TCC 프롬프트 문구 — 사용자가 프로젝트를 여는 곳이 정확히 이 폴더들이다.
         설명이 없으면 macOS가 이유 없는 접근 요청을 띄우고, 사용자는 거부한다. -->
    <key>NSDocumentsFolderUsageDescription</key><string>muxa가 이 폴더의 프로젝트를 열고 git 상태를 읽습니다.</string>
    <key>NSDesktopFolderUsageDescription</key><string>muxa가 이 폴더의 프로젝트를 열고 git 상태를 읽습니다.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>muxa가 이 폴더의 프로젝트를 열고 git 상태를 읽습니다.</string>
</dict>
</plist>
PLIST

# ── 코드 서명 ────────────────────────────────────────────────────────────────
# 기본은 ad-hoc(`-`) — 개발 실행용이고 Gatekeeper는 이걸 거부한다(배포 불가).
# 배포는 Developer ID를 넣는다:
#   CODESIGN_ID="Developer ID Application: … (TEAMID)" ./scripts/build-dmg.sh release
#   → 이어서 notarytool submit --wait + stapler staple 이 필요하다(docs/SETUP.md).
#
# **`--deep`을 쓰지 않는다.** Apple이 배포 서명에 비권장한다 — 중첩 실행파일에 상위의 식별자·
# entitlements가 상속되고 서명 순서가 안쪽→바깥쪽이 아니라, 공증에서 거부되는 대표 원인이다.
# 그래서 중첩 실행파일(muxa-notify) → .app 루트 순으로 **하나씩** 서명한다.
# SPM 리소스 번들(muxa_muxa·Bonsplit_Bonsplit)은 **실행 코드가 없는 평평한 리소스 디렉터리**라
# 개별 서명 대상이 아니다(codesign이 "bundle format unrecognized"로 거부한다) — 앱 루트 서명의
# CodeResources 봉인이 그대로 덮는다.
# 서명 정체성 결정. 명시 지정(CODESIGN_ID)이 없으면 로컬 self-signed 인증서를 찾고, 그것도 없으면 ad-hoc.
# **로컬 인증서를 자동으로 쓰는 이유**: ad-hoc은 재빌드마다 정체성이 바뀌어 TCC(문서 폴더 접근) 권한이
# 리셋된다 — "허용"을 눌러도 재설치하면 또 묻는다. self-signed는 designated requirement가 인증서 leaf에
# 고정돼 재빌드해도 권한이 유지된다. 인증서는 scripts/create-signing-cert.sh가 한 번 만든다.
LOCAL_CERT="muxa Local Signing"
if [ -z "${CODESIGN_ID:-}" ]; then
  if security find-certificate -c "$LOCAL_CERT" >/dev/null 2>&1; then
    CODESIGN_ID="$LOCAL_CERT"
  else
    CODESIGN_ID="-"
  fi
fi
SIGN_FLAGS=(--force --sign "$CODESIGN_ID")
# 하드닝 런타임·보안 타임스탬프는 **공증(Developer ID 배포)** 의 필수 조건이다. ad-hoc에는 붙일 수 없고
# (타임스탬프 서버가 서명자를 요구한다), 로컬 self-signed에도 불필요하다(오프라인이면 타임스탬프가 실패한다).
# Developer ID일 때만 준다.
case "$CODESIGN_ID" in
  "Developer ID Application:"*) SIGN_FLAGS+=(--options runtime --timestamp) ;;
esac

sign_all() {
  codesign "${SIGN_FLAGS[@]}" "$APP/Contents/MacOS/muxa-notify" || return 1
  codesign "${SIGN_FLAGS[@]}" "$APP" || return 1
}

if ! sign_all; then
  # 릴리스에서 조용히 넘어가면 **무서명 DMG가 그대로 나간다**(나갔는지조차 알 수 없다) — 즉시 중단.
  [ "$CONFIG" = "release" ] && { echo "코드 서명 실패 — 무서명 릴리스는 배포할 수 없다." >&2; exit 1; }
  echo "  (codesign 생략 — 개발 실행엔 영향 없음)"
fi

# 검증 게이트 — 릴리스는 서명이 실제로 유효한지 확인하고 실패면 중단한다.
if [ "$CONFIG" = "release" ]; then
  codesign --verify --strict --verbose=2 "$APP" || { echo "서명 검증 실패 — 중단." >&2; exit 1; }
  if [ "$CODESIGN_ID" = "-" ]; then
    echo "  경고: ad-hoc 서명이다 — 재빌드마다 TCC 권한이 리셋돼 문서 폴더 접근 프롬프트가 반복된다." >&2
    echo "  로컬은 './scripts/create-signing-cert.sh' 한 번이면 해결된다. 배포는 Developer ID + 공증." >&2
  elif [ "$CODESIGN_ID" = "$LOCAL_CERT" ]; then
    echo "  로컬 self-signed 서명('$LOCAL_CERT') — 재빌드해도 TCC 권한이 유지된다. 배포는 Developer ID + 공증." >&2
  else
    # 공증 전에는 rejected가 정상이다(참고용 출력 — 여기서 중단하지 않는다).
    spctl -a -t exec -vv "$APP" || true
  fi
fi

# LaunchServices에 강제 재등록 — 같은 slug를 다시 빌드해 CFBundleName이 바뀌어도 Dock·⌘Tab이
# 옛 이름을 캐시해 안 바뀌는 걸 막는다. 이게 없으면 "아무리 빌드해도 이름이 그대로"가 된다.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" 2>/dev/null || true

echo "빌드 완료: macos/$APP   ($APP_NAME · $BUNDLE_ID · $APP_VERSION ($APP_BUILD))"
echo "실행: open macos/$APP"
