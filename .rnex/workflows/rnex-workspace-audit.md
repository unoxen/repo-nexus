# Repo Nexus Workspace Audit Workflow

Use this workflow to audit workspace configuration integrity, member repository git statuses, and active plugin states.

---

## 1. Configuration & Health Audit
1. Run `rnex status` to inspect:
   - Configuration files (`rnex.yaml` and `.local.rnex.yaml`).
   - Main AI instructions file (`AGENTS.md`) and routing markers.
   - VS Code / Cursor `.code-workspace` synchronization.
   - Git ignore status for `repos/`, `.rnex/`, and local overrides.
   - Active plugins and member repository registry.

## 2. Multi-Repository Git Status Audit
1. Check working tree cleanliness across all active member repositories:
   ```sh
   rnex exec git status -s
   ```
2. Check branch tracking and unpushed/unpulled commits:
   ```sh
   rnex exec git status -uno
   ```
3. Report any detached HEADs, uncommitted modifications, or untracked changes.

## 3. Reconciliation & Remediation
1. If any configuration issues, missing directories, or unlinked plugin assets are detected, run:
   ```sh
   rnex fix
   ```
2. If member repositories declared in `rnex.yaml` are missing on disk, run:
   ```sh
   rnex clone
   ```
