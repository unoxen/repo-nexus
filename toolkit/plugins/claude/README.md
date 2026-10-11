# Claude Plugin for Repo Nexus

A built-in Repo Nexus plugin providing bidirectional alignment and operational prompt/skill mirroring for Anthropic Claude Code CLI and Claude Desktop.

## Capabilities

1. **Instructions Integration**: Generates and maintains `CLAUDE.md` with Repo Nexus routing instructions while preserving custom instructions outside delimiters.
2. **Slash Commands Mirroring**: Standardized Repo Nexus prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, etc.) and active plugins' workflows are mirrored into `.claude/commands/*.md` and `.claude/prompts/*.md` for native Claude Code command picker.
3. **Agent Skills**: Prompts and active plugin skills are mirrored into `.claude/skills/<name>/SKILL.md`.

## Usage

Enable the plugin across the workspace:
```bash
rnex plugin enable claude
```

Or configure options in `rnex.yaml` or `.local.rnex.yaml`:
```yaml
plugins:
  claude:
    instructions: true
    prompts: true
    skills: true
    agents: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `instructions` | boolean | `true` | Maintain routing in `CLAUDE.md` |
| `prompts` | boolean | `true` | Mirror prompts to `.claude/commands/` and `.claude/prompts/` |
| `skills` | boolean | `true` | Mirror skills to `.claude/skills/<name>/SKILL.md` |
| `agents` | boolean | `true` | Mirror custom agents to `.claude/agents/*.md` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
