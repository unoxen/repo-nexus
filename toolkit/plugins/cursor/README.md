# Cursor Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Cursor IDE.

## Capabilities

1. **Instructions Integration**: Generates and maintains `.cursorrules` and `.cursor/rules/rnex-context.mdc` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **Prompts Mirroring**: Standardized Repo Nexus prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, etc.) and active plugins' workflows are mirrored into `.cursor/prompts/*.md`.
3. **Codebase Indexing Un-Ignore**: Maintains `.cursorignore` (`!repos/*`) so Cursor's semantic indexing engine indexes code across member repositories.

## Usage

Enable the plugin across the workspace:
```bash
rnex plugin enable cursor
```

Or configure options in `rnex.yaml` or `.local.rnex.yaml`:
```yaml
plugins:
  cursor:
    instructions: true
    prompts: true
    workflows: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `instructions` | boolean | `true` | Maintain routing in `.cursorrules` & `.cursor/rules/` |
| `prompts` | boolean | `true` | Mirror prompts to `.cursor/prompts/` |
| `workflows` | boolean | `true` | Mirror workflows to `.cursor/prompts/` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
