---
title: Windsurf IDE Plugin
description: Integrate Windsurf IDE and Cascade with Repo Nexus, mirroring operational prompts to .windsurf/prompts/.
---

# Windsurf IDE Plugin

The **`windsurf`** plugin integrates Codeium's Windsurf IDE and Cascade into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share [`AGENTS.md`](file:///Users/admin/Projects/ai/repo-nexus/AGENTS.md) at the workspace root as the single universal source of truth for routing. The `windsurf` plugin mirrors human-facing operational prompts into `.windsurf/prompts/*.md` with standard YAML frontmatter.

Operational skills, workflows, rules, and subagents remain cleanly self-contained within `.rnex/` and active plugin directories (`.rnex/plugins/<plugin-name>/`).

---

## Capabilities

1. **Native Instructions Support via `.windsurfrules`**:
   - Synchronizes Repo Nexus routing instructions to `.windsurfrules` when `instructions: true` (default).
   - Preserves user custom rules and custom sections in `.windsurfrules`.

2. **Prompts Mirroring (`.windsurf/prompts/*.md`)**:
   - Converts standard Repo Nexus operational prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`) and active plugins' workflows into Windsurf prompt files with YAML frontmatter.

3. **Subagent & Skill Execution**:
   - Skills reside under `.rnex/skills/` and `.rnex/plugins/<plugin>/skills/`.
   - Workflows reside under `.rnex/workflows/` and `.rnex/plugins/<plugin>/workflows/`.
   - Subagents reside under `.rnex/agents/` and `.rnex/plugins/<plugin>/agents/` and are invoked as subagents without external mirroring.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable windsurf

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local windsurf
```

Or initialize a new workspace with Windsurf integration pre-configured:

```sh
rnex init --windsurf
```

---

## Configuration Options

Configure options under `plugins.windsurf` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  windsurf:
    instructions: true   # Sync routing instructions to .windsurfrules (default: true)
    prompts: true        # Mirror prompts to .windsurf/prompts/ (default: true)
    workflows: true      # Mirror active plugin workflows as prompts (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `instructions` | boolean | `true` | Merge routing instructions into `.windsurfrules`. |
| `prompts` | boolean | `true` | Mirror prompts to `.windsurf/prompts/*.md`. |
| `workflows` | boolean | `true` | Mirror plugin workflows into `.windsurf/prompts/*.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `windsurf` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── AGENTS.md                          # Universal workspace instructions & routing
├── .windsurfrules                     # Windsurf instructions (if instructions: true)
├── .windsurf/
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

To disable the Windsurf plugin:

```sh
rnex plugin disable windsurf
```

Repo Nexus automatically performs surgical cleanup:
- Removes auto-generated prompts under `.windsurf/prompts/`.
- Cleans up any legacy mirrored skills, agents, or instructions blocks.
- Developer-created custom files under `.windsurf/` are preserved.
