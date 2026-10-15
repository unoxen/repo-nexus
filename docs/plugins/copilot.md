---
title: GitHub Copilot Plugin
description: GitHub Copilot workspace routing instructions and user skill integration for Repo Nexus.
---

# GitHub Copilot Plugin (`copilot`)

The `copilot` plugin integrates GitHub Copilot with Repo Nexus by projecting workspace routing instructions into `.github/copilot-instructions.md` and user skills into `.github/skills/`.

## Architecture & Integration

GitHub Copilot operates natively within VS Code, Visual Studio, JetBrains, and GitHub.com:
- **Universal Routing (`AGENTS.md`)**: GitHub Copilot natively reads `AGENTS.md` at the workspace root.
- **Custom Instructions (`.github/copilot-instructions.md`)**: When `instructions: true`, Repo Nexus injects its non-destructive routing block inside `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`. Custom developer rules outside these markers are strictly preserved.
- **User Skills (`.github/skills/`)**: When `skills: true`, zero-logic User Skill pointers (`rnex-<name>.md`) redirect Copilot Chat to the underlying agentic skills under `.rnex/skills/` and active plugins.

## Configuration

Enable in `rnex.yaml`:

```yaml
plugins:
  copilot:
    instructions: true   # Maintain routing in .github/copilot-instructions.md
    skills: true         # Generate user skills in .github/skills/
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:

```yaml
plugins:
  copilot:
    enabled: false
```

## CLI Management

```bash
# Enable Copilot plugin across workspace
rnex plugin enable copilot

# Inspect Copilot plugin status
rnex plugin info copilot

# Disable Copilot plugin
rnex plugin disable copilot
```
