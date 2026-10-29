---
title: Plugin Ecosystem
description: Modular plugin architecture for Repo Nexus, multi-provider AI context mirroring, command engine, and custom plugin authoring.
---

# Plugin Ecosystem

Repo Nexus includes an extensible, modular plugin engine designed to equip multi-repo workspaces with AI assistant integrations, standardized skills, agent workflows, and shared context protocols.

Each plugin is self-contained and managed declaratively via `rnex.yaml` or workstation-specific overrides in `.local.rnex.yaml`.

---

## Core Architecture

### 1. Scoped Isolation (`.rnex/plugins/<plugin-name>/`)
When a plugin is enabled in `rnex.yaml` (or `.local.rnex.yaml`), its rules, instructions, commands, hooks, and skills are scoped directly under `.rnex/plugins/<plugin-name>/`. This keeps workspace root directories clean and avoids naming collisions between plugins while tracking active plugin configuration in `rnex.yaml`.

### 2. Complete Member Repository Autonomy
Member repositories live in the configured `repos_dir` (default: `./repos/`) and remain 100% clean and untouched with zero `.rnex/` directories inside member trees. All workspace orchestration, caches, and sync metadata reside exclusively within `.rnex/` at the workspace root.

### 3. Decoupled Two-Tier Skills Architecture
Repo Nexus decouples functional plugins from AI provider plugins:
- **Core Skills (`toolkit/skills/` $\rightarrow$ `.rnex/skills/`)**: Workspace-level capabilities owned by Repo Nexus core.
- **Plugin Skills (`<plugin-dir>/skills/` $\rightarrow$ `.rnex/plugins/<plugin>/skills/`)**: Scoped domain skills owned exclusively by individual plugins.
- **User Skills**: Provider plugins (`copilot`, `claude`, `codex`, `gemini`, `cursor`, and `windsurf`) project zero-logic user skill pointers into active provider directories using native `SKILL.md` bundles with YAML frontmatter in skill directories (`.github/skills/`, `.claude/skills/`, `.codex/skills/`, `.agents/skills/`) and flat files in rule directories (`.cursor/rules/`, `.windsurf/rules/`), redirecting AI assistants directly to the underlying agentic skills in `.rnex/`.

### 4. Extensible Plugin Command Engine
Plugins can declare parameterized CLI commands in their `plugin.yaml`:

```bash
# Explicit execution
rnex plugin <plugin-name> <command> [options...]

# Shorthand execution (when command name is unique across enabled plugins)
rnex plugin <command> [options...]
```

Every command execution automatically dispatches lifecycle hooks:
* `before_plugin_command <plugin> <cmd> [args...]`
* `after_plugin_command <plugin> <cmd> [args...]`

Environment variables exported to command scripts:
* `RNEX_PLUGIN_NAME`: Name of the plugin.
* `RNEX_PLUGIN_COMMAND`: Subcommand name.
* `RNEX_PLUGIN_ARGS`: Arguments string.

### 5. External & Custom Plugin Mounting (`plugins.<name>.path`)
Plugins are not limited to built-in toolkit packages. Any external plugin directory on disk, in a shared team repository, or on a developer's workstation can be mounted into `.rnex/plugins/<plugin-name>/` via `plugins.<name>.path` in `rnex.yaml` or `.local.rnex.yaml`. External plugins participate seamlessly in the full Repo Nexus lifecycle—including CLI subcommands, lifecycle hooks, skills, instructions, and rules mirroring.

---

## Built-In Plugins Catalog

| Plugin | Category | Description | Documentation |
|:---|:---|:---|:---|
| [`karpathy-llm`](../plugins/karpathy-llm) | Knowledge & Rules | Andrej Karpathy's 4 cardinal principles for coding agents, multi-repo context engineering standards, and autonomous zero-dependency LLM Wiki architecture. | [Read Guide](../plugins/karpathy-llm) |
| [`claude`](../plugins/claude) | AI Provider | Anthropic Claude Code integration: maintains `CLAUDE.md` and generates user skills in `.claude/skills/`. | [Read Guide](../plugins/claude) |
| [`codex`](../plugins/codex) | AI Provider | OpenAI Codex integration: maintains `CODEX.md` and generates user skills in `.codex/skills/`. | [Read Guide](../plugins/codex) |
| [`cursor`](../plugins/cursor) | AI Provider | Cursor IDE integration: maintains `.cursorrules`, `.cursorignore`, and generates user skills in `.cursor/rules/`. | [Read Guide](../plugins/cursor) |
| [`gemini`](../plugins/gemini) | AI Provider | Google Gemini CLI & Antigravity IDE integration: maintains `GEMINI.md`, `.geminiignore`, and generates user skills in `.agents/skills/`. | [Read Guide](../plugins/gemini) |
| [`copilot`](../plugins/copilot) | AI Provider | GitHub Copilot integration: maintains `.github/copilot-instructions.md` and generates user skills in `.github/skills/`. | [Read Guide](../plugins/copilot) |
| [`windsurf`](../plugins/windsurf) | AI Provider | Windsurf IDE integration: maintains `.windsurfrules` and generates user skills in `.windsurf/rules/`. | [Read Guide](../plugins/windsurf) |

---

## Managing Plugins via CLI

```bash
# List available and active plugins with declared commands
rnex plugin list

# Inspect detailed metadata and options of a plugin
rnex plugin info <name>

# Enable a plugin globally in rnex.yaml
rnex plugin enable <name>

# Enable a plugin locally in .local.rnex.yaml (workstation override)
rnex plugin enable --local <name>

# Disable a plugin from workspace
rnex plugin disable <name>

# Disable a plugin locally on this workstation only
rnex plugin disable --local <name>

# Execute a plugin command
rnex plugin <name> <command> [options...]
```

---

## Connecting External Plugins (`plugins.<name>.path`)

Repo Nexus supports external and custom plugins located anywhere on the filesystem, enabling enterprise teams to share centralized engineering plugins and developers to test local extensions without modifying the built-in toolkit.

External plugins are configured canonicalizing the location via the per-plugin **`plugins.<name>.path`** setting in `rnex.yaml` or workstation-specific `.local.rnex.yaml`.

### How `plugins.<name>.path` Works
When a plugin declares a `path`, Repo Nexus treats that directory as the plugin bundle's source of truth. Running `rnex sync` (or `rnex plugin enable <name>`) reads the plugin's `plugin.yaml` manifest, compiles its `instructions/` into `.rnex/ai-instructions.md`, links or copies its `skills/` to `.rnex/plugins/<name>/skills/`, hooks its CLI scripts into `rnex plugin <name> <cmd>`, and registers its lifecycle hooks.

### Team-Shared External Plugin (`rnex.yaml`)
In shared team workspaces, commit external plugin references to `rnex.yaml` using relative paths or submodule locations:

```yaml
# rnex.yaml
version: "1"
name: "my-platform"

plugins:
  # Built-in plugin (loaded from toolkit/plugins/claude)
  claude:
    enabled: true

  # External plugin (loaded from a relative path or shared repo)
  team-standards:
    enabled: true
    path: "./custom-plugins/team-standards"
    strict_mode: true
```

### Workstation-Local Plugin Override (`.local.rnex.yaml`)
Developers can test or enable personal external plugins locally, or override the source path of an existing team plugin without modifying the version-controlled `rnex.yaml`:

```yaml
# .local.rnex.yaml
plugins:
  # Personal workstation tool suite
  my-local-agent-tools:
    enabled: true
    path: "/Users/dev/dotfiles/rnex-plugins/agent-tools"

  # Override team-standards plugin with a local development checkout
  team-standards:
    path: "../repos/team-standards"
```

::: tip Path Resolution & Normalization Rules
* **Precedence:** `.local.rnex.yaml` (`plugins.<name>.path`) > `rnex.yaml` (`plugins.<name>.path`) > Built-in `toolkit/plugins/<name>/`. Local workstation overrides always take priority.
* **Relative vs. Absolute Paths:** Relative paths (e.g., `./custom-plugins/my-plugin` or `../shared-plugins/my-plugin`) are resolved relative to the workspace root directory; absolute paths (e.g., `/Users/dev/plugins/my-plugin`) are resolved directly.
* **Directory or Manifest Pointer:** `path` can point either to the plugin root directory (`./custom-plugins/my-plugin`) or directly to its manifest file (`./custom-plugins/my-plugin/plugin.yaml`). `rnex` automatically normalizes `/plugin.yaml` to the parent plugin directory.
* **Version Reporting:** Built-in plugins match the `rnex` CLI version, while external plugins loaded via `plugins.<name>.path` dynamically report the `version:` declared in their own `plugin.yaml` across `rnex plugin list` and `rnex plugin info <name>`.
:::

---

## Authoring Custom Plugins

Custom plugins allow packaging internal company standards, custom agent skills, or prompt libraries.

### Plugin Location & Discovery
A plugin can be hosted in one of two locations:
1. **External Plugin Path (`plugins.<name>.path`)**: External or custom plugins declared via `path:` in `rnex.yaml` or `.local.rnex.yaml` (e.g. `plugins: { my-plugin: { path: "./custom-plugins/my-plugin" } }`).
2. **Built-in Toolkit Directory**: Standard plugins bundled directly with Repo Nexus under `toolkit/plugins/<my-plugin>/`.

### Plugin Directory Structure
A plugin bundle is structured as follows:

```text
my-plugin/
├── plugin.yaml              # Plugin manifest
├── README.md                # Documentation
├── commands/                # Parameterized CLI executables
│   └── mycmd.sh
├── hooks/                   # Lifecycle hook handlers
│   ├── after_sync.sh
│   └── before_plugin_disable.sh
├── instructions/            # Instructions compiled into .rnex/ai-instructions.md
│   └── my-plugin.md
├── rules/                   # Rules mirrored to IDEs
├── skills/                  # Domain skills copied to .rnex/plugins/my-plugin/skills/
└── templates/               # Workspace template files (e.g. {wiki_dir}/...)
```

### Manifest Schema (`plugin.yaml`)

```yaml
name: my-plugin
version: 1.0.0
description: Custom engineering workflows and standards
author: internal-team
homepage: https://github.com/my-org/plugins

config_defaults:
  custom_option: "default-value"

config_descriptions:
  custom_option: "<string> (description of option)"

commands:
  mycmd: "Run custom command [--flag] [options]"

skills:
  - skills/my-skill.md: .rnex/plugins/my-plugin/skills/my-skill.md

instructions:
  - instructions/my-plugin.md: .rnex/plugins/my-plugin/instructions/my-plugin.md
```
