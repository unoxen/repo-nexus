# Windsurf IDE Integration for Repo Nexus

This workspace has the Repo Nexus `windsurf` plugin enabled.

## Operating Principles
- **Windsurf Rules (`.windsurfrules`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, preserving manual user rules outside delimiters.
- **User Skills (`.windsurf/rules/rnex-*.md`)**: Zero-logic user skill pointers linking directly to core skills (`.rnex/skills/`) and active plugins' skills (`.rnex/plugins/<name>/skills/`).
- **Decoupled Cross-Plugin Discovery**: The `windsurf` provider discovers and registers user skills from whatever Repo Nexus plugins are currently active.

## Configuration
Configure plugin options in `rnex.yaml` or override them per developer in `.local.rnex.yaml`:

```yaml
plugins:
  windsurf:
    skills: true         # Generate user skills in .windsurf/rules/ (default: true)
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:
```yaml
plugins:
  windsurf:
    enabled: false
```
