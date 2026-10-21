# Changelog

All notable changes to Repo Nexus (`rnex`) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.26] - 2026-10-21

### Added
- **Multi-Source Intake Configuration for Karpathy LLM Wiki (`sources`)**:
  - Replaced single `raw_dir` scalar configuration with multi-value `sources` list under `plugins.karpathy-llm.sources`.
  - Added pure POSIX `/bin/sh` glob and directory resolver (`resolve_plugin_sources`) supporting both explicit directory paths (e.g. `docs`) and recursive/single-level glob patterns (e.g. `"repos/**/README.md"`, `repos/*/README.md`).
  - Implemented automatic exclusion of member repositories disabled locally or globally (`enabled: false`) from resolved intake paths.
  - Enforced two-level configuration precedence: `.local.rnex.yaml` takes full precedence over `rnex.yaml` when defining `sources`.
  - Added automatic directory pruning for `.git`, `.rnex`, and `node_modules` during recursive file traversal.
  - Added safe directory provisioning in `rnex sync` that creates explicit directory sources (such as `docs`) while skipping wildcard patterns and file targets.

### Changed
- **Default Intake Sources**:
  - Default sources for `karpathy-llm` plugin are now `docs` and `"repos/**/README.md"`.
  - Updated `rnex init` templates, `rnex status`, and plugin scaffolding to render and configure multi-line `sources`.
  - Updated plugin lifecycle hooks (`after_sync.sh`, `git_*.sh`) and agentic skills (`wiki-ingest.md`, `wiki-lint.md`) to resolve documentation from `sources`.

### Deprecated
- **Legacy `raw_dir` Configuration**:
  - `plugins.karpathy-llm.raw_dir` is deprecated in favor of `sources`. Workspaces configuring `raw_dir` are automatically read via transparent fallback with a non-fatal deprecation notice advising migration to `sources`.

## [0.7.7] - 2026-10-15

### Added
- **Native `SKILL.md` Bundle Support for User Skills**:
  - Upgraded User Skill generator (`rnex_register_user_skill`) to emit dual formats tailored to each AI provider's discovery engine:
    - **Skill-Based Providers (`.github/skills/`, `.claude/skills/`, `.gemini/skills/`)**: Generates native `rnex-<name>/SKILL.md` directory bundles containing YAML frontmatter (`name: rnex-<name>`, `description: "..."`) for automatic discoverability in VS Code, Copilot Chat, Antigravity, and Claude Code skill-pickers.
    - **Rule-Based Providers (`.cursor/rules/`, `.windsurf/rules/`)**: Generates flat `rnex-<name>.md` pointer files aligning with Cursor and Windsurf rule conventions.
  - Automatically extracts skill descriptions from target markdown headers to populate YAML frontmatter cleanly.
- **GitHub Copilot Integration Plugin (`copilot`)**:
  - Restored `copilot` as a first-class AI provider plugin in `toolkit/plugins/copilot/`.
  - Supports `instructions: true` (managing `.github/copilot-instructions.md` within non-destructive delimiters) and `skills: true` (generating native User Skill bundles in `.github/skills/`).
  - Added CLI flags `--copilot` and `--no-copilot` to `rnex init`.

## [0.7.5] - 2026-10-15

### Added
- **Strict Separation of Core `rnex` Skills and Plugin Skills**:
  - Core agentic skills live exclusively in `toolkit/skills/*.md` and sync strictly to `.rnex/skills/*.md` (`clone-sync.md`, `batch-exec.md`, `workspace-status.md`).
  - Plugin-owned skills live strictly inside `toolkit/plugins/<plugin>/skills/*.md` and sync strictly to `.rnex/plugins/<plugin>/skills/*.md` (e.g. `wiki-ingest.md`, `wiki-lint.md`).
  - Strict isolation guarantee: plugin skills are never placed in `.rnex/skills/`, and core skills are never placed in plugin directories.
- **On-the-Fly Zero-Logic User Skill Generator**:
  - Generates lightweight User Skill pointers prefixed with `rnex-` (`rnex-<name>.md`) into active AI provider directories (`.cursor/rules/`, `.claude/skills/`, `.gemini/skills/`, `.windsurf/rules/`).
  - Contains zero inline operational heuristics—only a strict reference link directing AI assistants to the agentic protocol in `.rnex/`.
- **Plugin Contract Helper API**:
  - Added `rnex_register_user_skill <name> <path>` and `rnex_unregister_user_skill <name>` POSIX helper functions exported in `.rnex/bin/rnex-env.sh` and sourced in hook subshells.
  - Dynamically evaluates `RNEX_PROVIDER_SKILL_DIRS` based on enabled AI provider plugins (`skills: true`).
- **Provider Plugin Configuration (`skills: true`)**:
  - Added native `skills: true` configuration support across `claude`, `gemini`, `cursor`, and `windsurf` plugins.
- **Plugin Lifecycle Hooks Contract**:
  - Added `before_<cmd>` and `after_<cmd>` hook execution across all mutating commands while bypassing read-only commands (`status`, `list`, `completion`).
  - Added `before_plugin_disable` hook dispatched by `rnex plugin disable <name>` and plugin pruning in `rnex sync` to unregister plugin-owned User Skills.
- **Compiled AI Instructions (`.rnex/ai-instructions.md`)**:
  - `rnex sync` compiles a unified instruction file inside `.rnex/` from merged 2-level config, base template, and active plugin instruction fragments.
- **Event-Driven Auto-Sync**:
  - Checksum-based config drift detection (`.rnex/.sync_stamp`) that runs `rnex sync --quiet` automatically on any mutating command, `rnex list`, shell prompt hooks (`_rnex_auto_sync`), AI session startup (`SessionStart` hook), and Git hooks (`post-merge`, `post-checkout`, `pre-commit`).
- **Modular Test Suite Architecture**:
  - Decomposed test runner into modular test suites under `tests/suites/` (`01_core_cli.sh` through `06_plugins_advanced.sh`) with shared harness `tests/test_helper.sh`.

### Changed
- **Provider Plugin Options**: Deprecated and replaced legacy `prompts: true` and `workflows: true` options with `instructions: true` and `skills: true`.
- **Root AI Provider Directives**: Standardized `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, and `.windsurfrules` to route AI assistants cleanly to `.rnex/ai-instructions.md`.
- **Karpathy LLM Wiki Architecture**:
  - Moved workflows to plugin agentic skills under `toolkit/plugins/karpathy-llm/skills/`.
  - Added dynamic navigation index fallback: generated repository pages (`repo-<name>.md`) reference `index.md` when specialized navigation pages are absent.
  - Added hot cache word count ceiling: automatically bounds `.rnex/wiki/hot.md` to $\le 480$ words and collapses catalog links when workspace metadata expands across $>10$ repositories.

### Fixed
- **Custom Copilot Instructions Preservation**: Fixed non-destructive cleanup in `lib/ai.sh` to strictly preserve custom developer guidelines authored in `.github/copilot-instructions.md` outside `REPO-NEXUS` delimiters.
- **Documentation & Manifest Consistency**: Purged obsolete `prompts` and `workflows` references across plugin manifests (`plugin.yaml`), READMEs, CLI docs, configuration guides, and `lib/yaml.sh`.

### Removed
- **Legacy Prompts & Workflows**: Completely purged `toolkit/prompts/`, `toolkit/workflows/`, and obsolete `.rnex/prompts/` and `.rnex/workflows/` runtime directories.
- **Copilot Local Prompt Harness**: Removed `toolkit/plugins/copilot/`, `--copilot` flag, and prompt-mirroring harness in favor of universal `AGENTS.md` and native Copilot instruction reading.
- **`rnex fix` and `rnex status --fix`**: Permanently removed in favor of `rnex sync` as the single idempotent reconciliation command.


## [0.6.7] - 2026-10-12

### Documentation
- Updated project logo image.

## [0.6.6] - 2026-10-12

### Changed
- Streamlined `README.md` and `package.json` keywords for better documentation layout.

## [0.6.5] - 2026-10-12

### Added
- **Dynamic AI Instructions & Complete Plugin Deactivation in `rnex fix`**:
  - `get_rnex_instructions()` dynamically evaluates whether `karpathy-llm` is enabled. When disabled or omitted from configuration, the Karpathy LLM Wiki mandatory gate alert, wiki orientation startup step, forbidden wiki actions, and wiki subagent references are omitted from `AGENTS.md` and native provider instructions.
  - `sync_plugins` automatically prunes scoped directories (`.rnex/plugins/<plugin>/`) from both the workspace root and member repositories whenever a plugin is marked `enabled: false` or omitted from config.
  - Provider prompt mirrors across all supported assistants (`.github/prompts`, `.claude/commands`, `.gemini/prompts`, `.cursor/prompts`, `.windsurf/prompts`) are cleaned of prompts and workflows belonging to disabled plugins, while preserving base prompts and active plugin prompts.
  - Hook dispatchers and `status` reports evaluate active enablement (`yaml_plugin_enabled`) rather than key presence, preventing disabled plugins from registering hook alerts or status indicators.
  - User-authored content in wiki and intake directories is strictly preserved during plugin deactivation.

## [0.6.4] - 2026-10-12

### Documentation
- Switched documentation logo and favicon to `logo.png`.

## [0.6.3] - 2026-10-12

### Documentation
- Updated documentation logo asset to `logo.jpg`.

## [0.6.2] - 2026-10-12

### Documentation
- Switched branding to PNG logo and refined landing page copy.

## [0.6.1] - 2026-10-12

### Added
- **Mandatory Wiki Routing Protocol for AI Assistants**:
  - Enforced strict sequential startup routing protocol in `AGENTS.md` and provider instructions requiring AI assistants to inspect `.local.rnex.yaml` and `rnex.yaml` first, consult `.rnex/plugins/karpathy-llm/` instructions, check recent context in `wiki/hot.md` and `wiki/index.md`, and access only targeted files.
  - Added forbidden startup actions prohibiting blind searches across `repos/` and tree exploration.
- Updated logo asset to JPEG.

## [0.6.0] - 2026-10-11

### Changed
- Major version bump reflecting the completed Virtual Meta-Repo architecture: modular provider plugin architecture, universal `AGENTS.md` standard, VitePress documentation site, and prompts-only provider mirroring.
- Refined documentation site logo, branding, and tagline.

## [0.5.19] - 2026-10-11

### Documentation
- Consolidated FAQ and CLI documentation pages and updated project configuration.

## [0.5.18] - 2026-10-11

### Added
- **Universal `AGENTS.md` & Native Provider Instructions Architecture**:
  - Maintained `AGENTS.md` at the workspace root as the universal, cross-tool standard for workspace routing instructions. Assistants that read `AGENTS.md` unconditionally (such as GitHub Copilot) rely directly on `AGENTS.md`, eliminating redundant instruction files (`.github/copilot-instructions.md`) and diverging contexts.
  - Assistants with primary native configuration formats (Anthropic Claude Code with `CLAUDE.md`, Google Gemini CLI with `GEMINI.md`, Cursor with `.cursorrules` and `.cursor/rules/`, and Windsurf with `.windsurfrules`) have their instruction files maintained when their respective plugin is enabled (`instructions: true`, default). Since Claude Code only falls back to `AGENTS.md` when no `CLAUDE.md` is present, maintaining `CLAUDE.md` ensures Claude Code never misses Repo Nexus routing instructions when project-specific rules exist.
- **Self-Contained Skills, Workflows, Rules, and Subagents under `.rnex/`**:
  - Tools and autonomous agents operate directly on `.rnex/skills/`, `.rnex/workflows/`, `.rnex/rules/`, `.rnex/instructions/`, and active plugin scopes under `.rnex/plugins/<plugin-name>/`.
  - Autonomous subagents (e.g. `rnex-wiki-curator.agent.md`) are maintained under `.rnex/agents/` and `.rnex/plugins/<plugin>/agents/` without external mirroring to provider folders.
- **Prompts-Only AI Provider Synchronization**:
  - Streamlined provider plugins (`copilot`, `claude`, `gemini`, `cursor`, `windsurf`) to mirror human-facing prompts and active plugin workflows exclusively to native IDE prompt pickers (`.github/prompts/*.prompt.md`, `.claude/commands/*.md`, `.gemini/prompts/*.prompt.md`, `.cursor/prompts/*.md`, `.windsurf/prompts/*.md`).
  - Purged internal prompts from `.rnex/prompts/` and plugin directories.
  - Simplified provider plugin options: `copilot` uses `prompts: true|false` and `workflows: true|false`; `claude`, `gemini`, `cursor`, and `windsurf` use `instructions: true|false`, `prompts: true|false`, and `workflows: true|false`.
  - Surgical cleanup during `rnex fix` purges legacy mirrored skills and agents while preserving user-authored custom files.

## [0.5.17] - 2026-10-11

### Fixed
- Guarded variable expansion in `rm -rf` calls across POSIX shell scripts (resolving ShellCheck SC2115).

## [0.5.16] - 2026-10-11

### Added
- **Configurable Karpathy LLM Wiki Directories**:
  - Made wiki destination paths fully configurable via `plugins.karpathy-llm.wiki_dir` (default: `wiki`) and `plugins.karpathy-llm.raw_dir` (default: `raw`) in `rnex.yaml` and `.local.rnex.yaml`.
  - Workflows, templates, and Git hooks dynamically resolve configured paths.
- **Standardized `rnex-` Asset Naming**:
  - Standardized all workspace prompts, workflows, skills, and agents to consistently start with `rnex-` prefix.

## [0.5.15] - 2026-10-11

### Changed
- Updated author username and organization references from nu-nenoi to unoxen.

## [0.5.14] - 2026-10-11

### Added
- Comprehensive documentation site built with VitePress.
- Updated AI prompt synchronization logic and documentation recipes.

## [0.5.13] - 2026-10-10

### Documentation
- Fixed relative links across plugin guides and removed FAQ badge.

## [0.5.12] - 2026-10-10

### Added
- **Dedicated Plugins Documentation (`docs/plugins/`)**:
  - Comprehensive documentation suite covering all built-in AI provider and domain plugins, architecture, and developer authoring guides.
  - Added `docs/plugins/README.md` detailing scoped plugin isolation, member repo synchronization, decoupled cross-plugin asset discovery, two-level configuration, delimited instruction merging, CLI command reference, and custom plugin authoring specifications.
  - Added dedicated documentation pages: `copilot.md`, `claude.md`, `gemini.md`, `cursor.md`, `windsurf.md`, and `karpathy-llm.md`.

## [0.5.10] - 2026-10-10

### Changed
- Removed redundant `CLAUDE.md` in favor of standard `AGENTS.md`.

## [0.5.9] - 2026-10-10

### Changed
- **Modular POSIX Shell Codebase Architecture (`lib/`)**:
  - Decomposed the monolithic 3,700+ line `rnex` script into an extensible, modular architecture with dedicated libraries and command modules under `lib/`.
  - Streamlined `rnex` launcher to 110 lines focused on symlink-aware script path resolution (`RNEX_LIB_DIR`), core library discovery, and CLI dispatch.
  - Extracted core utilities and workspace operations into specialized modules: `lib/core.sh`, `lib/workspace.sh`, `lib/yaml.sh`, `lib/repos.sh`, `lib/plugins.sh`, `lib/ai.sh`, `lib/hooks.sh`.
  - Extracted CLI commands into dedicated modules under `lib/commands/`: `init.sh`, `repo.sh`, `status.sh`, `fix.sh`, `plugin.sh`, `completion.sh`, `system.sh`.
  - Maintained 100% backward compatibility, pure POSIX `/bin/sh` compliance, and zero external runtime dependencies.

## [0.5.8] - 2026-10-10

### Added
- Unified agent mirroring and cross-provider configuration.

## [0.5.7] - 2026-10-10

### Added
- **AI Provider Plugins for Claude, Gemini, Cursor, and Windsurf**:
  - Built-in provider plugins (`toolkit/plugins/claude/`, `toolkit/plugins/gemini/`, `toolkit/plugins/cursor/`, `toolkit/plugins/windsurf/`) alongside `copilot`.
  - Native instructions synthesis and sync for each provider: `CLAUDE.md`, `GEMINI.md`, `.cursorrules` (and `.cursor/rules/repo-nexus.mdc`), and `.windsurfrules`.
  - Standardized prompt mirroring to `.claude/commands/`, `.gemini/prompts/`, `.cursor/prompts/`, and `.windsurf/prompts/`.
  - Added `--claude`, `--gemini`, `--cursor`, and `--windsurf` initialization flags to `rnex init`.
- **Unified Single-Process Workspace Reconcile & Upgrade (`rnex fix`)**:
  - Merged configuration version updates directly into `rnex fix` as a single, idempotent process.
  - `rnex update` and `rnex upgrade` maintained as clean aliases pointing directly to `rnex fix`.

### Changed
- Removed legacy `ai_instructions` configuration key in favor of AI provider plugins.

## [0.5.6] - 2026-10-09

### Added
- **Modular GitHub Copilot Plugin & Extensible Provider Sync (`plugins: copilot: ...`)**:
  - Encapsulated GitHub Copilot integration as a built-in Repo Nexus plugin (`copilot`) located in `toolkit/plugins/copilot/`.
  - Extensible configuration options per provider under `plugins:` in `rnex.yaml` and `.local.rnex.yaml` (`prompts`, `skills`, `instructions`, `agents`).
  - Decoupled cross-plugin asset discovery: `copilot` provider inspects all active plugins (e.g. `karpathy-llm`) and mirrors their prompts, workflows, skills, agents, and guidelines without introducing plugin dependencies.
  - CLI management via `rnex plugin enable [--local] copilot`, `rnex plugin disable [--local] copilot`, and `rnex plugin info copilot`.
  - Added `--copilot` initialization flag to `rnex init`.

### Fixed
- Surgical non-destructive cleanup of skills, agents, and prompts during provider deactivation or reconciliation.

## [0.5.5] - 2026-10-09

### Changed
- **Track Workspace `.rnex/` in Version Control**:
  - Removed `.rnex/` from `.gitignore` templates and generation.
  - `reconcile_gitignore` and `rnex fix` actively strip legacy `.rnex/` ignore rules from `.gitignore` so that team prompts, plugins, and hooks are tracked in git.
  - Updated `rnex status` to expect `.rnex/` to remain tracked by git.

### Fixed
- Resolved hook self-rewrite bug where `rnex hooks run post-merge` invoked `cmd_fix`, which truncated and replaced `.rnex/hooks/post-merge` while actively executing it.

## [0.5.4] - 2026-10-09

### Fixed
- **Git Hooks Self-Rewrite Prevention & Wrapper Preservation**:
  - Added in-hook execution guard (`_RNEX_INSIDE_HOOK=1`) preventing hook script regeneration during active hook dispatch.
  - Preserved custom / repository-owned wrappers in `.rnex/hooks/` that are not auto-managed by `rnex`.
  - Added `cmp -s` check before writing hook files to eliminate unnecessary file churn and in-place overwrites.
  - Automatically chain to existing repository-owned `.githooks/` scripts if present.

## [0.5.3] - 2026-10-09

### Added
- **Explicit `git_hooks` Workspace Configuration (`rnex.yaml` & `.local.rnex.yaml`)**:
  - Top-level `git_hooks: true|false` setting establishes the workspace configuration as the single source of truth for automated Git hooks.
  - Two-level configuration support allowing per-workstation overrides in `.local.rnex.yaml`.
  - `rnex hooks install [--local]` and `rnex hooks uninstall [--local]` record preference directly to `rnex.yaml` or `.local.rnex.yaml`.
  - `rnex fix` (and `rnex sync`) automatically reconciles Git's `core.hooksPath` against the resolved `git_hooks` configuration.
  - Interactive `rnex init` determines and records `git_hooks` preference upfront in new workspaces.

## [0.5.2] - 2026-10-08

### Fixed
- Dynamic version matching in test suite (`tests/test_cli.sh`) resolving hardcoded version assertion on `package.json` bumps.

## [0.5.1] - 2026-10-08

### Added
- Comprehensive CLI Reference Manual (`docs/CLI.md`) documenting all workspace lifecycle commands, member repository operations, automated Git hooks, scoped plugins, standardized prompts catalog, and shell completion recipes.

### Fixed
- Dynamic version matching in test suite (`tests/test_cli.sh`, Test 26) resolving hardcoded version assertion on `package.json` bumps.
- Default version fallback in `rnex` CLI aligned with `package.json`.

## [0.5.0] - 2026-10-08

### Added
- **Version-Aware Upgrade System (`rnex update` / `rnex upgrade` and `rnex fix`)**:
  - Automatically compares workspace configuration against the running CLI version using semantic versioning.
  - Interactive upgrade prompt (`[y/N]`, bypassable with `-y` or `--yes`).
  - Non-destructively inserts missing schema keys (`version`, `ai_instructions`, `code_workspace`) while preserving comments and repo mappings.
  - Updates routing instructions in `AGENTS.md`, `CLAUDE.md`, and other detected AI assistant instruction files.
- **Config-Driven Automated Git Hooks (`rnex hooks`)**:
  - Native Git hooks managed under `.rnex/hooks/` via `git config core.hooksPath .rnex/hooks`.
  - Dynamic dispatchers for `post-merge`, `post-commit`, `pre-commit`, and `pre-push` that evaluate workspace triggers defined in `rnex.yaml` and `.local.rnex.yaml`.
  - Automated `post-merge` hook runs `rnex fix -y --quiet` to keep member clones and plugin scopes in sync after pulling team changes.
  - Subcommands: `rnex hooks install`, `rnex hooks uninstall`, and `rnex hooks status`.
  - Interactive hooks setup prompt during `rnex init` (controllable via `--hooks` and `--no-hooks` flags).
  - Health check integrated into `rnex status` reporting active hooks and triggers.
- **Standardized Prompts Suite & Master Catalog (`toolkit/prompts/`)**:
  - Master index catalog at `toolkit/prompts/index.md` (synced to `.rnex/prompts/index.md`).
  - New workflow prompts:
    - `rnex-cross-repo-feature.md`: Multi-repository feature planning and contract implementation.
    - `rnex-workspace-audit.md`: Multi-repo status, branch tracking, and configuration validation.
    - `rnex-wiki-ingest.md`: Autonomous intake decomposition into atomic Karpathy LLM Wiki pages.
    - `rnex-wiki-lint.md`: Graph integrity validation, backlink recalculation, and index rebuilding.
    - `rnex-setup-karpathy-wiki.md`: Deterministic knowledge base scaffolding.
  - Workspace `AGENTS.md` and `CLAUDE.md` maintain a minimal 1-line pointer to `.rnex/prompts/index.md` to conserve agent context.
- **Mandatory Session Startup Protocol**:
  - Enforced hard-gate instruction block in `AGENTS.md` and `CLAUDE.md` requiring AI coding assistants to inspect configuration (`.local.rnex.yaml`, `rnex.yaml`), plugin guidelines, and orientation notes (`wiki/hot.md` and `wiki/index.md`) before taking task actions.

## [0.4.7] - 2026-10-06

### Fixed
- Quoted variable expansion in parameter pattern removal (`_repos_rel="${REPOS_DIR#"$NEXUS_DIR"/}"`) resolving ShellCheck SC2295.

## [0.4.6] - 2026-10-06

### Added
- **Configurable AI Instructions Routing** (`ai_instructions` in `rnex.yaml`):
  - Support custom instruction files (e.g. `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, defaulting to `AGENTS.md`).
  - `rnex status` detects and highlights missing instruction files.
  - `rnex init` supports `--ai <file>` flag.
- **VS Code & Cursor Multi-Root Workspace Support** (`code_workspace` in `rnex.yaml`):
  - Automatically generates and synchronizes `.code-workspace` files mapping the workspace root and active member repositories.
  - `rnex init` supports `--code-workspace [file]` flag.

## [0.4.5] - 2026-10-06

### Fixed
- Guaranteed deterministic workspace initialization by tracking `repos/.gitkeep`.
- Prevented empty member directory creation during init.

## [0.4.4] - 2026-10-06

### Documentation
- Standardized deterministic Karpathy LLM Wiki initialization in `toolkit/plugins/karpathy-llm/`.

## [0.4.3] - 2026-10-05

### Refactored
- Separated behavioral rules (`rules/behavioral.md`) from architectural specifications (`instructions/wiki-architecture.md`) in `karpathy-llm` plugin.

## [0.4.2] - 2026-10-05

### Fixed
- Updated automated CLI test suite to dynamically inspect version from `package.json`.

## [0.4.1] - 2026-10-05

### Added
- Streamlined delimited routing protocol in `AGENTS.md` (`<!-- REPO-NEXUS:START -->` / `<!-- REPO-NEXUS:END -->`).
- Automated `.gitignore` reconciliation stripping legacy counters and ensuring `.rnex/` encapsulation.
- Purged legacy symlink mechanics in favor of physical autonomy.

## [0.4.0] - 2026-10-05

### Added
- **Virtual Meta-Repo 2.0**:
  - Physical member repository clones in `./repos/<name>` with complete Git isolation (no submodules).
  - Two-level configuration (`rnex.yaml` team manifest and `.local.rnex.yaml` machine overrides).
  - Cross-repository batch execution (`rnex exec <command...>`).
  - Member repository state management (`rnex enable`, `rnex disable`, `rnex list`, `rnex remove`).
  - Scoped workspace plugins (`.rnex/plugins/<plugin-name>/`).
