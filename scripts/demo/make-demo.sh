#!/usr/bin/env bash
# 데모 스크린샷용 리포·트랜스크립트 생성 (MUXA_DEMO 시드가 이 경로들을 참조한다).
# 실제 git 변경을 만들어야 git 패널이 채워진다(GitService는 라이브 셸아웃).
set -euo pipefail

DEMO="${MUXA_DEMO_DIR:-$HOME/muxa-demo}"
TR="$DEMO/.transcripts"
rm -rf "$DEMO"
mkdir -p "$TR"

# ─── 데모 git 리포 하나 만들기: 커밋 몇 개 + 스테이지/언스테이지 변경 ───
make_repo() {
  local dir="$1"; shift
  mkdir -p "$dir"; cd "$dir"
  git init -q -b main
  git config user.email demo@muxa.app; git config user.name "muxa demo"
  mkdir -p src
  printf 'export const config = { port: 3000 }\n' > src/config.ts
  printf 'import { config } from "./config"\nconsole.log(config.port)\n' > src/index.ts
  printf '# %s\n\nDemo project.\n' "$(basename "$dir")" > README.md
  git add -A; git commit -qm "chore: 초기 구조"
  printf 'export function auth(token: string) { return token.length > 0 }\n' > src/auth.ts
  git add -A; git commit -qm "feat: auth 스텁 추가"
  printf 'fix: 세션 만료 처리\n' >> README.md; git add -A; git commit -qm "fix: 세션 만료 처리"
  # 스테이지된 변경
  printf 'export const config = { port: 3000, host: "0.0.0.0" }\n' > src/config.ts
  printf 'export async function login(u: string, p: string) {\n  return auth(u + p)\n}\n' > src/login.ts
  git add src/config.ts src/login.ts
  # 언스테이지 변경 + 삭제
  printf 'import { config } from "./config"\nimport { login } from "./login"\nconsole.log(config.port, config.host)\n' > src/index.ts
  git rm -q src/auth.ts
}

make_repo "$DEMO/webapp"
make_repo "$DEMO/api-server"

# ─── ANSI 트랜스크립트 (셸이 `clear; cat <file>`로 표시 — ghostty가 진짜 렌더) ───
esc() { printf '%b' "$1"; }
O='\033[38;5;209m'   # 주황 — claude ● 불릿
B='\033[38;5;39m'    # 파랑 — 파일 경로
G='\033[38;5;71m'    # 초록 — 추가
R='\033[38;5;203m'   # 빨강 — 삭제
I='\033[38;5;111m'   # 인디고 — 작업중
Y='\033[38;5;175m'   # 로즈 — 대기
S='\033[38;5;108m'   # 세이지 — 완료
D='\033[38;5;245m'   # 흐림
W='\033[38;5;253m'   # 본문
X='\033[0m'          # reset
Bd='\033[1m'

# 작업 중 — claude 편집 세션
esc "${O}>${X} ${W}세션 복원 정합성을 고쳐줘${X}\n\n${O}●${X} ${W}트리는 터미널만 복원하도록 layoutSnapshot을 분리하겠습니다.${X}\n\n  ${D}Read${X}  ${B}TerminalStore.swift${X} ${D}(240 lines)${X}\n  ${D}Edit${X}  ${B}SessionRestore.swift${X}\n        ${G}+18${X} ${R}-6${X}\n\n${O}●${X} ${W}문서·diff는 SavedViewer로 별도 복원합니다.${X}\n\n  ${I}⟳${X} ${D}Bash${X} ${W}swift build${X} ${D}— 컴파일 중…${X}\n" > "$TR/working.ans"

# 대기 — 권한 요청 프롬프트
esc "${O}●${X} ${W}TermView.swift의 재부모화 로직을 손봐야 합니다.${X}\n\n${Y}╭─ 권한 요청 ───────────────────╮${X}\n${Y}│${X}  Edit ${B}TermView.swift${X}            ${Y}│${X}\n${Y}│${X}  ${D}이 편집을 허용할까요?${X}          ${Y}│${X}\n${Y}│${X}                               ${Y}│${X}\n${Y}│${X}  ${W}❯ 1. 예${X}                        ${Y}│${X}\n${Y}│${X}    2. 아니오, 이유를 설명        ${Y}│${X}\n${Y}╰───────────────────────────────╯${X}\n\n${Y}⏸ 입력 대기 · 2m째${X}\n" > "$TR/waiting.ans"

# 완료 — 작업 마무리
esc "${O}●${X} ${W}워크트리 정리까지 끝났습니다.${X}\n\n  ${S}✓${X} ${W}3개 브랜치 병렬 작업 병합 완료${X}\n  ${D}.worktrees/ 정리 · exclude 갱신${X}\n\n  ${D}Read${X}  ${B}GitService+Worktree.swift${X}\n  ${D}Bash${X}  ${W}git worktree prune${X}\n\n${S}✓ 완료 · 방금${X}\n" > "$TR/done.ans"

# zsh — git log
esc "${D}~/muxa-demo/webapp${X} ${O}❯${X} ${W}git log --oneline -4${X}\n${Y}a1f3c2d${X} ${D}fix: 세션 만료 처리${X}\n${Y}7b9e410${X} ${D}feat: auth 스텁 추가${X}\n${Y}3c2d5a8${X} ${D}chore: 초기 구조${X}\n${D}~/muxa-demo/webapp${X} ${O}❯${X} \n" > "$TR/zsh.ans"

# api 작업중
esc "${O}>${X} ${W}로그인 엔드포인트에 rate limit 추가해줘${X}\n\n${O}●${X} ${W}login 라우트에 슬라이딩 윈도우 리미터를 답니다.${X}\n\n  ${D}Edit${X}  ${B}src/login.ts${X}  ${G}+22${X}\n  ${D}Write${X} ${B}src/rate-limit.ts${X}  ${G}+41${X}\n\n  ${I}⟳${X} ${D}Bash${X} ${W}pnpm test rate-limit${X} ${D}— 12 tests${X}\n" > "$TR/api-working.ans"

echo "데모 생성 완료: $DEMO"
ls -1 "$TR"
