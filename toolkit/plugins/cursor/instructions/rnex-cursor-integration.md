# Cursor IDE Integration for Repo Nexus

This workspace has the Repo Nexus `cursor` plugin enabled.

## Operating Principles
- **Cursor Rules (`.cursorrules` & `.cursor/rules/repo-nexus.mdc`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, supporting both legacy `.cursorrules` and modern Cursor MDC rules format (`alwaysApply: true`).
- **Prompts (`.cursor/prompts/*.md`)**: Operational Repo Nexus prompts and active plugins' prompts/workflows are mirrored here.
- **Codebase Indexing Un-Ignore (`.cursorignore`)**: Un-ignores member repositories (`!repos/*`) so Cursor's semantic indexing engine indexes code across member repositories, while workspace Git continues to ignore them.
- **Decoupled Cross-Plugin Discovery**: The `cursor` provider discovers and mirrors operational prompts and workflows from whatever Repo Nexus plugins are currently active. Workspace skills reside under `.rnex/skills/`.

## Configuration
Configure plugin options in `rnex.yaml` or override them per developer in `.local.rnex.yaml`:

```yaml
plugins:
  cursor:
    instructions: true   # Maintain routing in .cursorrules & .cursor/rules/ (default: true)
    prompts: true        # Mirror prompts to .cursor/prompts/ (default: true)
    workflows: true      # Mirror workflows (default: true)
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:
```yaml
plugins:
  cursor:
    enabled: false
```
