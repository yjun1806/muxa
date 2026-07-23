#!/usr/bin/env bash
# muxa 원터치 설치 — clone → GhosttyKit 부트스트랩 → 빌드 → /Applications 설치.
#
# 붙여넣기 한 줄:
#   curl -fsSL https://raw.githubusercontent.com/yjun1806/muxa/main/scripts/install.sh | bash
#
# 또는 이미 clone 했다면 리포 안에서:  ./scripts/install.sh
#
# 멱등: 다시 실행하면 git pull로 최신화 후 재빌드(업그레이드 경로로도 쓴다).
# 설치 위치 바꾸기:  MUXA_DIR=~/code/muxa  앞에 붙여 실행.
set -euo pipefail

REPO="https://github.com/yjun1806/muxa.git"
DIR="${MUXA_DIR:-$HOME/Developer/muxa}"

say()  { printf '\033[36m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# ── 선행조건 검사 (없으면 명령만 안내하고 중단 — 몰래 설치하지 않는다) ──────────
[[ "$(uname)" == "Darwin" ]] || die "macOS 전용입니다."

# macOS 14+ (Sonoma). sw_vers는 예: 14.5 → major만 본다.
OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$OS_MAJOR" -ge 14 ]] || die "macOS 14 이상이 필요합니다 (현재 $(sw_vers -productVersion))."

command -v git  >/dev/null || die "git이 필요합니다 — 'xcode-select --install' 로 설치하세요."
command -v curl >/dev/null || die "curl이 필요합니다."

# Xcode Command Line Tools — swift/make/xcrun이 여기서 온다.
if ! xcode-select -p >/dev/null 2>&1; then
  die "Xcode Command Line Tools가 필요합니다. 먼저 실행하세요:  xcode-select --install"
fi
command -v swift >/dev/null || die "swift를 찾을 수 없습니다 — Xcode CLT 설치를 확인하세요."

# ── clone 또는 업데이트 ────────────────────────────────────────────────────
if [[ -d "$DIR/.git" ]]; then
  say "이미 있는 리포 최신화: $DIR"
  git -C "$DIR" pull --ff-only
else
  [[ -e "$DIR" ]] && die "$DIR 가 이미 있는데 git 리포가 아닙니다. MUXA_DIR로 다른 위치를 지정하세요."
  say "clone: $REPO → $DIR"
  mkdir -p "$(dirname "$DIR")"
  git clone --depth 1 "$REPO" "$DIR"
fi

cd "$DIR"

# ── 터미널 코어 설치 + 빌드 + /Applications 설치 ──────────────────────────────
say "GhosttyKit 부트스트랩 (최초 1회 다운로드)"
./scripts/bootstrap.sh

say "빌드 · /Applications 설치 (몇 분 걸립니다)"
make release-install

cat <<'DONE'

✅ 설치 완료 — /Applications/muxa.app

  실행:            open -a muxa
  알림 연결(선택): 앱 안에서 'Install' 버튼, 또는  make integrate

소스는 여기에 있습니다:
DONE
printf '  %s\n' "$DIR"
