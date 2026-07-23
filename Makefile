# muxa 개발 명령 모음.
#
# `make`(인자 없이) = 도움말. 각 타깃 옆 `## 설명`은 self-documenting makefile 관례이고,
# muxa의 **서비스 추가 시트**가 이 설명을 그대로 읽어 보여준다(ProjectScripts.parseMakefile).

MACOS := macos
# 앱 이름·번들 id·실행파일명의 단일 출처(scripts/app-identity.sh)를 셸에서 불러온다.
# 릴리스=`muxa`, 개발=`muxa-dev-<slug>`. 이 규칙 덕에 dev/prod·워크트리가 이름으로 완전히 갈린다.
IDENTITY := source scripts/app-identity.sh debug

.DEFAULT_GOAL := help
.PHONY: help bootstrap worktree build test dev dev-kill dev-relaunch whoami release-install release-dmg icons integrate clean

help: ## 사용 가능한 명령 보기
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

bootstrap: ## GhosttyKit 설치 — 새 머신에서 최초 1회 (docs/SETUP.md)
	./scripts/bootstrap.sh

worktree: ## 새 개발 워크트리 생성 (vendor 연결까지) — 예: make worktree BRANCH=feat/foo
	@./scripts/new-worktree.sh "$(BRANCH)"

build: ## 빌드
	cd $(MACOS) && swift build

test: ## 단위 테스트 (순수 로직)
	cd $(MACOS) && swift test

whoami: ## 이 워크트리 개발 앱의 이름·번들 id·프로세스명 출력 (무엇을 열고/죽일지 확인)
	@./scripts/app-identity.sh debug

dev: ## .app 번들로 빌드·실행 (debug) — 시스템 알림·아이콘·정식 이름(권장 개발 경로)
	@./scripts/build-app.sh && $(IDENTITY) && open "$(MACOS)/.build/debug/$$APP_FILE.app"

dev-kill: ## 이 워크트리의 개발 앱만 종료 — 릴리스·다른 워크트리는 절대 안 건드린다(정상 종료)
	@./scripts/dev-kill.sh

dev-relaunch: ## 이 워크트리 개발 앱 종료 → 재빌드 → 실행 (안전한 테스트 루프)
	@$(MAKE) dev-kill; sleep 1; $(MAKE) dev

release-install: ## 프로덕션(release) 빌드 후 /Applications에 설치 — 릴리스 muxa.app
	@./scripts/release-install.sh

release-dmg: ## 배포용 .dmg 만들기
	./scripts/build-dmg.sh

icons: ## 앱 아이콘·파일 아이콘 리소스 재생성
	./scripts/build-appicon
	./scripts/build-fileicons

integrate: ## Claude Code 훅·muxa notify 설치 (기본 dry-run, 실제 적용은 --apply)
	./scripts/integrate.sh

clean: ## 빌드 산출물 삭제
	cd $(MACOS) && swift package clean
