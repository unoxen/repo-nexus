---
title: Authoring Custom Plugins
description: Guide to building, structuring, and distributing custom Repo Nexus plugins with plugin.yaml manifests and agent context assets.
---

# Authoring Custom Plugins

Repo Nexus allows teams to author custom plugins containing specialized coding conventions, agent workflows, skills, subagents, and scaffolding templates.

---

## Plugin Locations

Custom plugins can be loaded from two discovery locations:
1. **Workspace Local**: `.rnex/plugins/<plugin-name>/` (scoped to the workspace).
2. **Toolkit Directory**: `toolkit/plugins/<plugin-name>/` (shipped or vendor-managed).

---

## The `plugin.yaml` Manifest

Every plugin requires a `plugin.yaml` manifest in its root directory:

```yaml
name: team-conventions
version: 1.0.0
description: Organization architecture guidelines, workflows, and subagents
author: Architecture Team <arch@my-org.com>
homepage: https://github.com/my-org/team-conventions

# Scaffolding templates copied into the workspace
templates:
  - templates/editorconfig.sample: .editorconfig
```

---

## Directory Conventions

A plugin can contain any of the following standard directories:

| Subdirectory | Purpose | Behavior |
|:---|:---|:---|
| `workflows/` | Multi-step agent procedural checklists and workflows. | Maintained under `.rnex/plugins/<plugin>/workflows/` and mirrored to provider prompt pickers when `prompts: true`. |
| `skills/` | Agent skills with `SKILL.md` definitions. | Scoped to `.rnex/plugins/<plugin>/skills/`. Ingested by agents via `AGENTS.md` routing. |
| `agents/` | Autonomous subagent declarations (`*.agent.md`). | Scoped to `.rnex/plugins/<plugin>/agents/`. Ingested by agents via `AGENTS.md` subagent routing. |
| `instructions/` | Markdown guidelines and domain principles. | Scoped to `.rnex/plugins/<plugin>/instructions/`. |
| `rules/` | Coding rules and architectural constraints. | Scoped to `.rnex/plugins/<plugin>/rules/`. |
| `templates/` | Starter configuration files copied during `rnex fix`. | Copied to mapped paths specified in `templates:`. |

> [!NOTE]
> All AI assistants share `AGENTS.md` at workspace root. Tools, skills, workflows, and subagents stay inside `.rnex/` and are not mirrored externally. Prompts are exclusively for user invocation through IDE prompt pickers (e.g. `.github/prompts/`, `.claude/commands/`).

---

## Testing Your Custom Plugin

1. Create your plugin directory in `.rnex/plugins/my-plugin/`.
2. Add `plugin.yaml` and desired assets.
3. Enable the plugin in `rnex.yaml`:
   ```yaml
   plugins:
     my-plugin: {}
   ```
4. Reconcile workspace state:
   ```bash
   rnex fix
   ```
5. Verify that assets were correctly scoped into `.rnex/plugins/my-plugin/`.
