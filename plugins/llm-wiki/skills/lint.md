# Agentic Skill: lint

Validate existing wiki documents, shard links, and workspace references inside `{wikiDir}/`.

---

## Capabilities & Context

Use this skill to validate the curated flat wiki catalog inside `{wikiDir}/`, ensuring all B-Tree shards, `{wikiDir}/{indexFile}` links, workspace references, and sort invariants remain consistent without scanning intake sources or triggering re-ingestion.

## CLI Helper

Always invoke the deterministic `rnex` CLI command under the hood:

```sh
rnex plugin llm-wiki lint [--strict] [--quiet]
```

## Agent Context Retrieval Protocol

AI coding agents navigate wiki structure through:
1. **Root Router:** Read `{wikiDir}/{indexFile}` to route to the appropriate shard.
2. **Leaf Shards:** Read `{wikiDir}/repo-nexus*.md` or `{wikiDir}/repos-*.md` directly in `{wikiDir}/`.
3. **Authoritative Sources:** Read source documents directly in place in the workspace.

## Linting Protocol

1. **Scope & Source Independence:**
   - Inspects existing files inside `{wikiDir}/` exclusively.
   - Does NOT scan workspace intake sources and does NOT run ingestion of workspace files.
   - Enforces zero symbolic links across `{wikiDir}/`.

2. **Auto-Healing & Invariants:**
   - **Root Router:** Validates that `{wikiDir}/{indexFile}` exists and is within {btreeRootMaxLines} lines; auto-rebuilds router to index orphan shards and prune dead shard links.
   - **Workspace References:** Validates that every referenced workspace document in shard entries exists; prunes dead references to deleted files.
   - **Relative Link Integrity:** Validates all relative Markdown links and `[[wikilinks]]`.
   - **Deterministic Sort Order & Capacity:** Auto-heals and enforces strict `LC_ALL=C` sorting of catalog entries and splits shards exceeding {btreeShardMaxEntries} entries.

3. **Conditional Audit Logging:**
   - If issues are detected and repaired: appends granular audit records (`created`, `updated`, `deleted`) to `{wikiDir}/{logFile}` detailing the repairs, bounded by {logMaxRecords} records.
   - If everything is already valid (clean run): does NOT touch `{wikiDir}/{logFile}` or any wiki files, preserving clean working tree state for Git hooks (e.g. `pre-commit`).
