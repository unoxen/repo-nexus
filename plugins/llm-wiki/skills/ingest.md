# Agentic Skill: ingest

Deterministically ingest missing documentation sources into the configured wiki directory (`plugins.llm-wiki.wiki_dir`) using the `rnex` CLI.

---

## Capabilities & Context

Use this skill when ingesting new reference materials, architecture documentation, transcripts, articles, or member repository documentation from `plugins.llm-wiki.sources` into the curated workspace wiki catalog shards.

## CLI Helper

Always scaffold and ingest missing documentation deterministically using the built-in CLI helper:

```sh
rnex plugin llm-wiki ingest [<source_path>] [--file <path>] [--rewrite-links] [--strip-links] [--quiet]
```

- Ingest all missing sources configured under `plugins.llm-wiki.sources`:
  ```sh
  rnex plugin llm-wiki ingest
  ```
- Ingest a specific missing document, directory, or glob pattern:
  ```sh
  rnex plugin llm-wiki ingest <source_path>
  ```

## Agent Context Retrieval Protocol

AI coding agents navigate wiki context via the 3-step zero-token-bloat protocol:
1. **Root Router:** Read `<wiki_dir>/<index_file>` (configured via `plugins.llm-wiki.wiki_dir` and `plugins.llm-wiki.index_file`, default: `.rnex/wiki/index.md`) to locate the target shard file (`<wiki_dir>/repo-nexus*.md` or `<wiki_dir>/repos-<member>*.md`).
2. **Shard Read:** Read the target shard directly in `<wiki_dir>/` to find the exact workspace file path and summary.
3. **In-Place Access:** Open the authoritative source file directly in place. To locate cross-references or backlinks, use native workspace search tools (`grep`, `ripgrep`).

## Ingestion Protocol

1. **Zero-Duplication In-Place Architecture:**
   - Files are indexed directly in place from authoritative workspace paths configured via `plugins.llm-wiki.sources`.
   - Zero symbolic links (`ln -s`) and zero redundant content copies.
   - Generated wiki artifacts reside exclusively inside `plugins.llm-wiki.wiki_dir` (default: `.rnex/wiki`): `<index_file>` (root router table), `<log_file>` (audit log), and flat leaf shards (`repo-nexus*.md`, `repos-*.md`).

2. **Deterministic CLI Ingestion (Missing Sources Only):**
   - Execute `rnex plugin llm-wiki ingest [<source_path>]` under the hood.
   - **NEVER** manually create, sort, or edit `<wiki_dir>/<index_file>` or `<wiki_dir>/*.md` shard files.
   - The CLI identifies which candidate sources from `plugins.llm-wiki.sources` have not yet been indexed and appends only missing entries into their respective B-Tree shards, preserving all existing shard entries and custom summaries intact.
   - B-Tree shards are maintained in strict `LC_ALL=C` sort order.
   - `<wiki_dir>/<index_file>` is recompiled atomically to route to all existing shards.
   - Relative Markdown links in source summaries are rewritten to resolve accurately from `plugins.llm-wiki.wiki_dir` (with unresolvable links stripped to plain text to prevent broken links). Use `--strip-links` (or `plugins.llm-wiki.relative_links: "strip"`) to strip all relative link formatting.
   - Detailed document lifecycle records (`created`, `updated`, `deleted`) are appended to `<wiki_dir>/<log_file>`, capped at `plugins.llm-wiki.log_max_records` (default: 1000) pruning oldest first.

3. **In-Place Synthesis & Enrichment:**
   - Read and enrich authoritative source documents directly where they live.
   - Maintain clear Markdown cross-references and backlinks.

4. **Integrity Verification:**
   - Execute `rnex plugin llm-wiki lint` to verify zero symlinks, zero broken links, valid workspace references, and root router line count bounds (`plugins.llm-wiki.btree_root_max_lines`).
