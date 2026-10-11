# Cross-Repository Feature Implementation Workflow

Use this workflow to guide the planning, execution, and verification of features spanning multiple member repositories in a Repo Nexus workspace.

---

## 1. Discovery & Scope Analysis
1. Inspect `.local.rnex.yaml` (if present) and `rnex.yaml` to identify active member repositories in `repos/<name>/`.
2. Inspect `repos/<name>/.rnex/` in each target repository for repo-specific architectural rules or constraints.
3. If `wiki/` is present, read `wiki/hot.md` and `wiki/index.md` to orient on existing domain contracts and data models.
4. Clearly define the interface contract or boundary change between repositories (e.g. API payload, shared type definitions, database schema).

## 2. Staged Implementation Plan
1. Order repository changes by dependency hierarchy (e.g. backend / shared models first, frontend / consumers second).
2. For each member repository:
   - Identify specific files to modify.
   - Check member repo test suite requirements.

## 3. Execution
1. Perform file modifications directly in the target `repos/<name>/` directory trees.
2. Maintain documentation and type integrity across boundary contracts.
3. Verify changes locally within each modified repository using `rnex exec` or targeted test runners:
   ```sh
   rnex exec npm test
   # or targeted:
   cd repos/<name> && npm test
   ```

## 4. Git & Commit Hygiene
1. Member repositories are autonomous Git repositories:
   - Commit changes independently within each member repository root:
     ```sh
     cd repos/<name> && git add -A && git commit -m "feat: <description>"
     ```
   - Never commit member repository source code directly to the Repo Nexus workspace root.
