# Agentic Skill: wiki-lint

Universal agentic skill protocol for maintaining Karpathy LLM Wiki graph integrity, auto-healing directory structures, verifying edge symmetry, and rebalancing B-Tree index shards.

---

## Capabilities & Context

Use this skill to perform health checks and maintenance on the curated wiki knowledge graph, auto-heal legacy directory layouts, verify edge table symmetry, and ensure B-Tree shards and TSV graph tables remain consistent.

## CLI Helper

Invoke the built-in deterministic lint helper directly from the terminal:

```sh
rnex plugin karpathy-llm lint [--strict] [--quiet]
```

Initialization, legacy migration, graph compilation, and B-Tree shard rebalancing execute automatically during linting.

## Agent Context Traversal

AI coding agents navigate wiki structure through:
- **Root Router:** `wiki/_index.md` ($\le 80$ lines).
- **Domain Shards:** `wiki/_index/concepts*.md` and `wiki/_index/repos-*.md`.
- **Property Graph Lookups:** `agent_internal_search <slug>` (`_search`) and `agent_internal_graph <node_id>` (`_graph`) in `plugins/karpathy-llm/lib/agent_query_helpers.sh`.

## Maintenance Protocol

1. **Auto-Healing & Legacy Migration:**
   - Moves legacy `wiki/overview/*.md` $\rightarrow$ `wiki/concepts/`.
   - Moves legacy `wiki/entities/*.md` $\rightarrow$ `wiki/repos/nexus/`.
   - Moves legacy `wiki/sources/<scope>/*` $\rightarrow$ `wiki/repos/<scope>/`.
   - Purges deprecated `wiki/hot.md` and legacy `wiki/index.md`.

2. **Graph Compilation & B-Tree Rebalancing:**
   - Rebuilds `wiki/_graph/{nodes,edges_out,edges_in}.tsv` via two-pass scanning.
   - Rebalances leaf shards `wiki/_index/concepts*.md`, `wiki/_index/repos-nexus*.md`, and `wiki/_index/repos-<member_repo>*.md` ($\ge 1$ shard per repo).
   - Compiles bounded root router at `wiki/_index.md` ($\le 80$ lines).

3. **Invariants Verification:**
   - Verifies strict `LC_ALL=C` sorting across all three TSV graph tables.
   - Verifies forward and reverse edge symmetry (`edges_out.tsv` count == `edges_in.tsv` count).
   - Validates that `wiki/_index.md` remains $\le 80$ lines.
   - When `--strict` is enabled, flags and rejects any dangling internal wikilink targets.

4. **Operational Logging:**
   - Appends a sanitized ISO-8601 UTC event entry to `wiki/_log.md`.
