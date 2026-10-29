---
title: Environment & Directory Layout
description: Complete reference for RNEX environment variables, internal directory structure, and process exit codes.
---

# Environment & Directory Layout

Reference for Repo Nexus runtime variables, directory layout conventions, and exit code specifications.

---

## Environment Variables

### Configuration & Discovery
| Variable | Description | Default |
|:---|:---|:---|
| `RNEX_CONFIG` | Overrides the workspace manifest path (`rnex.yaml`). | `rnex.yaml` |
| `RNEX_ROOT` | Workspace root directory resolved by `rnex`. | `$PWD` or nearest parent with `rnex.yaml` |
| `RNEX_LIB_DIR` | Internal library directory containing shell helpers. | `<install_root>/lib` |

### Batch Execution Variables (`rnex exec`)
When `rnex exec` iterates through member repositories, it sets:
* `RNEX_REPO_NAME`: Name of the repository currently executing the command.
* `RNEX_REPO_PATH`: Relative path to the repository directory (e.g. `./repos/backend` or `<repos_dir>/backend`).
* `RNEX_REPO_BRANCH`: Currently checked out Git branch or commit SHA.

### Hook Execution Variables (`rnex_hooks` & `git.hooks`)
* `RNEX_HOOK_EVENT`: Name of the triggering event (e.g. `after_sync`, `before_repo_add`).
* `RNEX_HOOK_ARGS`: Full argument string passed to the event.
* `RNEX_HOOK_ACTIVE`: Guard variable indicating active hook execution (prevents recursive loops).

### Plugin Execution Variables (`rnex plugin`)
* `RNEX_PLUGIN_NAME`: Target plugin name (e.g. `karpathy-llm`).
* `RNEX_PLUGIN_COMMAND`: Subcommand name (e.g. `ingest` or `lint`).
* `RNEX_PLUGIN_ARGS`: String of arguments passed to the plugin command.

---

## Directory Layout Reference

```text
my-workspace/
├── .git/                            # Meta-repo Git directory
│   └── hooks/                       # Git hook wrappers generated from git.hooks
├── .gitignore                       # Managed deterministically via git.ignore
├── .ignore                          # Un-ignores <repos_dir>/* for code search tools
├── rnex.yaml                        # Shared team configuration manifest
├── .local.rnex.yaml                 # (Optional) Developer workstation overrides
│
├── .rnex/                           # Internal runtime harness (git-ignored)
│   ├── ai-instructions.md           # Master compiled AI instructions
│   ├── sync_stamp                   # Checksum stamp for configuration drift detection
│   ├── skills/                      # Standardized core agentic skills
│   └── plugins/                     # Scoped plugin directories
│       └── <plugin-name>/
│           ├── commands/            # Plugin CLI executable commands
│           ├── skills/              # Plugin-owned agentic skills
│           └── rules/               # Mirrored plugin rules
│
├── <repos_dir>/                     # Autonomous member repositories (default: repos/, configurable via repos_dir)
│   ├── <repo-a>/                    # Standard independent Git repository
│   │   ├── .git/
│   │   └── ...
│   └── <repo-b>/
│
├── custom-plugins/                  # (Optional) External workspace plugins (mounted via plugins.<name>.path)
│   └── <plugin-name>/               # External plugin bundle (plugin.yaml, hooks/, commands/, skills/)
│
├── AGENTS.md                        # Permanent AI context routing file
├── CLAUDE.md                        # Permanent Claude Code routing file
├── CODEX.md                         # Permanent OpenAI Codex routing file
├── GEMINI.md                        # Permanent Google Gemini routing file
├── .cursorrules                     # Permanent Cursor routing file
├── .windsurfrules                   # Permanent Windsurf routing file
└── .github/copilot-instructions.md  # Permanent GitHub Copilot routing file
```

---

## Process Exit Codes

| Code | Meaning | Context |
|:---|:---|:---|
| `0` | Success | Command completed successfully. |
| `1` | General Failure | Missing arguments, syntax error, failed workspace validation. |
| `127` | Command Not Found | Subcommand or requested executable not found. |
| `N` | Preserved Exit Code | In `rnex exec` or hooks, the non-zero exit code of any failing command is bubbled directly to the parent shell. |
