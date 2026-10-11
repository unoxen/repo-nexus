---
title: Windsurf IDE Plugin
description: Integrate Windsurf IDE and Cascade with Repo Nexus, maintain .windsurfrules and mirror prompts to .windsurf/.
---

# Windsurf IDE Plugin

The **`windsurf`** plugin integrates Codeium's Windsurf IDE and Cascade into a Repo Nexus Virtual Meta-Repo.

It maintains instructions in `.windsurfrules` and synchronizes prompt templates, skills, and agents into `.windsurf/` for contextual pair programming and multi-repo workflows.

---

## Capabilities

1. **Instructions Integration (`.windsurfrules`)**:
   - Generates and maintains `.windsurfrules` with multi-repo orientation protocols and workspace context.
   - Windsurf Cascade automatically loads `.windsurfrules` on session startup to identify repository boundaries and active member projects.
   - Protected by `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->` delimiters.

2. **Prompts Mirroring (`.windsurf/prompts/*.md`)**:
   - Converts standard Repo Nexus operational prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, etc.) and active plugins' workflows into Windsurf prompt files with YAML frontmatter.

3. **Agent Skills (`.windsurf/skills/<name>/SKILL.md`)**:
   - Mirrors skills from active plugins (like `wiki-ingest` and `wiki-lint` from [`karpathy-llm`](karpathy-llm.md)) into `.windsurf/skills/<name>/SKILL.md`.

4. **Custom Agents (`.windsurf/agents/*.md`)**:
   - Mirrors custom agents declared in active plugins (e.g., `wiki-curator.md`) into `.windsurf/agents/`.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable windsurf

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local windsurf
```

Or initialize a new workspace for Windsurf:

```sh
rnex init --windsurf
```
*(When `--windsurf` is passed to `rnex init`, `.windsurfrules` is generated instead of `AGENTS.md`.)*

---

## Configuration Options

Configure options under `plugins.windsurf` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  windsurf:
    instructions: true   # Maintain routing in .windsurfrules (default: true)
    prompts: true        # Mirror prompts to .windsurf/prompts/ (default: true)
    skills: true         # Mirror skills to .windsurf/skills/<name>/SKILL.md (default: true)
    agents: true         # Mirror custom agents to .windsurf/agents/*.md (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `instructions` | boolean | `true` | Maintain delimited routing in `.windsurfrules`. |
| `prompts` | boolean | `true` | Mirror prompts to `.windsurf/prompts/*.md`. |
| `skills` | boolean | `true` | Mirror skills into `.windsurf/skills/<name>/SKILL.md`. |
| `agents` | boolean | `true` | Mirror custom agents into `.windsurf/agents/*.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `windsurf` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── .windsurfrules                     # Multi-repo routing context for Windsurf & Cascade
├── .windsurf/
│   ├── prompts/
│   │   ├── rnex-cross-repo-feature.md
│   │   ├── rnex-workspace-audit.md
│   │   ├── wiki-ingest.md
│   │   └── wiki-lint.md
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

To disable the Windsurf plugin:

```sh
rnex plugin disable windsurf
```

Repo Nexus automatically performs surgical cleanup:
- Strips Repo Nexus instructions from `.windsurfrules` (or removes it if empty).
- Removes auto-generated prompts, skills, and agents under `.windsurf/`.
- Developer-created custom files under `.windsurf/` are preserved.
