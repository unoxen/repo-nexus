# Claude Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Anthropic Claude Code CLI and Claude Desktop.

## Capabilities

1. **Instructions Integration**: Generates and maintains `CLAUDE.md` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **User Skills Generation**: Standardized Repo Nexus core skills and active plugins' skills are mirrored as zero-logic User Skill pointers (`rnex-<name>.md`) in `.claude/skills/`.
3. **Lifecycle Hooks Integration**: Projects user-configured hooks from `rnex.yaml` into `.claude/settings.json` using native Envelope hooks schema (e.g. `SessionStart`). Strictly opt-in.

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
    hooks:
      SessionStart:
        - "rnex sync --quiet"
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `skills` | boolean | `true` | Generate user skills in `.claude/skills/` |
| `hooks` | map | (none) | Configure AI provider lifecycle hooks projected into `.claude/settings.json` (e.g. `SessionStart: ["rnex sync --quiet"]`). Strictly opt-in. |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
