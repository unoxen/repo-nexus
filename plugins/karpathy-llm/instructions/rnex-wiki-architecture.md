# Karpathy LLM Wiki Directives

> Resolved `wiki_dir` and `sources` are compiled into `.rnex/ai-instructions.md` (Section 2). Do NOT read `rnex.yaml` or `.local.rnex.yaml`.

- **Behavioral Rules**: (1) State assumptions and surface trade-offs before coding; (2) Prefer minimal, non-speculative code; (3) Make surgical edits touching only required lines; (4) Verify changes against concrete goals.
- **Wiki-First**: Follow the 3-step B-Tree retrieval protocol: (1) Read `<wiki_dir>/index.md` (bounded root router <= 80 lines) or run `rnex plugin karpathy-llm search <keyword>`; (2) Read the target shard `<wiki_dir>/_index/<shard>.md` or run `rnex plugin karpathy-llm graph <node_id>`; (3) Open only the 1–3 target leaf pages in `<wiki_dir>/`.
- **Wiki Operations**: Never edit `<wiki_dir>/` ad-hoc. Run `rnex plugin karpathy-llm ingest` / `index` / `lint`, or load `.rnex/plugins/karpathy-llm/skills/wiki-ingest.md` / `wiki-lint.md` (which contain the frontmatter schema) only when executing ingestion or linting.
