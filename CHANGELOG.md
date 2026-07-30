# Changelog

All notable changes to muxa are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and versions follow
[Semantic Versioning](https://semver.org/) — pre-1.0, so a minor bump may break.

## [Unreleased]

## [0.7.0] - 2026-07-30

### Added
- **Agent panel** — a new tool panel (left rail, Claude mark) that answers a question the Git panel
  structurally cannot: *which claude session changed this?* A workspace often runs several sessions
  at once, and until now their edits all landed in one undifferentiated pile of working-tree changes.
  The panel groups them **by session**, titled with the prompt that started the session's first
  collected turn. One group is open at a time; clicking another session **moves you to that terminal
  tab**, so the panel doubles as a session switcher. Every row opens as a **diff** against the HEAD
  captured when that session first touched anything — not against the branch base, so unrelated work
  in the repo doesn't leak into the comparison. Files the session *created* render as documents with
  a header badge instead of a wall of green. Rows you haven't opened are **bold**; opening one mutes
  it, and the agent touching it again makes it bold once more. A residual row counts changes the
  panel doesn't know about (your own edits, or the agent's `Bash`-driven ones) and hands you off to
  the Git panel — the panel never claims to be the whole truth.
- **Session detail** — a per-session view with two regions: **변경** (what it edited) and **참고**
  (what it read, and which URLs it fetched), both grouped by folder and annotated with the
  instruction that led there. Opening it fills the group; clicking a file narrows it to a resizable
  sidebar with the diff alongside. It can be widened, expanded to full width, or collapsed to a rail,
  and it comes back where you left it after a restart.

  This costs Claude Code nothing new: it reads the `PreToolUse` hook muxa already subscribes to, so
  no hook is installed, no extra process is spawned per tool call, and `settings.json` is untouched.

### Fixed
- **`make test` no longer fails on a renamed target** — a test asserted the presence of a Makefile
  target that had been renamed, so a clean checkout failed its own suite.


## [0.6.1] - 2026-07-29

### Fixed
- **"분리됨" no longer swallows sessions that still have a tab** — the session manager decided
  attachment from tmux clients alone, so a session whose tab exists but isn't currently attached
  (right after launching the app, or after you detach) looked identical to one whose tab is gone.
  Only the second is lost; the first comes back the moment you go to that tab. They're now separate
  states — **미연결** (tab exists, not attached) and **분리됨** (no tab to return to) — and the
  "숨은 터미널" filter lists only the latter, so normal startup state no longer floods the list you
  opened to find abandoned sessions. The tab set is re-read on every poll, since tabs open and close
  while the window is up.


## [0.6.0] - 2026-07-29

### Added
- **Session manager** — a new window (right rail, or 창 ▸ 세션 관리자) listing every muxa tmux session
  on the machine, not just the ones this app knows about. muxa's terminals and services live in tmux
  sessions that outlive the app, and until now nothing showed you the ones left behind — on this
  machine that was 41 sessions across 5 sockets while the app itself could see one socket. Rows are
  grouped by workspace and sorted by memory, so what you must *not* touch surfaces first. Each row
  shows what is running inside it (`claude`, `esbuild`, …), its memory and CPU, and **who is currently
  looking at it**: this app, another muxa instance, an external terminal, or nobody. That last one is
  the point — a terminal still alive with no tab attached is what you came here to find. Select a row
  to see its last screen, double-click to jump to that tab (or bring the owning app forward), ⓧ to
  kill it. The confirmation names what is running inside, because weight predicts "is this safe to
  kill" far better than registration does: the heaviest session here was unregistered but had a
  headless Chrome and esbuild inside it.

### Fixed
- **Closing a tab no longer kills work you couldn't see** — the process scan behind *"is anything
  running in this pane?"* was reading a quarter of the machine's processes (it divided a count that
  was already a count) and then stopping at the first root-owned process in the chain — `login`, which
  sits between every tab and the app. Both made the tree look empty, so `⌘W` on a tab with a
  30-minute build running would close it without asking. It now enumerates the same way `ps` does.
- **Service logs and ports come back** — `capture-pane` was called with a target tmux rejects
  (`=<session>` without the trailing `:`), and since stderr is discarded the failure was
  indistinguishable from an empty log. That path feeds the service log view and the port on service
  chips, so `:3000` had stopped appearing.


## [0.5.2] - 2026-07-27

### Fixed
- **Markdown diff highlights land on the right characters** — in a document diff the highlight could sit on entirely the wrong text, from two independent causes. The model measured offsets against the raw markdown source while the painter looked them up in the rendered DOM, so any paragraph containing bold, inline code, or a link drifted by the length of its markup — and when a long link sat near the front, the offset ran past the end of the text and *nothing* was painted. Separately, restored deletions were inserted into the DOM before the highlight ranges were resolved, so editing `이 문단을` → `이 문단이` painted the deleted `을` instead of the new `이`; that one hit plain paragraphs, code blocks, and table cells alike.
- **Changed HTML blocks now say so** — a modified `html_block` silently painted nothing, because its offsets were measured against the raw HTML with tags included. It falls back to an "HTML 변경됨" badge now, the same way a table does when its row/column structure changes. Which part of the HTML changed is still not marked: stripping tags with a regex breaks on `>` inside attribute values, and an offset that is wrong paints the wrong characters without telling you.

### Documentation
- README brought up to date with everything shipped in 0.2.0–0.5.1.


## [0.5.1] - 2026-07-27

### Fixed
- **Claude IDE connection survives a muxa restart** — after restarting (including an auto-update), tabs that were already open lost their IDE connection for good: `claude` couldn't see muxa even after `/ide`, and only a brand-new terminal tab worked. muxa plants the IDE port in the shell's environment, but the shell lives in a tmux pane that outlives the app, so a fresh random port on every launch left that value pointing at nothing — and the CLI only skips its ancestry check when the port matches, which a tmux-hosted pane can never satisfy otherwise. muxa now remembers each session's port and reclaims it on the next launch (falling back to a random one if it's taken).
- Each shell now gets exactly one IDE server. Reclaiming a backgrounded session used to spin up a second server for the same shell, so `claude` stayed on the old port while selections were routed to the new one.


## [0.5.0] - 2026-07-27

### Added
- **Workspace reordering** — grab the grip on the left of a workspace row in the sidebar (it replaces the avatar on hover) and drag to change the order. The row lifts and follows the cursor while the others shift to open a gap; Esc cancels the drag. Order is the array position itself, so it persists with the rest of the state and needs no migration. Expanded sidebar only — the collapsed modes are too narrow for a grip.
- **Command tab follows `cd`** — moving the run path with `cd` now re-parses that folder's scripts, and running or favoriting a discovered script uses the same path the list came from, so the list and what actually runs can no longer disagree. The `cd` dropdown moves folders on Enter from the highlighted entry, and ↑↓ scrolls the completion popup to follow the highlight.

### Fixed
- Terminal tab drag-selection and copy restored (per-session mouse off in tmux).


## [0.4.0] - 2026-07-24

### Added
- **Claude Code IDE integration** — muxa now acts as an IDE that the `claude` CLI connects to (like the VS Code extension). Select text in a document or code viewer and it's shared with the Claude session in that pane automatically; a footer band under the terminal shows exactly what's shared (file · lines · preview) and clears it with an ✕. Each Claude session gets its own isolated endpoint, so a selection reaches only the session you're working in.
- **Auto-update** — muxa checks GitHub for newer tagged versions and can install them itself (source rebuild); an update entry surfaces on the activity rail, with controls in Settings.

## [0.3.0] - 2026-07-23

### Added
- **Activity rail** — the tool panels (explorer, git, notifications, settings) now sit on an always-visible right-side rail with one-click entry and notification badges, instead of a single toggle that reopened the last panel. The active panel is shown by background emphasis alone.
- **Subtab split & merge** — pull a viewer subtab out into its own split pane, or merge a pane back into a group, from the right-click menu or by dragging a file subtab (no libghostty fork needed).
- **Claude button** — a Claude icon in the tab action lane opens a persistent (∞) session and launches `claude` right away, run as the tab's first process (via a login shell) so there's no prompt-timing flicker.
- **Installer** — the one-line install script gained a progress spinner, version display, and an update mode; an optional `MUXA_SLIM` mode reclaims disk by cleaning `.build/` after install.

### Changed
- The install clone now lives under XDG (`~/.local/share/muxa`).

### Fixed
- Close-confirmation banner shortcuts (⌘W / ⌘B / ⌘C) now work with a Korean input source active — they were matched by character, which returns Hangul jamo, so only the mouse worked.
- Subtab drag-to-detach rewritten (movingTab); splitting or merging no longer jumps the tab selection.
- Code viewer — tightened the gap between line numbers and code (dropped a stray 44px pad).


## [0.2.0] - 2026-07-23

### Added
- **Document source toggle** — a "원본 / 미리보기" button in the top-right of the document viewer flips between the rendered document and the raw text. Works for both Markdown and HTML files, and inside grouped subtabs; scroll resets to top on switch.

## [0.1.0] - 2026-07-23

First tagged release — a macOS agent terminal with a built-in document viewer and diff.

### Added
- **Embedded terminal** — ghostty (libghostty) embedded directly as a real GPU-drawn terminal; splits and tabs via Bonsplit.
- **Rendered document viewer** — Markdown with tables and mermaid diagrams, syntax-highlighted code, images and video; auto-refreshes on agent edits without losing scroll position.
- **Diff on the rendered document** — changes painted on top of rendered Markdown (tables stay tables); revert per file or per hunk; a comment on a changed line is sent to the terminal.
- **File explorer** — VSCode-style colored icons, git status shown by name color, create/rename/delete (delete moves to Trash).
- **Tab grouping** — viewer tabs auto-grouped into Docs / HTML / Code / Media / Changes lanes, each sub-tab keeping its own scroll position.
- **Worktree awareness** — new worktrees detected instantly and offered as projects; create a worktree from inside the app; a running session can move across worktrees (persistent sessions only).
- **tmux-backed persistence** — sessions survive quitting, force-quitting, or restarting the app; with tmux, new tabs are persistent (∞) by default.
- **Status & notifications** — unified working / waiting / done glyphs across pane borders, tabs, the sidebar, and a missed-notification inbox; macOS notifications carry the agent's last words.
- **Services dock** — long-running services, on-demand scripts (built from the Makefile), and one-off processes, all managed independently of tabs; exit code and logs preserved on stop.
- **Also** — Claude usage display, window detach and merge-back, session restore (split tree / tabs / cwd), `⌘K` command palette, and resuming a dropped session via `--resume`.

### Notes
- Status and notifications are tuned to Claude Code. macOS 14+. Build from source — no prebuilt binary; install with the one-line script or `make`.

[Unreleased]: https://github.com/yjun1806/muxa/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/yjun1806/muxa/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/yjun1806/muxa/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/yjun1806/muxa/compare/v0.5.2...v0.6.0
[0.5.2]: https://github.com/yjun1806/muxa/compare/v0.5.1...v0.5.2
[0.3.0]: https://github.com/yjun1806/muxa/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/yjun1806/muxa/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yjun1806/muxa/releases/tag/v0.1.0
