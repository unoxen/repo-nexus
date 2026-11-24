# Core Skill: clone-sync

Agentic skill protocol for cloning missing member repositories and reconciling workspace state in a Repo Nexus Virtual Meta-Repo.

---

## Capabilities & Context

Use this skill when onboarding to a workspace, restoring missing member repository clones, or synchronizing workspace state after configuration updates.

## Operational Protocol

1. **Inspect Workspace Configuration:**
   - Read `.rnex/repos-instructions.md` and `.rnex/ai-instructions.md` (or run `rnex status`) to identify active member repositories, repository paths, and enabled plugins. Do NOT read `rnex.yaml` or `.local.rnex.yaml` directly.
   - If configuration was just edited, run `rnex sync` first so `.rnex/ai-instructions.md` and `.rnex/repos-instructions.md` reflect the merged state.

2. **Clone Missing Repositories:**
   - Run `rnex clone` to clone any missing member repositories declared in the configuration into `<reposDir>/<name>` (default: `repos/<name>`).
   - Never run manual `git clone` commands that bypass Repo Nexus path resolution.

3. **Reconcile Workspace State:**
   - Run `rnex sync` to reconcile:
     - Root `.rnex/` harness, compiled AI instructions, and `.rnex/repos-instructions.md` (member repositories remain 100% clean without internal `.rnex/` folders).
     - Core agentic skills in `.rnex/skills/` and active plugin skills.
     - Universal routing directives in `AGENTS.md` (or active provider instruction files).
     - Git ignores (`.gitignore` and `.ignore`).
     - VS Code / Cursor `.code-workspace` folder mappings.

4. **Verify Autonomous Clones:**
   - Confirm each cloned repository in `<reposDir>/<name>/` is an independent, autonomous Git repository with its own remote tracking and branch topology.
   - Do not commit member repository code directly to the workspace root.
