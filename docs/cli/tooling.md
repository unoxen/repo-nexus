---
title: Tooling & Git Hooks
description: CLI reference for automated Git hooks management and modular plugin operations in Repo Nexus.
---

# Tooling & Git Hooks

This section covers the `rnex hooks` and `rnex plugin` command suites used to configure workspace automations and modular integrations.

---

## Git Hooks Automation

Repo Nexus configures workspace-level Git hooks using Git's native `core.hooksPath = .rnex/hooks`.

### `rnex hooks install`
Installs native hook scripts into `.rnex/hooks/` and sets `git_hooks: true` in configuration.

```sh
rnex hooks install [--local]
```

#### Installed Hooks:
* **`post-merge`**: Runs `rnex sync -y --quiet` automatically whenever `git pull` or upstream merges change `rnex.yaml`, ensuring newly added repositories and plugin updates sync instantly.
* **`post-checkout`**: Runs `rnex sync -y --quiet` automatically whenever `rnex.yaml` changes across branch checkouts.
* **`post-commit`**: Alerts the user if documentation or wiki files were committed without running maintenance linters.
* **`pre-commit`**: Runs `rnex sync -y --quiet` when configuration files are staged, and triggers plugin validation.
* **`pre-push`**: Runs pre-push validation triggers before pushing to remote.

### `rnex hooks status`
Displays the active hooks configuration, current Git `core.hooksPath`, installed hook dispatchers, and active plugin triggers.

```sh
rnex hooks status
```

### `rnex hooks uninstall`
Unsets `core.hooksPath`, removes `.rnex/hooks/`, and sets `git_hooks: false` in configuration.

```sh
rnex hooks uninstall [--local]
```

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
copilot       AI Provider       disabled  GitHub Copilot workspace rules
cursor        AI Provider       enabled   Cursor IDE rules & context
gemini        AI Provider       disabled  Google Gemini & Antigravity
karpathy-llm  Knowledge/Rules   enabled   Karpathy LLM 4 Cardinal Rules & Wiki
windsurf      AI Provider       disabled  Windsurf IDE rules & context
```

### `rnex plugin info`
Displays detailed metadata, configurable YAML options, and scoped assets for a specific plugin.

```sh
rnex plugin info <name>
```

```bash
rnex plugin info claude
```

### `rnex plugin enable`
Enables a plugin, creates `.rnex/plugins/<name>/`, and syncs mirrored assets.

```sh
rnex plugin enable [--local] <name>
```

* Pass `--local` to enable the plugin only in `.local.rnex.yaml` without changing team configuration.

### `rnex plugin disable`
Disables a plugin and cleans up its assets from `.rnex/plugins/<name>/`.

```sh
rnex plugin disable [--local] <name>
```
