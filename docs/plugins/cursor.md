---
title: Cursor IDE Plugin
description: Integrate Cursor IDE with Repo Nexus, mirroring operational prompts to .cursor/prompts/.
---

# Cursor IDE Plugin

The **`cursor`** plugin integrates Cursor IDE and Cursor Agent Mode into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share [`AGENTS.md`](file:///Users/admin/Projects/ai/repo-nexus/AGENTS.md) at the workspace root as the single universal source of truth for routing. The `cursor` plugin mirrors human-facing operational prompts into `.cursor/prompts/*.md` with standard YAML frontmatter.

Operational skills, workflows, rules, and subagents remain cleanly self-contained within `.rnex/` and active plugin directories (`.rnex/plugins/<plugin-name>/`).

---

## Capabilities

1. **Native Instructions & Rules Support**:
   - Synchronizes Repo Nexus routing instructions to `.cursorrules` and `.cursor/rules/rnex-context.mdc` (`alwaysApply: true`) when `instructions: true` (default).
   - Preserves user custom rules and custom sections in `.cursorrules`.

2. **Prompts Mirroring (`.cursor/prompts/*.md`)**:
   - Converts standard Repo Nexus operational prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`) and active plugins' workflows into Cursor prompt templates with YAML frontmatter.

3. **Subagent & Skill Execution**:
   - Skills reside under `.rnex/skills/` and `.rnex/plugins/<plugin>/skills/`.
   - Workflows reside under `.rnex/workflows/` and `.rnex/plugins/<plugin>/workflows/`.
   - Subagents reside under `.rnex/agents/` and `.rnex/plugins/<plugin>/agents/` and are invoked as subagents without external mirroring.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable cursor

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local cursor
```

Or initialize a new workspace with Cursor integration pre-configured:

```sh
rnex init --cursor
```

---

## Configuration Options

Configure options under `plugins.cursor` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  cursor:
    instructions: true   # Sync routing instructions to .cursorrules & .cursor/rules/ (default: true)
    prompts: true        # Mirror prompts to .cursor/prompts/ (default: true)
    workflows: true      # Mirror active plugin workflows as prompts (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `instructions` | boolean | `true` | Merge routing instructions into `.cursorrules` and `.cursor/rules/`. |
| `prompts` | boolean | `true` | Mirror prompts to `.cursor/prompts/*.md`. |
| `workflows` | boolean | `true` | Mirror plugin workflows into `.cursor/prompts/*.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `cursor` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── AGENTS.md                          # Universal workspace instructions & routing
├── .cursorrules                       # Cursor root instructions (if instructions: true)
├── .cursor/
│   ├── rules/
│   │   └── rnex-context.mdc           # Cursor alwaysApply routing rule
│   └── prompts/
│       ├── rnex-cross-repo-feature.md
│       ├── rnex-workspace-audit.md
│       ├── rnex-wiki-ingest.md
│       └── rnex-wiki-lint.md
├── .rnex/
│   ├── skills/                        # Workspace operational skills
│   ├── workflows/                     # Workspace workflows
│   └── plugins/
│       └── karpathy-llm/              # Scoped plugin skills, workflows, and agents
└── rnex.yaml
```

---

## Disabling & Pruning

To disable the Cursor plugin:

```sh
rnex plugin disable cursor
```

Repo Nexus automatically performs surgical cleanup:
- Removes auto-generated prompts under `.cursor/prompts/`.
- Cleans up any legacy mirrored skills, agents, or instructions blocks.
- Developer-created custom rules and prompts under `.cursor/` are preserved.
