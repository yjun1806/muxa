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
# 창·프로세스가 서로 섞이지 않는다. → docs/SETUP.md, 종료는 `make kill`(이 워크트리 것만).
# shellcheck source=app-identity.sh
source "$SCRIPT_DIR/app-identity.sh" "$CONFIG"
BIN="$APP_BIN"

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
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# ad-hoc 코드 서명 — 미서명 실행 경고·일부 시스템 API 제약을 줄인다(배포 서명 아님).
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign 생략 — 실행엔 영향 없음)"

# LaunchServices에 강제 재등록 — 같은 slug를 다시 빌드해 CFBundleName이 바뀌어도 Dock·⌘Tab이
# 옛 이름을 캐시해 안 바뀌는 걸 막는다. 이게 없으면 "아무리 빌드해도 이름이 그대로"가 된다.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" 2>/dev/null || true

echo "빌드 완료: macos/$APP   ($APP_NAME · $BUNDLE_ID)"
echo "실행: open macos/$APP"
