<!-- REPO-NEXUS:START -->
# Multi-Repo AI Workspace Context

This workspace operates as a **Repo Nexus Virtual Meta-Repo** uniting independent repositories.

## Routing Protocol for AI Assistants

AI assistants working in this workspace must route context through the following configuration and instructions files:

1. **Read Configuration First (Highest Priority)**: Inspect and read `.local.rnex.yaml` (if present) and `rnex.yaml` before executing tasks to identify workspace structure (`repos_dir`), active member repositories (`repos/`), and enabled plugins.
   - `.local.rnex.yaml` takes highest priority over `rnex.yaml`.
   - Repositories are enabled by default unless explicitly marked `enabled: false`. Disabled repositories are excluded from active tasks.
2. **Member Repositories (`repos/<name>/`)**: Each member repository is an autonomous Git repository. For repository-specific instructions, inspect `repos/<name>/.rnex/`.
3. **Plugin Instructions & Rules Routing**: Detailed guidelines and workflows for enabled plugins are located under:
   `.rnex/plugins/<plugin-name>/`
4. **Git Operations**: Commit and push changes directly within the respective member repository root (`repos/<name>/`).
<!-- REPO-NEXUS:END -->
