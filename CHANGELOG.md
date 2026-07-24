# Changelog

All notable changes to muxa are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and versions follow
[Semantic Versioning](https://semver.org/) — pre-1.0, so a minor bump may break.

## [Unreleased]

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

[Unreleased]: https://github.com/yjun1806/muxa/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/yjun1806/muxa/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/yjun1806/muxa/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yjun1806/muxa/releases/tag/v0.1.0
