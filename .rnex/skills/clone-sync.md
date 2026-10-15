# Core Skill: clone-sync

Agentic skill protocol for cloning missing member repositories and reconciling workspace state in a Repo Nexus Virtual Meta-Repo.

---

## Capabilities & Context

Use this skill when onboarding to a workspace, restoring missing member repository clones, or synchronizing workspace state after configuration updates.

## Operational Protocol

1. **Inspect Workspace Configuration:**
   - Read `.local.rnex.yaml` (highest precedence) and `rnex.yaml` to identify declared member repositories under `repos:` and enabled plugins under `plugins:`.
   - Identify active member repositories where `enabled: true` (or omitted, default `true`).

2. **Clone Missing Repositories:**
   - Run `rnex clone` to clone any missing member repositories declared in the configuration into `repos/<name>`.
   - Never run manual `git clone` commands that bypass Repo Nexus path resolution.

3. **Reconcile Workspace State:**
   - Run `rnex sync` to reconcile:
     - Root `.rnex/` and member repository `repos/<name>/.rnex/` harnesses.
     - Core agentic skills in `.rnex/skills/` and active plugin skills.
     - Universal routing directives in `AGENTS.md`.
     - Git ignores (`.gitignore` and `.ignore`).
     - VS Code / Cursor `.code-workspace` folder mappings.

4. **Verify Autonomous Clones:**
   - Confirm each cloned repository in `repos/<name>/` is an independent, autonomous Git repository with its own remote tracking and branch topology.
   - Do not commit member repository code directly to the workspace root.
