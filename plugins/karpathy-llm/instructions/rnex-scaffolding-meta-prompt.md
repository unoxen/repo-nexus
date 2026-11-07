# Karpathy LLM Wiki Scaffolding Prompt

Universal meta-prompt for setting up a Karpathy LLM Wiki knowledge architecture. Works with any AI agent harness. No external MCP servers, vector databases, or embedding pipelines required — just markdown files with structured frontmatter.

---

```markdown
Set up a Karpathy LLM Wiki in this repository: a self-maintaining knowledge base where raw source material is ingested into interlinked atomic markdown files that any AI agent can navigate by reading indexes and following typed frontmatter relations.

Do not use external MCP servers, vector databases, or embedding pipelines.
Do not hard-code any specific AI tool or harness into the wiki structure itself.

---

### 1. Deterministic Scaffolding (Create Immediately)

Initialize the fixed baseline directories and control files:

- **`./docs/`** — Workspace documentation directory.
- **`wiki/_index.md`** — B-Tree Root routing table (bounded <= 80 lines) organizing domain shards.
- **`wiki/_index/`** — B-Tree leaf shards (`repo-nexus.md`, `repos-<member>.md`).
- **`wiki/_graph/`** — Sorted TSV property graph (`nodes.tsv`, `edges_out.tsv`, `edges_in.tsv`).
- **`wiki/_log.md`** — Append-only operation log recording all ingest and lint runs.

Do not create arbitrary or speculative subdirectories during initialization. Scaffolding is 100% deterministic. Domain subfolders and categories emerge organically during the source ingestion phase (`wiki-ingest`).

---

### 2. Agent Rules & Routing

- **Repo Nexus Workspaces**: Paths (`sources`, default: `["docs", "repos/**/README.md"]`; legacy `raw_dir`; `wiki_dir`, default: `wiki`) are configured in `rnex.yaml` under `plugins.karpathy-llm`. Plugin assets are scoped under `.rnex/plugins/karpathy-llm/` (`rules/behavioral.md` and `instructions/rnex-wiki-architecture.md`). Resolved paths are pre-compiled into `.rnex/ai-instructions.md`.
- **Standalone Repositories**: Append the `## Karpathy Wiki Rules` section (see Section 4) to the primary AI instructions file (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`, etc.), preserving all existing content.

---

### 2. Index File Format

`wiki/index.md` is the central content-oriented navigation catalog. It contains no YAML frontmatter, starting cleanly with `# Wiki Index`, followed by categorized Markdown link sections matching the project type from Q2. Every entry maintains a concise 1-line annotation (e.g. `- [Topic](./topic.md): Brief description`).

---

### 3. Wiki Page Format

Every wiki page is a single atomic markdown file covering one concept, entity, source, or decision.

**Required YAML frontmatter:**

```yaml
---
title: ""
tags: []
last_updated: YYYY-MM-DD
# Typed relation fields — paths relative to wiki/
sources: []          # ./docs/ files this page was derived from
related: []          # thematically related wiki pages
extends: []          # pages this one builds upon or specialises
contradicts: []      # pages with conflicting information
mentioned_in: []     # pages that link to this one (maintained by lint)
---
```

**Body:** concise summary, key facts or insights, and inline standard Markdown links (`[Label](./path.md)`) where contextually useful in prose.

The relation graph lives in frontmatter, not in prose links. Agents traverse the graph by reading frontmatter fields, not by scanning body text.

---

### 4. Agent Instructions (Standalone Repositories)

In standalone repositories (outside Repo Nexus), append:

```markdown
## Karpathy Wiki Rules

- **Intake**: All source material (articles, transcripts, docs, notes) is resolved from configured `sources` (or legacy `raw_dir`, default: `./docs`) unmodified. Never write directly to `wiki/` without ingesting.
- **Orientation**: Follow the 3-step B-Tree retrieval protocol: (1) Read `wiki/index.md` (bounded root router <= 80 lines) or run `rnex plugin karpathy-llm search <keyword>`; (2) Read the target shard `wiki/_index/<shard>.md` or run `rnex plugin karpathy-llm graph <node_id>`; (3) Open only the 1–3 target leaf pages in `wiki/`.
- **Ingestion**: When files appear in configured sources, run `rnex plugin karpathy-llm ingest` to scaffold deterministic 1-to-1 wiki pages (`repo-<name>.md` for root member repo READMEs; `<normalized-relative-path>.md` for all other sources), then enrich each page in-place.
- **Maintenance**: Run `rnex plugin karpathy-llm lint` to validate paths, update relations, verify B-Tree bounds, and preserve graph integrity.
```

---

### 5. Workflows

Create workflow instruction files at `.agent/workflows/` (or `.agent/skills/` depending on the harness):

**`wiki-ingest.md`**:
1. Scan configured `sources` (or `<raw_dir>/`) for files not yet recorded in `wiki/_log.md`.
2. Scaffold deterministic wiki pages via `rnex plugin karpathy-llm ingest` (`repo-<name>.md` for root member repo READMEs, `<path-prefix>-<name>.md` for intake sources).
3. Read each source fully and enrich the corresponding `<wiki_dir>/<slug>.md` page in-place (capturing architecture concepts, contracts, and patterns).
4. For each page, maintain typed frontmatter (`sources`, `related`, `extends`, `contradicts`, `mentioned_in`).
5. Write a concise body with inline links where contextually helpful.
6. Verify the corresponding domain shard in `wiki/_index/` contains the annotated link.
7. Run `rnex plugin karpathy-llm index` to synchronize the graph and recompile the root router.
8. Verify graph integrity using `rnex plugin karpathy-llm lint`.

**`wiki-lint.md`**:
1. For every page, verify that all paths in frontmatter relation fields (`related`, `extends`, `contradicts`, `sources`) resolve to existing files. Fix or flag broken paths.
2. Recompute `mentioned_in` for every page by scanning all other pages' relation fields and inline links. Update the field.
3. Find orphaned pages (not reachable from `nodes.tsv` or any `mentioned_in` field). Add them to the appropriate shard.
4. Detect duplicate or heavily overlapping pages. Consolidate and update relations.
5. Check for factual inconsistencies between pages in `contradicts` relations or covering the same topic.
6. Identify knowledge gaps: concepts referenced in relation fields but lacking their own page. Create stub pages or flag for future ingest.
7. Suggest source candidates from configured `sources` (or `<raw_dir>/`) or external searches to fill gaps.
8. Rebuild `wiki/_graph/*.tsv`, `wiki/_index/*.md`, and `wiki/index.md` via `rnex plugin karpathy-llm index`.
9. Append a lint summary to `wiki/_log.md`.

---

All files must be self-contained with no external dependencies.
```
