#!/usr/bin/env bash
# muxa.dmg 조립 — 드래그해서 /Applications에 바로 넣는 배포용 디스크 이미지.
# build-app.sh로 .app을 만든 뒤, [muxa.app | Applications 심볼릭 링크]를 담은 DMG를 굽는다.
#
#   ./scripts/build-dmg.sh            # debug 앱으로 DMG
#   ./scripts/build-dmg.sh release    # release 앱으로 DMG
#
# **배포하려면 서명 + 공증이 둘 다 필요하다.** 없으면 내려받은 사용자는 Gatekeeper에 막혀 앱을 열 수 없다:
#   CODESIGN_ID="Developer ID Application: … (TEAMID)" \
#   NOTARY_PROFILE="muxa"   # xcrun notarytool store-credentials 로 만든 키체인 프로필
#   ./scripts/build-dmg.sh release
# 둘 다 없으면 개발용 DMG다(README '설치'의 우회 절차가 필요하다).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
./scripts/build-app.sh "$CONFIG"

# 앱 이름은 app-identity.sh 단일 출처에서 받는다 — 개발 빌드는 muxa-dev-<slug>.app이라
# muxa.app으로 박아 두면 debug DMG가 통째로 깨진다.
# shellcheck source=app-identity.sh
source "scripts/app-identity.sh" "$CONFIG"

BIN="macos/$APP_BIN"
APP="$BIN/$APP_FILE.app"
VOL="$APP_NAME"
DMG="$BIN/muxa-$CONFIG.dmg"

# 스테이징 폴더에 앱 + /Applications 링크(드래그 대상)만 담는다.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
# UDZO = 압축 이미지. 볼륨을 열면 앱을 Applications로 끌어 넣게 된다.
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

# 공증 — 프로필이 있을 때만. DMG를 제출하고 티켓을 붙인다(stapler). 이게 있어야 오프라인에서도
# Gatekeeper가 통과시킨다. 실패하면 중단한다(공증 안 된 DMG가 배포되면 사용자가 앱을 못 연다).
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "공증 완료(티켓 첨부): $DMG"
else
  echo "  경고: 공증하지 않았다 — 내려받은 사용자는 Gatekeeper에 막힌다(README '설치' 참고)." >&2
fi

echo "빌드 완료: $DMG"
echo "열기: open $DMG  →  $APP_FILE.app을 Applications로 드래그"
