#!/usr/bin/env bash
# muxa.app 번들 조립 — SPM은 실행파일만 내므로 .app 구조를 손으로 만든다.
# bare 실행과 달리 번들이면 (1) Finder/Dock에 .icns 아이콘, (2) bundleIdentifier가 생겨
# UNUserNotificationCenter 시스템 알림이 동작한다(NotificationService의 번들 가드).
#
#   ./scripts/build-app.sh            # debug 번들
#   ./scripts/build-app.sh release    # release 번들
#   open macos/.build/<config>/muxa.app
set -euo pipefail
cd "$(dirname "$0")/../macos"

CONFIG="${1:-debug}"
if [ "$CONFIG" = "release" ]; then
  swift build -c release
  BIN=.build/release
else
  swift build
  BIN=.build/debug
fi

# ── 빌드 식별자 ───────────────────────────────────────────────────────────
# 워크트리마다 개발빌드를 띄우면 Dock·⌘Tab에 전부 "muxa"로 떠서 어느 창이 어느 브랜치인지 알 수 없다.
# 그래서 개발빌드는 리포(=워크트리) 이름 또는 브랜치명을 앱 이름·번들 id·파일명에 박는다.
# 번들 id가 갈리면 알림 권한·LaunchServices 등록도 각각이라 창이 서로 섞이지 않는다.
if [ "$CONFIG" = "release" ]; then
  APP_NAME="muxa"
  BUNDLE_ID="com.muxa.app"
  APP_FILE="muxa"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
  LABEL="$(basename "${ROOT:-$PWD}")"
  # 메인 체크아웃(디렉터리명이 그냥 muxa)이면 이름이 안 갈리므로 브랜치명을 쓴다.
  if [ "$LABEL" = "muxa" ]; then
    LABEL="$(git branch --show-current 2>/dev/null || echo "dev")"
  fi
  # 파일명·번들 id에 쓸 수 있게 영숫자·하이픈만 남긴다.
  SLUG="$(printf '%s' "$LABEL" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')"
  [ -n "$SLUG" ] || SLUG="dev"
  APP_NAME="muxa · $SLUG"     # Dock·⌘Tab·메뉴바에 이 이름이 뜬다
  BUNDLE_ID="com.muxa.dev.$SLUG"
  APP_FILE="muxa-$SLUG"
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

echo "빌드 완료: macos/$APP"
echo "실행: open macos/$APP"
