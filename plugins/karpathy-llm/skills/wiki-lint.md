# Agentic Skill: wiki-lint

Universal agentic skill protocol for maintaining Karpathy LLM Wiki graph integrity, validating typed relations, recomputing bidirectional links, and rebuilding indexes.

---

## Capabilities & Context

Use this skill to perform health checks and maintenance on the curated wiki knowledge graph, resolve broken links, recompute bidirectional relations, and ensure B-Tree shards and TSV graph tables remain consistent.

## CLI Helper

You can also invoke the built-in deterministic lint helper directly from the terminal:

```sh
rnex plugin karpathy-llm lint [--strict] [--quiet]
```

## Maintenance Protocol

1. **Resolve Configuration & Verify Paths:**
   - Take the resolved `wiki_dir`, `repos_dir`, `sources` list, and active/disabled repositories from **Section 2 (Merged Workspace Configuration)** of the already-loaded `.rnex/ai-instructions.md`. Do NOT read `rnex.yaml` or `.local.rnex.yaml`.
   - Direct input scope resolves all files matching `sources` (read-only):
     1. All files in configured directory sources (e.g. `docs/`) with hidden directories and `node_modules` pruned.
     2. Files matching recursive or single-level glob patterns (e.g. `repos/**/README.md` or `<repos_dir>/**/README.md`), excluding disabled member repositories.
     3. `./<repos_dir>/<name>/README.md` (default: `./repos/<name>/README.md`) for every active member repository listed in `.rnex/ai-instructions.md` (read-only).
   - Intake sources and member repositories (`./<repos_dir>/`) are strictly read-only inputs during wiki operations. Never create, copy, or modify files inside intake sources; write generated output exclusively inside `wiki_dir` (`wiki/`).
   - For every page under `<wiki_dir>/`, verify that all paths in frontmatter relation fields (`related`, `extends`, `contradicts`, `sources`) resolve to existing files under `<wiki_dir>/`, active configured intake sources, or `./<repos_dir>/<name>/README.md`.
   - Fix or flag broken paths.
   - Validate every page against the typed frontmatter relation schema (paths relative to `<wiki_dir>/`, or workspace root for intake sources):
   ```yaml
   ---
   title: ""
   tags: []
   last_updated: YYYY-MM-DD
   sources: []          # intake files (<source_path> or repos/<name>/README.md) this page was derived from
   related: []          # thematically related wiki pages
   extends: []          # pages this one builds upon or specialises
   contradicts: []      # pages with conflicting information
   mentioned_in: []     # pages that link to this one (maintained by wiki-lint)
   ---
   ```

2. **Recompute `mentioned_in` Relations:**
   - Recompute `mentioned_in` for every page under `<wiki_dir>/` by scanning relation fields and inline links across all wiki pages.
   - Update frontmatter accordingly.

3. **Find Orphaned Pages:**
   - Detect pages under `<wiki_dir>/` not registered in `<wiki_dir>/_graph/nodes.tsv` or leaf shards.
   - Run `rnex plugin karpathy-llm index` to compile them into their designated shard.

4. **Detect Duplicate or Overlapping Pages:**
   - Detect duplicate or heavily overlapping concepts across pages.
   - Consolidate concepts and update relation fields across the wiki graph.

5. **Identify & Address Knowledge Gaps:**
   - Identify concepts referenced in relation fields, wikilinks, or prose that lack their own atomic page.
   - Create stub pages or flag them for future intake in `_log.md`.

6. **Rebuild B-Tree Shards & TSV Adjacency Graph:**
   - Run `rnex plugin karpathy-llm index` to synchronize `<wiki_dir>/_graph/*.tsv`, rebalance shards in `<wiki_dir>/_index/`, and recompile the bounded `<wiki_dir>/index.md` router.

7. **Verify Graph & B-Tree Invariants:**
   - Run `rnex plugin karpathy-llm lint` to verify that `nodes.tsv`, `edges_out.tsv`, and `edges_in.tsv` maintain strict `LC_ALL=C` sorting and that root `index.md` remains `<= 80` lines.

8. **Append Operation Log:**
   - Append a maintenance summary of tracked wiki pages to `<wiki_dir>/_log.md` detailing fixed links, `mentioned_in` updates, resolved orphans, and gaps.
