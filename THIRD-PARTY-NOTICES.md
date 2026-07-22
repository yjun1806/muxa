# Third-Party Notices

muxa is licensed under the MIT License (see [LICENSE](LICENSE)). It bundles,
links, or builds on the third-party software listed below, each under its own
license. This file collects the required attributions.

If you redistribute a build of muxa, include this file (and the upstream
license texts it points to).

---

## Bundled / linked at build time

### ghostty (terminal core)
- **What**: The terminal engine (PTY, VT parsing, GPU rendering). muxa embeds it
  as a prebuilt `GhosttyKit.xcframework` (universal binary), downloaded by
  `scripts/bootstrap.sh`. The prebuilt is produced from the cmux fork
  (`manaflow-ai/ghostty`) of upstream ghostty.
- **Upstream**: https://github.com/ghostty-org/ghostty
- **License**: MIT
- **Note**: The `GhosttyKit` binary statically includes several C/C++ libraries
  (e.g. zlib, FreeType, HarfBuzz, oniguruma, Dear ImGui, libpng, gettext/libintl).
  Each carries its own permissive/OSS license; see ghostty's upstream
  `third_party` and build manifests for the authoritative list and texts.

### Bonsplit (split & tab framework)
- **What**: SwiftUI split/tab layout engine used for panes and tabs. muxa uses
  our own fork, revision-pinned in `macos/Package.swift`.
- **Fork chain**: almonk/bonsplit → manaflow-ai/bonsplit → yjun1806/bonsplit (`muxa` branch)
- **Our fork**: https://github.com/yjun1806/bonsplit
- **License**: MIT

## Bundled document/code rendering (in-app WebView resources)

| Library | Used for | License | Upstream |
|---|---|---|---|
| markdown-it | Markdown parsing/rendering | MIT | https://github.com/markdown-it/markdown-it |
| highlight.js | Code syntax highlighting (markdown viewer) | BSD-3-Clause | https://github.com/highlightjs/highlight.js |
| Mermaid | Diagram rendering in markdown | MIT | https://github.com/mermaid-js/mermaid |
| Shiki | Code syntax highlighting (code viewer) | MIT | https://github.com/shikijs/shiki |

## Bundled assets

### Material Icon Theme (file-tree icons)
- **What**: File/folder icon set and extension→icon mapping used by the explorer.
- **Upstream**: https://github.com/PKief/vscode-material-icon-theme
- **License**: MIT

---

## Referenced for design (no code copied)

These projects were studied as reference implementations for architecture and
technique while building muxa's native layer. No source code from them is
included in muxa.

- **cmux** — https://github.com/manaflow-ai/cmux — **GPL-3.0-or-later**.
  Studied for the native Swift + libghostty approach and for feature design
  (session persistence, notification hooks, worktree handling). muxa's
  implementation is independently written; where a low-level helper originally
  echoed cmux's expression, it was rewritten clean-room before release.
- **orca** — referenced for design comparison.
