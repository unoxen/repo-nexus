---
title: Cursor IDE Plugin
description: Integrate Cursor IDE with Repo Nexus, generating zero-logic user skill pointers in .cursor/rules/.
---

# Cursor IDE Plugin

The **`cursor`** plugin integrates Cursor IDE and Cursor Agent Mode into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share `AGENTS.md` at the workspace root as the single universal source of truth for routing. When enabled, the `cursor` plugin generates zero-logic User Skill pointers into `.cursor/rules/` (e.g. `rnex-clone-sync.md`, `rnex-batch-exec.md`, `rnex-wiki-ingest.md`).

Operational skills, rules, and subagents remain cleanly encapsulated within `.rnex/skills/` and active plugin directories (`.rnex/plugins/<plugin-name>/`).

---

## Capabilities

1. **Zero-Logic User Skills (`.cursor/rules/rnex-*.md`)**:
   - Generates lightweight user skill pointers prefixed with `rnex-` in `.cursor/rules/`.
   - Contains zero inline heuristics—redirects Cursor directly to the underlying agentic skill protocols inside `.rnex/`.

2. **Native Instructions & Rules Support**:
   - Automatically synchronizes Repo Nexus routing instructions to `.cursorrules` and `.cursor/rules/rnex-context.mdc`.
   - Preserves user custom rules and custom sections in `.cursorrules`.

3. **Subagent & Skill Execution**:
   - Core skills reside under `.rnex/skills/`.
   - Plugin skills reside under `.rnex/plugins/<plugin>/skills/`.
   - Subagents reside under `.rnex/agents/` and `.rnex/plugins/<plugin>/agents/` and are invoked as subagents without external mirroring.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable cursor

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local cursor
```

Or initialize a new workspace with Cursor integration pre-configured:

```sh
rnex init --cursor
```

---

## Configuration Options

Configure options under `plugins.cursor` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  cursor:
    skills: true         # Generate user skills in .cursor/rules/ (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `skills` | boolean | `true` | Generate user skill pointers in `.cursor/rules/rnex-*.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `cursor` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── AGENTS.md                          # Universal workspace instructions & routing
├── .cursorrules                       # Cursor root instructions
├── .cursor/
│   └── rules/                         # Zero-logic User Skill pointers
│       ├── rnex-clone-sync.md
│       ├── rnex-batch-exec.md
│       ├── rnex-workspace-status.md
│       ├── rnex-karpathy-llm-wiki-ingest.md
│       └── rnex-karpathy-llm-wiki-lint.md
├── .rnex/
│   ├── skills/                        # Core workspace agentic skills
│   └── plugins/
│       └── karpathy-llm/              # Scoped plugin skills and rules
└── rnex.yaml
```

---

## Disabling & Pruning

To disable the Cursor plugin:

```sh
rnex plugin disable cursor
```

Repo Nexus automatically performs surgical cleanup:
- Removes auto-generated user skills under `.cursor/rules/rnex-*.md`.
- Preserves routing instructions in `.cursorrules` and `AGENTS.md`.
- Developer-created custom rules under `.cursor/` are preserved.
