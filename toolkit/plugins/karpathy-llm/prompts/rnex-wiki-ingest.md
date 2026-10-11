# Karpathy LLM Wiki Ingestion Workflow (`wiki-ingest`)

Autonomous workflow for decomposing and ingesting raw source documents from the configured raw intake directory into atomic Karpathy LLM Wiki pages.

## Protocol
1. Resolve `raw_dir` (default: `raw`) and `wiki_dir` (default: `wiki`) from `rnex.yaml` / `.local.rnex.yaml` under `plugins.karpathy-llm`.
2. Scan `<raw_dir>/` for uningested documents not yet recorded in `<wiki_dir>/_log.md`.
3. Read source materials completely; preserve original files in `<raw_dir>/` unmodified.
4. Decompose each source document into atomic wiki pages in `<wiki_dir>/` (5–25 pages per source).
5. For every page, write required YAML frontmatter with typed relations (`sources`, `related`, `extends`, `contradicts`, `mentioned_in`).
6. Update `<wiki_dir>/index.md` and append an entry to `<wiki_dir>/_log.md`.
