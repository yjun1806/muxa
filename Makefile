# muxa 개발 명령 모음.
#
# `make`(인자 없이) = 도움말. 각 타깃 옆 `## 설명`은 self-documenting makefile 관례이고,
# muxa의 **서비스 추가 시트**가 이 설명을 그대로 읽어 보여준다(ProjectScripts.parseMakefile).

MACOS := macos
# 앱 이름·번들 id·실행파일명의 단일 출처(scripts/app-identity.sh)를 셸에서 불러온다.
# 릴리스=`muxa`, 개발=`muxa-dev-<slug>`. 이 규칙 덕에 dev/prod·워크트리가 이름으로 완전히 갈린다.
IDENTITY := source scripts/app-identity.sh debug
# 릴리스 정체성(muxa / com.muxa.app) — 프로덕션 빌드·설치용.
IDENTITY_RELEASE := source scripts/app-identity.sh release

.DEFAULT_GOAL := help
.PHONY: help bootstrap build test run app kill relaunch whoami install dmg icons integrate clean

help: ## 사용 가능한 명령 보기
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## GhosttyKit 설치 — 새 머신에서 최초 1회 (docs/SETUP.md)
	./scripts/bootstrap.sh

build: ## 빌드
	cd $(MACOS) && swift build

test: ## 단위 테스트 (순수 로직)
	cd $(MACOS) && swift test

whoami: ## 이 워크트리 개발 앱의 이름·번들 id·프로세스명 출력 (무엇을 열고/죽일지 확인)
	@./scripts/app-identity.sh debug

run: ## 빌드 후 bare 실행 — 프로세스명을 muxa-dev-<slug>로 복사해 실행(구분 유지). 알림·아이콘은 번들만
	@$(IDENTITY) && cd $(MACOS) && swift build \
		&& cp .build/debug/muxa ".build/debug/$$APP_FILE" \
		&& echo "실행(bare): $$APP_FILE" && "./.build/debug/$$APP_FILE"

app: ## .app 번들로 빌드·실행 — 시스템 알림·아이콘·정식 이름(권장 테스트 경로)
	@./scripts/build-app.sh && $(IDENTITY) && open "$(MACOS)/.build/debug/$$APP_FILE.app"

kill: ## 이 워크트리의 개발 앱만 종료 — 릴리스·다른 워크트리는 절대 안 건드린다(정상 종료)
	@$(IDENTITY); \
		if pkill -TERM -f "$$APP_FILE"; then echo "종료: $$APP_FILE"; else echo "실행 중 아님: $$APP_FILE"; fi
	@# 실행파일명 muxa-dev-<slug>는 유니크 — bare(상대경로)·번들 둘 다 잡고,
	@# 릴리스 muxa·muxa-notify·다른 slug는 이 문자열을 포함하지 않아 안 걸린다.

relaunch: ## 이 워크트리 개발 앱 종료 → 재빌드 → 실행 (안전한 테스트 루프)
	@$(MAKE) kill; sleep 1; $(MAKE) app

install: ## 프로덕션(release) 빌드 후 /Applications에 설치 — 릴리스 muxa.app
	@./scripts/build-app.sh release
	@$(IDENTITY_RELEASE); \
		SRC="$(MACOS)/.build/release/$$APP_FILE.app"; \
		DST="/Applications/$$APP_FILE.app"; \
		echo "설치: $$SRC → $$DST"; \
		rm -rf "$$DST" && cp -R "$$SRC" "$$DST" \
			&& echo "완료: $$DST  — 실행: open \"$$DST\""

dmg: ## 배포용 .dmg 만들기
	./scripts/build-dmg.sh

icons: ## 앱 아이콘·파일 아이콘 리소스 재생성
	./scripts/build-appicon
	./scripts/build-fileicons

integrate: ## Claude Code 훅·muxa notify 설치 (기본 dry-run, 실제 적용은 --apply)
	./scripts/install-integration.sh

clean: ## 빌드 산출물 삭제
	cd $(MACOS) && swift package clean
