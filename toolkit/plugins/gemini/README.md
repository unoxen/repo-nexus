# Gemini Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Google Gemini CLI and Google Antigravity.

## Capabilities

1. **Instructions Integration**: Generates and maintains `GEMINI.md` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **Prompts Mirroring**: Standardized Repo Nexus prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, etc.) and active plugins' workflows are mirrored into `.gemini/prompts/*.prompt.md`.
3. **Agent Skills**: Prompts and active plugin skills are mirrored into `.gemini/skills/<name>/SKILL.md`.

## Usage

Enable the plugin across the workspace:
```bash
rnex plugin enable gemini
```

Or configure options in `rnex.yaml` or `.local.rnex.yaml`:
```yaml
plugins:
  gemini:
    instructions: true
    prompts: true
    skills: true
    agents: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `instructions` | boolean | `true` | Maintain routing in `GEMINI.md` |
| `prompts` | boolean | `true` | Mirror prompts to `.gemini/prompts/` |
| `skills` | boolean | `true` | Mirror skills to `.gemini/skills/<name>/SKILL.md` |
| `agents` | boolean | `true` | Mirror custom agents to `.gemini/agents/*.md` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
