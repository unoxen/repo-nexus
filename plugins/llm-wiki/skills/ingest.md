# Agentic Skill: ingest

Deterministically ingest missing documentation sources from {sources} into `{wiki_dir}/` using the `rnex` CLI.

---

## Capabilities & Context

Use this skill when ingesting new reference materials, architecture documentation, transcripts, articles, or member repository documentation from {sources} into the curated wiki catalog shards inside `{wiki_dir}/`.

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
1. **Root Router:** Read `{wiki_dir}/{index_file}` to locate the target shard file (`{wiki_dir}/repo-nexus*.md` or `{wiki_dir}/repos-*.md`).
2. **Shard Read:** Read the target shard directly in `{wiki_dir}/` to find the exact workspace file path and summary.
3. **In-Place Access:** Open the authoritative source file directly in place. To locate cross-references or backlinks, use native workspace search tools (`grep`, `ripgrep`).

## Ingestion Protocol

1. **Zero-Duplication In-Place Architecture:**
   - Files are indexed directly in place from authoritative workspace paths in {sources} and member repositories under `{repos_dir}/`.
   - Zero symbolic links (`ln -s`) and zero redundant content copies.
   - Generated wiki artifacts reside exclusively inside `{wiki_dir}/`: `{wiki_dir}/{index_file}` (root router table), `{wiki_dir}/{log_file}` (audit log), and flat leaf shards (`{wiki_dir}/repo-nexus*.md`, `{wiki_dir}/repos-*.md`).

2. **Deterministic CLI Ingestion (Missing Sources Only):**
   - Execute `rnex plugin llm-wiki ingest [path/to/source]` under the hood.
   - **NEVER** manually create, sort, or edit `{wiki_dir}/{index_file}` or `{wiki_dir}/*.md` shard files.
   - The CLI identifies which candidate sources from {sources} have not yet been indexed and appends only missing entries into their respective B-Tree shards, preserving all existing shard entries and custom summaries intact.
   - B-Tree shards are maintained in strict `LC_ALL=C` sort order and split automatically above {btree_shard_max_entries} entries.
   - `{wiki_dir}/{index_file}` is recompiled atomically (bounded to {btree_root_max_lines} lines) to route to all existing shards.
   - Relative Markdown links in source summaries use the active `{relative_links}` mode from `{wiki_dir}/` (pass `--strip-links` or `--rewrite-links` to override for a single run).
   - Detailed document lifecycle records (`created`, `updated`, `deleted`) are appended to `{wiki_dir}/{log_file}`, capped at {log_max_records} records pruning oldest first.

3. **In-Place Synthesis & Enrichment:**
   - Read and enrich authoritative source documents directly where they live.
   - Maintain clear Markdown cross-references and backlinks.

4. **Integrity Verification:**
   - Execute `rnex plugin llm-wiki lint` to verify zero symlinks, zero broken links, valid workspace references, and the {btree_root_max_lines}-line limit on `{wiki_dir}/{index_file}`.
