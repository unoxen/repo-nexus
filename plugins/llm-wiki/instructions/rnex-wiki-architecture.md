# LLM Wiki Directives

> Follow the execution gate and routing directives in `.rnex/ai-instructions.md` and `.rnex/plugins/llm-wiki/ai-instructions.md`.

- **Behavioral Rules**: (1) State assumptions and surface trade-offs before coding; (2) Prefer minimal, non-speculative code; (3) Make surgical edits touching only required lines; (4) Verify changes against concrete goals.
- **Wiki-First**: Follow the B-Tree retrieval protocol: (1) Read `{wikiDir}/{indexFile}`; (2) Read the target index shard `{wikiDir}/repo-nexus*.md` or `{wikiDir}/repos-*.md` and open only the authoritative source documents referenced by the shard.
- **Wiki Operations**: Never edit `{wikiDir}/` shards ad-hoc. Run `rnex plugin llm-wiki ingest` or `rnex plugin llm-wiki lint`, or load `.rnex/plugins/llm-wiki/skills/ingest.md` or `.rnex/plugins/llm-wiki/skills/lint.md` when executing ingestion or linting.
