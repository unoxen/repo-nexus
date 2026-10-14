# GitHub Copilot Integration for Repo Nexus

This workspace has the Repo Nexus `copilot` plugin enabled.

## Operating Principles
- **Prompts (`.github/prompts/*.prompt.md`)**: Operational Repo Nexus prompts and active plugins' prompts/workflows are mirrored here with YAML frontmatter (`name`, `description`) for use in the VS Code Copilot Chat prompt picker and slash commands.
- **Universal Routing (`AGENTS.md`)**: GitHub Copilot natively reads `AGENTS.md` for workspace routing and active plugin guidelines between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`.
- **Decoupled Cross-Plugin Discovery**: Plugins remain independent and decoupled; the `copilot` provider discovers and mirrors operational prompts and workflows from whatever plugins are currently active. Workspace skills reside under `.rnex/skills/`.

## Configuration
Configure plugin options in `rnex.yaml` or override them per developer in `.local.rnex.yaml`:

```yaml
plugins:
  copilot:
    prompts: true        # Mirror prompts to .github/prompts/ (default: true)
    workflows: true      # Mirror workflows (default: true)
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:
```yaml
plugins:
  copilot:
    enabled: false
```
