#!/usr/bin/env bash
# 새 개발 워크트리를 만든다 — 브랜치 생성 + vendor(GhosttyKit) 연결까지 한 번에.
#
# 왜 필요한가: `git worktree add`만으론 빌드가 안 된다. 리포엔 **추적되는 심링크**
#   macos/GhosttyKit.xcframework -> ../vendor/ghostty/macos/GhosttyKit.xcframework
# 가 있는데 vendor/는 .gitignore라 새 워크트리엔 없다 → 심링크가 끊겨 빌드가 통째로 깨진다.
# 이 스크립트가 그 vendor를 **메인 체크아웃 것으로 이어주거나**(심링크 — 빠름·재다운로드 없음),
# 메인에도 없으면 bootstrap으로 내려받아, 워크트리가 곧바로 `make build` 되게 한다.
#
# .build/ 는 일부러 안 건드린다 — SPM 빌드 산출물은 워크트리마다 따로여야 한다(공유하면 교차 오염).
# 첫 빌드가 콜드인 건 그래서 정상이다. Bonsplit은 Package.swift가 SHA 고정(git URL)이라 SPM이
# 워크트리의 .build로 알아서 받아온다 — 손댈 것 없음.
#
# 사용:
#   ./scripts/new-worktree.sh <branch> [base-ref]
#   예) ./scripts/new-worktree.sh feat/foo          # main에서 분기 → ../muxa-foo
#       ./scripts/new-worktree.sh fix/bar develop   # develop에서 분기 → ../muxa-bar
set -euo pipefail

BRANCH="${1:?사용: ./scripts/new-worktree.sh <branch> [base-ref]}"
BASE="${2:-main}"

# 메인 체크아웃 경로 = `git worktree list`의 첫 줄(주 워크트리). vendor의 정본이 여기 있다.
# 이 스크립트를 다른 워크트리에서 실행해도 항상 메인의 vendor를 가리키게 한다.
MAIN_ROOT="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
[ -n "$MAIN_ROOT" ] || { echo "error: git 리포 안에서 실행하세요." >&2; exit 1; }

# 워크트리 디렉터리 = 리포 부모/muxa-<slug>. slug = 브랜치 basename에서 영숫자·하이픈만 남긴다
# (app-identity.sh가 디렉터리명을 slug로 삼아 dev 앱 이름 muxa-dev-<slug>를 만든다 — 규칙 일치).
PARENT="$(dirname "$MAIN_ROOT")"
SLUG="$(basename "$BRANCH" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')"
[ -n "$SLUG" ] || { echo "error: 브랜치명에서 slug를 못 뽑았습니다: $BRANCH" >&2; exit 1; }
WT="$PARENT/muxa-$SLUG"

[ -e "$WT" ] && { echo "error: 이미 있습니다: $WT" >&2; exit 1; }

echo "▸ 워크트리 생성: $WT  (branch $BRANCH ← $BASE)"
git worktree add -b "$BRANCH" "$WT" "$BASE"

# ── vendor 연결 — 심링크(빠름) 우선, 메인에 없으면 bootstrap(다운로드) ─────────────
VENDOR_XCF="$MAIN_ROOT/vendor/ghostty/macos/GhosttyKit.xcframework"
if [ -d "$VENDOR_XCF" ]; then
  ln -s "$MAIN_ROOT/vendor" "$WT/vendor"
  echo "▸ vendor 연결(심링크): $WT/vendor -> $MAIN_ROOT/vendor  (재다운로드 없음)"
else
  echo "▸ 메인에 vendor 없음 → 워크트리에서 bootstrap 실행(다운로드)"
  ( cd "$WT" && ./scripts/bootstrap.sh )
fi

# ── 정체성·다음 단계 안내 ──────────────────────────────────────────────────────
echo
echo "✅ 완료. 이 워크트리의 개발 앱:"
( cd "$WT" && ./scripts/app-identity.sh debug 2>/dev/null | sed -n '2,4p' )
echo
echo "다음:"
echo "  cd $WT"
echo "  make build      # 첫 빌드는 콜드(전체 컴파일)라 좀 걸린다"
echo "  make dev        # .app 번들로 실행"
echo
echo "제거할 땐 (워크트리 + 심링크 정리):"
echo "  git worktree remove $WT"
