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
#   ./scripts/integrate.sh            # dry-run (권장: 먼저 확인)
#   ./scripts/integrate.sh --apply     # 실제 적용
#   ./scripts/integrate.sh --apply --resume   # 재개(SessionStart) 훅까지
#   ./scripts/integrate.sh --help
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
# 1) muxa-notify 바이너리 → ~/.local/bin/muxa-notify (복사)
# ═══════════════════════════════════════════════════════════════════════════
info "1) muxa-notify 바이너리 설치"

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

# **심링크가 아니라 복사한다.** 예전엔 .build 산출물을 심링크했는데, 그 빌드 디렉터리(특히 워크트리)를
# 지우면 링크가 끊겨(dangling) 훅이 매 도구 호출마다 "command not found"를 뱉었다. 복사본은 소스
# 빌드가 사라져도 살아남는다(업데이트하려면 이 스크립트를 다시 돌린다). 앱 설치기와 동일한 원칙.
if $APPLY; then
  mkdir -p "$BIN_DIR"
  [[ -e "$BIN_LINK" ]] && backup "$BIN_LINK" # 기존(심링크든 파일이든) 백업 후 교체
  rm -f "$BIN_LINK"
  cp "$SRC_BIN" "$BIN_LINK"
  chmod +x "$BIN_LINK"
  ok "복사: $SRC_BIN → $BIN_LINK"
else
  plan "복사할 것: $SRC_BIN → $BIN_LINK (심링크 아님 — 빌드 디렉터리 삭제에도 안 깨진다)"
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
# **이벤트 집합은 앱 enum(ClaudeHookEvent)과 일치해야 한다** — 7개. `PostToolUse`는 일부러 뺐다:
# PreToolUse만으로 진행 표시가 충분하고, 둘 다 구독하면 도구 호출당 프로세스가 두 번 뜨며 PostToolUse
# payload(tool_response 전문)는 소켓 버퍼를 넘긴다. 스크립트가 이걸 넣으면 앱이 피하려던 비용이 되살아난다.
#
# **명령은 절대경로 + 존재 가드**로 감싼다(앱 설치기와 동일). muxa/바이너리를 지워도 훅이 남는데,
# 가드가 없으면 muxa 밖의 모든 claude 세션이 매 도구 호출마다 "command not found"를 뱉는다.
# `if [ -x <경로> ]; then <경로> …; fi` 로 없으면 조용히 통과시킨다(exit 0).
guard_cmd() { printf "if [ -x '%s' ]; then '%s' hook --event %s; fi" "$BIN_LINK" "$BIN_LINK" "$1"; }

if command -v jq >/dev/null 2>&1; then
  PRESETS_JSON="$(jq -n \
    --arg ss  "$(guard_cmd SessionStart)" \
    --arg up  "$(guard_cmd UserPromptSubmit)" \
    --arg pre "$(guard_cmd PreToolUse)" \
    --arg no  "$(guard_cmd Notification)" \
    --arg st  "$(guard_cmd Stop)" \
    --arg sas "$(guard_cmd SubagentStart)" \
    --arg sap "$(guard_cmd SubagentStop)" \
    '{
      SessionStart:     { hooks: [ { type: "command", command: $ss } ] },
      UserPromptSubmit: { hooks: [ { type: "command", command: $up } ] },
      PreToolUse:       { matcher: "*", hooks: [ { type: "command", command: $pre } ] },
      Notification:     { hooks: [ { type: "command", command: $no } ] },
      Stop:             { hooks: [ { type: "command", command: $st } ] },
      SubagentStart:    { hooks: [ { type: "command", command: $sas } ] },
      SubagentStop:     { hooks: [ { type: "command", command: $sap } ] }
    }')"
else
  PRESETS_JSON=""
fi

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
  warn "jq 가 없어 자동 병합을 건너뛴다. muxa 앱의 알림 벨 → \"설치\" 버튼을 쓰면 jq 없이 등록된다(권장)."
  echo "      각 이벤트에 아래 형식의 command 를 넣어라(절대경로 + 존재 가드):"
  for e in SessionStart UserPromptSubmit PreToolUse Notification Stop SubagentStart SubagentStop; do
    echo "        $e: $(guard_cmd "$e")"
  done
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
# 4) tmux OSC 통합 (persistent_sessions = true 일 때 필요)
# ═══════════════════════════════════════════════════════════════════════════
info "4) tmux OSC 통합 rc 스니펫 (~/.zshrc)"

# **왜 필요한가**: persistent_sessions를 켜면 터미널이 tmux 세션 안에서 돈다. 그런데 tmux는 안쪽
# OSC 시퀀스를 자체 소비해 바깥으로 흘리지 않는다 — muxa가 못 받으면 cwd 추적(OSC 7)과
# 완료 배지·알림(OSC 133)이 통째로 죽는다(실측 확인).
#
# 게다가 ghostty의 셸 통합은 tmux가 띄운 셸에서 **자동 실행되지 않는다**(업스트림 주석에 명시).
# 그래서 tmux 안에서는 muxa가 직접 OSC를 쏘되, tmux passthrough(`\ePtmux;…\e\\`)로 감싼다.
# tmux 쪽 `allow-passthrough on`은 muxa가 세션을 만들 때 켠다(TerminalSession.startCommand).
TMUX_MARK="muxa tmux integration"
read -r -d '' TMUX_SNIPPET <<'SNIP' || true

# >>> muxa tmux integration >>>
# tmux 안에서만 동작한다. OSC를 passthrough로 감싸 muxa까지 내보낸다(감싸지 않으면 tmux가 삼킨다).
if [ -n "${TMUX:-}" ] && [ -n "${MUXA_TAB_ID:-}" ] && [ -n "${ZSH_VERSION:-}" ]; then
  _muxa_osc() { printf '\ePtmux;\e\e]%s\a\e\\' "$1"; }
  _muxa_cwd()    { _muxa_osc "7;file://${HOST:-localhost}${PWD}"; }
  _muxa_precmd() { local _e=$?; _muxa_osc "133;D;${_e}"; _muxa_osc "133;A"; _muxa_cwd; }
  _muxa_preexec(){ _muxa_osc "133;C"; }
  autoload -Uz add-zsh-hook 2>/dev/null && {
    add-zsh-hook precmd  _muxa_precmd
    add-zsh-hook preexec _muxa_preexec
  }
  _muxa_cwd
fi
# <<< muxa tmux integration <<<
SNIP

install_tmux_snippet() {
  local rc="$1"
  if [[ -f "$rc" ]] && grep -q "$TMUX_MARK" "$rc"; then
    skip "이미 있음: $rc"
    return 0
  fi
  if $APPLY; then
    backup "$rc"
    printf '%s\n' "$TMUX_SNIPPET" >> "$rc"
    ok "tmux OSC 스니펫 추가: $rc"
  else
    plan "tmux OSC 스니펫 추가할 것: $rc"
  fi
}
install_tmux_snippet "$HOME/.zshrc"
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
