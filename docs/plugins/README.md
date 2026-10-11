# Repo Nexus Plugins

Repo Nexus includes an extensible, modular plugin engine designed to equip multi-repo workspaces with AI assistant integrations, standardized prompts, agent workflows, and shared context protocols.

Each plugin is self-contained and managed declaratively via `rnex.yaml` or workstation-specific overrides in `.local.rnex.yaml`.

---

## Core Architecture

### 1. Scoped Isolation (`.rnex/plugins/<plugin-name>/`)
When a plugin is enabled, its rules, instructions, workflows, prompts, and skills are scoped directly under `.rnex/plugins/<plugin-name>/`. This keeps workspace root directories clean, avoids naming collisions between plugins, and ensures version-controlled tracking of active extensions.

### 2. Member Repository Isolation
Active plugins are mirrored into each active member repository under `repos/<name>/.rnex/plugins/<plugin-name>/`. When an AI assistant operates inside a specific member repository, it has full local access to the workspace's shared instructions and rules without breaking repository autonomy.

### 3. Decoupled Cross-Plugin Asset Discovery
Repo Nexus decouples functional plugins from AI provider plugins:
- **Functional Plugins** (such as [`karpathy-llm`](karpathy-llm.md)) declare operational prompts, skills, custom agents, and behavioral guidelines.
- **Provider Plugins** (such as [`copilot`](copilot.md), [`claude`](claude.md), [`gemini`](gemini.md), [`cursor`](cursor.md), and [`windsurf`](windsurf.md)) automatically scan all active plugins and mirror their prompts, skills, and agents into the provider's native format (`.github/`, `.claude/`, `.gemini/`, `.cursor/`, `.windsurf/`).

Adding a new skill or prompt to any functional plugin automatically makes it available across all enabled AI provider tools without manual duplication.

### 4. Non-Destructive Delimited Merging
When plugins update root instruction files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, `.windsurfrules`, `.github/copilot-instructions.md`), Repo Nexus isolates auto-managed routing between explicit delimiters:

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
| [`copilot`](copilot.md) | AI Provider | GitHub Copilot integration: mirrors prompts to `.github/prompts/`, skills to `.github/skills/`, custom agents to `.github/agents/`, and maintains `.github/copilot-instructions.md`. | [Read Guide](copilot.md) |
| [`claude`](claude.md) | AI Provider | Anthropic Claude Code & Desktop integration: maintains `CLAUDE.md` and mirrors commands, prompts, skills, and agents to `.claude/`. | [Read Guide](claude.md) |
| [`gemini`](gemini.md) | AI Provider | Google Gemini CLI & Antigravity IDE integration: maintains `GEMINI.md` and mirrors prompts, skills, and agents to `.gemini/`. | [Read Guide](gemini.md) |
| [`cursor`](cursor.md) | AI Provider | Cursor IDE integration: maintains `.cursorrules` and `.cursor/rules/rnex-context.mdc`, and mirrors prompts, skills, and agents to `.cursor/`. | [Read Guide](cursor.md) |
| [`windsurf`](windsurf.md) | AI Provider | Windsurf IDE integration: maintains `.windsurfrules` and mirrors prompts, skills, and agents to `.windsurf/`. | [Read Guide](windsurf.md) |
| [`karpathy-llm`](karpathy-llm.md) | Agent Knowledge & Principles | Andrej Karpathy's 4 cardinal principles for coding agents, multi-repo context engineering standards, and autonomous zero-dependency LLM Wiki architecture (`raw/`, `wiki/`). | [Read Guide](karpathy-llm.md) |

---

## Managing Plugins via CLI

The [`rnex plugin`](../CLI.md#plugin-management-commands) command family provides full management capabilities:

```sh
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
    instructions: true
    prompts: true
    skills: true
    agents: true

  copilot:
    prompts: true
    skills: true
    instructions: true
    agents: true

  # Functional / Knowledge Plugins
  karpathy-llm:
    lint_trigger: git-post-merge
    notify_on_changes: true
```

Whenever you modify plugin configuration manually, run:
```sh
rnex fix
```
to reconcile scoped directories, prompt assets, provider mirrors, and member `.rnex/` folders.

---

## Authoring Custom Plugins

Custom plugins can be placed inside `toolkit/plugins/<name>/` or `.rnex/plugins/<name>/`.

A plugin requires a `plugin.yaml` manifest:

```yaml
name: my-plugin
version: 1.0.0
description: Custom team workflow guidelines and prompt suite
author: Your Team
homepage: https://github.com/my-org/my-plugin

instructions:
  - instructions/guidelines.md: .rnex/plugins/my-plugin/instructions/guidelines.md

rules:
  - rules/conventions.md: .rnex/plugins/my-plugin/rules/conventions.md

templates:
  - templates/config.sample.json: config/config.json
```

### Supported Plugin Subdirectories
- `instructions/`: Markdown instruction documents referenced by agents.
- `rules/`: Coding guidelines and architectural rules.
- `prompts/`: Operational prompts (automatically mirrored to AI providers with frontmatter).
- `skills/`: Agent skills (`SKILL.md`) for autonomous execution.
- `agents/`: Agent specification files (`*.agent.md`).
- `workflows/`: Multi-step agent procedural checklists.
- `templates/`: Workspace scaffolding files copied to destinations declared in `templates:`.
