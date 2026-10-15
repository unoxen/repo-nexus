# Repo Nexus (`rnex`) — Command Line Interface Reference

Lightweight zero-dependency Virtual Meta-Repo companion for multi-repo workspaces and shared AI context.

## Core Commands

| Command | Syntax | Description |
|:---|:---|:---|
| `init` | `rnex init [-y] [--claude] [--copilot] [--gemini] [--cursor] [--windsurf] [--code-workspace]` | Initialize a new workspace, create `rnex.yaml`, `.rnex/`, `.ignore`, and minimal AI instructions. |
| `sync` | `rnex sync [-y] [--quiet]` | **Single reconciliation command**: syncs prompts, `.rnex/` harness, plugins, and compiles `.rnex/ai-instructions.md`. |
| `status` | `rnex status` | **Strictly read-only**: inspect workspace health, active repos, loaded config, git hooks, sync stamp, and plugins. |
| `add` | `rnex add <name> <git-url> [--local]` | Register a new member repository and clone into `./repos/<name>`. |
| `clone` | `rnex clone` | Clone all declared member repositories missing from disk. |
| `exec` | `rnex exec <command>` | Run an arbitrary shell command across all active member repositories. |
| `list` | `rnex list` | List all member repositories and their active status. |
| `enable` | `rnex enable <name> [--local]` | Enable a member repository in active workspace. |
| `disable` | `rnex disable <name> [--local]` | Disable a member repository in active workspace. |
| `remove` | `rnex remove <name> [-y]` | Unregister repository and remove its clone from disk. |
| `rnex-dir`| `rnex rnex-dir <enable\|disable> <name>` | Toggle `.rnex/` harness inside a member repository. |
| `update` | `rnex update [-y] [--quiet]` | Check configuration version and upgrade to latest schema (delegates to `sync`). |
| `hooks` | `rnex hooks <install\|uninstall\|status>` | Manage automated workspace Git hooks. |
| `plugin` | `rnex plugin <list\|info\|enable\|disable\|update>` | Manage workspace plugins. |
| `completion` | `rnex completion <bash\|zsh\|fish>` | Generate shell completions with event-driven auto-sync hooks. |

---

## Reconciliation Command: `rnex sync`

`rnex sync` is the sole reconciliation command (`rnex fix` and `rnex status --fix` have been removed).

```bash
rnex sync [-y|--yes] [-q|--quiet]
```

### Reconciliation Actions
1. **Config Version Upgrade**: Detects schema drift and non-destructively upgrades `rnex.yaml` if older than the installed CLI version.
2. **Git Ignore & Search Indexing**: Reconciles `.gitignore` (ignoring `repos/*` and `.local.rnex.yaml`) and `.ignore` (un-ignoring `repos/*` for search tools).
3. **Plugin Sync**: Prunes disabled plugins and deterministically copies enabled plugin assets, rules, workflows, templates, and executable lifecycle hooks into `.rnex/plugins/<plugin-name>/`.
4. **Compiled AI Instructions**: Compiles `.rnex/ai-instructions.md` by combining the base template with active configuration and all enabled plugin `instructions.md` fragments. Top-level provider files (`AGENTS.md`, `CLAUDE.md`, etc.) receive only a single strict directive pointing to `.rnex/ai-instructions.md`.
5. **Prompt Sync**: Copies all operational prompts matching `rnex-*` from `toolkit/prompts/` into configured AI assistant directories (Claude, Gemini, Cursor, Windsurf, Copilot) and workspace prompt directories.
6. **Harness Sync**: Reconciles root `.rnex/` and member repository harnesses (`repos/<name>/.rnex/`) for all enabled member repositories where `rnex_dir: true`.
7. **Git Hooks**: Installs or reconciles workspace Git hooks in `.rnex/hooks` when `git_hooks: true`.
8. **Multi-Root Workspace**: Synchronizes `.code-workspace` folder mappings when `code_workspace: true`.
9. **Event-Driven Auto-Sync Scripts & Stamp**: Generates `.rnex/bin/auto-sync.sh` and updates `.rnex/.sync_stamp`.

---

## Plugin Contract & Lifecycle Hooks

Repo Nexus core is 100% agnostic of specific plugins. All mutating commands dispatch lifecycle hooks before and after execution.

### Action Command Hook Dispatcher
All state-changing commands (`init`, `add`, `clone`, `exec`, `remove`, `enable`, `disable`, `rnex-dir`, `sync`, `update`, `hooks`, `plugin`) trigger:
- `before_<cmd>` hook
- `after_<cmd>` hook

Read-only commands (`status`, `list`, `completion`, `--help`, `--version`) bypass lifecycle hooks.

### Plugin Manifest & File Layout
Plugins are authored in `toolkit/plugins/<plugin-name>/` and synced into `.rnex/plugins/<plugin-name>/`:

```text
toolkit/plugins/<plugin-name>/
├── plugin.yaml                  # Manifest (name, version, description, default config)
├── instructions.md              # Optional AI instruction fragment merged during rnex sync
├── hooks/                       # POSIX /bin/sh hook scripts (chmod +x)
│   ├── after_sync.sh            # Executes after workspace reconciliation
│   ├── after_init.sh            # Executes after workspace initialization
│   └── before_remove.sh         # Executes before member repo removal
├── rules/                       # AI assistant behavioral rules
├── workflows/                   # Standardized agent workflow procedures
└── templates/                   # Default files and scaffold templates
```

### Environment Context Passed to Hooks
Every lifecycle hook receives the following environment variables:

| Variable | Description |
|:---|:---|
| `RNEX_ROOT` | Absolute path to the Repo Nexus workspace root directory. |
| `RNEX_CONFIG_MERGED` | Path to the active workspace configuration (`rnex.yaml`). |
| `RNEX_PLUGIN_DIR` | Path to the scoped plugin directory (`.rnex/plugins/<plugin-name>`). |
| `RNEX_CMD` | The command being executed (e.g., `sync`, `init`, `add`). |
| `RNEX_ARGS` | Arguments passed to the command. |
| `RNEX_QUIET` | Set to `1` when `--quiet` was passed, `0` otherwise. |

### Karpathy LLM Wiki Plugin
The `karpathy-llm` plugin uses lifecycle hooks to manage its domain directories:
- **Default curated knowledge base (`wiki_dir`)**: `.rnex/wiki`
- **Default append-only raw intake (`raw_dir`)**: `./docs`
- **Master navigation index**: `.rnex/wiki/index.md`
- **Rolling orientation cache**: `.rnex/wiki/hot.md`
- **Operation log**: `.rnex/wiki/_log.md`
