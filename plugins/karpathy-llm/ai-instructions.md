# Karpathy LLM AI Instructions

## 1. Cardinal Behavioral Principles

- **Think Before Coding**: Explicitly state assumptions and surface architectural trade-offs before implementing non-trivial changes. In multi-repo workspaces, verify repository boundaries before acting.
- **Simplicity First**: Favor readable, minimal, non-speculative implementations over complex abstractions or framework bloat. Zero boilerplate bloat.
- **Surgical Changes**: Keep diffs tight. Modify only the lines and files required for the task. Never perform broad reformats or delete unrelated comments.
- **Goal-Driven Verification**: Define success criteria upfront. Verify changes with automated test commands and inspect your git diff before completing.

## 2. B-Tree Wiki Retrieval Protocol

When exploring codebase concepts, architectures, or member repositories, follow the strict 3-step retrieval protocol:

1. **Step 1 — B-Tree Root Index**: Read `.rnex/wiki/index.md` (bounded root router <= 80 lines) to identify the relevant shard.
2. **Step 2 — Leaf Shard Pinpointing**: Read only the specific B-Tree leaf shard identified in Step 1 (e.g., `.rnex/wiki/repo-nexus.md` or `.rnex/wiki/repos-<member>.md`).
3. **Step 3 — Authoritative Source Access**: Open only the authoritative source documents referenced in that shard.

## 3. Maintenance & Operations

- **Zero Ad-Hoc Edits**: Never edit `.rnex/wiki/` shards manually or create ad-hoc files inside the wiki directory.
- **Ingestion**: Run `rnex plugin karpathy-llm ingest` (or shorthand `rnex plugin ingest`) to index missing sources or update documentation.
- **Linting & Auto-Healing**: Run `rnex plugin karpathy-llm lint` (or shorthand `rnex plugin lint`) to validate shard bounds, cross-references, and alphabetical sorting.
- **Agent Skills**: Load skills from `.rnex/plugins/karpathy-llm/skills/` (`wiki-query.md`, `wiki-ingest.md`, `wiki-lint.md`) only when performing corresponding wiki tasks.
