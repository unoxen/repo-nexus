# Google Gemini & Antigravity Integration for Repo Nexus

This workspace has the Repo Nexus `gemini` plugin enabled.

## Operating Principles
- **Gemini Instructions (`GEMINI.md`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, preserving any manual user instructions outside those markers. This serves as the primary instructions file for Google Gemini CLI and Google Antigravity.
- **Prompts (`.gemini/prompts/*.prompt.md`)**: Operational Repo Nexus prompts and active plugins' prompts/workflows are mirrored here with YAML frontmatter (`name`, `description`).
- **Agent Skills (`.gemini/skills/<name>/SKILL.md`)**: Standard prompts and active plugin skills are mirrored as individual skill bundles conforming to the Antigravity / Gemini skills specification.
- **Decoupled Cross-Plugin Discovery**: The `gemini` provider discovers and mirrors prompts and skills from whatever Repo Nexus plugins are currently active.

## Configuration
Configure plugin options in `rnex.yaml` or override them per developer in `.local.rnex.yaml`:

```yaml
plugins:
  gemini:
    instructions: true   # Maintain routing in GEMINI.md (default: true)
    prompts: true        # Mirror prompts to .gemini/prompts/ (default: true)
    skills: true         # Mirror skills to .gemini/skills/ (default: true)
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:
```yaml
plugins:
  gemini:
    enabled: false
```
