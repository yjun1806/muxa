# muxa 개발 명령 모음.
#
# `make`(인자 없이) = 도움말. 각 타깃 옆 `## 설명`은 self-documenting makefile 관례이고,
# muxa의 **서비스 추가 시트**가 이 설명을 그대로 읽어 보여준다(ProjectScripts.parseMakefile).

MACOS := macos
APP := $(MACOS)/.build/debug/muxa.app

.DEFAULT_GOAL := help
.PHONY: help bootstrap build test run app dmg icons integrate clean

help: ## 사용 가능한 명령 보기
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## GhosttyKit 설치 — 새 머신에서 최초 1회 (docs/SETUP.md)
	./scripts/bootstrap.sh

build: ## 빌드
	cd $(MACOS) && swift build

test: ## 단위 테스트 (순수 로직)
	cd $(MACOS) && swift test

run: ## 빌드 후 실행 — bare 바이너리(창은 뜨지만 시스템 알림·아이콘은 폴백)
	cd $(MACOS) && swift build && ./.build/debug/muxa

app: ## .app 번들로 빌드·실행 — 시스템 알림·아이콘이 정상 동작하는 실사용 경로
	./scripts/build-app.sh && open $(APP)

dmg: ## 배포용 .dmg 만들기
	./scripts/build-dmg.sh

icons: ## 앱 아이콘·파일 아이콘 리소스 재생성
	./scripts/build-appicon
	./scripts/build-fileicons

integrate: ## Claude Code 훅·muxa notify 설치 (기본 dry-run, 실제 적용은 --apply)
	./scripts/install-integration.sh

clean: ## 빌드 산출물 삭제
	cd $(MACOS) && swift package clean
