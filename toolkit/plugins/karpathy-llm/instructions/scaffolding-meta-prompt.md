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

- **`/raw/`** — Append-only intake directory. Add `.gitkeep`. All original source material goes here unmodified.
- **`/wiki/index.md`** — Master navigation index organizing links to atomic pages.
- **`/wiki/hot.md`** — Rolling ~500-word orientation cache for quick agent onboarding.
- **`/wiki/_log.md`** — Append-only operation log recording all ingest and lint runs.

Do not create arbitrary or speculative subdirectories during initialization. Scaffolding is 100% deterministic. Domain subfolders and categories emerge organically during the source ingestion phase (`wiki-ingest`).

---

### 2. Agent Rules & Routing

- **Repo Nexus Workspaces**: Scoped under `.rnex/plugins/karpathy-llm/` (`rules/behavioral.md` and `instructions/wiki-architecture.md`). Agents route through `rnex.yaml` automatically.
- **Standalone Repositories**: Append the `## Karpathy Wiki Rules` section (see Section 4) to the primary AI instructions file (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`, etc.), preserving all existing content.

---

### 2. Index File Format

`/wiki/index.md` uses its own frontmatter schema (it is the wiki navigation file, not an atomic content page):

```yaml
---
title: Wiki Index
last_updated: YYYY-MM-DD
---
```

Followed by categorized Markdown link sections matching the project type from Q2.

---

### 3. Wiki Page Format

Every wiki page is a single atomic markdown file covering one concept, entity, source, or decision.

**Required YAML frontmatter:**

```yaml
---
title: ""
tags: []
last_updated: YYYY-MM-DD
# Typed relation fields — paths relative to /wiki/
sources: []          # /raw/ files this page was derived from
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

- **Intake**: All source material (articles, transcripts, docs, notes) goes to `/raw/` unmodified. Never write directly to `/wiki/` without ingesting.
- **Orientation**: Before answering domain questions, read `/wiki/index.md` to find relevant pages, then read only those pages. If `hot.md` exists, read it first as a quick-orient step.
- **Ingestion**: When files appear in `/raw/`, run the `wiki-ingest` workflow. One source document typically produces many atomic pages — do not collapse a source into a single file.
- **Maintenance**: Run the `wiki-lint` workflow to validate paths, update `mentioned_in`, and preserve graph integrity.
```

---

### 5. Workflows

Create workflow instruction files at `.agent/workflows/` (or `.agent/skills/` depending on the harness):

**`wiki-ingest.md`**:
1. Scan `/raw/` for files not yet recorded in `/wiki/_log.md`.
2. For each source, read it fully. If scope or depth is unclear, ask one round of clarifying questions before proceeding.
3. Decompose into atomic wiki pages — one per distinct concept, person, organization, event, or theme. A single article commonly produces 5–25 pages.
4. For each page, write the required frontmatter (including `sources`, `related`, `extends`, `contradicts`). Leave `mentioned_in` empty — lint maintains it.
5. Write a concise body with inline links where contextually helpful.
6. Update `/wiki/index.md` with links to all new pages.
7. Update `/wiki/hot.md` if it exists.
8. Append a timestamped entry to `/wiki/_log.md`.

**`wiki-lint.md`**:
1. For every page, verify that all paths in frontmatter relation fields (`related`, `extends`, `contradicts`, `sources`) resolve to existing files. Fix or flag broken paths.
2. Recompute `mentioned_in` for every page by scanning all other pages' relation fields and inline links. Update the field.
3. Find orphaned pages (not reachable from `index.md` or any `mentioned_in` field). Add them to the index.
4. Detect duplicate or heavily overlapping pages. Consolidate and update relations.
5. Check for factual inconsistencies between pages in `contradicts` relations or covering the same topic.
6. Identify knowledge gaps: concepts referenced in relation fields but lacking their own page. Create stub pages or flag for future ingest.
7. Suggest source candidates from `/raw/` or external searches to fill gaps.
8. Rebuild `/wiki/index.md` to reflect the current set of pages.
9. Update `/wiki/hot.md` if it exists.
10. Append a lint summary to `/wiki/_log.md`.

---

All files must be self-contained with no external dependencies.
```
