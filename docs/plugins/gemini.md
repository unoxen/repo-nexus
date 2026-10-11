---
title: Google Gemini & Antigravity Plugin
description: Integrate Google Gemini CLI and Antigravity IDE with Repo Nexus, maintaining GEMINI.md and mirroring assets to .gemini/.
---

# Google Gemini & Antigravity Plugin

The **`gemini`** plugin integrates Google Gemini CLI and Google Antigravity IDE into a Repo Nexus Virtual Meta-Repo.

It maintains instructions in `GEMINI.md` and synchronizes prompt templates, skills, and agents into `.gemini/` for agentic pair programming and automated coding workflows.

---

## Capabilities

1. **Instructions Management (`GEMINI.md`)**:
   - Generates and maintains `GEMINI.md` with multi-repo orientation protocols and workspace context.
   - On session startup, Gemini agents inspect `GEMINI.md` to identify repository structures and enabled plugins.
   - Protected by `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->` delimiters.

2. **Prompts Mirroring (`.gemini/prompts/*.prompt.md`)**:
   - Converts standard Repo Nexus operational prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, etc.) and active plugins' workflows into Gemini prompt files with YAML frontmatter.

3. **Agent Skills (`.gemini/skills/<name>/SKILL.md`)**:
   - Mirrors skills from active plugins (like `wiki-ingest` and `wiki-lint` from [`karpathy-llm`](karpathy-llm.md)) into `.gemini/skills/<name>/SKILL.md`.

4. **Custom Agents (`.gemini/agents/*.md`)**:
   - Mirrors custom agents declared in active plugins (e.g., `wiki-curator.md`) into `.gemini/agents/`.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable gemini

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local gemini
```

Or initialize a new workspace for Gemini:

```sh
rnex init --gemini
```
*(When `--gemini` is passed to `rnex init`, `GEMINI.md` is generated instead of `AGENTS.md`.)*

---

## Configuration Options

Configure options under `plugins.gemini` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  gemini:
    instructions: true   # Maintain routing in GEMINI.md (default: true)
    prompts: true        # Mirror prompts to .gemini/prompts/ (default: true)
    skills: true         # Mirror skills to .gemini/skills/<name>/SKILL.md (default: true)
    agents: true         # Mirror custom agents to .gemini/agents/*.md (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `instructions` | boolean | `true` | Maintain delimited multi-repo routing in `GEMINI.md`. |
| `prompts` | boolean | `true` | Mirror prompts to `.gemini/prompts/*.prompt.md`. |
| `skills` | boolean | `true` | Mirror skills into `.gemini/skills/<name>/SKILL.md`. |
| `agents` | boolean | `true` | Mirror custom agents into `.gemini/agents/*.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `gemini` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── GEMINI.md                          # Multi-repo routing context for Gemini & Antigravity
├── .gemini/
│   ├── prompts/
│   │   ├── rnex-cross-repo-feature.prompt.md
│   │   ├── rnex-workspace-audit.prompt.md
│   │   ├── wiki-ingest.prompt.md
│   │   └── wiki-lint.prompt.md
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

To disable the Gemini plugin:

```sh
rnex plugin disable gemini
```

Repo Nexus automatically performs surgical cleanup:
- Strips Repo Nexus instructions from `GEMINI.md` (or deletes it if no custom instructions exist).
- Removes auto-generated prompts, skills, and agents under `.gemini/`.
- Developer-created files under `.gemini/` that do not originate from Repo Nexus are preserved.
