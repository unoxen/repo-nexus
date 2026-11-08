# Agentic Skill: wiki-lint

Universal agentic skill protocol for maintaining flat Karpathy LLM Wiki structure, auto-healing legacy artifacts, and rebalancing B-Tree index shards.

---

## Capabilities & Context

Use this skill to perform health checks and maintenance on the curated flat wiki catalog, auto-heal legacy directory layouts, and ensure B-Tree shards and root router remain consistent.

## CLI Helper

Invoke the built-in deterministic lint helper directly from the terminal:

```sh
rnex plugin karpathy-llm lint [--strict] [--quiet]
```

Auto-healing legacy purge, shard splitting, and B-Tree root rebalancing execute automatically during linting.

## Agent Context Retrieval Protocol

AI coding agents navigate wiki structure through:
1. **Root Router:** Read `wiki/index.md` ($\le 80$ lines) to route to the appropriate shard.
2. **Leaf Shards:** Read `wiki/repo-nexus*.md` or `wiki/repos-<member>*.md` directly in `wiki/`.
3. **Authoritative Sources:** Read source documents directly in place in the workspace.

## Maintenance Protocol

1. **Auto-Healing & Legacy Purge:**
   - Purges obsolete directories `wiki/_graph/`, `wiki/_index/`, `wiki/concepts/`, `wiki/repos/`, `wiki/overview/`, `wiki/entities/`, and `wiki/sources/`.
   - Purges deprecated `wiki/_index.md`, `wiki/_log.md`, `wiki/hot.md`. Migrates historical audit entries from `_log.md` to `log.md`.
   - Enforces zero symbolic links (`[ -f ] && [ ! -L ]`) across the entire `wiki/` directory.

2. **B-Tree Shard Rebalancing:**
   - Scans authoritative documents in place and rebuilds leaf shards `wiki/repo-nexus*.md` and `wiki/repos-<member_repo>*.md` ($\ge 1$ shard per enabled member repo).
   - Automatically splits shards exceeding `btree_shard_max_entries` into lexicographical ranges (`a-m` and `n-z`).
   - Compiles bounded root router at `wiki/index.md` ($\le 80$ lines).

3. **Invariants Verification:**
   - Verifies zero symbolic links.
   - Verifies zero `_graph/` and zero `_index/` directories.
   - Validates that `wiki/index.md` remains $\le 80$ lines.

4. **Operational Logging:**
   - Appends a sanitized ISO-8601 UTC event entry to `wiki/log.md`.
