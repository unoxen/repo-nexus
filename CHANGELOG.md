# Changelog

All notable changes to Repo Nexus (`rnex`) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.1] - 2026-10-25

### Added
- **Deterministic `git:` (`ignore` & `hooks`) Configuration Schema**:
  - Replaced legacy `git_hooks` with a unified `git:` configuration block.
  - Added declarative `git.ignore` list specifying custom ignore patterns reconciled into `.gitignore`.
  - Enforced safe, directory-only recursive ignore rules (`**/.rnex*/`, `**/rnex*/`, `repos/`) with trailing slashes, preventing accidental exclusion of the root `rnex` executable or `rnex.yaml`.
  - Added `git.hooks.<hook_name>` mapping Git events (`post-merge`, `post-checkout`, `pre-commit`, `pre-push`) to sequential command lists.
- **Formalized `rnex_hooks:` Lifecycle Engine**:
  - Added top-level `rnex_hooks:` mapping 18 workspace lifecycle events (`before_init`, `after_init`, `before_sync`, `after_sync`, `before_clone`, `after_clone`, `before_repo_add`, `after_repo_add`, `before_repo_remove`, `after_repo_remove`, `before_repo_set`, `after_repo_set`, `before_plugin_enable`, `after_plugin_enable`, `before_plugin_disable`, `after_plugin_disable`, `before_plugin_command`, `after_plugin_command`, `before_exec`, `after_exec`) to sequential command lists.
  - Added re-entrancy protection guard (`RNEX_HOOK_ACTIVE`) and exported hook execution environment variables.
- **Unified Single-Repository CLI Operations (`rnex repo`)**:
  - Namespaced all single-repository operations under `rnex repo`:
    - `rnex repo add <url> [--name <name>] [--branch <branch>] [--local] [--disabled] [--readonly]`
    - `rnex repo remove <name> [--purge] [-y|--yes]`
    - `rnex repo set <name> [--enable|--disable] [--readonly|--readwrite] [--global|--local]`
    - `rnex repo clone <name>`, `rnex repo status <name>`, `rnex repo exec <name> <cmd...>`, `rnex repo list`
- **Permanent AI Context Routing Across All 7 Providers**:
  - Ensured routing instruction blocks are permanently maintained in `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CODEX.md`, `.cursorrules`, `.windsurfrules`, and `.github/copilot-instructions.md` without stripping or deletion when plugins are disabled.
- **Extensible Plugin Command Engine**:
  - Added `rnex plugin <name> <command> [options...]` dispatcher (with shorthand fallback `rnex plugin <cmd>`).
  - Added command discovery and formatted tree branches in `rnex plugin list`.
  - Bound execution to `before_plugin_command` and `after_plugin_command` lifecycle hooks.
- **Karpathy LLM Wiki Subcommands & Config Cleanup**:
  - Defaulted `wiki_dir` to `wiki` at workspace root and removed legacy `lint_trigger` and `notify_on_changes`.
  - Shipped `rnex plugin karpathy-llm ingest [options]` and `rnex plugin karpathy-llm lint [options]`.
- **Documentation Site Overhaul (GitHub Pages / VitePress)**:
  - Responsive full-width layout with `--vp-layout-max-width: 100%`.
  - Always-visible left sidebar across all documentation pages (including Welcome via `layout: doc`).
  - Added desktop hide/show sidebar toggle button (`SidebarToggle.vue`) in the top-right navbar persisting preference in `sessionStorage`.
  - Restructured site into 5 clean top-level sections with dropdown menus on all navbar items: **Introduction**, **Documentation**, **Reference**, **Plugins**, and **FAQ**.
  - Configured `vitepress-plugin-mermaid` to natively render the RNEX architecture flowchart.

### Removed
- **Obsolete Commands**: Permanently removed `rnex upgrade`, `rnex update`, `rnex rnex-dir`, `rnex hooks`, `rnex enable`, `rnex disable`, and `rnex readonly`.
- **Legacy Flags**: Removed `rnex status --fix` in favor of `rnex sync`.

---

## [0.8.0] - 2026-10-24

### Added
- OpenAI Codex AI provider plugin (`codex`) maintaining `CODEX.md` and `.codex/skills/`.
- Read-only member repository mode (`readonly: true`) for reference repositories.
- Lazy, on-demand member `.rnex/` directory model.

---

## [0.7.0] - 2026-10-15

### Added
- Decoupled two-tier skills architecture: core agentic skills in `toolkit/skills/` and domain plugin skills in `toolkit/plugins/<plugin>/skills/`.
- Dual-format User Skill generator emitting `SKILL.md` bundles for Claude, Copilot, Codex, Gemini, and flat rule files for Cursor and Windsurf.
- Multi-source intake configuration (`sources`) supporting directory paths and recursive globs for the Karpathy LLM Wiki plugin.
- Event-driven auto-sync engine with checksum-based drift detection (`.rnex/sync_stamp`).

---

## [0.6.0] - 2026-10-11

### Added
- Initial VitePress documentation site for GitHub Pages deployment.
- Universal `AGENTS.md` standard with non-destructive delimited merging.
- Two-level configuration model (`rnex.yaml` team manifest and `.local.rnex.yaml` workstation overrides).

---

## [0.5.0] - 2026-10-08

### Added
- Modular library architecture in pure POSIX `/bin/sh` (`lib/core.sh`, `lib/workspace.sh`, `lib/yaml.sh`, `lib/repos.sh`, `lib/plugins.sh`, `lib/ai.sh`, `lib/hooks.sh`).
- Cross-repository batch execution engine (`rnex exec <command...>`).
- Declarative Git hook wrappers in `.git/hooks/*`.
