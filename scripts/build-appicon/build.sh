#!/usr/bin/env bash
# muxa 앱 아이콘 재생성 — Core Graphics 드로잉(icon-gen.swift, SVG 래스터라이저 의존 없음)
# → 여러 해상도 iconset → macos/AppIcon.icns + Resources/AppIcon.png(런타임 Dock 아이콘).
# 아이콘을 바꾸려면 icon-gen.swift만 고치고 이 스크립트를 다시 돌린다.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../..

OUT=out; rm -rf "$OUT"; mkdir "$OUT"
# variant x = 낙서 X(다크 그래파이트 배경 + 버밀리언 손그림 X "muXa"). 옛 청록 안은 a~e로 재생성 가능.
swift icon-gen.swift x "$OUT/icon_1024.png"

ICONSET="$OUT/AppIcon.iconset"; mkdir "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z "$sz" "$sz" "$OUT/icon_1024.png" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  d=$((sz * 2))
  sips -z "$d" "$d" "$OUT/icon_1024.png" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
cp "$OUT/icon_1024.png" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ROOT/macos/AppIcon.icns"
cp "$OUT/icon_1024.png" "$ROOT/macos/Sources/muxa/Resources/AppIcon.png"
rm -rf "$OUT"
echo "생성 완료: macos/AppIcon.icns + macos/Sources/muxa/Resources/AppIcon.png"
