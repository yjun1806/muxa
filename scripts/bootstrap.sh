#!/usr/bin/env bash
# muxa 부트스트랩 — 터미널 코어(GhosttyKit.xcframework) 설치.
# 새 머신에서 한 번 실행하면 `cd macos && swift build`가 바로 된다.
#
# 방식: cmux fork가 배포하는 prebuilt universal xcframework(ReleaseFast, self-contained)를
#       고정 SHA로 내려받고 SHA256으로 검증한다. zig 빌드도, ghostty 소스도 필요 없다.
#       업그레이드는 GHOSTTY_SHA와 GHOSTTYKIT_SHA256을 함께 바꾸는 의식적 이벤트로만 한다.
set -euo pipefail

# ── pin (업그레이드 시 두 값을 함께 갱신) ─────────────────────────────────
# ghostty 커밋 SHA(cmux fork)와 그 prebuilt 아카이브의 SHA256.
# 값 출처: cmux 리포 scripts/ghosttykit-checksums.txt (<ghostty_sha> <sha256>)
GHOSTTY_SHA="dd726a9a6050abd67f0dee7bba65136557567994"
GHOSTTYKIT_SHA256="dafc9e3db622dcfa5e8c2581b89afdb55a97ba754c38f0712a60555a6a917bab"
BUILD_FLAVOR="crashsubdir-cmux-crash-v1"   # 릴리스 태그 접미사(prebuilt 빌드 flavor)
BASE_URL="https://github.com/manaflow-ai/ghostty/releases/download"
# ─────────────────────────────────────────────────────────────────────────

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$(pwd)"
DEST="$ROOT/vendor/ghostty/macos/GhosttyKit.xcframework"
STAMP="$DEST/.muxa_ghostty_sha"
LIB_DIR="macos-arm64_x86_64"
LIB="$DEST/$LIB_DIR/libghostty-internal.a"

# 멱등: 같은 SHA로 이미 설치돼 있으면 아무것도 안 한다.
if [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$GHOSTTY_SHA" && -f "$LIB" ]]; then
  echo "✅ GhosttyKit 이미 설치됨 (ghostty ${GHOSTTY_SHA:0:12}). 건너뜀."
  exit 0
fi

command -v curl >/dev/null || { echo "error: curl이 필요합니다." >&2; exit 1; }
command -v xcrun >/dev/null || { echo "error: Xcode Command Line Tools(xcrun)가 필요합니다." >&2; exit 1; }

TAG="xcframework-${GHOSTTY_SHA}-${BUILD_FLAVOR}"
URL="${BASE_URL}/${TAG}/GhosttyKit.xcframework.tar.gz"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TAR="$TMP/GhosttyKit.xcframework.tar.gz"

echo "==> prebuilt GhosttyKit 다운로드 (ghostty ${GHOSTTY_SHA:0:12})..."
curl -fSL --connect-timeout 10 --max-time 600 --retry 3 --retry-delay 2 --retry-all-errors -o "$TAR" "$URL"

echo "==> SHA256 검증..."
ACTUAL="$(shasum -a 256 "$TAR" | awk '{print $1}')"
if [[ "$ACTUAL" != "$GHOSTTYKIT_SHA256" ]]; then
  echo "error: 체크섬 불일치 — 신뢰할 수 없는 아카이브. 중단." >&2
  echo "  기대: $GHOSTTYKIT_SHA256" >&2
  echo "  실제: $ACTUAL" >&2
  exit 1
fi

echo "==> 압축 해제 · 설치: vendor/ghostty/macos/"
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST" "$TMP/extract"
mkdir -p "$TMP/extract"
tar --no-same-owner -xzf "$TAR" -C "$TMP/extract"
mv "$TMP/extract/GhosttyKit.xcframework" "$DEST"

# SPM은 xcframework 안의 정적 라이브러리 이름이 lib* 여야 링크한다.
# prebuilt는 ghostty-internal.a라 lib 접두사로 rename하고 Info.plist를 맞춘다.
# (cmux는 Xcode 프로젝트로 링크해 이 제약이 없지만, muxa는 SPM이라 필요.)
echo "==> SPM 호환: ghostty-internal.a → libghostty-internal.a"
mv "$DEST/$LIB_DIR/ghostty-internal.a" "$LIB"
sed -i '' 's|<string>ghostty-internal.a</string>|<string>libghostty-internal.a</string>|' "$DEST/Info.plist"

# Xcode 26 ld는 아카이브 복사 후 심볼 인덱스 리프레시가 필요할 수 있다.
echo "==> ranlib 인덱스 리프레시..."
xcrun ranlib "$LIB" >/dev/null 2>&1 || true

echo "$GHOSTTY_SHA" > "$STAMP"
echo "✅ 완료 — 이제 'cd macos && swift build'"
