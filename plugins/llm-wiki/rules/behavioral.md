# Coding Agent Behavioral Principles

These rules define standing behavioral principles for AI coding assistants working in this workspace.

---

## 1. The Four Cardinal Principles

### Principle 1: Think Before Coding
* **State Assumptions Explicitly:** Before implementing any non-trivial change, state your understanding of the problem, assumptions made, and proposed solution.
* **Surface Trade-Offs:** If multiple approaches exist, outline the alternatives with their trade-offs before generating code.
* **Verify Repository Boundaries:** In multi-repo workspaces, determine which member repositories are affected. Never make silent architectural assumptions that span across repo boundaries.

### Principle 2: Simplicity First
* **Favor Readable Over Clever:** Write the simplest code that solves the immediate problem. Avoid unnecessary abstractions, speculative generics, and premature optimizations.
* **Zero Boilerplate Bloat:** Do not introduce extra wrapper layers, helper classes, or framework-heavy patterns unless explicitly requested or required by existing codebase conventions.
* **Less Code is Better Code:** If an existing utility, POSIX primitive, or library function does the job, reuse it.

### Principle 3: Surgical Changes
* **Minimal Blast Radius:** Touch *only* the lines and files required to achieve the goal.
* **Preserve Documentation & Comments:** Never delete or overwrite existing comments, documentation, or code structure unrelated to your changes.
* **Zero Unintended Reformatting:** Avoid running blanket code formatters across entire files that create massive, unreadable git diffs. Keep diffs tight, focused, and reviewable.

### Principle 4: Goal-Driven Execution & Verification
* **Define Success Criteria Upfront:** Know how you will prove that your change works before you write the first line of code.
* **Verify with Automated Checks:** Run linters, unit tests, and build commands before declaring a task complete.
* **Inspect the Diff:** Review your own git diff before committing or presenting the solution to ensure no extraneous changes were introduced.

---

## 2. Multi-Repo Context Engineering

In a Repo Nexus workspace, independent repositories are organized into `<repos_dir>/<name>/` (configured via `repos_dir`, default: `repos`) as autonomous Git repositories. Coding agents must follow these rules:

1. **Repository Boundaries & Encapsulation:**
   - Edits made to `<repos_dir>/<name>/` modify the underlying member repository directly.
   - Member repositories are autonomous projects and remain 100% clean of workspace `.rnex/` metadata. Do not introduce cross-repository source imports or shared runtime dependencies unless an explicit monorepo architecture is configured.
   - Run Git operations (commits, branches, pushes) directly within the respective member repository root (`<repos_dir>/<name>/`).

2. **Context Economy:**
   - Do not redundantly read entire files or directory trees when targeted symbol lookups or line ranges suffice.
   - Rely on active workspace context, indexing, and compiled documentation rather than re-scanning raw files repeatedly.

3. **In-Place Source Indexing & Encapsulated Metadata:**
   - Source documents configured in `plugins.llm-wiki.sources` and member repositories in `repos_dir` are indexed directly in place without symlinks (`ln -s`) or redundant copies.
   - Generated wiki metadata (`<index_file>`, `<log_file>`, `repo-nexus*.md`, `repos-*.md`) resides exclusively inside the configured `plugins.llm-wiki.wiki_dir` (default: `.rnex/wiki`).

4. **Wiki Navigation Order:**
   - **Step 1 — B-Tree Root Index**: Consult `<wiki_dir>/<index_file>` (configured via `plugins.llm-wiki.wiki_dir` and `plugins.llm-wiki.index_file`, bounded by `plugins.llm-wiki.btree_root_max_lines`) to locate the appropriate shard (`<wiki_dir>/repo-nexus*.md` or `<wiki_dir>/repos-<member>*.md`).
   - **Step 2 — Domain Shard Pinpointing**: Read only the specific B-Tree leaf shard `<wiki_dir>/<shard>.md` identified in Step 1 to locate the target source path.
   - **Step 3 — Authoritative Source Retrieval**: Open only the 1–3 authoritative workspace source document(s) referenced in the shard.
