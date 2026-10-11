---
title: Google Gemini & Antigravity Plugin
description: Integrate Google Gemini and Antigravity IDE with Repo Nexus, mirroring operational prompts to .gemini/prompts/.
---

# Google Gemini & Antigravity Plugin

The **`gemini`** plugin integrates Google Gemini CLI and Google Antigravity IDE into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share [`AGENTS.md`](file:///Users/admin/Projects/ai/repo-nexus/AGENTS.md) at the workspace root as the single universal source of truth for routing. The `gemini` plugin mirrors human-facing operational prompts into `.gemini/prompts/*.prompt.md` with standard YAML frontmatter.

Operational skills, workflows, rules, and subagents remain cleanly self-contained within `.rnex/` and active plugin directories (`.rnex/plugins/<plugin-name>/`).

---

## Capabilities

1. **Native Instructions Support via `GEMINI.md`**:
   - Synchronizes Repo Nexus routing instructions to `GEMINI.md` (when `instructions: true`, default) for native support by the Google Gemini CLI.
   - Preserves user-defined custom sections in `GEMINI.md` across updates.

2. **Prompts Mirroring (`.gemini/prompts/*.prompt.md`)**:
   - Converts standard Repo Nexus operational prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`) and active plugins' workflows into Gemini prompt files with YAML frontmatter.

3. **Subagent & Skill Execution**:
   - Skills reside under `.rnex/skills/` and `.rnex/plugins/<plugin>/skills/`.
   - Workflows reside under `.rnex/workflows/` and `.rnex/plugins/<plugin>/workflows/`.
   - Subagents reside under `.rnex/agents/` and `.rnex/plugins/<plugin>/agents/` and are invoked as subagents without external mirroring.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable gemini

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local gemini
```

Or initialize a new workspace with Gemini integration pre-configured:

```sh
rnex init --gemini
```

---

## Configuration Options

Configure options under `plugins.gemini` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  gemini:
    instructions: true   # Sync routing instructions to GEMINI.md (default: true)
    prompts: true        # Mirror prompts to .gemini/prompts/ (default: true)
    workflows: true      # Mirror active plugin workflows as prompts (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `instructions` | boolean | `true` | Merge routing instructions into `GEMINI.md`. |
| `prompts` | boolean | `true` | Mirror prompts to `.gemini/prompts/*.prompt.md`. |
| `workflows` | boolean | `true` | Mirror active plugin workflows into `.gemini/prompts/*.prompt.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `gemini` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── AGENTS.md                          # Universal workspace instructions & routing
├── GEMINI.md                          # Gemini-specific instructions (if instructions: true)
├── .gemini/
│   └── prompts/
│       ├── rnex-cross-repo-feature.prompt.md
│       ├── rnex-workspace-audit.prompt.md
│       ├── rnex-wiki-ingest.prompt.md
│       └── rnex-wiki-lint.prompt.md
├── .rnex/
│   ├── skills/                        # Workspace operational skills
│   ├── workflows/                     # Workspace workflows
│   └── plugins/
│       └── karpathy-llm/              # Scoped plugin skills, workflows, and agents
└── rnex.yaml
```

---

## Disabling & Pruning

To disable the Gemini plugin:

```sh
rnex plugin disable gemini
```

Repo Nexus automatically performs surgical cleanup:
- Removes auto-generated prompts under `.gemini/prompts/`.
- Cleans up any legacy mirrored skills, agents, or instructions blocks.
- Developer-created files under `.gemini/` that do not originate from Repo Nexus are preserved.
