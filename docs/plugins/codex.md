---
title: OpenAI Codex Plugin
description: Integrate OpenAI Codex CLI and assistants with Repo Nexus, generating zero-logic user skill pointers in .codex/skills/.
---

# OpenAI Codex Plugin

The **`codex`** plugin integrates OpenAI Codex CLI (`codex`) and environments into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share `AGENTS.md` at the workspace root as the single universal source of truth for routing. When enabled, the `codex` plugin generates zero-logic User Skill pointers into `.codex/skills/` (e.g. `rnex-clone-sync/SKILL.md`, `rnex-batch-exec/SKILL.md`, `rnex-llm-wiki-ingest/SKILL.md`).

Operational skills, rules, and subagents remain cleanly encapsulated within `.rnex/skills/` and active plugin directories (`.rnex/plugins/<plugin-name>/`).

---

## Capabilities

1. **Zero-Logic User Skills (`.codex/skills/rnex-*/SKILL.md`)**:
   - Generates native `SKILL.md` bundles prefixed with `rnex-` in `.codex/skills/` with YAML frontmatter for Codex skill discovery.
   - Contains zero inline heuristics—redirects Codex directly to the underlying agentic skill protocols inside `.rnex/`.

2. **Native Instruction Support via `CODEX.md` & `AGENTS.md`**:
   - OpenAI Codex natively looks for `CODEX.md` as its primary instruction file; it falls back to `AGENTS.md` when no `CODEX.md` exists in the project.
   - When enabled, the Codex plugin automatically synchronizes Repo Nexus routing instructions to `CODEX.md` (or merges them cleanly if you already have custom instructions).
   - Routing instructions in `CODEX.md` are permanently maintained across plugin state transitions (such as disabling the plugin), guaranteeing uninterrupted context routing without breaking assistant workflows.

3. **Subagent & Skill Execution**:
   - Core skills reside under `.rnex/skills/`.
   - Plugin skills reside under `.rnex/plugins/<plugin>/skills/`.
   - Subagents reside under `.rnex/agents/` and `.rnex/plugins/<plugin>/agents/` and are invoked as subagents without external mirroring.

4. **Lifecycle Hooks Integration (`.codex/hooks.json`)**:
   - Projects user-configured hooks from `rnex.yaml` into `.codex/hooks.json` using Codex's native hook schema (e.g. `SessionStart`).
   - Hooks are strictly opt-in; omitting `hooks` ensures `.codex/hooks.json` remains clean or is deleted if empty.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable codex

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local codex
```

Or initialize a new workspace with Codex integration pre-configured:

```sh
rnex init --codex
```

---

## Configuration Options

Configure options under `plugins.codex` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  codex:
    skills: true         # Generate user skills in .codex/skills/ (default: true)
    instructions: true   # Maintain routing instructions in CODEX.md (default: true)
    hooks:               # Strictly opt-in AI lifecycle hooks
      SessionStart:
        - "rnex sync --quiet"
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `skills` | boolean | `true` | Generate user skill pointers in `.codex/skills/rnex-*/SKILL.md`. |
| `instructions` | boolean | `true` | Maintain routing directive in `CODEX.md`. |
| `hooks` | map | *(none)* | Strictly opt-in lifecycle hooks projected into `.codex/hooks.json` (e.g. `SessionStart: ["rnex sync --quiet"]`). Cleanly removed when unconfigured. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `codex` is enabled with functional plugins like `llm-wiki`, it generates:

```text
my-workspace/
├── AGENTS.md                          # Universal workspace instructions & routing
├── CODEX.md                           # Codex-specific instructions
├── .codex/
│   └── skills/                        # Zero-logic User Skill pointers
│       ├── rnex-clone-sync/
│       │   └── SKILL.md
│       ├── rnex-batch-exec/
│       │   └── SKILL.md
│       ├── rnex-workspace-status/
│       │   └── SKILL.md
│       ├── rnex-llm-wiki-ingest/
│       │   └── SKILL.md
│       └── rnex-llm-wiki-lint/
│           └── SKILL.md
├── .rnex/
│   ├── skills/                        # Core workspace agentic skills
│   └── plugins/
│       └── llm-wiki/              # Scoped plugin skills and rules
└── rnex.yaml
```

---

## Disabling & Pruning

To disable the Codex plugin:

```sh
rnex plugin disable codex
```

Repo Nexus automatically performs surgical cleanup:
- Removes auto-generated user skills under `.codex/skills/rnex-*`.
- Preserves routing instructions in `CODEX.md` and `AGENTS.md`.
- Developer-created custom skills and rules under `.codex/` are preserved.
