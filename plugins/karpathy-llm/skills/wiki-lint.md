# Agentic Skill: wiki-lint

Validate existing wiki documents, shard links, and workspace references inside .rnex/wiki.

---

## Capabilities & Context

Use this skill to validate the curated flat wiki catalog, ensuring all B-Tree shards, root router links, workspace references, and sort invariants remain consistent without inspecting workspace sources or triggering re-ingestion.

## CLI Helper

Always invoke the deterministic rnex CLI command under the hood:

```sh
rnex plugin karpathy-llm lint [--strict] [--quiet]
```

## Agent Context Retrieval Protocol

AI coding agents navigate wiki structure through:
1. **Root Router:** Read `.rnex/wiki/index.md` ($\le 80$ lines) to route to the appropriate shard.
2. **Leaf Shards:** Read `.rnex/wiki/repo-nexus*.md` or `.rnex/wiki/repos-<member>*.md` directly in `.rnex/wiki/`.
3. **Authoritative Sources:** Read source documents directly in place in the workspace.

## Linting Protocol

1. **Scope & Source Independence:**
   - Inspects existing files inside `.rnex/wiki/` exclusively.
   - Does NOT inspect `rnex.yaml` `sources` and does NOT run ingestion of workspace files.
   - Enforces zero symbolic links across `.rnex/wiki/`.

2. **Auto-Healing & Invariants:**
   - **Root Router:** Validates that `.rnex/wiki/index.md` exists and is $\le 80$ lines; auto-rebuilds router to index orphan shards and prune dead shard links.
   - **Workspace References:** Validates that every referenced workspace document in shard entries exists; prunes dead references to deleted files.
   - **Relative Link Integrity:** Validates all relative Markdown links and `[[wikilinks]]`.
   - **Deterministic Sort Order:** Auto-heals and enforces strict `LC_ALL=C` sorting of catalog entries across all shards.

3. **Conditional Audit Logging:**
   - If issues are detected and repaired: appends granular audit records (`created`, `updated`, `deleted`) to `log.md` detailing the repairs, bounded to a rolling max of 1000 records.
   - If everything is already valid (clean run): does NOT touch `log.md` or any wiki files, preserving clean working tree state for Git hooks (e.g. `pre-commit`).
