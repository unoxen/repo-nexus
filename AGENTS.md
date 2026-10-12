<!-- REPO-NEXUS:START -->
# Multi-Repo AI Workspace Context

This workspace operates as a **Repo Nexus Virtual Meta-Repo** uniting independent repositories.

## Routing Protocol for AI Assistants

> [!IMPORTANT]
> **MANDATORY GATE: DO NOT INSPECT `repos/` BEFORE CONSULTING THE WIKI (`wiki/`).**
> Never run broad codebase searches, recursive directory listings, or grep commands across `repos/`.
> The Karpathy LLM Wiki (`wiki/`) is the authoritative architectural index. Always query `wiki/hot.md` and `wiki/index.md` first to identify exact files and cross-repo contracts.

### Mandatory Session Startup

Before answering the first task or making any task-specific tool call in a new session, execute these steps in strict sequence:

1. **Read Configuration First (Highest Priority)**: Inspect and read `.local.rnex.yaml` (if present) and `rnex.yaml` to identify workspace structure (`repos_dir`), active member repositories (`repos/`), and enabled plugins.
   - `.local.rnex.yaml` takes highest priority over `rnex.yaml`.
   - Repositories are enabled by default unless explicitly marked `enabled: false`. Disabled repositories are excluded from active tasks.
2. **Wiki Orientation (MANDATORY GATE BEFORE REPO ACCESS)**:
   - If `wiki/` is present: you MUST read `wiki/hot.md` and `wiki/index.md` to orient on architecture, cross-repo contracts, and domain concepts.
   - Follow links from the index to wiki pages relevant to the request.
   - **STRICT PROHIBITION**: Any tool call inspecting, grepping, or listing files in `repos/` before reading the wiki is a protocol violation.
3. **Plugin Instructions**: Inspect instructions for every enabled Repo Nexus plugin under `.rnex/plugins/<plugin-name>/`.
4. **Targeted Member Repository Access Only**:
   - Only after consulting the wiki, navigate directly to the specific files in `repos/<name>/` identified by the wiki.
   - Never perform blind repository-wide scans or unbounded searches across `repos/`.

This is a hard gate, not optional orientation. Complete it once per session and retain the resulting context; do not repeatedly reload these files.

### Forbidden Startup Actions
- ❌ **DO NOT** grep or search `repos/` as your first step.
- ❌ **DO NOT** perform recursive tree exploration of member repositories.
- ❌ **DO NOT** guess architecture or cross-repo contracts without checking `wiki/`.
- ❌ **DO NOT** bypass `wiki/hot.md` and `wiki/index.md`.

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
Each member repository is an autonomous Git repository. For repository-specific instructions, inspect `repos/<name>/.rnex/`. Inspect only files pinpointed through wiki routing.

## Workspace Maintenance
When workspace configuration, routing blocks, plugin assets, or member repository structures require reconciliation or schema upgrades:
- Run `rnex fix` (or its alias `rnex update` / `rnex upgrade`, which runs the unified fix reconciliation with upfront version checking).
- Use `rnex fix -y` to non-destructively apply configuration version upgrades automatically.

## Git Operations
Commit and push changes directly within the respective member repository root (`repos/<name>/`).
<!-- REPO-NEXUS:END -->
