---
title: Anthropic Claude Plugin
description: Integrate Anthropic Claude Code and Claude Desktop with Repo Nexus, CLAUDE.md instructions, and .claude/ prompt mirroring.
---

# Anthropic Claude Plugin

The **`claude`** plugin integrates Anthropic Claude Code CLI (`claude`) and Claude Desktop into a Repo Nexus Virtual Meta-Repo.

It maintains instructions in `CLAUDE.md` and mirrors operational prompts, skills, and agents into `.claude/` for native slash-command and tool picker discovery.

---

## Capabilities

1. **Instructions Management (`CLAUDE.md`)**:
   - Generates and maintains `CLAUDE.md` with multi-repo orientation protocols.
   - Claude Code automatically reads `CLAUDE.md` on session startup to orient on workspace structure (`rnex.yaml`), active member repositories (`repos/`), and available plugin workflows.
   - Protected by `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->` delimiters.

2. **Slash Commands & Prompts Mirroring (`.claude/commands/*.md` & `.claude/prompts/*.md`)**:
   - Mirrors standardized Repo Nexus operational workflows into `.claude/commands/*.md` and `.claude/prompts/*.md`.
   - In Claude Code CLI, workflows can be invoked directly as custom slash commands (e.g. `/rnex-cross-repo-feature`, `/rnex-workspace-audit`, `/wiki-ingest`).

3. **Agent Skills (`.claude/skills/<name>/SKILL.md`)**:
   - Mirrors skills from active plugins (like `wiki-ingest` and `wiki-lint` from [`karpathy-llm`](karpathy-llm.md)) into `.claude/skills/<name>/SKILL.md`.

4. **Custom Agents (`.claude/agents/*.md`)**:
   - Mirrors custom agents declared in active plugins (e.g., `wiki-curator.md`) into `.claude/agents/`.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable claude

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local claude
```

Or initialize a new workspace for Claude Code:

```sh
rnex init --claude
```
*(When `--claude` is passed to `rnex init`, `CLAUDE.md` is generated instead of `AGENTS.md`.)*

---

## Configuration Options

Configure options under `plugins.claude` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  claude:
    instructions: true   # Maintain routing in CLAUDE.md (default: true)
    prompts: true        # Mirror prompts to .claude/commands/ and .claude/prompts/ (default: true)
    skills: true         # Mirror skills to .claude/skills/<name>/SKILL.md (default: true)
    agents: true         # Mirror custom agents to .claude/agents/*.md (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `instructions` | boolean | `true` | Maintain delimited multi-repo routing in `CLAUDE.md`. |
| `prompts` | boolean | `true` | Mirror prompts to `.claude/commands/*.md` and `.claude/prompts/*.md`. |
| `skills` | boolean | `true` | Mirror skills into `.claude/skills/<name>/SKILL.md`. |
| `agents` | boolean | `true` | Mirror custom agents into `.claude/agents/*.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `claude` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── CLAUDE.md                          # Multi-repo routing context for Claude Code
├── .claude/
│   ├── commands/                      # Slash command shortcuts
│   │   ├── rnex-cross-repo-feature.md
│   │   ├── rnex-workspace-audit.md
│   │   ├── wiki-ingest.md
│   │   └── wiki-lint.md
│   ├── prompts/                       # Prompts catalog
│   ├── skills/
│   │   ├── wiki-ingest/
│   │   │   └── SKILL.md
│   │   └── wiki-lint/
│   │       └── SKILL.md
│   └── agents/
│       └── wiki-curator.md
└── rnex.yaml
```

---

## Disabling & Pruning

To disable the Claude plugin:

```sh
rnex plugin disable claude
```

Repo Nexus automatically performs surgical cleanup:
- Strips Repo Nexus instructions from `CLAUDE.md` (or deletes it if no custom instructions exist).
- Removes auto-generated commands, prompts, skills, and agents under `.claude/`.
- Developer-created files under `.claude/` that do not originate from Repo Nexus are preserved.
