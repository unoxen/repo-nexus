# Karpathy LLM Wiki Directives

> Resolved `wiki_dir` and `sources` are compiled into `.rnex/ai-instructions.md` (Section 2). Do NOT read `rnex.yaml` or `.local.rnex.yaml`.

- **Behavioral Rules**: (1) State assumptions and surface trade-offs before coding; (2) Prefer minimal, non-speculative code; (3) Make surgical edits touching only required lines; (4) Verify changes against concrete goals.
- **Wiki-First**: Follow the 3-step B-Tree retrieval protocol: (1) Read `<wiki_dir>/index.md` (bounded root router <= 80 lines); (2) Read the target index shard `<wiki_dir>/repo-nexus*.md` or `<wiki_dir>/repos-<member>*.md`; (3) Open only the authoritative source documents referenced by the shard.
- **Wiki Operations**: Never edit `<wiki_dir>/` shards ad-hoc. Run `rnex plugin karpathy-llm ingest` or `rnex plugin karpathy-llm lint`, or load `.rnex/plugins/karpathy-llm/skills/wiki-ingest.md` / `wiki-lint.md` when executing ingestion or linting.
