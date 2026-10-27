# Karpathy LLM Wiki Directives

> Resolved `wiki_dir` and `sources` are compiled into `.rnex/ai-instructions.md` (Section 2). Do NOT read `rnex.yaml` or `.local.rnex.yaml`.

- **Behavioral Rules**: (1) State assumptions and surface trade-offs before coding; (2) Prefer minimal, non-speculative code; (3) Make surgical edits touching only required lines; (4) Verify changes against concrete goals.
- **Wiki-First**: Read `<wiki_dir>/hot.md`, then `<wiki_dir>/index.md` and only the relevant atomic page(s), before accessing raw intake sources or member repositories.
- **Wiki Operations**: Never edit `<wiki_dir>/` ad-hoc. Run `rnex plugin karpathy-llm ingest` / `lint`, or load `.rnex/plugins/karpathy-llm/skills/wiki-ingest.md` / `wiki-lint.md` (which contain the frontmatter schema) only when executing ingestion or linting.
