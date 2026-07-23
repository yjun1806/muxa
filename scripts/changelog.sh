#!/usr/bin/env bash
# CHANGELOG.md 갱신 — 직전 태그 이후 커밋으로 "새 릴리스 한 섹션"을 만들어 [Unreleased] 아래에 끼운다.
# 손으로 다듬은 옛 항목·서문·링크 규칙은 그대로 둔다(전체 재생성 안 함). 컨벤션 커밋만, chore/ci 제외.
#
#   usage: scripts/changelog.sh v0.3.0      (make changelog TAG=v0.3.0)
#
# 순서: (1) 이 스크립트로 CHANGELOG 갱신 → (2) 사람이 검토·다듬기 → (3) 커밋 → (4) git tag v0.3.0
# 태그는 스크립트가 찍지 않는다 — 검토 후 사람이 찍는다.
set -euo pipefail

TAG="${1:-}"
case "$TAG" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "usage: scripts/changelog.sh vX.Y.Z  (예: v0.3.0)" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."
FILE="CHANGELOG.md"
REPO="https://github.com/yjun1806/muxa"

command -v git-cliff >/dev/null || { echo "git-cliff 미설치 — 'brew install git-cliff'" >&2; exit 1; }
[ -f "$FILE" ] || { echo "$FILE 없음" >&2; exit 1; }

ver="${TAG#v}"
grep -q "^## \[$ver\]" "$FILE" && { echo "[$ver] 섹션이 이미 있음 — 중단(중복 방지)" >&2; exit 1; }

PREV="$(git describe --tags --abbrev=0 2>/dev/null || true)"
[ -n "$PREV" ] || { echo "직전 태그를 못 찾음 — 첫 릴리스는 수동으로" >&2; exit 1; }
prevver="${PREV#v}"

# 직전 태그 이후 커밋으로 섹션 생성(앞뒤 빈 줄은 정리 — BSD/GNU 공통 awk로).
sectmp="$(mktemp)"; trap 'rm -f "$sectmp"' EXIT
git-cliff "$PREV..HEAD" --tag "$TAG" 2>/dev/null \
  | awk 'NF{p=1} p' \
  | awk '{a[NR]=$0} END{n=NR; while(n>0 && a[n] ~ /^[ \t]*$/) n--; for(i=1;i<=n;i++) print a[i]}' \
  > "$sectmp"

grep -q '^- ' "$sectmp" \
  || echo "경고: $PREV..HEAD 에 노트에 넣을 커밋이 없음(전부 chore/ci/비컨벤션?) — 빈 섹션이 들어간다" >&2

# [Unreleased] 아래에 섹션 삽입 + compare 링크 갱신/추가. 나머지는 그대로 통과.
out="$(mktemp)"
awk -v secfile="$sectmp" -v tag="$TAG" -v ver="$ver" \
    -v prev="$PREV" -v prevver="$prevver" -v repo="$REPO" '
  /^## \[Unreleased\]/ {
    print; print ""
    while ((getline l < secfile) > 0) print l
    print ""
    next
  }
  /^\[Unreleased\]:/ { print "[Unreleased]: " repo "/compare/" tag "...HEAD"; next }
  $0 ~ ("^\\[" prevver "\\]:") {
    print "[" ver "]: " repo "/compare/" prev "..." tag
    print; next
  }
  { print }
' "$FILE" > "$out"
mv "$out" "$FILE"

echo "✓ $FILE 에 [$ver] 섹션을 추가했다($PREV..HEAD). 검토 후 커밋·태그:"
echo "    git add $FILE && git commit -m 'docs: $ver 체인지로그' && git tag -a $TAG -m '$TAG'"
