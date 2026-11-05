# Gemini Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Google Gemini CLI and Google Antigravity.

## Capabilities

1. **Instructions Integration**: Generates and maintains `GEMINI.md` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **User Skills Generation**: Standardized Repo Nexus core skills and active plugins' skills are mirrored as zero-logic User Skill pointers (`rnex-<name>.md`) in `.agents/skills/`.
3. **File Discovery Un-Ignore**: Maintains `.geminiignore` (`!repos/*`) so Gemini CLI and Google Antigravity can discover and access member repository files.

## Usage

Enable the plugin across the workspace:
```bash
rnex plugin enable gemini
```

Or configure options in `rnex.yaml` or `.local.rnex.yaml`:
```yaml
plugins:
  gemini:
    skills: true
    hooks:
      SessionStart:
        - "rnex sync --quiet"
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `skills` | boolean | `true` | Generate user skills in `.agents/skills/` |
| `hooks` | map/boolean | `SessionStart: ["rnex sync --quiet"]` | AI provider lifecycle hooks generated in `.agents/hooks/rnex-hook-<event>.sh` and `.agents/hooks.json` (or `false` to disable) |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
