<div align="center">

<img src="macos/Sources/muxa/Resources/AppIcon.png" width="120" alt="muxa" />

# muxa

### 여러 코딩 에이전트를 한 화면에서 지켜보는 macOS 터미널

어느 세션이 나를 기다리는지, 방금 뭘 바꿔놨는지 — 놓치지 않는다.

<br />

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://github.com/yjun1806/muxa/releases/latest)
[![Claude Code](https://img.shields.io/badge/agent-Claude%20Code-D97757?logo=anthropic&logoColor=white)](#지원-에이전트)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-F05138?logo=swift&logoColor=white)](macos/Package.swift)
[![Stars](https://img.shields.io/github/stars/yjun1806/muxa?style=flat&logo=github)](https://github.com/yjun1806/muxa/stargazers)

<br />

### [⬇︎ 다운로드 (macOS)](https://github.com/yjun1806/muxa/releases/latest)

<br />

<img src="docs/assets/real-split.png" width="960" alt="muxa — 여러 에이전트를 한 화면에서 지켜본다" />

<sub><i>사이드바 맨 위 로즈 카드가 나를 기다리는 세션을 모은다. 오른쪽 위 칸은 대기(로즈 테두리), 아래는 완료(세이지). 사이드바·탭·칸 테두리가 같은 어휘로 상태를 말한다.</i></sub>

</div>

<br />

**muxa**는 코딩 에이전트를 여러 개 띄워두고 지켜보는 macOS 터미널이다. Claude Code 세션을 한 프로젝트에서 동시에 돌리다 보면 정작 힘든 건 터미널이 느려서가 아니다 — 어느 세션이 내 입력을 기다리는지, 방금 뭘 바꿔놨는지를 놓치는 게 문제다. muxa는 그걸 한 화면에 모은다.

이름은 **mux + a(gent)**. tmux 계열 터미널 멀티플렉서에 "보는 눈"을 더했다.

> **현재 Claude Code 전용입니다.** 알림·상태 표시의 1차 소스가 Claude Code 훅이라, 지금은 Claude Code에 맞춰져 있습니다. 다른 에이전트 지원은 로드맵에 있습니다. → [지원 에이전트](#지원-에이전트)

<br />

## 기능

> 맨 위 화면이 **에이전트 알림**이다 — 어느 칸이 나를 기다리는지 **칸(pane) 단위**로 표시한다. Claude Code 훅이 1차 소스이고, 훅이 없으면 출력·프로세스 상태로 추정한다. 작업중·대기·완료를 **칸 테두리·탭·사이드바가 같은 기호**(스피너·⏸·✓)로 공유한다.

위 화면이 그대로 **자유 화면 분할 + 에이전트 알림**이다 — 경로 기반 워크스페이스 위에서 세로·가로 임의 중첩으로 재귀 분할하고, 각 칸의 상태(작업중 인디고·대기 로즈·완료 세이지)를 칸 테두리·탭·사이드바가 같은 어휘로 말한다. 나를 기다리는 세션은 사이드바 맨 위 큐 카드에 모인다.

<table>
<tr>
<td width="46%" valign="top">

### git 가시성

상태·diff·히스토리를 바로 보고 **스테이징·커밋까지 앱 안에서**. 실제 변경이 스테이지됨/변경으로 갈려 색으로 뜬다(추가·수정·삭제). 워크트리를 만들고 정리해 **브랜치별로 에이전트를 병렬**로 돌린다.

</td>
<td width="54%"><img src="docs/assets/real-git.png" alt="git 변경·스테이징·커밋 패널" /></td>
</tr>

<tr>
<td width="54%"><img src="docs/assets/real-viewer.png" alt="렌더된 Markdown 뷰어 + git 패널" /></td>
<td width="46%" valign="top">

### 보는 눈 (읽기 전용)

mermaid까지 그리는 **Markdown 뷰어**, 코드·diff 뷰어. 에이전트가 문서를 쓰는 동안 **실시간 리로드**로 지켜본다. 결과물을 보려고 VS Code를 따로 열 필요가 없다.

</td>
</tr>

<tr>
<td width="46%" valign="top">

### 파일 익스플로러

git 색·Material 아이콘이 붙은 파일 트리. 우클릭으로 여기서 터미널을 열고, 파일을 뷰어로 연다. 에이전트가 만든 결과물을 그 자리에서 훑는다.

</td>
<td width="54%"><img src="docs/assets/real-explorer.png" alt="파일 익스플로러 트리" /></td>
</tr>
</table>

**그 밖에** — **서비스·스크립트**(dev 서버·빌드를 탭 밖 전용 tmux에서, 앱을 꺼도 유지·푸터에서 상태 확인) · 창 분리(프로젝트를 별도 창으로 떼었다 셸을 죽이지 않고 다시 합치기) · ⌘F libghostty 네이티브 검색 · 세션 복원(분할 트리·탭·cwd) · 완벽한 한글 IME · ⌘K 명령 팔레트.

<br />

## 설치

### DMG (권장)

1. [최신 릴리스](https://github.com/yjun1806/muxa/releases/latest)에서 `.dmg`를 받아 열고 **muxa.app을 `/Applications`로 드래그**한다.
2. 처음 실행하면 **"개발자를 확인할 수 없어 열 수 없습니다"**가 뜬다 — 아직 공증(notarization) 전이라 정상이다.
   **시스템 설정 › 개인정보 보호 및 보안**을 열고 아래쪽 "muxa이(가) 차단되었습니다"에서 **'그래도 열기'**를 누른다.
   (macOS 15+에서는 Control-클릭 '열기' 우회가 막혀 이 경로만 동작한다.)

### Homebrew

```sh
brew install --cask yjun1806/tap/muxa   # 준비 중 — tap 출시 후 활성화됩니다
```

### 첫 실행 권한

- **알림** — 에이전트가 나를 기다릴 때 알려준다(거부해도 앱 안 인박스에는 쌓인다).
- **폴더 접근**(문서·데스크탑·다운로드) — 그 폴더의 프로젝트를 열고 git 상태를 읽는다. 거부하면 파일 트리가 빈다.

### 필요한 외부 도구

| 도구 | 용도 | |
|---|---|---|
| `git` | diff·히스토리·워크트리 | 필수 |
| `tmux` | 서비스·스크립트 (없으면 앱이 설치 명령을 안내) | 선택 |
| `gh` | PR 배지 | 선택 |

**설정**은 앱 메뉴 › `설정 파일 열기…`(⌘,) — `~/.config/muxa/config`에 주석 달린 기본본이 생기고, 저장하면 즉시 반영된다.
**단축키**는 메뉴바 `명령` 메뉴에 전부 있다.

<br />

## 왜 muxa?

에이전트 여럿 사이를 오가는 워크플로에서 병목은 렌더링 처리량이 아니라 **주의와 전환**이다. 어느 칸이 나를 부르는지, 방금 뭘 만들었는지. 그래서 muxa가 갈고닦는 "터미널 품질"은 렌더러 충실도가 아니라 **멀티플렉싱의 질** — 전환, 주의, 동시 감시다.

그리고 muxa는 **편집기가 아니다.** 코드는 에이전트가 고치고, 사람이 직접 손댈 일이 생기면 VS Code를 연다. muxa의 뷰어가 전부 읽기 전용인 이유다 — 보고, 판단하고, 다음 지시를 내리는 자리다.

<br />

## 지원 에이전트

지금은 **Claude Code 전용**이다. 알림·상태 표시의 1차 소스가 Claude Code 훅(`muxa-notify`)이라, 완결된 상태 판정(작업중·대기·완료·유휴)이 Claude Code에 맞춰져 있다. 다른 CLI 에이전트도 터미널로 띄워 쓸 수는 있지만, 정밀한 알림은 아직 Claude Code에서만 완전하다.

다른 에이전트(Codex·Gemini 등) 지원은 **로드맵**에 있다.

<br />

## 스택

Swift/SwiftUI + AppKit으로 만든 네이티브 앱이다(macOS 14+). 터미널 코어는 **libghostty** 임베딩, 분할·탭은 **Bonsplit**, git은 CLI 셸아웃으로 처리한다.

macOS 전용인 이유가 하나 있다 — 한국어로 에이전트와 대화하려면 완벽한 한글 IME가 필요한데, 그건 네이티브 `NSTextInputClient` 구현으로만 가능하다. WebView·Electron 스택은 IME composition 결손으로 자모가 샌다.

<br />

## 문서

| 문서 | 내용 |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | 왜 이렇게 만들었나 — 결정 로그·아키텍처·서브시스템 |
| [DESIGN.md](docs/DESIGN.md) | 어떻게 보이나 — 색·타이포·간격·컴포넌트 |
| [STATUS.md](docs/STATUS.md) | 현재 상태·다음 할 일 |
