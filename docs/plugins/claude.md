---
title: Anthropic Claude Plugin
description: Integrate Anthropic Claude Code with Repo Nexus, generating zero-logic user skill pointers in .claude/skills/.
---

# Anthropic Claude Plugin

The **`claude`** plugin integrates Anthropic Claude Code CLI (`claude`) and Claude Desktop into a Repo Nexus Virtual Meta-Repo.

All AI assistants in Repo Nexus share [`AGENTS.md`](file:///Users/admin/Projects/ai/repo-nexus/AGENTS.md) at the workspace root as the single universal source of truth for routing. When enabled, the `claude` plugin generates zero-logic User Skill pointers into `.claude/skills/` (e.g. `rnex-clone-sync.md`, `rnex-batch-exec.md`, `rnex-karpathy-llm-wiki-ingest`).

Operational skills, rules, and subagents remain cleanly encapsulated within `.rnex/skills/` and active plugin directories (`.rnex/plugins/<plugin-name>/`).

---

## Capabilities

1. **Zero-Logic User Skills (`.claude/skills/rnex-*/SKILL.md`)**:
   - Generates native `SKILL.md` bundles prefixed with `rnex-` in `.claude/skills/` with YAML frontmatter for Claude Code skill discovery.
   - Contains zero inline heuristics—redirects Claude directly to the underlying agentic skill protocols inside `.rnex/`.

2. **Native Instruction Support via `CLAUDE.md` & `AGENTS.md`**:
   - Claude Code natively reads `CLAUDE.md` as its primary instructions file; it only falls back to `AGENTS.md` when no `CLAUDE.md` exists in the project.
   - When enabled, the Claude plugin automatically synchronizes Repo Nexus routing instructions to `CLAUDE.md` (or merges them cleanly if you already have custom instructions).
   - If the plugin is disabled, the routing block is removed, allowing Claude Code to read `AGENTS.md` directly.

3. **Subagent & Skill Execution**:
   - Core skills reside under `.rnex/skills/`.
   - Plugin skills reside under `.rnex/plugins/<plugin>/skills/`.
   - Subagents reside under `.rnex/agents/` and `.rnex/plugins/<plugin>/agents/` and are invoked as subagents without external mirroring.

---

## Enabling the Plugin

### Via CLI

```sh
# Enable across the workspace in rnex.yaml
rnex plugin enable claude

# Enable locally in .local.rnex.yaml for your workstation only
rnex plugin enable --local claude
```

Or initialize a new workspace with Claude Code integration pre-configured:

```sh
rnex init --claude
```

---

## Configuration Options

Configure options under `plugins.claude` in `rnex.yaml` or `.local.rnex.yaml`:

```yaml
plugins:
  claude:
    skills: true         # Generate user skills in .claude/skills/ (default: true)
    auto_sync_on: SessionStart # Trigger auto-sync on lifecycle event (default: SessionStart, or false)
    enabled: true        # Set to false to disable
```

| Option | Type | Default | Description |
|:---|:---|:---|:---|
| `skills` | boolean | `true` | Generate user skill pointers in `.claude/skills/rnex-*.md`. |
| `auto_sync_on` | string/boolean | `SessionStart` | Lifecycle event triggering auto-sync in `.claude/settings.json` (or `false` to disable). |
| `enabled` | boolean | `true` | Enable or disable the plugin. Overridable in `.local.rnex.yaml`. |

---

## Generated Directory Structure

When `claude` is enabled with functional plugins like `karpathy-llm`, it generates:

```text
my-workspace/
├── AGENTS.md                          # Universal workspace instructions & routing
├── CLAUDE.md                          # Claude-specific instructions
├── .claude/
│   └── skills/                        # Zero-logic User Skill pointers
│       ├── rnex-clone-sync.md
│       ├── rnex-batch-exec.md
│       ├── rnex-workspace-status.md
│       ├── rnex-karpathy-llm-wiki-ingest/
│       └── rnex-karpathy-llm-wiki-lint/
├── .rnex/
│   ├── skills/                        # Core workspace agentic skills
│   └── plugins/
│       └── karpathy-llm/              # Scoped plugin skills and rules
└── rnex.yaml
```

---

## Disabling & Pruning

To disable the Claude plugin:

```sh
rnex plugin disable claude
```

Repo Nexus automatically performs surgical cleanup:
- Removes auto-generated user skills under `.claude/skills/rnex-*.md`.
- Cleans up managed routing instructions in `CLAUDE.md`.
- Developer-created custom skills under `.claude/` are preserved.
