# Core Skill: clone-sync

Agentic skill protocol for cloning missing member repositories and reconciling workspace state in a Repo Nexus Virtual Meta-Repo.

---

## Capabilities & Context

Use this skill when onboarding to a workspace, restoring missing member repository clones, or synchronizing workspace state after configuration updates.

## Operational Protocol

1. **Inspect Workspace Configuration:**
   - Use **Section 2 (Merged Workspace Configuration)** of the already-loaded `.rnex/ai-instructions.md` to identify the `repos_dir`, active and disabled member repositories, and enabled plugins. Do NOT read `rnex.yaml` or `.local.rnex.yaml`.
   - If configuration was just edited, run `rnex sync` first so `.rnex/ai-instructions.md` reflects the merged state.

2. **Clone Missing Repositories:**
   - Run `rnex clone` to clone any missing member repositories declared in the configuration into `<repos_dir>/<name>` (default: `repos/<name>`).
   - Never run manual `git clone` commands that bypass Repo Nexus path resolution.

3. **Reconcile Workspace State:**
   - Run `rnex sync` to reconcile:
     - Root `.rnex/` and member repository `<repos_dir>/<name>/.rnex/` harnesses.
     - Core agentic skills in `.rnex/skills/` and active plugin skills.
     - Universal routing directives in `AGENTS.md`.
     - Git ignores (`.gitignore` and `.ignore`).
     - VS Code / Cursor `.code-workspace` folder mappings.

4. **Verify Autonomous Clones:**
   - Confirm each cloned repository in `<repos_dir>/<name>/` is an independent, autonomous Git repository with its own remote tracking and branch topology.
   - Do not commit member repository code directly to the workspace root.
