# Karpathy LLM Wiki Directives

> Follow the execution gate and routing directives in `.rnex/ai-instructions.md` and `.rnex/plugins/karpathy-llm/ai-instructions.md`.

- **Behavioral Rules**: (1) State assumptions and surface trade-offs before coding; (2) Prefer minimal, non-speculative code; (3) Make surgical edits touching only required lines; (4) Verify changes against concrete goals.
- **Wiki-First**: Follow the B-Tree retrieval protocol: (1) Read `<wiki_dir>/index.md`; (2) Read the target index shard `<wiki_dir>/repo-nexus*.md` or `<wiki_dir>/repos-<member>*.md` and open only the authoritative source documents referenced by the shard.
- **Wiki Operations**: Never edit `<wiki_dir>/` shards ad-hoc. Run `rnex plugin karpathy-llm ingest` or `rnex plugin karpathy-llm lint`, or load `.rnex/plugins/karpathy-llm/skills/wiki-ingest.md` / `wiki-lint.md` when executing ingestion or linting.
