# GitHub Copilot Plugin for Repo Nexus

A built-in Repo Nexus plugin providing operational prompt mirroring for GitHub Copilot.

## Architecture

- **Universal Routing (`AGENTS.md`)**: GitHub Copilot ingests `AGENTS.md` directly at the workspace root, eliminating duplicate instruction files.
- **Prompts Mirroring**: Standardized Repo Nexus prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`) and active plugins' workflows are synchronized into `.github/prompts/*.prompt.md` with standard YAML frontmatter (`name`, `description`).
- **Internal Assets**: Skills, workflows, rules, and subagents are stored directly inside `.rnex/` (`.rnex/skills/`, `.rnex/workflows/`, `.rnex/agents/`) and within active plugin directories (`.rnex/plugins/<plugin>/`), avoiding external mirroring duplication.

## Usage

Enable the plugin across the workspace:
```bash
rnex plugin enable copilot
```

Or configure options in `rnex.yaml` or `.local.rnex.yaml`:
```yaml
plugins:
  copilot:
    prompts: true
    workflows: true
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `prompts` | boolean | `true` | Mirror operational prompts to `.github/prompts/*.prompt.md` |
| `workflows` | boolean | `true` | Mirror active plugin workflows into `.github/prompts/*.prompt.md` |
| `enabled` | boolean | `true` | Set to `false` in `.local.rnex.yaml` to override team config |
