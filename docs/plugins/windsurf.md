---
title: Windsurf IDE Plugin
description: Integrate Windsurf IDE and Cascade with Repo Nexus, generating zero-logic user skill pointers in .windsurf/rules/.
---

# Windsurf IDE Plugin

The **`windsurf`** plugin integrates Codeium's Windsurf IDE and Cascade into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share `AGENTS.md` at the workspace root as the single universal source of truth for routing. When enabled, the `windsurf` plugin generates zero-logic User Skill pointers into `.windsurf/rules/` (e.g. `rnex-clone-sync.md`, `rnex-batch-exec.md`, `rnex-karpathy-llm-wiki-ingest.md`).

Operational skills, rules, and subagents remain cleanly encapsulated within `.rnex/skills/` and active plugin directories (`.rnex/plugins/<plugin-name>/`).

---

## Capabilities

1. **Zero-Logic User Skills (`.windsurf/rules/rnex-*.md`)**:
   - Generates lightweight user skill pointers prefixed with `rnex-` in `.windsurf/rules/`.
   - Contains zero inline heuristics—redirects Cascade directly to the underlying agentic skill protocols inside `.rnex/`.

2. **Native Instructions Support via `.windsurfrules`**:
   - Automatically synchronizes Repo Nexus routing instructions to `.windsurfrules`.
   - Preserves user custom rules and custom sections in `.windsurfrules`.

3. **Subagent & Skill Execution**:
   - Core skills reside under `.rnex/skills/`.
   - Plugin skills reside under `.rnex/plugins/<plugin>/skills/`.
   - Subagents reside under `.rnex/agents/` and `.rnex/plugins/<plugin>/agents/` and are invoked as subagents without external mirroring.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable windsurf

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local windsurf
```

Or initialize a new workspace with Windsurf integration pre-configured:

```sh
rnex init --windsurf
```

---

## Configuration Options

Configure options under `plugins.windsurf` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  windsurf:
    skills: true         # Generate user skills in .windsurf/rules/ (default: true)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `skills` | boolean | `true` | Generate user skill pointers in `.windsurf/rules/rnex-*.md`. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `windsurf` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── AGENTS.md                          # Universal workspace instructions & routing
├── .windsurfrules                     # Windsurf instructions
├── .windsurf/
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

To disable the Windsurf plugin:

```sh
rnex plugin disable windsurf
```

Repo Nexus automatically performs surgical cleanup:
- Removes auto-generated user skills under `.windsurf/rules/rnex-*.md`.
- Preserves routing instructions in `.windsurfrules` and `AGENTS.md`.
- Developer-created custom files under `.windsurf/` are preserved.
