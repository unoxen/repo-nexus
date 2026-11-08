# Agentic Skill: wiki-ingest

Universal agentic skill protocol for deterministically ingesting and enriching source materials in the flat Karpathy LLM Wiki.

---

## Capabilities & Context

Use this skill when ingesting new reference materials, architecture documentation, transcripts, articles, or member repository documentation into the workspace curated wiki catalog shards.

## CLI Helper

Always scaffold and rebalance flat wiki shards deterministically using the built-in CLI helper:

```sh
rnex plugin karpathy-llm ingest [<file_path>] [--file <path>] [--quiet]
```

Initialization and flat B-Tree compilation execute automatically on ingest.

## Agent Context Retrieval Protocol

AI coding agents traverse wiki context via the 3-step zero-token-bloat protocol:
1. **Root Router:** Read `wiki/index.md` ($\le 80$ lines) to locate the target shard file (`wiki/repo-nexus*.md` or `wiki/repos-<member>*.md`).
2. **Shard Read:** Read the target shard directly in `wiki/` to find the exact workspace file path and summary.
3. **In-Place Access:** Open the authoritative source file directly in place. To locate cross-references or backlinks, use native workspace search tools (`grep`, `ripgrep`).

## Ingestion Protocol

1. **Zero-Duplication In-Place Architecture:**
   - Files are indexed directly in place from authoritative workspace paths (e.g., `README.md`, `docs/**/*.md`, `architecture/*.md`, and `repos/<member>/**/*.md`).
   - Zero symbolic links (`ln -s`) and zero redundant content copies (`wiki/concepts/` and `wiki/repos/` do not exist).
   - Generated wiki artifacts reside exclusively directly in `wiki/`: `wiki/index.md` (root router table), `wiki/log.md` (audit log), and flat leaf shards (`wiki/repo-nexus*.md`, `wiki/repos-*.md`). Zero `_graph/` and zero `_index/` subdirectories.

2. **Step 1 — Deterministic CLI Ingestion:**
   - Run `rnex plugin karpathy-llm ingest [<file_path>]` (or batch-ingest with bare `rnex plugin karpathy-llm ingest`).
   - The CLI inspects source documents in-place, synchronizes flat B-Tree leaf shards (`wiki/*.md`), compiles bounded `wiki/index.md`, and records an entry in `wiki/log.md`.

3. **Step 2 — In-Place Synthesis & Enrichment:**
   - Read and enrich authoritative source documents directly where they live.
   - Maintain clear Markdown cross-references.

4. **Audit Verification:**
   - Run `rnex plugin karpathy-llm lint` to verify zero symlinks, zero legacy artifacts, and root bounds ($\le 80$ lines).
