# Cursor Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Cursor IDE.

## Capabilities

1. **Instructions Integration**: Generates and maintains `.cursorrules` and `.cursor/rules/rnex-context.mdc` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **User Skills Generation**: Standardized Repo Nexus core skills and active plugins' skills are mirrored as zero-logic User Skill pointers (`rnex-<name>.md`) in `.cursor/rules/`.
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
    skills: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `instructions` | boolean | `true` | Maintain routing in `.cursorrules` & `.cursor/rules/` |
| `skills` | boolean | `true` | Generate user skills in `.cursor/rules/` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
