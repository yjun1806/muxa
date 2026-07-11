#!/usr/bin/env bash
# muxa.dmg 조립 — 드래그해서 /Applications에 바로 넣는 배포용 디스크 이미지.
# build-app.sh로 .app을 만든 뒤, [muxa.app | Applications 심볼릭 링크]를 담은 DMG를 굽는다.
#
#   ./scripts/build-dmg.sh            # debug 앱으로 DMG
#   ./scripts/build-dmg.sh release    # release 앱으로 DMG(배포용)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
./scripts/build-app.sh "$CONFIG"

BIN="macos/.build/$CONFIG"
APP="$BIN/muxa.app"
VOL="muxa"
DMG="$BIN/muxa-$CONFIG.dmg"

# 스테이징 폴더에 앱 + /Applications 링크(드래그 대상)만 담는다.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
# UDZO = 압축 이미지. 볼륨을 열면 muxa.app을 Applications로 끌어 넣게 된다.
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "빌드 완료: $DMG"
echo "열기: open $DMG  →  muxa.app을 Applications로 드래그"
