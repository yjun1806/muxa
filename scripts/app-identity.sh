#!/usr/bin/env bash
# muxa 앱 정체성(이름·번들 id·실행파일명)의 **단일 출처**.
#
# 왜 한 곳에 모으나: 이름 규칙이 build-app.sh(번들 조립)와 Makefile(kill/relaunch/app)에 따로
# 있으면 서로 어긋나, dev/prod를 헷갈려 **엉뚱한 인스턴스를 죽인다**(실제로 반복됐다).
# 이름을 정하는 곳도, 죽일 대상을 계산하는 곳도 전부 이 스크립트를 source 해서 같은 값을 쓴다.
#
# 사용:
#   source scripts/app-identity.sh [debug|release]   # APP_* 변수를 export
#   scripts/app-identity.sh [debug|release]           # (직접 실행) 값들을 사람이 읽게 출력
#
# export 하는 값: APP_CONFIG · APP_BIN · APP_NAME · BUNDLE_ID · APP_FILE
#
# 이름 규칙 — **dev와 prod가 이름만 봐도 완전히 갈린다**:
#   릴리스  실행파일 `muxa`            번들 `com.muxa.app`        Dock/⌘Tab `muxa`
#   개발    실행파일 `muxa-dev-<slug>`  번들 `com.muxa.dev.<slug>`  Dock/⌘Tab `Muxa Dev · <slug>`
# <slug> = 워크트리(git 루트 디렉터리) 이름. 메인 체크아웃(디렉터리명이 muxa)이면 브랜치명.
# 영숫자·하이픈만 남긴다. 개발 실행파일은 반드시 `muxa-dev-` 접두라 릴리스 `muxa`와 절대 안 겹친다.

_muxa_identity() {
  local config="${1:-debug}"
  if [ "$config" = "release" ]; then
    APP_CONFIG="release"; APP_BIN=".build/release"
    APP_NAME="muxa"; BUNDLE_ID="com.muxa.app"; APP_FILE="muxa"
  else
    APP_CONFIG="debug"; APP_BIN=".build/debug"
    local root label slug
    root="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
    label="$(basename "$root")"
    # 메인 체크아웃이면 디렉터리명이 그냥 muxa라 안 갈리므로 브랜치명을 쓴다.
    [ "$label" = "muxa" ] && label="$(git branch --show-current 2>/dev/null || echo dev)"
    slug="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')"
    [ -n "$slug" ] || slug="dev"
    APP_NAME="Muxa Dev · $slug"; BUNDLE_ID="com.muxa.dev.$slug"; APP_FILE="muxa-dev-$slug"
  fi

  # 버전도 여기가 단일 출처다 — 스크립트에 상수로 박아 두면 모든 빌드가 `0.1.0 (1)`로 나가
  # crash report·Finder 정보에서 서로 구분되지 않는다("어느 빌드에서 터졌나"를 물을 수 없다).
  #   APP_VERSION  = 최신 태그(v0.2.0 → 0.2.0), 태그가 없으면 0.0.0
  #   APP_BUILD    = 커밋 수(단조 증가 — LaunchServices·업데이터가 요구하는 성질)
  # `|| true` 없이 쓰면 태그가 없을 때 git이 128로 죽고, 이 파일을 source 하는 `set -e` 스크립트가
  # 통째로 중단된다(빌드가 아무 메시지 없이 실패한다 — 실제로 그랬다).
  APP_VERSION="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  APP_VERSION="${APP_VERSION#v}"
  [ -n "$APP_VERSION" ] || APP_VERSION="0.0.0"
  APP_BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
  [ -n "$APP_BUILD" ] || APP_BUILD="0"

  export APP_CONFIG APP_BIN APP_NAME BUNDLE_ID APP_FILE APP_VERSION APP_BUILD
}

_muxa_identity "${1:-debug}"

# 직접 실행(= source 아님)이면 값을 출력한다 — 무엇을 열고/죽일지 눈으로 확인용.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'config      %s\n' "$APP_CONFIG"
  printf 'app name    %s\n' "$APP_NAME"
  printf 'bundle id   %s\n' "$BUNDLE_ID"
  printf 'executable  %s   (ps/pgrep 에 이 이름으로 뜬다)\n' "$APP_FILE"
  printf 'version     %s (%s)\n' "$APP_VERSION" "$APP_BUILD"
  printf 'bundle path macos/%s/%s.app\n' "$APP_BIN" "$APP_FILE"
fi
