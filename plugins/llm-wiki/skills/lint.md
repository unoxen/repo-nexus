# Agentic Skill: lint

Validate existing wiki documents, shard links, and workspace references inside the configured wiki directory (`plugins.llm-wiki.wiki_dir`).

---

## Capabilities & Context

Use this skill to validate the curated flat wiki catalog, ensuring all B-Tree shards, root router links, workspace references, and sort invariants remain consistent without inspecting `plugins.llm-wiki.sources` or triggering re-ingestion.

## CLI Helper

Always invoke the deterministic `rnex` CLI command under the hood:

```sh
rnex plugin llm-wiki lint [--strict] [--quiet]
```

## Agent Context Retrieval Protocol

AI coding agents navigate wiki structure through:
1. **Root Router:** Read `<wiki_dir>/<index_file>` (configured via `plugins.llm-wiki.wiki_dir` and `plugins.llm-wiki.index_file`, default: `.rnex/wiki/index.md`) to route to the appropriate shard.
2. **Leaf Shards:** Read `<wiki_dir>/repo-nexus*.md` or `<wiki_dir>/repos-<member>*.md` directly in `<wiki_dir>/`.
3. **Authoritative Sources:** Read source documents directly in place in the workspace.

## Linting Protocol

1. **Scope & Source Independence:**
   - Inspects existing files inside `plugins.llm-wiki.wiki_dir` (default: `.rnex/wiki`) exclusively.
   - Does NOT inspect `plugins.llm-wiki.sources` and does NOT run ingestion of workspace files.
   - Enforces zero symbolic links across `<wiki_dir>/`.

2. **Auto-Healing & Invariants:**
   - **Root Router:** Validates that `<wiki_dir>/<index_file>` exists and is within `plugins.llm-wiki.btree_root_max_lines` (default: 80 lines); auto-rebuilds router to index orphan shards and prune dead shard links.
   - **Workspace References:** Validates that every referenced workspace document in shard entries exists; prunes dead references to deleted files.
   - **Relative Link Integrity:** Validates all relative Markdown links and `[[wikilinks]]`.
   - **Deterministic Sort Order & Capacity:** Auto-heals and enforces strict `LC_ALL=C` sorting of catalog entries and splits shards exceeding `plugins.llm-wiki.btree_shard_max_entries` (default: 100).

3. **Conditional Audit Logging:**
   - If issues are detected and repaired: appends granular audit records (`created`, `updated`, `deleted`) to `<wiki_dir>/<log_file>` detailing the repairs, bounded by `plugins.llm-wiki.log_max_records` (default: 1000).
   - If everything is already valid (clean run): does NOT touch `<log_file>` or any wiki files, preserving clean working tree state for Git hooks (e.g. `pre-commit`).
