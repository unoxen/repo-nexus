---
title: Plugin Ecosystem
description: Modular plugin architecture for Repo Nexus, multi-provider AI context mirroring, and scoped workspace extensions.
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

### 4. Non-Destructive Delimited Merging
When plugins update root instruction files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `GEMINI.md`, `.cursorrules`, `.windsurfrules`), Repo Nexus isolates auto-managed routing between explicit delimiters:

```markdown
<!-- REPO-NEXUS:START -->
... auto-managed routing and instructions ...
<!-- REPO-NEXUS:END -->
```

Developer-authored instructions outside of these delimiters are strictly preserved.

### 5. Two-Level Configuration (Team vs. Workstation)
- **Team Configuration (`rnex.yaml`)**: Checked into version control; establishes the baseline plugins for all repository contributors.
- **Workstation Overrides (`.local.rnex.yaml`)**: Gitignored; allows individual developers to enable/disable plugins or toggle provider options locally without modifying team configuration.

---

## Built-In Plugins Catalog

| Plugin | Category | Description | Documentation |
|:---|:---|:---|:---|
| [`claude`](claude.md) | AI Provider | Anthropic Claude Code & Desktop integration: maintains `CLAUDE.md` and generates user skills in `.claude/skills/`. | [Read Guide](claude.md) |
| [`codex`](codex.md) | AI Provider | OpenAI Codex integration: maintains `CODEX.md` and generates user skills in `.codex/skills/`. | [Read Guide](codex.md) |
| [`copilot`](copilot.md) | AI Provider | GitHub Copilot integration: maintains `.github/copilot-instructions.md` and generates user skills in `.github/skills/`. | [Read Guide](copilot.md) |
| [`cursor`](cursor.md) | AI Provider | Cursor IDE integration: maintains `.cursorrules`, `.cursorignore`, and generates user skills in `.cursor/rules/`. | [Read Guide](cursor.md) |
| [`gemini`](gemini.md) | AI Provider | Google Gemini CLI & Antigravity IDE integration: maintains `GEMINI.md`, `.geminiignore`, and generates user skills in `.agents/skills/`. | [Read Guide](gemini.md) |
| [`windsurf`](windsurf.md) | AI Provider | Windsurf IDE integration: maintains `.windsurfrules` and generates user skills in `.windsurf/rules/`. | [Read Guide](windsurf.md) |
| [`karpathy-llm`](karpathy-llm.md) | Knowledge & Rules | Andrej Karpathy's 4 cardinal principles for coding agents, multi-repo context engineering standards, and autonomous zero-dependency LLM Wiki architecture (`./docs`, `.rnex/wiki`). | [Read Guide](karpathy-llm.md) |

---

## Authoring Custom Plugins

Want to package internal company standards, custom agent skills, or prompt libraries? Check out our [Authoring Custom Plugins Guide](authoring.md).

---

## Managing Plugins via CLI

The [`rnex plugin`](../cli/tooling.md#plugin-management) command family provides full management capabilities:

```bash
# List available and active plugins
rnex plugin list

# Inspect detailed metadata, options, and status of a plugin
rnex plugin info <name>

# Enable a plugin globally in rnex.yaml
rnex plugin enable <name>

# Enable a plugin locally in .local.rnex.yaml (workstation override)
rnex plugin enable --local <name>

# Disable a plugin from workspace
rnex plugin disable <name>

# Disable a plugin locally on this workstation only
rnex plugin disable --local <name>
```

---

## Declarative Configuration

Plugins are declared under the `plugins:` block in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
version: 0.5.8
repos_dir: ./repos

plugins:
  # AI Provider Plugins
  claude:
    skills: true
    auto_sync_on: SessionStart

  codex:
    skills: true

  gemini:
    skills: true
    auto_sync_on: SessionStart

  # Functional / Knowledge Plugins
  karpathy-llm:
    lint_trigger: manual
    notify_on_changes: true
```

Whenever you modify plugin configuration manually, run:

```bash
rnex sync
```

to reconcile scoped directories, prompt assets, provider mirrors, and member `.rnex/` folders.

