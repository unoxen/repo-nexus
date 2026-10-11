# Karpathy LLM Wiki Lint & Graph Maintenance (`wiki-lint`)

Periodic maintenance workflow to preserve wiki graph integrity, validate typed relations, and recompute bidirectional links.

## Protocol
1. Resolve `wiki_dir` (default: `wiki`) and `raw_dir` (default: `raw`) from `rnex.yaml` / `.local.rnex.yaml` under `plugins.karpathy-llm`.
2. Verify all frontmatter relation paths (`sources`, `related`, `extends`, `contradicts`) resolve to existing files under `<wiki_dir>/` and `<raw_dir>/`.
3. Recompute `mentioned_in` backlinks for every page across the entire wiki graph.
4. Find orphaned pages not reachable from `<wiki_dir>/index.md` or any `mentioned_in` link, and index them.
5. Detect duplicate/overlapping pages and check for factual contradictions.
6. Identify knowledge gaps, suggest source candidates from `<raw_dir>/`, and append audit results to `<wiki_dir>/_log.md`.
