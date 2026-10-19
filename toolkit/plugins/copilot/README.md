# GitHub Copilot Plugin for Repo Nexus

A built-in Repo Nexus plugin providing instructions and skill integration for GitHub Copilot.

## Capabilities

1. **Instructions Integration**: Generates and maintains `.github/copilot-instructions.md` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **User Skills Generation**: Standardized Repo Nexus core skills and active plugins' skills are mirrored as zero-logic User Skill pointers (`rnex-<name>/SKILL.md`) in `.github/skills/`.

## Usage

Enable the plugin across the workspace:
```bash
rnex plugin enable copilot
```

Or configure options in `rnex.yaml` or `.local.rnex.yaml`:
```yaml
plugins:
  copilot:
    skills: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `skills` | boolean | `true` | Generate user skills in `.github/skills/` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
