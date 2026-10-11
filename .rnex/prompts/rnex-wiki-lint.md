# Karpathy LLM Wiki Lint & Graph Integrity Workflow

Use this workflow to validate link integrity, update bidirectional backlinks, and detect orphaned pages in the curated wiki directory.

---

## 1. Graph Traversal & Validation
1. Resolve `wiki_dir` (default: `wiki`) and `raw_dir` (default: `raw`) from `rnex.yaml` (or `.local.rnex.yaml`) under `plugins.karpathy-llm`.
2. Verify that all markdown links (`[text](./target.md)`) and frontmatter references (`sources`, `related`, `extends`, `contradicts`) point to existing files on disk under `<wiki_dir>/` or `<raw_dir>/`.
3. Recompute bidirectional `mentioned_in: []` frontmatter backlinks:
   - If Page A references Page B in `related`, `extends`, or body links, ensure Page B includes Page A in its `mentioned_in` list.
4. Detect orphan pages: any page in `<wiki_dir>/` that has no incoming links and is not listed in `<wiki_dir>/index.md`.

## 2. Master Index Rebuild
1. Inspect all atomic pages in `<wiki_dir>/`.
2. Reconcile categories and alphabetical links in `<wiki_dir>/index.md`.
3. Record lint operations in `<wiki_dir>/_log.md`.
