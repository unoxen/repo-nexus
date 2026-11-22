# Agentic Skill: ingest

Deterministically ingest missing documentation sources from {sources} into `{wikiDir}/` using the `rnex` CLI.

---

## Capabilities & Context

Use this skill when ingesting new reference materials, architecture documentation, transcripts, articles, or member repository documentation from {sources} into the curated wiki catalog shards inside `{wikiDir}/`.

## CLI Helper

Always scaffold and ingest missing documentation deterministically using the built-in CLI helper:

```sh
rnex plugin llm-wiki ingest [path/to/source] [--force|-f] [--rewrite-links] [--strip-links] [--quiet|-q]
```

- Ingest all missing sources from {sources}:
  ```sh
  rnex plugin llm-wiki ingest
  ```
- Ingest a specific missing document, directory, or glob pattern:
  ```sh
  rnex plugin llm-wiki ingest path/to/source.md
  ```
- Force-refresh existing wiki entries for a modified document, directory, or all {sources}:
  ```sh
  rnex plugin llm-wiki ingest --force path/to/source.md
  rnex plugin llm-wiki ingest -f
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

2. **Deterministic CLI Ingestion (Missing Sources by Default, `--force` for Updates):**
   - Execute `rnex plugin llm-wiki ingest [path/to/source]` under the hood. Pass `--force` (`-f`) to re-index already-cataloged documents after header or summary edits.
   - **NEVER** manually create, sort, or edit `{wikiDir}/{indexFile}` or `{wikiDir}/*.md` shard files.
   - By default, the CLI identifies which candidate sources from {sources} have not yet been indexed and appends only missing entries into their respective B-Tree shards. When `--force` (`-f`) is passed, existing entries matching the target path (or {sources}) are rebuilt from their authoritative source files and re-routed if their title changed.
   - Each catalog entry extracts Markdown headers ordered by level (`#`, then `##`, then `###` and lower) or `#` comments for non-Markdown files up to {recordSummaryMaxLength} characters (emitting only the title link when no readable headers or comments exist).
   - B-Tree shards are maintained in strict `LC_ALL=C` sort order and split automatically above {btreeShardMaxEntries} entries.
   - `{wikiDir}/{indexFile}` is recompiled atomically (bounded to {btreeRootMaxLines} lines) to route to all existing shards.
   - Relative Markdown links in source summaries use the active `{relativeLinks}` mode from `{wikiDir}/` (pass `--strip-links` or `--rewrite-links` to override for a single run).
   - Detailed document lifecycle records (`created`, `updated`, `deleted`) are appended to `{wikiDir}/{logFile}`, capped at {logMaxRecords} records pruning oldest first.

3. **In-Place Synthesis & Enrichment:**
   - Read and enrich authoritative source documents directly where they live.
   - Maintain clear Markdown cross-references and backlinks.

4. **Integrity Verification:**
   - Execute `rnex plugin llm-wiki lint` to verify zero symlinks, zero broken links, valid workspace references, and the {btreeRootMaxLines}-line limit on `{wikiDir}/{indexFile}`.
