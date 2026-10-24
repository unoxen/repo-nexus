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
| `commands/` | Native CLI subcommands (`<command>.sh`). | Scoped to `.rnex/plugins/<plugin>/commands/`. Executed via `rnex plugin <plugin> <command> [options]`. |
| `skills/` | Plugin-owned agentic skills (`<skill-name>.md`). | Scoped to `.rnex/plugins/<plugin>/skills/`. Registered as User Skills via `rnex_register_user_skill`. |
| `rules/` | Coding rules and architectural constraints. | Scoped to `.rnex/plugins/<plugin>/rules/`. |
| `agents/` | Autonomous subagent declarations (`*.agent.md`). | Scoped to `.rnex/plugins/<plugin>/agents/`. Ingested by agents via `AGENTS.md` subagent routing. |
| `instructions/` | Markdown guidelines and domain principles. | Scoped to `.rnex/plugins/<plugin>/instructions/`. |
| `hooks/` | Lifecycle hook scripts (`after_sync.sh`, `before_plugin_disable.sh`). | Executed during workspace events. Register/unregister User Skills. |
| `templates/` | Starter configuration files copied during `rnex sync`. | Copied to mapped paths specified in `templates:`. |

> [!NOTE]
> All AI assistants share `AGENTS.md` at workspace root. Agentic skills, rules, and subagents stay inside `.rnex/` and are not mirrored externally. Active provider plugins expose zero-logic User Skill pointers (`rnex-<name>.md`) in active provider directories (`.cursor/rules/`, `.claude/skills/`, etc.) linking directly to the agentic skill protocols inside `.rnex/`.

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
   rnex sync
   ```
5. Verify that assets were correctly scoped into `.rnex/plugins/my-plugin/`.
