# GitHub Copilot Integration for Repo Nexus

This workspace has the Repo Nexus `copilot` plugin enabled.

## Operating Principles
- **Prompts (`.github/prompts/*.prompt.md`)**: Operational Repo Nexus prompts and active plugins' prompts/workflows are mirrored here with YAML frontmatter (`name`, `description`) for use in the VS Code Copilot Chat prompt picker and slash commands.
- **Agent Skills (`.github/skills/<name>/SKILL.md`)**: Standard prompts, active plugin skills, and agent bundles are mirrored as individual skill bundles with frontmatter for GitHub Copilot Agent mode and `gh skill`.
- **Custom Agents (`.github/agents/*.agent.md`)**: Active plugins' agent definitions (such as `wiki-curator`) are mirrored here for Copilot workspace custom agents.
- **Copilot Instructions (`.github/copilot-instructions.md`)**: Synthesizes workspace routing and active plugin guidelines between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, preserving any manual user instructions outside those markers.
- **Decoupled Cross-Plugin Discovery**: Plugins remain independent and decoupled; the `copilot` provider discovers and mirrors assets from whatever plugins are currently active.

## Configuration
Configure plugin options in `rnex.yaml` or override them per developer in `.local.rnex.yaml`:

```yaml
plugins:
  copilot:
    prompts: true        # Mirror prompts to .github/prompts/ (default: true)
    skills: true         # Mirror skills to .github/skills/ (default: true)
    instructions: true   # Mirror routing & plugin guidelines to .github/copilot-instructions.md (default: true)
    agents: true         # Mirror custom agents to .github/agents/ (default: true)
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:
```yaml
plugins:
  copilot:
    enabled: false
```
