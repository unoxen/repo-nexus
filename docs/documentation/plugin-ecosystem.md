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
When a plugin is enabled, its rules, instructions, workflows, and skills are scoped directly under `.rnex/plugins/<plugin-name>/`. This keeps workspace root directories clean, avoids naming collisions between plugins, and ensures version-controlled tracking of active extensions.

### 2. Member Repository Isolation
Active plugins are mirrored into each active member repository under `repos/<name>/.rnex/plugins/<plugin-name>/`. When an AI assistant operates inside a specific member repository, it has full local access to the workspace's shared instructions and rules without breaking repository autonomy.

### 3. Decoupled Two-Tier Skills Architecture
Repo Nexus decouples functional plugins from AI provider plugins:
- **Core Skills (`toolkit/skills/` $\rightarrow$ `.rnex/skills/`)**: Workspace-level capabilities owned by Repo Nexus core.
- **Plugin Skills (`toolkit/plugins/<plugin>/skills/` $\rightarrow$ `.rnex/plugins/<plugin>/skills/`)**: Scoped domain skills owned exclusively by individual plugins.
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

## Authoring Custom Plugins

Custom plugins allow packaging internal company standards, custom agent skills, or prompt libraries.

### Plugin Directory Structure
A plugin lives in a directory (e.g. `toolkit/plugins/<my-plugin>/`):

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
