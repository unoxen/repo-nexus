# OpenAI Codex Integration for Repo Nexus

This workspace has the Repo Nexus `codex` plugin enabled.

## Operating Principles
- **Codex Instructions (`CODEX.md`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, preserving any manual user instructions outside those markers. This serves as the primary instructions file for OpenAI Codex and ChatGPT.
- **User Skills (`.codex/skills/rnex-*.md`)**: Zero-logic user skill pointers linking directly to core skills (`.rnex/skills/`) and active plugins' skills (`.rnex/plugins/<name>/skills/`).
- **Decoupled Cross-Plugin Discovery**: The `codex` provider discovers and registers user skills from whatever Repo Nexus plugins are currently active.

## Configuration
Configure plugin options in `rnex.yaml` or override them per developer in `.local.rnex.yaml`:

```yaml
plugins:
  codex:
    skills: true         # Generate user skills in .codex/skills/ (default: true)
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:
```yaml
plugins:
  codex:
    enabled: false
```
