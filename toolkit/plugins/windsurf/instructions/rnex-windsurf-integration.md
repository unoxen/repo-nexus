# Windsurf IDE Integration for Repo Nexus

This workspace has the Repo Nexus `windsurf` plugin enabled.

## Operating Principles
- **Windsurf Rules (`.windsurfrules`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, preserving manual user rules outside delimiters.
- **Prompts (`.windsurf/prompts/*.md`)**: Operational Repo Nexus prompts and active plugins' prompts/workflows are mirrored here.
- **Agent Skills (`.windsurf/skills/<name>/SKILL.md`)**: Standard prompts and active plugin skills are mirrored as individual skill bundles.

## Configuration
Configure plugin options in `rnex.yaml` or override them per developer in `.local.rnex.yaml`:

```yaml
plugins:
  windsurf:
    instructions: true   # Maintain routing in .windsurfrules (default: true)
    prompts: true        # Mirror prompts to .windsurf/prompts/ (default: true)
    skills: true         # Mirror skills to .windsurf/skills/ (default: true)
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:
```yaml
plugins:
  windsurf:
    enabled: false
```
