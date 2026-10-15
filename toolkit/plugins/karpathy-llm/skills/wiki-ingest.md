# Agentic Skill: wiki-ingest

Universal agentic skill protocol for decomposing and ingesting raw source materials into atomic Karpathy LLM Wiki pages.

---

## Capabilities & Context

Use this skill when ingesting new reference materials, architecture documentation, transcripts, articles, or member repository READMEs into the workspace curated wiki knowledge graph.

## Ingestion Protocol

1. **Resolve Configuration & Scan Intake:**
   - Read `rnex.yaml` (and `.local.rnex.yaml` if present) to resolve the active `raw_dir` (default: `./docs`) and `wiki_dir` (default: `.rnex/wiki`) under `plugins.karpathy-llm`.
   - Scan `<raw_dir>/` for source materials not yet recorded in `<wiki_dir>/_log.md`.
   - All source material must reside in `<raw_dir>/` unmodified. Never write directly to `<wiki_dir>/` without ingesting.

2. **Read & Clarify:**
   - Read each source document thoroughly.
   - If scope, domain boundaries, or terminology are ambiguous, ask one round of clarifying questions before decomposing.

3. **Atomic Decomposition:**
   - Decompose each source into atomic wiki pages — **one per distinct concept, architecture contract, subsystem, or pattern**.
   - A single source document commonly produces **5–25 atomic pages**. Never collapse an entire source document into a single page.
   - Place pages directly under `<wiki_dir>/` (e.g. `<wiki_dir>/<concept>.md`) or organized by clear domain categories.

4. **Frontmatter Relations:**
   - For every page, specify typed frontmatter relations:
   ```yaml
   ---
   title: ""
   tags: []
   last_updated: YYYY-MM-DD
   sources: []          # <raw_dir>/ files this page was derived from
   related: []          # thematically related wiki pages
   extends: []          # pages this one builds upon or specialises
   contradicts: []      # pages with conflicting information
   mentioned_in: []     # pages that link to this one (maintained by wiki-lint)
   ---
   ```
   - **Crucial:** The relation graph lives in frontmatter, not in prose links. Agents traverse the graph by reading frontmatter fields.

5. **Author Concise Body:**
   - Write a concise body with summary, architectural responsibilities, and key insights.
   - Include standard Markdown links (`[Label](./page.md)`) inline where helpful.

6. **Update Navigation Index (Annotated Links):**
   - Update `<wiki_dir>/index.md` with links to all new pages in their corresponding sections.
   - Include a concise 1-line summary next to each link (e.g. `- [Auth Flow](auth.md): JWT validation and token rotation`) so agents pinpoint target pages in a single read.

7. **Update Hot Cache (Bounded ~500-Word Ceiling):**
   - Update `<wiki_dir>/hot.md` with rolling orientation summaries across 3 sections:
     1. Architecture & Member Repo Map
     2. Current Focus & Recent Ingests
     3. Key Contracts & Boundaries
   - Maintain the strict ~500-word ceiling. Condense or prune older focus items.

8. **Append Operation Log:**
   - Append a timestamped entry to `<wiki_dir>/_log.md` detailing date, raw source processed, generated atomic pages, and follow-ups.
