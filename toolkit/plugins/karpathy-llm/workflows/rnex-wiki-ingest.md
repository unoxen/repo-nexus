# Wiki Ingestion Workflow (`wiki-ingest`)

Universal workflow for decomposing and ingesting raw source materials into atomic Karpathy LLM Wiki pages.

---

## Ingestion Protocol

1. **Resolve Configuration & Scan Intake:**
   - Read `rnex.yaml` (and `.local.rnex.yaml` if present) to resolve the active `raw_dir` (default: `./docs`) and `wiki_dir` (default: `.rnex/wiki`) under `plugins.karpathy-llm`.
   - Scan `<raw_dir>/` (default: `./docs`) for source materials (articles, transcripts, documents, research notes, meeting logs) not yet recorded in `<wiki_dir>/_log.md` (default: `.rnex/wiki/_log.md`).
   - All source material must reside in `<raw_dir>/` unmodified. Never write directly to `<wiki_dir>/` without ingesting.

2. **Read & Clarify:**
   - Read each source fully.
   - If scope, domain boundaries, target audience, or level of detail is unclear, ask one round of clarifying questions before proceeding.

3. **Atomic Decomposition:**
   - Decompose each source into atomic wiki pages — **one per distinct concept, person, organization, event, or theme** (or architecture decision/contract).
   - A single source document commonly produces **5–25 pages**. Never collapse an entire source into a single file.
   - Place pages according to workspace wiki organization:
     - **Flat:** directly under `<wiki_dir>/` (e.g., `<wiki_dir>/<topic>.md`)
     - **Structured:** in categorical subfolders within `<wiki_dir>/`:
       - Research → `concepts/`, `people/`, `organizations/`, `sources/`, `analysis/`
       - Second brain → `projects/`, `people/`, `decisions/`, `logs/`
       - Content archive → `sources/`, `people/`, `tools/`, `concepts/`
       - Codebase → `architecture/`, `decisions/`, `runbooks/`, `people/`

4. **Frontmatter Relations:**
   - For each page, write the required YAML frontmatter with typed relations:
   ```yaml
   ---
   title: ""
   tags: []
   last_updated: YYYY-MM-DD
   # Typed relation fields — paths relative to <wiki_dir>/ (or workspace root for raw sources)
   sources: []          # <raw_dir>/ files this page was derived from
   related: []          # thematically related wiki pages
   extends: []          # pages this one builds upon or specialises
   contradicts: []      # pages with conflicting information
   mentioned_in: []     # pages that link to this one (leave empty; maintained by lint)
   ---
   ```
   - **Crucial:** The relation graph lives in frontmatter, not in prose links. Agents traverse the graph by reading frontmatter fields, not by scanning body text.

5. **Author Concise Body:**
   - Write a concise body with summary, key facts, and insights.
   - Add inline standard Markdown links (`[Label](./path.md)`) where contextually useful in prose.

6. **Update Navigation Index (Annotated Links):**
   - Update `<wiki_dir>/index.md` (default: `.rnex/wiki/index.md`) with links to all new pages in their corresponding categorized sections.
   - Include a concise 1-line summary next to each link (e.g. `- [Concept Name](path.md): One-line summary of role or contract`) so agents pinpoint target pages in a single read without exploratory scanning.

7. **Update Hot Cache (Bounded ~500-Word Ceiling):**
   - Update `<wiki_dir>/hot.md` (default: `.rnex/wiki/hot.md`) with the rolling orientation summary across 3 structured sections:
     1. **Architecture & Member Repo Map**: Active domain ownership per member repo.
     2. **Current Focus & Recent Ingests**: Active topics from recent ingests.
     3. **Key Contracts & Boundaries**: Critical cross-repo or subsystem rules.
   - **Enforce Token Economy**: Keep `<wiki_dir>/hot.md` strictly under ~500 words. Condense or prune older focus items to prevent bloat.

8. **Append Operation Log:**
   - Append a timestamped entry to `<wiki_dir>/_log.md` (default: `.rnex/wiki/_log.md`) detailing:
     - Date & time
     - Raw intake file processed
     - List of atomic pages generated
     - Any flagged follow-ups or knowledge gaps
