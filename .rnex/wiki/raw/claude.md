---
title: Anthropic Claude Plugin
description: Integrate Anthropic Claude Code with Repo Nexus, mirroring operational prompts into .claude/commands/ for custom slash commands.
---

# Anthropic Claude Plugin

The **`claude`** plugin integrates Anthropic Claude Code CLI (`claude`) and Claude Desktop into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share [`AGENTS.md`](file:///Users/admin/Projects/ai/repo-nexus/AGENTS.md) at the workspace root as the single universal source of truth for routing. The `claude` plugin mirrors human-facing operational prompts and plugin workflows into `.claude/commands/` and `.claude/prompts/` so they can be triggered directly as custom slash commands (e.g. `/rnex-cross-repo-feature`, `/rnex-workspace-audit`, `/rnex-wiki-ingest`).

Operational skills, workflows, rules, and subagents remain cleanly self-contained within `.rnex/` and active plugin directories (`.rnex/plugins/<plugin-name>/`).

---

## Capabilities

1. **Custom Slash Commands (`.claude/commands/*.md` & `.claude/prompts/*.md`)**:
   - Mirrors standardized Repo Nexus operational workflows into `.claude/commands/*.md` and `.claude/prompts/*.md`.
   - In Claude Code CLI, workflows can be invoked directly as custom slash commands (e.g. `/rnex-cross-repo-feature`, `/rnex-workspace-audit`, `/rnex-wiki-ingest`).

2. **Native Instruction Support via `CLAUDE.md` & `AGENTS.md`**:
   - Claude Code natively reads `CLAUDE.md` as its primary instructions file; it only falls back to `AGENTS.md` when no `CLAUDE.md` exists in the project.
   - When enabled (`instructions: true`), the Claude plugin synchronizes Repo Nexus routing instructions to `CLAUDE.md` (or merges them cleanly if you already have custom instructions).
   - If `CLAUDE.md` is absent and `instructions: false`, Claude Code falls back to reading `AGENTS.md` directly.

3. **Subagent & Skill Execution**:
   - Skills reside under `.rnex/skills/` and `.rnex/plugins/<plugin>/skills/`.
   - Workflows reside under `.rnex/workflows/` and `.rnex/plugins/<plugin>/workflows/`.
   - Subagents reside under `.rnex/agents/` and `.rnex/plugins/<plugin>/agents/` and are invoked as subagents without external mirroring.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable claude

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local claude
```

Or initialize a new workspace with Claude Code integration pre-configured:

```sh
rnex init --claude
```

---

## Configuration Options

Configure options under `plugins.claude` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  claude:
    instructions: true   # Sync routing instructions to CLAUDE.md (default: true)
    prompts: true        # Mirror prompts to .claude/commands/ and .claude/prompts/ (default: true)
    workflows: true      # Mirror active plugin workflows (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `instructions` | boolean | `true` | Merge routing instructions into `CLAUDE.md`. |
| `prompts` | boolean | `true` | Mirror prompts to `.claude/commands/*.md` and `.claude/prompts/*.md`. |
| `workflows` | boolean | `true` | Mirror plugin workflows as Claude slash commands. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `claude` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── AGENTS.md                          # Universal workspace instructions & routing
├── CLAUDE.md                          # Claude-specific instructions (if instructions: true)
├── .claude/
│   ├── commands/                      # Slash command shortcuts
│   │   ├── rnex-cross-repo-feature.md
│   │   ├── rnex-workspace-audit.md
│   │   ├── rnex-wiki-ingest.md
│   │   └── rnex-wiki-lint.md
│   └── prompts/                       # Prompts catalog
├── .rnex/
│   ├── skills/                        # Workspace operational skills
│   ├── workflows/                     # Workspace workflows
│   └── plugins/
│       └── karpathy-llm/              # Scoped plugin skills, workflows, and agents
└── rnex.yaml
```

---

## Disabling & Pruning

To disable the Claude plugin:

```sh
rnex plugin disable claude
```

Repo Nexus automatically performs surgical cleanup:
- Removes auto-generated commands and prompts under `.claude/`.
- Cleans up any legacy mirrored skills or instructions blocks.
- Developer-created custom commands, skills, or agents under `.claude/` are preserved.
