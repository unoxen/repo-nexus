# Agentic Skill: ingest

Deterministically ingest missing documentation sources from {sources} into `{wikiDir}/` using the `rnex` CLI.

---

## Capabilities & Context

Use this skill when ingesting new reference materials, architecture documentation, transcripts, articles, or member repository documentation from {sources} into the curated wiki catalog shards inside `{wikiDir}/`.

## CLI Helper

Always scaffold and ingest missing documentation deterministically using the built-in CLI helper:

```sh
rnex plugin llm-wiki ingest [path/to/source] [--file path/to/doc.md] [--rewrite-links] [--strip-links] [--quiet]
```

- Ingest all missing sources from {sources}:
  ```sh
  rnex plugin llm-wiki ingest
  ```
- Ingest a specific missing document, directory, or glob pattern:
  ```sh
  rnex plugin llm-wiki ingest path/to/source.md
  ```

## Agent Context Retrieval Protocol

AI coding agents navigate wiki context via the 3-step zero-token-bloat protocol:
1. **Root Router:** Read `{wikiDir}/{indexFile}` to locate the target shard file (`{wikiDir}/repo-nexus*.md` or `{wikiDir}/repos-*.md`).
2. **Shard Read:** Read the target shard directly in `{wikiDir}/` to find the exact workspace file path and summary.
3. **In-Place Access:** Open the authoritative source file directly in place. To locate cross-references or backlinks, use native workspace search tools (`grep`, `ripgrep`).

## Ingestion Protocol

1. **Zero-Duplication In-Place Architecture:**
   - Files are indexed directly in place from authoritative workspace paths in {sources} and member repositories under `{reposDir}/`.
   - Zero symbolic links (`ln -s`) and zero redundant content copies.
   - Generated wiki artifacts reside exclusively inside `{wikiDir}/`: `{wikiDir}/{indexFile}` (root router table), `{wikiDir}/{logFile}` (audit log), and flat leaf shards (`{wikiDir}/repo-nexus*.md`, `{wikiDir}/repos-*.md`).

2. **Deterministic CLI Ingestion (Missing Sources Only):**
   - Execute `rnex plugin llm-wiki ingest [path/to/source]` under the hood.
   - **NEVER** manually create, sort, or edit `{wikiDir}/{indexFile}` or `{wikiDir}/*.md` shard files.
   - The CLI identifies which candidate sources from {sources} have not yet been indexed and appends only missing entries into their respective B-Tree shards, preserving all existing shard entries and custom summaries intact.
   - B-Tree shards are maintained in strict `LC_ALL=C` sort order and split automatically above {btreeShardMaxEntries} entries.
   - `{wikiDir}/{indexFile}` is recompiled atomically (bounded to {btreeRootMaxLines} lines) to route to all existing shards.
   - Relative Markdown links in source summaries use the active `{relativeLinks}` mode from `{wikiDir}/` (pass `--strip-links` or `--rewrite-links` to override for a single run).
   - Detailed document lifecycle records (`created`, `updated`, `deleted`) are appended to `{wikiDir}/{logFile}`, capped at {logMaxRecords} records pruning oldest first.

3. **In-Place Synthesis & Enrichment:**
   - Read and enrich authoritative source documents directly where they live.
   - Maintain clear Markdown cross-references and backlinks.

4. **Integrity Verification:**
   - Execute `rnex plugin llm-wiki lint` to verify zero symlinks, zero broken links, valid workspace references, and the {btreeRootMaxLines}-line limit on `{wikiDir}/{indexFile}`.
