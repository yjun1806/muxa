#!/usr/bin/env bash
# 이 워크트리의 개발 앱만 종료 — 릴리스·다른 워크트리는 절대 안 건드린다 (정상 종료).
# 실행파일명 muxa-dev-<slug>는 유니크 — bare(상대경로)·번들 둘 다 잡고,
# 릴리스 muxa·muxa-notify·다른 slug는 이 문자열을 포함하지 않아 안 걸린다.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# shellcheck source=app-identity.sh
source scripts/app-identity.sh debug

if pkill -TERM -f "$APP_FILE"; then
  echo "종료: $APP_FILE"
else
  echo "실행 중 아님: $APP_FILE"
fi
