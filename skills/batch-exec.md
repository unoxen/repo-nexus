# Core Skill: batch-exec

Agentic skill protocol for executing batch commands across member repositories in a Repo Nexus Virtual Meta-Repo.

---

## Capabilities & Context

Use this skill when inspecting, testing, building, or modifying multiple member repositories across the workspace.

## Operational Protocol

1. **Verify Active Repositories:**
   - Use **Section 2 (Merged Workspace Configuration)** of `.rnex/ai-instructions.md` (or run `rnex list`) to verify which member repositories are active vs disabled. Do NOT read `rnex.yaml` or `.local.rnex.yaml`.
   - Disabled repositories are intentionally skipped during batch execution.

2. **Execute Staged Batch Commands:**
   - Execute commands across all active member repositories:
     ```sh
     rnex exec <command>
     ```
   - For example, checking git status across all member repositories:
     ```sh
     rnex exec git status -s
     ```
   - Running test suites across member repositories:
     ```sh
     rnex exec npm test
     ```

3. **Handle Repository Boundaries & Dependency Order:**
   - If changes span multiple repositories, determine dependency relationships (e.g., shared packages/libraries first, consumer services second).
   - Use targeted directory execution (`cd <repos_dir>/<name> && ...`, defaulting to `cd repos/<name> && ...`) when only a subset of repositories is involved.

4. **Independent Commits & Git Hygiene:**
   - Commit changes independently within each member repository root:
     ```sh
     cd <repos_dir>/<name> && git add -A && git commit -m "feat: <message>"
     ```
   - Never stage or commit member repository files directly from the workspace root.
