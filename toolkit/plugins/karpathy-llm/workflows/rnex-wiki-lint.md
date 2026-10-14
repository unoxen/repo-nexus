# Wiki Lint & Maintenance Workflow (`wiki-lint`)

Periodic health check and maintenance workflow to preserve wiki graph integrity, validate typed relations, recompute bidirectional links, resolve knowledge gaps, and rebuild indexes.

---

## Lint & Maintenance Protocol

1. **Resolve Configuration & Verify Paths:**
   - Read `rnex.yaml` (and `.local.rnex.yaml` if present) to resolve the active `wiki_dir` (default: `wiki`) and `raw_dir` (default: `raw`) under `plugins.karpathy-llm`.
   - For every page under `<wiki_dir>/`, verify that all paths in frontmatter relation fields (`related`, `extends`, `contradicts`, `sources`) resolve to existing files under `<wiki_dir>/` or `<raw_dir>/`.
   - Fix or flag broken paths.

2. **Recompute `mentioned_in`:**
   - Recompute `mentioned_in` for every page under `<wiki_dir>/` by scanning all other pages' relation fields and inline links.
   - Update the field in frontmatter.

3. **Find Orphaned Pages:**
   - Detect pages under `<wiki_dir>/` not reachable from `<wiki_dir>/index.md` or any `mentioned_in` field.
   - Add them to the index in their appropriate category.

4. **Detect Duplicate or Overlapping Pages:**
   - Detect duplicate or heavily overlapping pages.
   - Consolidate and update relations across the wiki graph.

5. **Check Factual Inconsistencies:**
   - Check for factual inconsistencies between pages in `contradicts` relations or covering the same topic.
   - Clarify or resolve contradictions.

6. **Identify Knowledge Gaps:**
   - Identify knowledge gaps: concepts referenced in relation fields or prose but lacking their own atomic page.
   - Create stub pages or flag for future ingest.

7. **Suggest Source Candidates:**
   - Suggest source candidates from `<raw_dir>/` or external searches to fill identified knowledge gaps.

8. **Rebuild Navigation Index (Annotated Links):**
   - Rebuild `<wiki_dir>/index.md` to reflect the current set of pages and categories accurately.
   - Ensure every page entry maintains a concise 1-line descriptive annotation.

9. **Update Hot Cache (Bounded ~500-Word Ceiling):**
   - Refresh `<wiki_dir>/hot.md`, verifying the 3 structured sections (Architecture & Repo Map, Current Focus, Key Contracts).
   - Ensure the total length remains strictly under ~500 words by pruning superseded entries.

10. **Append Operation Log:**
    - Append a lint summary to `<wiki_dir>/_log.md` detailing:
      - Broken links fixed or flagged
      - `mentioned_in` updates
      - Orphans and duplicates resolved
      - Gaps identified or stubbed
