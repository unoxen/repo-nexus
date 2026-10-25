---
title: Tooling & Git Hooks
description: CLI reference for declarative Git hooks automation and modular plugin operations in Repo Nexus.
---

# Tooling & Git Hooks

This section covers workspace Git hooks automation and the extensible `rnex plugin` command suite.

---

## Git Hooks Automation

Repo Nexus configures Git hooks declaratively through the `git.hooks` section in `rnex.yaml` (with optional workstation-specific overrides in `.local.rnex.yaml`).

Hook dispatcher wrappers in `.git/hooks/` are installed and kept in sync automatically during `rnex init` and `rnex sync`.

### Configuration Schema

```yaml
git:
  hooks:
    post-merge:
      - "rnex sync --quiet"
    post-checkout:
      - "rnex sync --quiet"
    pre-commit:
      - "rnex plugin karpathy-llm lint"
    pre-push: []
```

### Supported Git Hooks

You can define command lists under any standard Git hook name:

* **`post-merge`**: Runs after `git pull` or upstream merges. Default: `rnex sync --quiet` ensures newly added repositories, plugins, and instructions sync instantly.
* **`post-checkout`**: Runs when switching branches. Default: `rnex sync --quiet` ensures workspace state reflects the checked-out branch.
* **`pre-commit`**: Runs before a commit is created. Ideal for running linters, formatting, or `rnex plugin karpathy-llm lint`.
* **`pre-push`**: Runs before pushing to remote. Useful for sanity checks or cross-repository tests.

### Execution Model

- When a Git event fires, the `.git/hooks/<hook>` wrapper reads the command list from `git.hooks.<hook>` in `rnex.yaml` (overridden by `.local.rnex.yaml` if present).
- Commands execute sequentially from the workspace root.
- If any command fails with a non-zero exit code in a pre-commit or pre-push hook, Git aborts the operation.

---

## Plugin Management

Plugins provide AI routing rules, standardized skills, agent workflows, and shared context protocols.

### `rnex plugin list`

Displays all available plugins distributed with `rnex` and indicates whether they are enabled.

```sh
rnex plugin list
```

```text
Plugin        Category          Status    Description
claude        AI Provider       enabled   Anthropic Claude Code & Desktop
codex         AI Provider       enabled   OpenAI Codex CLI & assistants
copilot       AI Provider       disabled  GitHub Copilot workspace rules
cursor        AI Provider       enabled   Cursor IDE rules & context
gemini        AI Provider       disabled  Google Gemini & Antigravity
karpathy-llm  Knowledge/Rules   enabled   Karpathy LLM 4 Cardinal Rules & Wiki
windsurf      AI Provider       disabled  Windsurf IDE rules & context
```

---

### `rnex plugin info`

Displays detailed metadata, configurable YAML options, and scoped assets for a specific plugin.

```sh
rnex plugin info <name>
```

```bash
rnex plugin info claude
```

---

### `rnex plugin enable`

Enables a plugin, creates `.rnex/plugins/<name>/`, and syncs mirrored assets.

```sh
rnex plugin enable [--local] <name>
```

* Pass `--local` to enable the plugin only in `.local.rnex.yaml` without changing team configuration.

---

### `rnex plugin disable`

Disables a plugin and cleans up its assets from `.rnex/plugins/<name>/`.

```sh
rnex plugin disable [--local] <name>
```

* Pass `--local` to disable the plugin locally on this workstation only.
* Routing instructions in root provider files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, etc.) are permanently preserved to prevent disruption to assistant workflows.

---

### `rnex plugin update`

Re-syncs and updates an enabled plugin (or all enabled plugins when `<name>` is omitted) from the toolkit sources.

```sh
rnex plugin update [<name>]
```

---

### Extensible Plugin Commands (`rnex plugin <name> <command>`)

Plugins can declare and expose native CLI subcommands. Subcommand scripts are located under `.rnex/plugins/<name>/commands/<command>.sh`.

#### Syntax
```sh
rnex plugin <name> <command> [options...]
```

#### Examples

```bash
# Ingest raw documentation into atomic Karpathy LLM Wiki pages
rnex plugin karpathy-llm ingest --repo backend

# Audit wiki integrity in strict mode
rnex plugin karpathy-llm lint --strict
```
