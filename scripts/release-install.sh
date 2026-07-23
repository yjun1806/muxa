#!/usr/bin/env bash
# 프로덕션(release) 빌드 후 /Applications에 설치 — 릴리스 muxa.app.
# 한 줄 설치 `scripts/install.sh`가 clone·bootstrap을 마친 뒤 이걸 부른다.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

./scripts/build-app.sh release

# shellcheck source=app-identity.sh
source scripts/app-identity.sh release

SRC="macos/.build/release/$APP_FILE.app"
DST="/Applications/$APP_FILE.app"
echo "설치: $SRC → $DST"
rm -rf "$DST"
cp -R "$SRC" "$DST"
echo "완료: $DST  — 실행: open \"$DST\""
