#!/usr/bin/env bash
# muxa 원터치 설치 — clone → 터미널 코어 → 빌드 → /Applications.
#
# 붙여넣기 한 줄:
#   curl -fsSL https://raw.githubusercontent.com/yjun1806/muxa/main/scripts/install.sh | bash
#
# 재실행하면 git pull로 최신화(업그레이드 경로로도 쓴다).
# 설치 위치 바꾸기:  MUXA_DIR=~/code/muxa  앞에 붙여 실행.
set -euo pipefail

REPO="https://github.com/yjun1806/muxa.git"
DIR="${MUXA_DIR:-$HOME/Developer/muxa}"

# 스피너가 출력을 숨기므로, git이 자격증명 프롬프트로 조용히 멈추지 않게 막는다.
export GIT_TERMINAL_PROMPT=0

# ── 스타일: 터미널이면 색·스피너, 파이프/CI면 플레인 ─────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C=$'\033[36m'; G=$'\033[32m'; R=$'\033[31m'; D=$'\033[2m'; B=$'\033[1m'; Z=$'\033[0m'; TTY=1
else
  C=; G=; R=; D=; B=; Z=; TTY=
fi
trap 'printf "\033[?25h" 2>/dev/null || true' EXIT   # 커서 항상 복원

die() { printf '\n%s✗%s %s\n' "$R" "$Z" "$1" >&2; exit 1; }

# run_step "라벨" cmd…  — 출력은 숨기고 스피너를 돌린다. 실패할 때만 로그를 보여준다.
run_step() {
  local label="$1"; shift
  local log start=$SECONDS
  log="$(mktemp -t muxa-install)"
  if [ -z "$TTY" ]; then
    if "$@" >"$log" 2>&1; then
      printf '%s✓%s %s (%ss)\n' "$G" "$Z" "$label" "$((SECONDS-start))"; rm -f "$log"; return 0
    fi
    printf '%s✗%s %s\n' "$R" "$Z" "$label" >&2; tail -n 40 "$log" >&2; die "$label 실패 — 전체 로그: $log"
  fi
  "$@" >"$log" 2>&1 &
  local pid=$! fr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  printf '\033[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s%s%s %s %s(%ss)%s\033[K' "$C" "${fr:$((i%10)):1}" "$Z" "$label" "$D" "$((SECONDS-start))" "$Z"
    i=$((i+1)); sleep 0.1
  done
  printf '\033[?25h'
  if wait "$pid"; then
    printf '\r%s✓%s %s %s(%ss)%s\033[K\n' "$G" "$Z" "$label" "$D" "$((SECONDS-start))" "$Z"; rm -f "$log"
  else
    printf '\r%s✗%s %s\033[K\n' "$R" "$Z" "$label" >&2
    tail -n 40 "$log" >&2; die "$label 실패 — 전체 로그: $log"
  fi
}

# 버전은 앱(About·plist)과 같은 SSOT에서 뽑는다 — app-identity.sh가 태그·커밋 수에서 파생.
# 자식 프로세스로 실행하므로 이 스크립트의 set -euo를 상속하지 않아 안전하다.
version_at() {  # $1 = 리포 경로 → "0.2.0 (395)"
  ( cd "$1" 2>/dev/null && ./scripts/app-identity.sh release 2>/dev/null ) \
    | awk '/^version/{print $2, $3; exit}' || true
}

# ── 선행조건 (없으면 명령만 안내하고 중단 — 몰래 설치하지 않는다) ─────────────
[ "$(uname)" = Darwin ] || die "macOS 전용입니다."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || die "macOS 14 이상이 필요합니다 (현재 $(sw_vers -productVersion))."
command -v git  >/dev/null || die "git이 필요합니다 — 'xcode-select --install' 로 설치하세요."
command -v curl >/dev/null || die "curl이 필요합니다."
xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools가 필요합니다. 먼저:  xcode-select --install"
command -v swift >/dev/null || die "swift를 찾을 수 없습니다 — Xcode CLT 설치를 확인하세요."

# ── 실행 ────────────────────────────────────────────────────────────────────
printf '%smuxa%s installer   %s→ %s%s\n\n' "$B" "$Z" "$D" "$DIR" "$Z"

# 설치냐 업데이트냐 — 기존 muxa 리포가 있으면 업데이트, 옛 버전을 미리 기억해 둔다.
# $DIR이 git 리포라도 muxa가 아니면(엉뚱한 프로젝트) 건드리지 않고 중단한다.
MODE=install; OLD_VER=
if [ -d "$DIR/.git" ]; then
  case "$(git -C "$DIR" remote get-url origin 2>/dev/null)" in
    *yjun1806/muxa*) : ;;
    *) die "$DIR 는 muxa 리포가 아닙니다 — MUXA_DIR로 다른 위치를 지정하세요" ;;
  esac
  MODE=update; OLD_VER="$(version_at "$DIR")"
fi

# 버전은 태그에서 파생된다(git describe). shallow로 받으면 태그·커밋 수가 빠져
# APP_VERSION/APP_BUILD가 깨지므로 full clone 한다.
fetch_repo() {
  if [ -d "$DIR/.git" ]; then
    git -C "$DIR" pull --ff-only --tags --quiet
  elif [ -e "$DIR" ]; then
    echo "$DIR 가 이미 있는데 git 리포가 아닙니다 — MUXA_DIR로 다른 위치를 지정하세요" >&2
    return 1
  else
    mkdir -p "$(dirname "$DIR")"
    git clone "$REPO" "$DIR"
  fi
}

run_step "리포 가져오기"             fetch_repo
cd "$DIR"
NEW_VER="$(version_at "$DIR")"; NEW_VER="${NEW_VER:-unknown}"
if [ "$MODE" = update ] && [ "$OLD_VER" != "$NEW_VER" ]; then
  printf '  업데이트: %s → %s%s%s\n\n' "${OLD_VER:-?}" "$B" "$NEW_VER" "$Z"
elif [ "$MODE" = update ]; then
  printf '  버전: %s%s%s (이미 최신)\n\n' "$B" "$NEW_VER" "$Z"
else
  printf '  버전: %s%s%s\n\n' "$B" "$NEW_VER" "$Z"
fi

run_step "터미널 코어 내려받기"       ./scripts/bootstrap.sh
run_step "빌드 · /Applications 설치"  make release-install

[ "$MODE" = update ] && DONE="업데이트 완료" || DONE="설치 완료"
printf '\n%s✓ muxa %s %s%s — /Applications/muxa.app\n\n' "$G" "$NEW_VER" "$DONE" "$Z"
printf '  실행:            open -a muxa\n'
printf '  알림 연결(선택): 앱에서 %sInstall%s 버튼, 또는  make integrate\n' "$B" "$Z"
printf '  소스:            %s\n' "$DIR"

# tmux는 선택이지만 강력 권장 — 앱을 꺼도 세션이 살아남고(∞) 서비스 기능이 켜진다.
# 직접 설치하지 않는다(앱이 brew를 대신 실행하지 않는다) — 명령만 안내한다.
if ! command -v tmux >/dev/null 2>&1; then
  printf '\n%s권장%s tmux를 설치하면 앱을 꺼도 세션이 유지되고(∞) 서비스 기능이 켜집니다:\n' "$C" "$Z"
  printf '    brew install tmux\n'
fi
