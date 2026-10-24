# Repo Nexus (`rnex`) — Command Line Interface Reference

Lightweight zero-dependency Virtual Meta-Repo companion for multi-repo workspaces and shared AI context.

## Core Commands

| Command | Syntax | Description |
|:---|:---|:---|
| `init` | `rnex init [-y] [--claude] [--codex] [--copilot] [--gemini] [--cursor] [--windsurf] [--code-workspace]` | Initialize a new workspace, create `rnex.yaml`, Git ignore rules, and AI routing instructions. |
| `sync` | `rnex sync [-y] [--quiet]` | **Single reconciliation command**: syncs skills, plugins, Git hooks & ignore rules, and compiles `.rnex/ai-instructions.md`. |
| `status` | `rnex status` | **Strictly read-only**: inspect workspace health, active repos, loaded config, git hooks, sync stamp, and plugins. |
| `repo add` | `rnex repo add <git-url> [--name <n>] [--branch <b>] [--local]` | Register a new member repository and clone into `./repos/<name>`. |
| `repo remove` | `rnex repo remove <name> [--force]` | Unregister repository and remove its clone from disk. |
| `repo set` | `rnex repo set <name> [--enable\|--disable] [--readonly\|--readwrite] [--local]` | Configure state and flags for an individual member repository. |
| `repo clone` | `rnex repo clone <name>` | Clone a specific registered member repository into `./repos/<name>`. |
| `repo status` | `rnex repo status <name>` | Inspect branch, dirty state, and configuration for a specific repository. |
| `repo exec` | `rnex repo exec <name> <command...>` | Run an arbitrary shell command inside a specific member repository. |
| `clone` | `rnex clone` | Clone all declared member repositories missing from disk. |
| `exec` | `rnex exec <command...>` | Run an arbitrary shell command across all active member repositories. |
| `list` | `rnex list` | List all member repositories and their active status. |
| `plugin` | `rnex plugin <list\|info\|enable\|disable>` / `rnex plugin <name> <cmd> [options]` | Manage plugins or execute plugin-defined CLI subcommands. |
| `completion` | `rnex completion <bash\|zsh\|fish>` | Generate shell completions with event-driven auto-sync hooks. |
| `version` | `rnex version` / `rnex -v` | Display the installed version of `rnex`. |

---

## Reconciliation Command: `rnex sync`

`rnex sync` is the sole reconciliation command in Repo Nexus (`rnex update`, `rnex upgrade`, `rnex fix`, and `rnex status --fix` are removed).

```bash
rnex sync [-y|--yes] [-q|--quiet]
```

### Reconciliation Actions
1. **Config Version Upgrade**: Detects schema drift and non-destructively upgrades `rnex.yaml` if older than the installed CLI version.
2. **Git Ignore & Search Indexing**: Reconciles `.gitignore` (safely ignoring `repos/`, `**/.rnex*/`, `**/rnex*/`, and `.local.rnex.yaml` with trailing-slash directory rules) and `.ignore` (un-ignoring `repos/*` for search tools).
3. **Plugin Sync**: Prunes disabled plugins and deterministically copies enabled plugin assets, rules, skills, commands, templates, and executable lifecycle hooks into `.rnex/plugins/<plugin-name>/`.
4. **Compiled AI Instructions**: Compiles `.rnex/ai-instructions.md` by combining the base template with active configuration and all enabled plugin `instructions.md` fragments. Top-level provider files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, etc.) permanently maintain strict routing directives pointing to `.rnex/ai-instructions.md`.
5. **Skill Reconciliation & User Skill Generation**: Copies core agentic skills from `toolkit/skills/` to `.rnex/skills/`, and generates lightweight, zero-logic User Skills (prefixed with `rnex-`) in configured AI assistant directories (`.cursor/rules/`, `.claude/skills/`, `.agents/skills/`, `.codex/skills/`, `.windsurf/rules/`) pointing directly to `.rnex/skills/` or plugin skill directories.
6. **Clean Member Repositories**: Member repositories remain clean by default; reconciles on-demand `.rnex/` harnesses only if required by active plugins.
7. **Git Hooks**: Reconciles workspace Git hook dispatchers in `.git/hooks/` against declarative `git.hooks` commands.
8. **Multi-Root Workspace**: Synchronizes `.code-workspace` folder mappings when `code_workspace: true`.
9. **Event-Driven Auto-Sync Scripts & Stamp**: Generates `.rnex/bin/auto-sync.sh` and updates `.rnex/sync_stamp`.

---

## Plugin Contract & Lifecycle Hooks

Repo Nexus core is 100% agnostic of specific plugins. All mutating commands dispatch lifecycle hooks before and after execution.

### Action Command Hook Dispatcher
All state-changing commands (`init`, `sync`, `repo`, `clone`, `exec`, `plugin`) trigger:
- `before_<cmd>` hook
- `after_<cmd>` hook

Read-only commands (`status`, `list`, `completion`, `--help`, `--version`) bypass lifecycle hooks.

### Plugin Manifest & File Layout
Plugins are authored in `toolkit/plugins/<plugin-name>/` and synced into `.rnex/plugins/<plugin-name>/`:

```text
toolkit/plugins/<plugin-name>/
├── plugin.yaml                  # Manifest (name, version, description, default config)
├── instructions.md              # Optional AI instruction fragment merged during rnex sync
├── commands/                    # Plugin CLI subcommands (e.g. ingest.sh, lint.sh)
├── hooks/                       # POSIX /bin/sh hook scripts (chmod +x)
│   ├── after_sync.sh            # Executes after workspace reconciliation
│   ├── after_init.sh            # Executes after workspace initialization
│   ├── before_plugin_disable.sh # Executes before plugin disable/removal
│   └── before_remove.sh         # Executes before member repo removal
├── rules/                       # AI assistant behavioral rules
├── skills/                      # Plugin-owned agentic skills (e.g. wiki-ingest.md)
└── templates/                   # Default files and scaffold templates
```

### Environment Context & Helper Functions
Every lifecycle hook receives the following environment variables:

| Variable | Description |
|:---|:---|
| `RNEX_ROOT` | Absolute path to the Repo Nexus workspace root directory. |
| `RNEX_CONFIG_MERGED` | Path to the active workspace configuration (`rnex.yaml`). |
| `RNEX_PLUGIN_DIR` | Path to the scoped plugin directory (`.rnex/plugins/<plugin-name>`). |
| `RNEX_PROVIDER_SKILL_DIRS` | Space-separated list of active provider skill directories. |
| `RNEX_CMD` | The command being executed (e.g., `sync`, `init`, `repo`). |
| `RNEX_ARGS` | Arguments passed to the command. |
| `RNEX_QUIET` | Set to `1` when `--quiet` was passed, `0` otherwise. |

Hooks have access to POSIX helper functions for managing User Skill pointers:
- `rnex_register_user_skill <skill_name> <target_path_in_rnex>`: Generates a zero-logic user skill pointer (either a native `rnex-<name>/SKILL.md` bundle with YAML frontmatter for skill-based providers, or a flat `rnex-<name>.md` file for rule-based providers) linking to the target skill protocol.
- `rnex_unregister_user_skill <skill_name>`: Removes the `rnex-<skill_name>` user skill pointer (bundle or flat file) from all active provider directories.

### Karpathy LLM Wiki Plugin
The `karpathy-llm` plugin uses lifecycle hooks to manage its domain directories:
- **Default curated knowledge base (`wiki_dir`)**: `wiki` (at workspace root)
- **Default intake sources (`sources`)**: `docs` directory and `"repos/**/README.md"` glob pattern
- **Master navigation index**: `wiki/index.md`
- **Rolling orientation cache**: `wiki/hot.md`
- **Operation log**: `wiki/_log.md`
- **CLI Commands**: `rnex plugin karpathy-llm ingest [options]` and `rnex plugin karpathy-llm lint [options]`
