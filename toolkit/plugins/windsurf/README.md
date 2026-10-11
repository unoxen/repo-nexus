# Windsurf Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Windsurf IDE.

## Capabilities

1. **Instructions Integration**: Generates and maintains `.windsurfrules` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **Prompts Mirroring**: Standardized Repo Nexus prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, etc.) and active plugins' workflows are mirrored into `.windsurf/prompts/*.md`.
3. **Agent Skills**: Prompts and active plugin skills are mirrored into `.windsurf/skills/<name>/SKILL.md`.

## Usage

Enable the plugin across the workspace:
```bash
rnex plugin enable windsurf
```

Or configure options in `rnex.yaml` or `.local.rnex.yaml`:
```yaml
plugins:
  windsurf:
    instructions: true
    prompts: true
    skills: true
    agents: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `instructions` | boolean | `true` | Maintain routing in `.windsurfrules` |
| `prompts` | boolean | `true` | Mirror prompts to `.windsurf/prompts/` |
| `skills` | boolean | `true` | Mirror skills to `.windsurf/skills/<name>/SKILL.md` |
| `agents` | boolean | `true` | Mirror custom agents to `.windsurf/agents/*.md` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
