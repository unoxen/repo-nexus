<!-- REPO-NEXUS:START -->
# Multi-Repo AI Workspace Context

This workspace operates as a **Repo Nexus Virtual Meta-Repo** uniting independent repositories.

## Routing Protocol for AI Assistants

### Mandatory Session Startup

Before answering the first task or making any task-specific tool call in a new session:

1. **Read Configuration First (Highest Priority)**: Inspect and read `.local.rnex.yaml` (if present) and `rnex.yaml` to identify workspace structure (`repos_dir`), active member repositories (`repos/`), and enabled plugins.
   - `.local.rnex.yaml` takes highest priority over `rnex.yaml`.
   - Repositories are enabled by default unless explicitly marked `enabled: false`. Disabled repositories are excluded from active tasks.
2. Inspect instructions for every enabled Repo Nexus plugin under `.rnex/plugins/<plugin-name>/`.
3. If `wiki/` is present: read `wiki/hot.md` and `wiki/index.md` to orient on architecture and domain concepts.
4. Follow links from the index to wiki pages relevant to the request.
5. Only then inspect member repositories (`repos/<name>/`) or produce an answer.

This is a hard gate, not optional orientation. Complete it once per session and retain the resulting context; do not repeatedly reload these files.

## Workspace Skills, Workflows & Rules
Tools and agents operate on skills, workflows, instructions, and rules located under `.rnex/`:
- **Skills**: Inspect `.rnex/skills/` and active plugin skills under `.rnex/plugins/<plugin-name>/skills/`.
- **Workflows**: Inspect `.rnex/workflows/` and active plugin workflows under `.rnex/plugins/<plugin-name>/workflows/`.
- **Rules & Instructions**: Inspect `.rnex/rules/`, `.rnex/instructions/`, and active plugin rules/instructions under `.rnex/plugins/<plugin-name>/`.

## Subagents
Autonomous subagents are defined under `.rnex/agents/` and active plugin agents under `.rnex/plugins/<plugin-name>/agents/` (e.g. `rnex-wiki-curator.agent.md`).
- Subagents are kept in `.rnex/` and are not mirrored to external provider folders.
- To execute a task requiring a subagent, adopt the role, operational persona, and constraints specified in the corresponding subagent definition file.

## Member Repositories (`repos/<name>/`)
Each member repository is an autonomous Git repository. For repository-specific instructions, inspect `repos/<name>/.rnex/`.

## Workspace Maintenance
When workspace configuration, routing blocks, plugin assets, or member repository structures require reconciliation or schema upgrades:
- Run `rnex fix` (or its alias `rnex update` / `rnex upgrade`, which runs the unified fix reconciliation with upfront version checking).
- Use `rnex fix -y` to non-destructively apply configuration version upgrades automatically.

## Git Operations
Commit and push changes directly within the respective member repository root (`repos/<name>/`).
<!-- REPO-NEXUS:END -->
