# Windsurf IDE Integration for Repo Nexus

This workspace has the Repo Nexus `windsurf` plugin enabled.

## Operating Principles
- **Windsurf Rules (`.windsurfrules`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, preserving manual user rules outside delimiters.
- **Prompts (`.windsurf/prompts/*.md`)**: Operational Repo Nexus prompts and active plugins' prompts/workflows are mirrored here.
- **Decoupled Cross-Plugin Discovery**: The `windsurf` provider discovers and mirrors operational prompts and workflows from whatever Repo Nexus plugins are currently active. Workspace skills reside under `.rnex/skills/`.

## Configuration
Configure plugin options in `rnex.yaml` or override them per developer in `.local.rnex.yaml`:

```yaml
plugins:
  windsurf:
    instructions: true   # Maintain routing in .windsurfrules (default: true)
    prompts: true        # Mirror prompts to .windsurf/prompts/ (default: true)
    workflows: true      # Mirror workflows (default: true)
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:
```yaml
plugins:
  windsurf:
    enabled: false
```
