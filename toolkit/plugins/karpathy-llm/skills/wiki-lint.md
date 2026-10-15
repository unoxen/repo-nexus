# Agentic Skill: wiki-lint

Universal agentic skill protocol for maintaining Karpathy LLM Wiki graph integrity, validating typed relations, recomputing bidirectional links, and rebuilding indexes.

---

## Capabilities & Context

Use this skill to perform health checks and maintenance on the curated wiki knowledge graph, resolve broken links, recompute bidirectional relations, and preserve the ~500-word hot cache boundary.

## Maintenance Protocol

1. **Resolve Configuration & Verify Paths:**
   - Read `rnex.yaml` (and `.local.rnex.yaml` if present) to resolve `wiki_dir` (default: `.rnex/wiki`) and `raw_dir` (default: `./docs`) under `plugins.karpathy-llm`.
   - Direct input scope explicitly reads:
     1. All files in `raw_dir` (`./docs`) (read-only).
     2. `./repos/<name>/README.md` for every enabled member repository in `rnex.yaml` / `.local.rnex.yaml` (read-only).
   - `raw_dir` (`./docs`) and `./repos/` are strictly read-only inputs during wiki operations. Never create, copy, or modify files inside `./docs`; write generated output exclusively inside `wiki_dir` (`.rnex/wiki/`).
   - For every page under `<wiki_dir>/`, verify that all paths in frontmatter relation fields (`related`, `extends`, `contradicts`, `sources`) resolve to existing files under `<wiki_dir>/`, `<raw_dir>/`, or `./repos/<name>/README.md`.
   - Fix or flag broken paths.

2. **Recompute `mentioned_in` Relations:**
   - Recompute `mentioned_in` for every page under `<wiki_dir>/` by scanning relation fields and inline links across all wiki pages.
   - Update frontmatter accordingly.

3. **Find Orphaned Pages:**
   - Detect pages under `<wiki_dir>/` not reachable from `<wiki_dir>/index.md` or any `mentioned_in` field.
   - Add them to `<wiki_dir>/index.md` under their appropriate category.

4. **Detect Duplicate or Overlapping Pages:**
   - Detect duplicate or heavily overlapping concepts across pages.
   - Consolidate concepts and update relation fields across the wiki graph.

5. **Identify & Address Knowledge Gaps:**
   - Identify concepts referenced in relation fields or prose that lack their own atomic page.
   - Create stub pages or flag them for future intake in `_log.md`.

6. **Rebuild Navigation Index (Annotated Links):**
   - Rebuild `<wiki_dir>/index.md` to reflect current pages and categories.
   - Ensure every page entry maintains a concise 1-line descriptive annotation.

7. **Refresh Hot Cache (Bounded ~500-Word Ceiling):**
   - Refresh `<wiki_dir>/hot.md`, verifying the 3 structured sections (Architecture & Repo Map, Current Focus, Key Contracts).
   - Ensure total length remains strictly under ~500 words by pruning superseded entries.

8. **Append Operation Log:**
   - Append a maintenance summary to `<wiki_dir>/_log.md` detailing fixed links, `mentioned_in` updates, resolved orphans, and gaps.
