# Karpathy Coding Agent Behavioral Principles

> "The delicate art and science of context engineering: filling the context window with just the right information for the next step." — Andrej Karpathy

These rules define standing behavioral principles for AI coding assistants (Cursor, Claude Code, GitHub Copilot, Antigravity, Windsurf) working in this workspace.

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

In a Repo Nexus workspace, independent repositories are organized into `./repos/<name>/` as autonomous Git repositories. Coding agents must follow these rules:

1. **Repository Boundaries:**
   - Edits made to `repos/<name>/` modify the underlying member repository directly.
   - Member repositories are autonomous projects. Do not introduce cross-repository source imports or shared runtime dependencies unless an explicit monorepo architecture is configured.

2. **Member .rnex Directory Routing:**
   - Member repositories may contain an `.rnex/` directory (e.g. `repos/<name>/.rnex/`) containing repository-specific documents, instructions, rules, workflows, and scripts. Coding assistants must inspect this directory for member-specific instructions.
   - Run git operations (commits, branches, pushes) directly within the respective member repository root (`repos/<name>/`).

3. **Context Economy:**
   - Do not redundantly read entire files or directory trees when targeted symbol lookups or line ranges suffice.
   - Rely on active workspace context, indexing, and compiled documentation rather than re-scanning raw files repeatedly.
