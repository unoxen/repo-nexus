---
title: GitHub Copilot Plugin
description: Integrate GitHub Copilot with Repo Nexus, mirror prompts, skills, and agents directly into .github/copilot-instructions.md.
---

# GitHub Copilot Plugin

The **`copilot`** plugin integrates GitHub Copilot (GitHub Copilot Chat in VS Code / JetBrains / Visual Studio, GitHub Copilot CLI, and Copilot Agent Mode) into a Repo Nexus Virtual Meta-Repo.

It synchronizes workspace prompts, agent skills, custom agents, and multi-repo routing instructions directly into the standard `.github/` folder structure.

---

## Capabilities

1. **Instructions Synthesis (`.github/copilot-instructions.md`)**:
   - Synthesizes Repo Nexus multi-repo routing instructions into `.github/copilot-instructions.md`.
   - Incorporates rules and instructions from all active workspace plugins (e.g. [`karpathy-llm`](karpathy-llm.md)).
   - Protected by `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->` delimiters so existing custom team instructions are never overwritten.

2. **Prompts Mirroring (`.github/prompts/*.prompt.md`)**:
   - Automatically converts standard Repo Nexus operational prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, etc.) and active plugins' workflows into Copilot prompt templates with YAML frontmatter (`name`, `description`).
   - Surfaces directly in GitHub Copilot's prompt picker.

3. **Agent Skills (`.github/skills/<name>/SKILL.md`)**:
   - Mirrors skills from active plugins (like `wiki-ingest` and `wiki-lint` from `karpathy-llm`) into `.github/skills/<name>/SKILL.md`.
   - Generates skill wrappers from operational prompts and custom agents for autonomous Copilot agents.

4. **Custom Agents (`.github/agents/*.agent.md`)**:
   - Mirrors custom agents declared in active plugins (e.g., `wiki-curator.agent.md`) into `.github/agents/`.

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
    skills: true         # Mirror skills to .github/skills/<name>/SKILL.md (default: true)
    instructions: true   # Maintain routing in .github/copilot-instructions.md (default: true)
    agents: true         # Mirror custom agents to .github/agents/*.agent.md (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `prompts` | boolean | `true` | Mirror operational prompts into `.github/prompts/*.prompt.md` with YAML frontmatter. |
| `skills` | boolean | `true` | Mirror skills and agents into `.github/skills/<name>/SKILL.md`. |
| `instructions` | boolean | `true` | Maintain delimited multi-repo routing in `.github/copilot-instructions.md`. |
| `agents` | boolean | `true` | Mirror custom agent definitions into `.github/agents/*.agent.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `copilot` is enabled alongside functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── .github/
│   ├── copilot-instructions.md        # Routing instructions & synthesized plugin rules
│   ├── prompts/
│   │   ├── rnex-cross-repo-feature.prompt.md
│   │   ├── rnex-workspace-audit.prompt.md
│   │   ├── wiki-ingest.prompt.md
│   │   └── wiki-lint.prompt.md
│   ├── skills/
│   │   ├── rnex-cross-repo-feature/
│   │   │   └── SKILL.md
│   │   ├── wiki-ingest/
│   │   │   └── SKILL.md
│   │   ├── wiki-lint/
│   │   │   └── SKILL.md
│   │   └── wiki-curator/
│   │       └── SKILL.md
│   └── agents/
│       └── wiki-curator.agent.md
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
- Removes auto-generated skills in `.github/skills/`.
- Removes auto-generated agents in `.github/agents/`.
- Strips the delimited Repo Nexus routing block from `.github/copilot-instructions.md` while preserving custom developer instructions.
- User-created skills or prompts outside of Repo Nexus naming conventions are left completely untouched.
