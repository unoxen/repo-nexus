---
title: Cursor IDE Plugin
description: Integrate Cursor IDE with Repo Nexus, maintain .cursorrules and MDC rules, and mirror prompts into .cursor/.
---

# Cursor IDE Plugin

The **`cursor`** plugin integrates Cursor IDE and Cursor Agent Mode into a Repo Nexus Virtual Meta-Repo.

It maintains instructions in both `.cursorrules` (legacy format) and `.cursor/rules/rnex-context.mdc` (modern Cursor MDC format), and mirrors prompts, skills, and agents into `.cursor/`.

---

## Capabilities

1. **Instructions & Rules Integration (`.cursorrules` & `.cursor/rules/rnex-context.mdc`)**:
   - Generates and maintains `.cursorrules` with multi-repo orientation protocols and delimiter guards.
   - Generates `.cursor/rules/rnex-context.mdc` with Cursor rule frontmatter (`description`, `globs: *`, `alwaysApply: true`), ensuring Cursor Agent Mode applies multi-repo awareness globally.

2. **Prompts Mirroring (`.cursor/prompts/*.md`)**:
   - Converts standard Repo Nexus operational prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, `rnex-wiki-ingest`, `rnex-wiki-lint`) and active plugins' workflows into Cursor prompt templates with YAML frontmatter.

3. **Agent Skills (`.cursor/skills/<name>/SKILL.md`)**:
   - Mirrors skills from active plugins (like `rnex-wiki-ingest` and `rnex-wiki-lint` from [`karpathy-llm`](karpathy-llm.md)) into `.cursor/skills/<name>/SKILL.md`.

4. **Custom Agents (`.cursor/agents/*.md`)**:
   - Mirrors custom agents declared in active plugins (e.g., `rnex-wiki-curator.md`) into `.cursor/agents/`.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable cursor

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local cursor
```

Or initialize a new workspace for Cursor:

```sh
rnex init --cursor
```
*(When `--cursor` is passed to `rnex init`, `.cursorrules` and `.cursor/rules/rnex-context.mdc` are generated instead of `AGENTS.md`.)*

---

## Configuration Options

Configure options under `plugins.cursor` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  cursor:
    instructions: true   # Maintain routing in .cursorrules and .cursor/rules/ (default: true)
    prompts: true        # Mirror prompts to .cursor/prompts/ (default: true)
    skills: true         # Mirror skills to .cursor/skills/<name>/SKILL.md (default: true)
    agents: true         # Mirror custom agents to .cursor/agents/*.md (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `instructions` | boolean | `true` | Maintain delimited routing in `.cursorrules` and `.cursor/rules/rnex-context.mdc`. |
| `prompts` | boolean | `true` | Mirror prompts to `.cursor/prompts/*.md`. |
| `skills` | boolean | `true` | Mirror skills into `.cursor/skills/<name>/SKILL.md`. |
| `agents` | boolean | `true` | Mirror custom agents into `.cursor/agents/*.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `cursor` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── .cursorrules                       # Legacy Cursor instructions
├── .cursor/
│   ├── rules/
│   │   └── rnex-context.mdc           # Modern Cursor MDC rule (alwaysApply: true)
│   ├── prompts/
│   │   ├── rnex-cross-repo-feature.md
│   │   ├── rnex-workspace-audit.md
│   │   ├── rnex-wiki-ingest.md
│   │   └── rnex-wiki-lint.md
│   ├── skills/
│   │   ├── rnex-wiki-ingest/
│   │   │   └── SKILL.md
│   │   └── rnex-wiki-lint/
│   │       └── SKILL.md
│   └── agents/
│       └── rnex-wiki-curator.md
└── rnex.yaml
```

---

## Disabling & Pruning

To disable the Cursor plugin:

```sh
rnex plugin disable cursor
```

Repo Nexus automatically performs surgical cleanup:
- Strips Repo Nexus instructions from `.cursorrules` (or removes it if empty).
- Removes `.cursor/rules/rnex-context.mdc`.
- Removes auto-generated prompts, skills, and agents under `.cursor/`.
- Developer-created custom rules and prompts under `.cursor/` are preserved.
