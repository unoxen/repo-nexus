# Windsurf Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Windsurf IDE.

## Capabilities

1. **Instructions Integration**: Generates and maintains `.windsurfrules` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **Prompts Mirroring**: Standardized Repo Nexus prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, etc.) and active plugins' workflows are mirrored into `.windsurf/prompts/*.md`.

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
    workflows: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `instructions` | boolean | `true` | Maintain routing in `.windsurfrules` |
| `prompts` | boolean | `true` | Mirror prompts to `.windsurf/prompts/` |
| `workflows` | boolean | `true` | Mirror workflows to `.windsurf/prompts/` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
