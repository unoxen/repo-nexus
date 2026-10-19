# Windsurf Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Windsurf IDE.

## Capabilities

1. **Instructions Integration**: Generates and maintains `.windsurfrules` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **User Skills Generation**: Standardized Repo Nexus core skills and active plugins' skills are mirrored as zero-logic User Skill pointers (`rnex-<name>.md`) in `.windsurf/rules/`.

## Usage

Enable the plugin across the workspace:
```bash
rnex plugin enable windsurf
```

Or configure options in `rnex.yaml` or `.local.rnex.yaml`:
```yaml
plugins:
  windsurf:
    skills: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `skills` | boolean | `true` | Generate user skills in `.windsurf/rules/` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
