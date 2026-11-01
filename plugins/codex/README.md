# OpenAI Codex Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for OpenAI Codex and ChatGPT.

## Capabilities

1. **Instructions Integration**: Generates and maintains `CODEX.md` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **User Skills Generation**: Standardized Repo Nexus core skills and active plugins' skills are mirrored as zero-logic User Skill pointers (`rnex-<name>.md`) in `.codex/skills/`.

## Usage

Enable the plugin across the workspace:
```bash
rnex plugin enable codex
```

Or configure options in `rnex.yaml` or `.local.rnex.yaml`:
```yaml
plugins:
  codex:
    skills: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `skills` | boolean | `true` | Generate user skills in `.codex/skills/` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
