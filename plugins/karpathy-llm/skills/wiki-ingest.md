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
- **Root Router:** Read `wiki/_index.md` ($\le 80$ lines) to route into `_index/repo-nexus*.md` or `_index/repos-<member>*.md`.
- **Prefix / Keyword Search (`_search`):** Query `nodes.tsv` via `agent_internal_search <slug>` in `plugins/karpathy-llm/lib/agent_query_helpers.sh`.
- **Ego-Subgraph Traversal (`_graph`):** Query 1-hop outbound dependencies and inbound backlinks via `agent_internal_graph <node_id>` in `plugins/karpathy-llm/lib/agent_query_helpers.sh`.

## Ingestion Protocol

1. **Zero-Duplication In-Place Architecture:**
   - Files are indexed directly in place from authoritative workspace paths (e.g., `README.md`, `docs/*.md`, `RFC/*.md`, and `repos/<member>/**/*.md`).
   - Zero symbolic links (`ln -s`) and zero redundant content copies (`wiki/concepts/` and `wiki/repos/` are completely eradicated).
   - Generated wiki artifacts reside exclusively in `wiki/_index/` (B-Tree leaf shards), `wiki/_graph/` (sorted TSV graph), `wiki/_index.md` (root router table), and `wiki/_log.md` (audit log).

2. **Step 1 — Deterministic CLI Ingestion:**
   - Run `rnex plugin karpathy-llm ingest [<file_path>]` (or batch-ingest with bare `rnex plugin karpathy-llm ingest`).
   - The CLI inspects source documents in-place, updates the two-pass property graph (`_graph/*.tsv`), synchronizes B-Tree leaf shards (`_index/*.md`), compiles `wiki/_index.md`, and records an entry in `_log.md`.

3. **Step 2 — In-Place Synthesis & Enrichment:**
   - Read and enrich authoritative source documents directly where they live.
   - Maintain explicit `[[wikilink]]` and Markdown links for bidirectional graph connectivity.

4. **Audit Verification:**
   - Run `rnex plugin karpathy-llm lint` to verify zero symlinks, `LC_ALL=C` sorting, edge symmetry, and root bounds ($\le 80$ lines).
