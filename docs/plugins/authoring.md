---
title: Authoring Custom Plugins
description: Guide to building, structuring, and distributing custom Repo Nexus plugins with plugin.yaml manifests and agent context assets.
---

# Authoring Custom Plugins

Repo Nexus allows teams to author custom plugins containing specialized coding conventions, prompt libraries, agent skills, and scaffolding templates.

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
description: Organization architecture guidelines, prompt suites, and agent skills
author: Architecture Team <arch@my-org.com>
homepage: https://github.com/my-org/team-conventions

# Destination mappings for instructions
instructions:
  - instructions/guidelines.md: .rnex/plugins/team-conventions/instructions/guidelines.md

# Destination mappings for coding rules
rules:
  - rules/typescript.md: .rnex/plugins/team-conventions/rules/typescript.md

# Scaffolding templates copied into the workspace
templates:
  - templates/editorconfig.sample: .editorconfig
```

---

## Directory Conventions

A plugin can contain any of the following standard directories:

| Subdirectory | Purpose | Behavior |
|:---|:---|:---|
| `instructions/` | Markdown guidelines referenced by AI agents. | Mirrored to AI provider instructions. |
| `rules/` | Coding rules and architectural constraints. | Injected into provider rule systems (e.g. `.cursor/rules/`). |
| `prompts/` | Operational task prompts (`*.md`). | Automatically indexed in `.rnex/prompts/index.md` and mirrored to `.github/prompts/` and `.claude/`. |
| `skills/` | Agent skills with `SKILL.md` definitions. | Mirrored to `.github/skills/`, `.claude/skills/`, `.gemini/skills/`. |
| `agents/` | Custom sub-agent declarations (`*.agent.md`). | Mirrored to provider agent folders. |
| `workflows/` | Multi-step agent procedural checklists. | Tracked under plugin scope. |
| `templates/` | Starter configuration files copied during `rnex fix`. | Copied to mapped paths specified in `templates:`. |

---

## Testing Your Custom Plugin

1. Create your plugin directory in `.rnex/plugins/my-plugin/`.
2. Add `plugin.yaml` and desired assets.
3. Enable the plugin in `rnex.yaml`:
   ```yaml
   plugins:
     my-plugin:
       enabled: true
   ```
4. Reconcile workspace state:
   ```bash
   rnex fix
   ```
5. Verify that assets were correctly discovered and mirrored across enabled AI providers.
