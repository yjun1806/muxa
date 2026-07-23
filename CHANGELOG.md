# Changelog

All notable changes to muxa are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and versions follow
[Semantic Versioning](https://semver.org/) — pre-1.0, so a minor bump may break.

## [Unreleased]

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

[Unreleased]: https://github.com/yjun1806/muxa/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yjun1806/muxa/releases/tag/v0.1.0
