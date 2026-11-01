# Claude Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Anthropic Claude Code CLI and Claude Desktop.

## Capabilities

1. **Instructions Integration**: Generates and maintains `CLAUDE.md` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **User Skills Generation**: Standardized Repo Nexus core skills and active plugins' skills are mirrored as zero-logic User Skill pointers (`rnex-<name>.md`) in `.claude/skills/`.

## Usage

Enable the plugin across the workspace:
```bash
rnex plugin enable claude
```

Or configure options in `rnex.yaml` or `.local.rnex.yaml`:
```yaml
plugins:
  claude:
    skills: true
    auto_sync_on: SessionStart
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `skills` | boolean | `true` | Generate user skills in `.claude/skills/` |
| `auto_sync_on` | string/boolean | `SessionStart` | Lifecycle event triggering auto-sync in `.claude/settings.json` (or `false` to disable) |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
