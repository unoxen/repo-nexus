# Agentic Skill: wiki-ingest

Universal agentic skill protocol for deterministically ingesting and enriching source materials in the Karpathy LLM Wiki.

---

## Capabilities & Context

Use this skill when ingesting new reference materials, architecture documentation, transcripts, articles, or member repository READMEs into the workspace curated wiki knowledge graph.

## CLI Helper

Always scaffold wiki pages deterministically using the built-in CLI helper first before enriching in-place:

```sh
rnex plugin karpathy-llm ingest [<file_path>] [--file <path>] [--repo <name>] [--quiet]
```

Initialization and B-Tree / Graph synchronization execute automatically on ingest.

## Agent Context Traversal

AI coding agents traverse wiki context via internal helpers:
- **Root Router:** Read `wiki/_index.md` ($\le 80$ lines) to route into `_index/concepts*.md` or `_index/repos-*.md`.
- **Prefix / Keyword Search (`_search`):** Query `nodes.tsv` via `agent_internal_search <slug>` in `plugins/karpathy-llm/lib/agent_query_helpers.sh`.
- **Ego-Subgraph Traversal (`_graph`):** Query 1-hop outbound dependencies and inbound backlinks via `agent_internal_graph <node_id>` in `plugins/karpathy-llm/lib/agent_query_helpers.sh`.

## Ingestion Protocol

1. **Resolve Configuration & Direct Source Paths:**
   - Direct input scope resolves files matching configured sources and member repositories (read-only):
     1. **Nexus Concepts & Architecture:** General cross-cutting architecture and design concepts map to `wiki/concepts/<slug>.md`.
     2. **Repository-Scoped Documentation:** Scoped repository documentation maps to `wiki/repos/<repo_scope>/<slug>.md` (e.g., `wiki/repos/nexus/` or `wiki/repos/<member_repo>/`).
   - Intake sources and member repositories (`./repos/`) are strictly read-only inputs during wiki operations. Generated output resides exclusively inside `wiki/` (`wiki/concepts/` and `wiki/repos/<repo_scope>/`).

2. **Step 1 — Deterministic CLI Ingestion:**
   - Run `rnex plugin karpathy-llm ingest <file_path>` (or batch-ingest with bare `rnex plugin karpathy-llm ingest`).
   - The CLI automatically scaffolds the target page, rebuilds the two-pass property graph (`_graph/*.tsv`), updates B-Tree leaf shards (`_index/*.md`), compiles `wiki/_index.md`, and records an entry in `_log.md`.

3. **Step 2 — In-Place Synthesis & Enrichment:**
   - Read the source document(s) in-place.
   - Synthesize architectural concepts, contracts, patterns, and trade-offs directly into the curated page.
   - Ensure explicit `[[wikilink]]` and relative Markdown links are maintained for bidirectional graph connectivity.

4. **Audit Verification:**
   - Run `rnex plugin karpathy-llm lint` to verify that link paths, B-Tree root bounds, and TSV graph sort and symmetry invariants are satisfied.
