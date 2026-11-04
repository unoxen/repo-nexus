# Karpathy LLM Wiki Directives

> Resolved `wiki_dir` and `sources` are compiled into `.rnex/ai-instructions.md` (Section 2). Do NOT read `rnex.yaml` or `.local.rnex.yaml`.

- **Behavioral Rules**: (1) State assumptions and surface trade-offs before coding; (2) Prefer minimal, non-speculative code; (3) Make surgical edits touching only required lines; (4) Verify changes against concrete goals.
- **Wiki-First**: Read `<wiki_dir>/hot.md` first for workspace architecture, repository boundaries, and direct links to curated `<wiki_dir>/*.md` pages. If `<wiki_dir>/hot.md` links the needed page, read that page directly and skip `<wiki_dir>/index.md`. Read `<wiki_dir>/index.md` only if the needed topic or page is not listed in `<wiki_dir>/hot.md`.
- **Wiki Operations**: Never edit `<wiki_dir>/` ad-hoc. Run `rnex plugin karpathy-llm ingest` / `lint`, or load `.rnex/plugins/karpathy-llm/skills/wiki-ingest.md` / `wiki-lint.md` (which contain the frontmatter schema) only when executing ingestion or linting.
