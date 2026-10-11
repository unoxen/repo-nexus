---
title: GitHub Copilot Plugin
description: Integrate GitHub Copilot with Repo Nexus by mirroring operational prompts to .github/prompts/.
---

# GitHub Copilot Plugin

The **`copilot`** plugin integrates GitHub Copilot (GitHub Copilot Chat in VS Code / JetBrains / Visual Studio, GitHub Copilot CLI, and Copilot Agent Mode) into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share [`AGENTS.md`](file:///Users/admin/Projects/ai/repo-nexus/AGENTS.md) at the workspace root as the single universal source of truth for routing. The `copilot` plugin mirrors human-facing operational prompts into `.github/prompts/` with standard YAML frontmatter so they appear in GitHub Copilot's prompt picker.

Operational skills, workflows, rules, and subagents remain cleanly self-contained within `.rnex/` and active plugin directories (`.rnex/plugins/<plugin-name>/`).

---

## Capabilities

1. **Prompts Mirroring (`.github/prompts/*.prompt.md`)**:
   - Converts standard Repo Nexus operational prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`) and active plugins' workflows into Copilot prompt templates with YAML frontmatter (`name`, `description`).
   - Surfaces directly in GitHub Copilot's prompt picker.

2. **Universal Routing via `AGENTS.md`**:
   - GitHub Copilot ingests `AGENTS.md` directly at the workspace root.
   - Eliminates redundant instruction files or diverging contexts across tools.

3. **Subagent & Skill Execution**:
   - Skills reside under `.rnex/skills/` and `.rnex/plugins/<plugin>/skills/`.
   - Workflows reside under `.rnex/workflows/` and `.rnex/plugins/<plugin>/workflows/`.
   - Autonomous subagents (e.g. `rnex-wiki-curator.agent.md`) reside under `.rnex/agents/` and `.rnex/plugins/<plugin>/agents/` and are invoked as subagents without external mirroring.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable copilot

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local copilot
```

Or initialize a new workspace with Copilot integration pre-configured:

```sh
rnex init --copilot
```

---

## Configuration Options

Configure options under `plugins.copilot` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  copilot:
    prompts: true        # Mirror prompts to .github/prompts/*.prompt.md (default: true)
    workflows: true      # Mirror active workflows as prompts (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `prompts` | boolean | `true` | Mirror operational prompts into `.github/prompts/*.prompt.md` with YAML frontmatter. |
| `workflows` | boolean | `true` | Mirror plugin workflows into `.github/prompts/*.prompt.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `copilot` is enabled alongside functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── AGENTS.md                          # Universal workspace instructions & routing
├── .github/
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

To disable the Copilot plugin:

```sh
rnex plugin disable copilot
```

Repo Nexus automatically performs surgical cleanup:
- Removes auto-generated prompts in `.github/prompts/`.
- Cleans up any legacy mirrored skills or instructions blocks.
- User-created files and custom developer prompts outside of Repo Nexus naming conventions are left completely untouched.
