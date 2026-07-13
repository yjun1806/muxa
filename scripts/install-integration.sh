#!/usr/bin/env bash
# muxa 에이전트 통합 설치 — 세 관문을 한 번에 켠다.
#
#   1) muxa-notify 바이너리를 PATH(~/.local/bin)에 심링크 — 훅이 이 이름으로 호출한다.
#   2) Claude Code 훅(~/.claude/settings.json) 등록 — 결정론적 상태/재개 신호.
#   3) 스크롤백 재출력 rc 스니펫(~/.zshrc·~/.bashrc) — 세션 복원 시 이전 화면을 되살린다.
#
# 안전 최우선:
#   • 기본은 dry-run(무엇을 할지 출력만). 실제 수정은 --apply 를 줄 때만.
#   • 사용자 파일을 고치기 전에 항상 .bak.<timestamp> 백업.
#   • 멱등 — 이미 심링크/훅/스니펫이 있으면 스킵(중복 추가 없음).
#   • settings.json 은 jq 가 있으면 병합, 없으면 수동 안내만.
#
# 사용:
#   ./scripts/install-integration.sh            # dry-run (권장: 먼저 확인)
#   ./scripts/install-integration.sh --apply     # 실제 적용
#   ./scripts/install-integration.sh --apply --resume   # 재개(SessionStart) 훅까지
#   ./scripts/install-integration.sh --help
set -euo pipefail

# ── 색 출력 ────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYN=""; RST=""
fi
info()  { printf '%s\n' "${CYN}==>${RST} $*"; }
ok()    { printf '%s\n' "${GRN}  ✓${RST} $*"; }
warn()  { printf '%s\n' "${YLW}  ⚠${RST} $*"; }
err()   { printf '%s\n' "${RED}error:${RST} $*" >&2; }
skip()  { printf '%s\n' "${DIM}  ·${RST} $*"; }
plan()  { printf '%s\n' "${YLW}  [dry-run]${RST} $*"; }

# ── 인자 파싱 ──────────────────────────────────────────────────────────────
APPLY=false
WANT_RESUME=false
for arg in "$@"; do
  case "$arg" in
    --apply)  APPLY=true ;;
    --resume) WANT_RESUME=true ;;
    -h|--help)
      sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) err "알 수 없는 인자: $arg (--help 참고)"; exit 1 ;;
  esac
done

TS="$(date +%Y%m%d%H%M%S)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/muxa-notify"

if $APPLY; then
  info "적용 모드 — 파일을 실제로 수정한다 (백업: *.bak.$TS)"
else
  info "dry-run — 무엇을 할지 출력만 한다. 실제 적용하려면 ${BOLD}--apply${RST}"
fi
printf '\n'

# 백업 헬퍼 — apply 모드에서 대상이 존재하면 .bak.<ts> 로 복사.
backup() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  if $APPLY; then
    cp -p "$f" "$f.bak.$TS"
    ok "백업: $f.bak.$TS"
  else
    plan "백업할 것: $f → $f.bak.$TS"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# 1) muxa-notify 바이너리 → ~/.local/bin/muxa-notify 심링크
# ═══════════════════════════════════════════════════════════════════════════
info "1) muxa-notify 바이너리 심링크"

RELEASE_BIN="$ROOT/macos/.build/release/muxa-notify"
DEBUG_BIN="$ROOT/macos/.build/debug/muxa-notify"
SRC_BIN=""
if [[ -x "$RELEASE_BIN" ]]; then
  SRC_BIN="$RELEASE_BIN"
elif [[ -x "$DEBUG_BIN" ]]; then
  SRC_BIN="$DEBUG_BIN"
fi

if [[ -z "$SRC_BIN" ]]; then
  err "muxa-notify 바이너리를 찾지 못했다."
  echo   "      먼저 빌드하라: ${BOLD}cd $ROOT/macos && swift build${RST}"
  echo   "      (릴리스로 쓰려면: swift build -c release)"
  exit 1
fi
ok "발견: ${SRC_BIN#"$ROOT/"}"

# 멱등: 이미 같은 대상을 가리키는 심링크면 스킵.
if [[ -L "$BIN_LINK" && "$(readlink "$BIN_LINK")" == "$SRC_BIN" ]]; then
  skip "이미 심링크됨: $BIN_LINK → $SRC_BIN"
else
  if $APPLY; then
    mkdir -p "$BIN_DIR"
    # 기존이 심링크가 아닌 실제 파일이면 함부로 지우지 않고 백업.
    if [[ -e "$BIN_LINK" && ! -L "$BIN_LINK" ]]; then
      backup "$BIN_LINK"
    fi
    ln -sf "$SRC_BIN" "$BIN_LINK"
    ok "심링크 생성: $BIN_LINK → $SRC_BIN"
  else
    plan "심링크할 것: $BIN_LINK → $SRC_BIN"
  fi
fi

# PATH 안내 — ~/.local/bin 이 없으면 훅에서 muxa-notify 를 못 찾는다.
case ":$PATH:" in
  *":$BIN_DIR:"*) ok "PATH 에 $BIN_DIR 포함됨" ;;
  *) warn "PATH 에 $BIN_DIR 가 없다 — 훅이 muxa-notify 를 못 찾는다."
     echo "      셸 rc 에 추가: ${BOLD}export PATH=\"\$HOME/.local/bin:\$PATH\"${RST}" ;;
esac
printf '\n'

# ═══════════════════════════════════════════════════════════════════════════
# 2) Claude Code 훅 → ~/.claude/settings.json
# ═══════════════════════════════════════════════════════════════════════════
info "2) Claude Code 훅 등록 (~/.claude/settings.json)"

SETTINGS="$HOME/.claude/settings.json"

# 프리셋 — 훅이 stdin JSON(payload)을 **해석하지 않고 그대로** 앱에 넘긴다(`hook --event <E>`).
# 분류·게이팅은 전부 앱이 한다: 훅 명령줄은 사용자의 settings.json 에 박혀 있어서, 여기에 로직을
# 넣으면 앱 업데이트로 못 고친다. 덕분에 런타임 jq 의존도 사라졌다(세션 ID·배경작업 판정 모두 앱이 한다).
#
# 앱 안에서 벨(알림 인박스) → "설치" 버튼으로도 같은 일을 할 수 있다(권장 — 절대경로를 쓰므로 PATH 불필요).
# 예전 형식(`muxa-notify --state …`)이 남아 있으면 앱 설치기가 새 형식으로 갈아끼운다(이중 발화 방지).
read -r -d '' PRESETS_JSON <<'JSON' || true
{
  "SessionStart":     { "hooks": [ { "type": "command", "command": "muxa-notify hook --event SessionStart" } ] },
  "UserPromptSubmit": { "hooks": [ { "type": "command", "command": "muxa-notify hook --event UserPromptSubmit" } ] },
  "PreToolUse":       { "matcher": "*", "hooks": [ { "type": "command", "command": "muxa-notify hook --event PreToolUse" } ] },
  "PostToolUse":      { "matcher": "*", "hooks": [ { "type": "command", "command": "muxa-notify hook --event PostToolUse" } ] },
  "Notification":     { "hooks": [ { "type": "command", "command": "muxa-notify hook --event Notification" } ] },
  "Stop":             { "hooks": [ { "type": "command", "command": "muxa-notify hook --event Stop" } ] },
  "SubagentStart":    { "hooks": [ { "type": "command", "command": "muxa-notify hook --event SubagentStart" } ] },
  "SubagentStop":     { "hooks": [ { "type": "command", "command": "muxa-notify hook --event SubagentStop" } ] }
}
JSON

if command -v jq >/dev/null 2>&1; then
  if $WANT_RESUME; then
    skip "--resume 은 이제 불필요 — SessionStart 훅이 기본 포함이고, 세션 ID 는 앱이 payload 에서 읽는다"
  fi

  # 현재 settings(없으면 빈 객체)를 읽어, 각 이벤트에 이미 muxa-notify 훅이
  # 있으면 스킵하고 없으면 추가한다(멱등). 결과를 임시파일에 쓰고 원자적 교체.
  CURRENT='{}'
  [[ -f "$SETTINGS" ]] && CURRENT="$(cat "$SETTINGS")"

  MERGED="$(printf '%s' "$CURRENT" | jq --argjson presets "$PRESETS_JSON" '
    .hooks //= {}
    | reduce ($presets | to_entries[]) as $p (.;
        ($p.key) as $event
        | ((.hooks[$event] // [])
            | [ .[]?.hooks[]?.command // empty | select(test("muxa-notify")) ]
            | length) as $already
        | if $already > 0
          then .
          else .hooks[$event] = ((.hooks[$event] // []) + [$p.value])
          end
      )')"

  # 무엇이 새로 추가되는지 계산(안내용).
  ADDED="$(printf '%s' "$CURRENT" | jq -r --argjson presets "$PRESETS_JSON" '
    (.hooks // {}) as $h
    | [ $presets | to_entries[]
        | select( (($h[.key] // []) | [ .[]?.hooks[]?.command // empty | select(test("muxa-notify")) ] | length) == 0 )
        | .key ] | join(", ")')"

  if [[ -z "$ADDED" ]]; then
    skip "이미 등록됨 — 추가할 훅 없음"
  elif $APPLY; then
    mkdir -p "$(dirname "$SETTINGS")"
    backup "$SETTINGS"
    TMP="$(mktemp)"
    printf '%s\n' "$MERGED" > "$TMP"
    mv "$TMP" "$SETTINGS"
    ok "훅 추가: $ADDED → $SETTINGS"
  else
    plan "훅 추가할 것: $ADDED → $SETTINGS"
    printf '%s\n' "${DIM}--- 병합 결과 미리보기(.hooks) ---${RST}"
    printf '%s' "$MERGED" | jq '.hooks'
  fi
else
  warn "jq 가 없어 자동 병합을 건너뛴다. muxa 앱의 알림 벨 → \"설치\" 버튼을 쓰면 jq 없이 등록된다."
  echo "      직접 병합하려면 아래를 ~/.claude/settings.json 의 \"hooks\" 에 넣어라:"
  printf '%s\n' "$PRESETS_JSON" | sed 's/^/        /'
fi
printf '\n'

# ═══════════════════════════════════════════════════════════════════════════
# 3) 스크롤백 재출력 rc 스니펫 → ~/.zshrc · ~/.bashrc
# ═══════════════════════════════════════════════════════════════════════════
info "3) 스크롤백 재출력 rc 스니펫 (~/.zshrc · ~/.bashrc)"

SNIPPET_MARK="muxa scrollback restore"
# 마커로 감싸 멱등·식별 가능하게 한다.
read -r -d '' SNIPPET <<'SNIP' || true

# >>> muxa scrollback restore >>>
# 세션 복원 시 muxa 가 심는 MUXA_RESTORE_SCROLLBACK_FILE 을 재출력하고 지운다.
[ -n "$MUXA_RESTORE_SCROLLBACK_FILE" ] && [ -f "$MUXA_RESTORE_SCROLLBACK_FILE" ] && { cat "$MUXA_RESTORE_SCROLLBACK_FILE"; rm -f "$MUXA_RESTORE_SCROLLBACK_FILE"; }
# <<< muxa scrollback restore <<<
SNIP

install_snippet() {
  local rc="$1"
  if [[ -f "$rc" ]] && grep -q "$SNIPPET_MARK" "$rc"; then
    skip "이미 있음: $rc"
    return 0
  fi
  if $APPLY; then
    backup "$rc"
    printf '%s\n' "$SNIPPET" >> "$rc"
    ok "스니펫 추가: $rc"
  else
    plan "스니펫 추가할 것: $rc"
  fi
}
install_snippet "$HOME/.zshrc"
install_snippet "$HOME/.bashrc"
printf '\n'

# ═══════════════════════════════════════════════════════════════════════════
info "완료."
if $APPLY; then
  ok "통합이 적용됐다. 새 셸/새 muxa 세션부터 반영된다."
  echo "   • 훅 확인:   ${BOLD}muxa-notify --state done${RST} (muxa 안에서 실행 시 배지 변화)"
  echo "   • 백업 복원: ${BOLD}mv <파일>.bak.$TS <파일>${RST}"
else
  echo "   실제 적용: ${BOLD}$0 --apply${RST}   (재개 훅까지: ${BOLD}--apply --resume${RST})"
fi
