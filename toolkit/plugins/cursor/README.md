# Cursor Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Cursor IDE.

## Capabilities

1. **Instructions Integration**: Generates and maintains `.cursorrules` and `.cursor/rules/rnex-context.mdc` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **Prompts Mirroring**: Standardized Repo Nexus prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, etc.) and active plugins' workflows are mirrored into `.cursor/prompts/*.md`.
3. **Agent Skills**: Prompts and active plugin skills are mirrored into `.cursor/skills/<name>/SKILL.md`.

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
    skills: true
    agents: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `instructions` | boolean | `true` | Maintain routing in `.cursorrules` & `.cursor/rules/` |
| `prompts` | boolean | `true` | Mirror prompts to `.cursor/prompts/` |
| `skills` | boolean | `true` | Mirror skills to `.cursor/skills/<name>/SKILL.md` |
| `agents` | boolean | `true` | Mirror custom agents to `.cursor/agents/*.md` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
