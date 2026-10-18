---
title: Google Gemini & Antigravity Plugin
description: Integrate Google Gemini and Antigravity IDE with Repo Nexus, generating zero-logic user skill pointers in .agents/skills/.
---

# Google Gemini & Antigravity Plugin

The **`gemini`** plugin integrates Google Gemini CLI and Google Antigravity IDE into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share [`AGENTS.md`](file:///Users/admin/Projects/ai/repo-nexus/AGENTS.md) at the workspace root as the single universal source of truth for routing. When enabled, the `gemini` plugin generates zero-logic User Skill pointers into `.agents/skills/` (e.g. `rnex-clone-sync/SKILL.md`, `rnex-batch-exec/SKILL.md`, `rnex-karpathy-llm-wiki-ingest/SKILL.md`).

Operational skills, rules, and subagents remain cleanly encapsulated within `.rnex/skills/` and active plugin directories (`.rnex/plugins/<plugin-name>/`).

---

## Capabilities

1. **Zero-Logic User Skills (`.agents/skills/rnex-*/SKILL.md`)**:
   - Generates native `SKILL.md` bundles prefixed with `rnex-` in `.agents/skills/` with YAML frontmatter for Gemini and Antigravity skill discovery.
   - Contains zero inline heuristics—redirects Gemini/Antigravity directly to the underlying agentic skill protocols inside `.rnex/`.

2. **Native Instructions Support via `GEMINI.md`**:
   - Synchronizes Repo Nexus routing instructions to `GEMINI.md` (when `instructions: true`, default) for native support by the Google Gemini CLI.
   - Preserves user-defined custom sections in `GEMINI.md` across updates.

3. **Subagent & Skill Execution**:
   - Core skills reside under `.rnex/skills/`.
   - Plugin skills reside under `.rnex/plugins/<plugin>/skills/`.
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
    skills: true         # Generate user skills in .agents/skills/ (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `instructions` | boolean | `true` | Merge routing instructions into `GEMINI.md`. |
| `skills` | boolean | `true` | Generate user skill pointers in `.agents/skills/rnex-*/SKILL.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `gemini` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── GEMINI.md                          # Gemini-specific instructions (if instructions: true)
├── .agents/
│   └── skills/                        # Zero-logic User Skill pointers
│       ├── rnex-clone-sync/
│       │   └── SKILL.md
│       ├── rnex-batch-exec/
│       │   └── SKILL.md
│       ├── rnex-workspace-status/
│       │   └── SKILL.md
│       ├── rnex-karpathy-llm-wiki-ingest/
│       │   └── SKILL.md
│       └── rnex-karpathy-llm-wiki-lint/
│           └── SKILL.md
├── .rnex/
│   ├── skills/                        # Core workspace agentic skills
│   └── plugins/
│       └── karpathy-llm/              # Scoped plugin skills and rules
└── rnex.yaml
```

---

## Disabling & Pruning

To disable the Gemini plugin:

```sh
rnex plugin disable gemini
```

Repo Nexus automatically performs surgical cleanup:
- Removes auto-generated user skills under `.agents/skills/rnex-*`.
- Cleans up managed routing instructions in `GEMINI.md`.
- Developer-created files under `.agents/` or `.gemini/` that do not originate from Repo Nexus are preserved.
