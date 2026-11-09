# Agentic Skill: wiki-ingest

Deterministically ingest missing documentation sources into .rnex/wiki using the rnex CLI.

---

## Capabilities & Context

Use this skill when ingesting new reference materials, architecture documentation, transcripts, articles, or member repository documentation into the curated workspace wiki catalog shards.

## CLI Helper

Always scaffold and ingest missing documentation deterministically using the built-in CLI helper:

```sh
rnex plugin karpathy-llm ingest [<source_path>] [--file <path>] [--rewrite-links] [--strip-links] [--quiet]
```

- Ingest all configured missing sources:
  ```sh
  rnex plugin karpathy-llm ingest
  ```
- Ingest a specific missing document, directory, or glob pattern:
  ```sh
  rnex plugin karpathy-llm ingest docs/new-feature.md
  ```

## Agent Context Retrieval Protocol

AI coding agents navigate wiki context via the 3-step zero-token-bloat protocol:
1. **Root Router:** Read `.rnex/wiki/index.md` ($\le 80$ lines) to locate the target shard file (`.rnex/wiki/repo-nexus*.md` or `.rnex/wiki/repos-<member>*.md`).
2. **Shard Read:** Read the target shard directly in `.rnex/wiki/` to find the exact workspace file path and summary.
3. **In-Place Access:** Open the authoritative source file directly in place. To locate cross-references or backlinks, use native workspace search tools (`grep`, `ripgrep`).

## Ingestion Protocol

1. **Zero-Duplication In-Place Architecture:**
   - Files are indexed directly in place from authoritative workspace paths (e.g., `README.md`, `docs/**/*.md`, `architecture/*.md`, and `repos/<member>/**/*.md`).
   - Zero symbolic links (`ln -s`) and zero redundant content copies.
   - Generated wiki artifacts reside exclusively directly in `.rnex/wiki/`: `.rnex/wiki/index.md` (root router table), `.rnex/wiki/log.md` (audit log), and flat leaf shards (`.rnex/wiki/repo-nexus*.md`, `.rnex/wiki/repos-*.md`). Zero `_graph/` and zero `_index/` subdirectories.

2. **Deterministic CLI Ingestion (Missing Sources Only):**
   - Execute `rnex plugin karpathy-llm ingest [<source_path>]` under the hood.
   - **NEVER** manually create, sort, or edit `.rnex/wiki/index.md` or `.rnex/wiki/*.md` shard files.
   - The CLI identifies which candidate sources have not yet been indexed and appends only missing entries into their respective B-Tree shards, preserving all existing shard entries and custom summaries intact.
   - B-Tree shards are maintained in strict `LC_ALL=C` sort order.
   - `.rnex/wiki/index.md` is recompiled atomically to route to all existing shards.
   - Relative Markdown links in source summaries are rewritten to resolve accurately from `.rnex/wiki/` (with unresolvable links stripped to plain text to prevent broken links). Use `--strip-links` to strip all relative link formatting.
   - Detailed document lifecycle records (`created`, `updated`, `deleted`) are appended to `log.md`, capped at a rolling maximum of 1000 records pruning oldest first.

3. **In-Place Synthesis & Enrichment:**
   - Read and enrich authoritative source documents directly where they live.
   - Maintain clear Markdown cross-references and backlinks.

4. **Integrity Verification:**
   - Execute `rnex plugin karpathy-llm lint` to verify zero symlinks, zero broken links, valid workspace references, and root router line count bounds ($\le 80$ lines).
