# Changelog

All notable changes to Repo Nexus (`rnex`) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] - 2026-10-24

### Added
- **Unified `git:` Configuration Section (`git.ignore` & `git.hooks`)**:
  - Replaced legacy top-level `git_hooks` with a structured `git:` block in `rnex.yaml` and `.local.rnex.yaml`.
  - Added declarative `git.ignore` list specifying custom patterns added to `.gitignore`.
  - Added recursive, directory-only rules (`**/.rnex*/`, `**/rnex*/`, `repos/`) with trailing slashes so the `rnex` CLI binary and `rnex.yaml` remain tracked.
  - Added `git.hooks.<hook_name>` mapping Git hook events (`post-merge`, `post-checkout`, `pre-commit`, `pre-push`) to sequential command lists.
- **Unified Single-Repository CLI Operations (`rnex repo`)**:
  - Consolidated single-repository commands under the `rnex repo` subcommand namespace:
    - `rnex repo add <url> [--name <name>] [--branch <branch>] [--local] [--disabled] [--readonly]`
    - `rnex repo remove <name> [--force]`
    - `rnex repo set <name> [--enable|--disable] [--readonly|--readwrite] [--local]`
    - `rnex repo clone <name>`
    - `rnex repo status <name>`
    - `rnex repo exec <name> <cmd...>`
- **Permanent Main Context Files**:
  - AI routing instructions in `AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `GEMINI.md`, `.cursorrules`, `.windsurfrules`, and `.github/copilot-instructions.md` are permanently preserved across plugin disable transitions.
- **Extensible Plugin CLI Engine**:
  - Added `rnex plugin <name> <command> [options...]` dispatcher executing subcommands discovered from `.rnex/plugins/<name>/commands/<command>.sh`.
- **Karpathy LLM Wiki CLI Subcommands & Root Directory**:
  - Defaulted `wiki_dir` to `wiki` at the workspace root.
  - Shipped `rnex plugin karpathy-llm ingest [options]` and `rnex plugin karpathy-llm lint [options]` subcommands.

### Changed
- **CLI Command Consolidation & Deletion**:
  - Removed obsolete standalone commands: `rnex update`, `rnex upgrade`, `rnex rnex-dir`, `rnex hooks`, `rnex enable`, `rnex disable`, and `rnex readonly`.
  - Consolidated all workspace synchronization and reconciliation into `rnex sync`.
  - Cleaned up `karpathy-llm` plugin options by removing legacy `lint_trigger` and `notify_on_changes`.

---

## [0.7.39] - 2026-10-22

### Added
- **OpenAI Codex AI Provider Plugin (`codex`)**:
  - Integrated OpenAI Codex CLI (`codex`) into Repo Nexus via `toolkit/plugins/codex/`.
  - Maintains routing instructions in `CODEX.md` and generates zero-logic User Skill bundles in `.codex/skills/`.
  - Added `--codex` flag to `rnex init`.
- **Read-Only Member Repository Mode (`readonly: true`)**:
  - Added `readonly: true|false` flag to member repository declarations in `rnex.yaml` and `.local.rnex.yaml`.
  - Designates reference repositories as information-only for AI coding assistants.
- **Lazy / On-Demand Member `.rnex/` Directory Model**:
  - Member repositories remain completely clean and untouched by default.
  - Member `.rnex/` folders are only instantiated on-demand when active plugins require repository-level state.

---

## [0.7.30] - 2026-10-21

### Refactored
- **Core Library Architecture & Unified YAML Primitives**:
  - Extracted single-source plugin SDK into `lib/sdk.sh` and unified YAML parsing primitives in `lib/yaml.sh`.
  - Standardized plugin hook execution and lifecycle dispatchers across core modules.
  - Hardened template placeholder substitution and eliminated intermediate path leakage.

---

## [0.7.26] - 2026-10-21

### Added
- **Multi-Source Intake Configuration for Karpathy LLM Wiki (`sources`)**:
  - Replaced single `raw_dir` scalar configuration with multi-value `sources` list under `plugins.karpathy-llm.sources`.
  - Added pure POSIX `/bin/sh` glob and directory resolver supporting both directory paths (e.g. `docs`) and recursive/single-level globs (e.g. `"repos/**/README.md"`).
  - Automatically excludes member repositories marked `enabled: false` from resolved intake paths.
  - Enforced two-level configuration precedence: `.local.rnex.yaml` overrides `rnex.yaml`.
  - Added automatic directory pruning for `.git`, `.rnex`, and `node_modules`.

---

## [0.7.7] - 2026-10-15

### Added
- **Dual-Format User Skill Generator (`SKILL.md` Bundles & Rules)**:
  - Upgraded User Skill generator (`rnex_register_user_skill`) to emit dual formats tailored to each AI provider's discovery engine:
    - **Skill-Based Providers (`.github/skills/`, `.claude/skills/`, `.agents/skills/`, `.codex/skills/`)**: Generates native `rnex-<name>/SKILL.md` directory bundles containing YAML frontmatter for VS Code, Copilot Chat, Antigravity, and Claude Code.
    - **Rule-Based Providers (`.cursor/rules/`, `.windsurf/rules/`)**: Generates flat `rnex-<name>.md` pointer files aligning with Cursor and Windsurf conventions.
- **GitHub Copilot Integration Plugin (`copilot`)**:
  - Restored `copilot` as a first-class AI provider plugin supporting `instructions: true` (`.github/copilot-instructions.md`) and `skills: true` (`.github/skills/`).

---

## [0.7.5] - 2026-10-15

### Added
- **Strict Separation of Core `rnex` Skills and Plugin Skills**:
  - Core agentic skills live exclusively in `toolkit/skills/*.md` (`clone-sync.md`, `batch-exec.md`, `workspace-status.md`).
  - Plugin-owned skills live strictly inside `toolkit/plugins/<plugin>/skills/*.md` (e.g. `wiki-ingest.md`, `wiki-lint.md`).
- **On-the-Fly Zero-Logic User Skill Generator**:
  - Lightweight User Skill pointers (`rnex-<name>.md` / `rnex-<name>/SKILL.md`) direct AI assistants strictly to underlying agentic protocols in `.rnex/`.
- **Event-Driven Auto-Sync Engine**:
  - Checksum-based drift detection (`.rnex/sync_stamp`) that runs `rnex sync --quiet` automatically on mutating commands, shell prompt hooks, and Git hooks.
- **Modular Test Suite Architecture**:
  - Decomposed test runner into modular test suites under `tests/suites/` (`01_core_cli.sh` through `07_goal_fixes.sh`).

### Removed
- **`rnex fix` and `rnex status --fix`**: Permanently replaced by `rnex sync` as the single idempotent reconciliation entrypoint.

---

## [0.6.5] - 2026-10-12

### Added
- **Dynamic AI Instructions & Plugin Deactivation**:
  - Dynamic evaluation of active plugins when assembling routing instructions.
  - Scoped directories (`.rnex/plugins/<plugin>/`) and prompt mirrors are cleaned when a plugin is disabled.
  - Strict preservation of user-authored knowledge in wiki and intake directories.

---

## [0.6.0] - 2026-10-11

### Added
- **VitePress Documentation Site**:
  - Comprehensive documentation site covering architecture, guides, CLI reference, plugin ecosystem, and examples.
- **Universal `AGENTS.md` & Provider Instructions Architecture**:
  - `AGENTS.md` at workspace root established as universal cross-tool standard.
  - Assistants with native formats (`CLAUDE.md`, `GEMINI.md`, `CODEX.md`, `.cursorrules`, `.windsurfrules`) maintained cleanly.

---

## [0.5.9] - 2026-10-10

### Refactored
- **Modular POSIX Shell Codebase Architecture (`lib/`)**:
  - Decomposed monolithic script into modular libraries: `lib/core.sh`, `lib/workspace.sh`, `lib/yaml.sh`, `lib/repos.sh`, `lib/plugins.sh`, `lib/ai.sh`, `lib/hooks.sh`.
  - Extracted CLI commands into `lib/commands/`.

---

## [0.5.0] - 2026-10-08

### Added
- **Version-Aware Upgrade System**:
  - Automatically compares workspace configuration against the running CLI version and upgrades schema keys non-destructively.
- **Config-Driven Automated Git Hooks**:
  - Git hook dispatcher scripts executing configured actions on `post-merge`, `post-checkout`, `pre-commit`, and `pre-push`.
- **Standardized Prompts & Skills Catalog**:
  - Standardized agentic workflows for cross-repo feature implementation, workspace auditing, and wiki curation.

---

## [0.4.0] - 2026-10-05

### Added
- **Virtual Meta-Repo 2.0**:
  - Physical member repository clones in `./repos/<name>` with complete Git isolation (no submodules).
  - Two-level configuration (`rnex.yaml` team manifest and `.local.rnex.yaml` workstation overrides).
  - Cross-repository batch execution (`rnex exec <command...>`).
  - Scoped workspace plugins (`.rnex/plugins/<plugin-name>/`).
