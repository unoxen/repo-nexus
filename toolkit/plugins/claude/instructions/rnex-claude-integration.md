# Anthropic Claude Code Integration for Repo Nexus

This workspace has the Repo Nexus `claude` plugin enabled.

## Operating Principles
- **Claude Instructions (`CLAUDE.md`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, preserving any manual user instructions outside those markers. This serves as the primary instructions file for Anthropic Claude Code CLI and Claude Desktop.
- **Commands & Prompts (`.claude/commands/*.md` & `.claude/prompts/*.md`)**: Operational Repo Nexus prompts and active plugins' prompts/workflows are mirrored here for direct invocation via Claude Code custom slash commands (e.g. `/rnex-cross-repo-feature`).
- **Agent Skills (`.claude/skills/<name>/SKILL.md`)**: Standard prompts and active plugin skills are mirrored as individual skill bundles conforming to the agent skills specification.
- **Decoupled Cross-Plugin Discovery**: The `claude` provider discovers and mirrors prompts and skills from whatever Repo Nexus plugins are currently active.

## Configuration
Configure plugin options in `rnex.yaml` or override them per developer in `.local.rnex.yaml`:

```yaml
plugins:
  claude:
    instructions: true   # Maintain routing in CLAUDE.md (default: true)
    prompts: true        # Mirror prompts/commands to .claude/commands/ (default: true)
    skills: true         # Mirror skills to .claude/skills/ (default: true)
```

To disable locally without altering team configuration, add to `.local.rnex.yaml`:
```yaml
plugins:
  claude:
    enabled: false
```
