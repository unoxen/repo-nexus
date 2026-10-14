<!-- REPO-NEXUS:START -->
# Multi-Repo AI Workspace Context

This workspace operates as a **Repo Nexus Virtual Meta-Repo** uniting independent repositories.

## Routing Protocol for AI Assistants

### Mandatory Session Startup
Execute in sequence before task execution:
1. **Read Configuration First (Highest Priority)**: Read `.local.rnex.yaml` (if present) and `rnex.yaml` to identify active member repositories (`repos/`) and enabled plugins.
2. **Plugin & Skill Routing**: Inspect active plugin instructions under `.rnex/plugins/<plugin-name>/`, and tools under `.rnex/skills/` and `.rnex/workflows/` when relevant.
3. **Targeted Member Repository Access Only**: Navigate directly to specific files in `repos/<name>/` relevant to the user request. Avoid blind repository-wide scans or unbounded searches across `repos/`.

## Subagents
Autonomous subagents are defined under `.rnex/agents/` and active plugin agents under `.rnex/plugins/<plugin-name>/agents/`.

## Member Repositories (`repos/<name>/`)
Each member repository is an autonomous Git repository. For repository-specific instructions, inspect `repos/<name>/.rnex/`. Inspect only targeted files required for the task.

## Workspace Maintenance
When workspace configuration, routing blocks, plugin assets, or member repository structures require reconciliation or schema upgrades:
- Run `rnex sync --fix` (or `rnex sync` to check for inconsistencies).
- Use `rnex sync --fix -y` to non-destructively apply configuration version upgrades automatically.

## Git Operations
Commit and push changes directly within the respective member repository root (`repos/<name>/`).
<!-- REPO-NEXUS:END -->
