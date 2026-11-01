# Core Skill: workspace-status

Agentic skill protocol for auditing workspace integrity, configuration consistency, and member repository status in a Repo Nexus Virtual Meta-Repo.

---

## Capabilities & Context

Use this skill when auditing workspace health, verifying git tracking status across repositories, or inspecting active plugins and AI context routing.

## Operational Protocol

1. **Workspace Health Audit:**
   - Run `rnex status` to inspect:
     - Merged workspace configuration (pre-compiled into `.rnex/ai-instructions.md`, including configured `repos_dir`). Do NOT read `rnex.yaml` or `.local.rnex.yaml` directly.
     - Universal routing directives in `AGENTS.md`.
     - Compiled AI context at `.rnex/ai-instructions.md`.
     - Multi-root workspace mapping (`.code-workspace`).
     - Git ignores (`<repos_dir>/` ignored, local configs ignored, search un-ignore active).
     - Active plugins and member repository registry.

2. **Multi-Repository Git Status Audit:**
   - Audit working tree cleanliness across member repositories:
     ```sh
     rnex exec git status -s
     ```
   - Check upstream branch tracking:
     ```sh
     rnex exec git status -uno
     ```
   - Surface uncommitted changes, unpushed commits, or detached HEAD states to the user.

3. **Reconciliation & Remediation:**
   - If configuration drift, missing `.rnex/` harnesses, or outdated AI instructions are detected, run `rnex sync` (or `rnex sync -y` for automatic non-destructive upgrades).
   - If repositories are missing from disk, run `rnex clone`.
