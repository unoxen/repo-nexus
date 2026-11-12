---
title: Windsurf IDE Plugin
description: Integrate Windsurf IDE and Cascade with Repo Nexus, generating zero-logic user skill pointers in .windsurf/rules/.
---

# Windsurf IDE Plugin

The **`windsurf`** plugin integrates Codeium's Windsurf IDE and Cascade into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share `AGENTS.md` at the workspace root as the single universal source of truth for routing. When enabled, the `windsurf` plugin generates zero-logic User Skill pointers into `.windsurf/rules/` (e.g. `rnex-clone-sync.md`, `rnex-batch-exec.md`, `rnex-llm-wiki-ingest.md`).

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

4. **Lifecycle Hooks Integration (`.windsurf/hooks.json`)**:
   - Projects user-configured hooks from `rnex.yaml` into `.windsurf/hooks.json` (normalizing `SessionStart` to `pre_user_prompt`).
   - Hooks are strictly opt-in; omitting `hooks` ensures `.windsurf/hooks.json` remains clean or is deleted if empty.

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
    hooks:               # Strictly opt-in AI lifecycle hooks
      SessionStart:
        - "rnex sync --quiet"
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `skills` | boolean | `true` | Generate user skill pointers in `.windsurf/rules/rnex-*.md`. |
| `hooks` | map | *(none)* | Strictly opt-in lifecycle hooks projected into `.windsurf/hooks.json` (e.g. `SessionStart: ["rnex sync --quiet"]`). Cleanly removed when unconfigured. |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `windsurf` is enabled with functional plugins like `llm-wiki`, it generates:

```text
my-workspace/
├── AGENTS.md                          # Universal workspace instructions & routing
├── .windsurfrules                     # Windsurf instructions
├── .windsurf/
│   └── rules/                         # Zero-logic User Skill pointers
│       ├── rnex-clone-sync.md
│       ├── rnex-batch-exec.md
│       ├── rnex-workspace-status.md
│       ├── rnex-llm-wiki-ingest.md
│       └── rnex-llm-wiki-lint.md
├── .rnex/
│   ├── skills/                        # Core workspace agentic skills
│   └── plugins/
│       └── llm-wiki/              # Scoped plugin skills and rules
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
