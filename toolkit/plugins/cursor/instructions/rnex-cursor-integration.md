# Cursor IDE Integration for Repo Nexus

This workspace has the Repo Nexus `cursor` plugin enabled.

## Operating Principles
- **Cursor Rules (`.cursorrules` & `.cursor/rules/repo-nexus.mdc`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, supporting both legacy `.cursorrules` and modern Cursor MDC rules format (`alwaysApply: true`).
- **Prompts (`.cursor/prompts/*.md`)**: Operational Repo Nexus prompts and active plugins' prompts/workflows are mirrored here.
- **Agent Skills (`.cursor/skills/<name>/SKILL.md`)**: Standard prompts and active plugin skills are mirrored as individual skill bundles.
- **Decoupled Cross-Plugin Discovery**: The `cursor` provider discovers and mirrors prompts and skills from whatever Repo Nexus plugins are currently active.

## Configuration
Configure plugin options in `rnex.yaml` or override them per developer in `.local.rnex.yaml`:

```yaml
plugins:
  cursor:
    instructions: true   # Maintain routing in .cursorrules & .cursor/rules/ (default: true)
    prompts: true        # Mirror prompts to .cursor/prompts/ (default: true)
    skills: true         # Mirror skills to .cursor/skills/ (default: true)
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:
```yaml
plugins:
  cursor:
    enabled: false
```
