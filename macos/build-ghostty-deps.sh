#!/bin/bash
# GhosttyKit fat.a가 참조하는 정적 의존성을, zig가 만든 (정렬 안 된) .a에서
# ld -r로 라이브러리별 재배치 오브젝트(.o)로 변환한다.
#
# 왜 이렇게 하나:
#  - zig가 만든 .a는 멤버가 8-byte 정렬이 안 돼 Xcode 26 ld가 거부(zig#31658 계열)
#  - libtool 재패키징은 정렬은 고치지만 동명/무심볼 오브젝트를 통째로 누락시킴
#    (예: libdcimgui.a의 imgui.o가 사라짐)
#  - ld -r은 모든 오브젝트를 하나의 재배치 .o로 병합 → 정렬·누락 문제 동시 해결
#
# 전제: `zig build ... -Di18n=false -Dsentry=false`로 GhosttyKit을 이미 빌드했고,
#       deps/liblist.txt에 zig-cache의 각 라이브러리 경로가 있어야 한다.
# 재빌드로 zig-cache 해시가 바뀌면 liblist.txt를 갱신하고 이 스크립트를 재실행한다.
set -euo pipefail
cd "$(dirname "$0")"   # vendor/ghostty
ROOT="$(pwd)"

while read -r rel; do
  name="$(basename "$rel" .a)"
  [ "$name" = "libintl" ] && continue   # i18n=false라 gettext 불필요
  d="deps/obj/$name"
  rm -rf "$d"; mkdir -p "$d"
  ( cd "$d" && ar x "$ROOT/$rel" && chmod u+rw ./*.o )
  ld -r -o "deps/$name.o" "$d"/*.o
  echo "  $name.o ($(ls "$d"/*.o | wc -l | tr -d ' ') objs)"
done < deps/liblist.txt

# fat.a는 LibtoolStep 조립 시 libghostty.a의 일부 오브젝트(simd C++·compiler_rt·stb)를
# 누락시킨다. non-fat libghostty.a에서 "fat.a에 없는 것"만 뽑아 보충한다.
LG="$(grep '/libghostty\.a$' deps/all_libs.txt | head -1)"
FAT="macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a"
if [ -n "$LG" ]; then
  missing=$(comm -23 <(ar t "$LG" | sort -u) <(ar t "$FAT" | sort -u))
  d="deps/obj/ghostty-missing"; rm -rf "$d"; mkdir -p "$d"
  ( cd "$d" && ar x "$ROOT/$LG" $missing && chmod u+rw ./*.o )
  ld -r -o "deps/libghostty_missing.o" "$d"/*.o
  echo "  libghostty_missing.o ($missing)"
fi

echo "deps/*.o 생성 완료"
