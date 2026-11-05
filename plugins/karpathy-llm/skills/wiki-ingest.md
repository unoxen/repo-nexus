# Agentic Skill: wiki-ingest

Universal agentic skill protocol for deterministically ingesting and enriching source materials in the Karpathy LLM Wiki.

---

## Capabilities & Context

Use this skill when ingesting new reference materials, architecture documentation, transcripts, articles, or member repository READMEs into the workspace curated wiki knowledge graph.

## CLI Helper

Always scaffold wiki pages deterministically using the built-in CLI helper first before enriching in-place:

```sh
rnex plugin karpathy-llm ingest [--file <path> | <path>] [--source <path>] [--repo <name>] [--quiet]
```

## Ingestion Protocol

1. **Resolve Configuration & Direct Source Paths:**
   - Take the resolved `sources` list, `repos_dir`, `wiki_dir`, and active/disabled repositories from **Section 2 (Merged Workspace Configuration)** of the already-loaded `.rnex/ai-instructions.md`. Do NOT read `rnex.yaml` or `.local.rnex.yaml`.
   - Direct input scope resolves all files matching `sources` (read-only):
     1. **Configured Directory Sources (e.g. `docs` or `docs/`):** When a directory path is specified without glob patterns, recursively discover (`find "$NEXUS_DIR/<dir>" -type f`) all markdown, text, and documentation files across all nested subdirectories, ignoring hidden files/folders (`.*`) and `node_modules`.
     2. **Glob Patterns:** Files matching recursive or single-level glob patterns (e.g. `repos/**/README.md` or `<repos_dir>/**/README.md`), excluding disabled repositories (`enabled: false`).
     3. **Specific File Paths:** Files explicitly targeted in `sources` or passed via CLI `--source <path>`.
     4. **Member Repositories:** `./<repos_dir>/<name>/README.md` (default: `./repos/<name>/README.md`) for every active member repository listed in `.rnex/ai-instructions.md` (read-only).
   - Intake sources and member repositories (`./<repos_dir>/`) are strictly read-only inputs during wiki operations. Never create, copy, or modify files inside intake sources; write generated output exclusively inside `wiki_dir` (`wiki/`).
   - Scan direct source paths for source materials not yet recorded in `<wiki_dir>/_log.md`.
   - All source material is read directly in-place without staging copies. Never write directly to `<wiki_dir>/` without ingesting.

2. **Step 1 — Deterministic CLI Scaffolding:**
   - Run `rnex plugin karpathy-llm ingest` (or `rnex plugin karpathy-llm ingest <path>`).
   - The CLI deterministically scaffolds the exact 1-to-1 wiki file and registers it in `index.md` and `_log.md` (and independently in the local git-ignored `hot.md` when `hot_file: true`):
     - **Root Member Repository READMEs:** Mapped strictly to `<wiki_dir>/repo-<repo_name>.md`.
     - **All Other Sources & Nested READMEs:** Mapped strictly to `<wiki_dir>/<slug>.md`, where `<slug>` is the normalized lowercase workspace-relative path (e.g., `docs/overview.md` becomes `<wiki_dir>/docs-overview.md`; `docs/api/README.md` becomes `<wiki_dir>/docs-api-readme.md`; `repos/app/apps/web/README.md` becomes `<wiki_dir>/repos-app-apps-web-readme.md`).
     - Root-level files without a directory prefix normalizing to reserved wiki control file names (`index`, `hot`, `_log`) are prefixed with `root-` (e.g., `index.md` becomes `root-index.md`).

3. **Step 2 — In-Place Synthesis & Enrichment:**
   - Read the source document(s) thoroughly in-place.
   - Enrich the deterministically generated `<wiki_dir>/<slug>.md` page **in-place** rather than inventing ad-hoc file names.
   - Synthesize architectural concepts, contracts, patterns, and trade-offs directly into the curated page.
   - Do NOT append duplicate audit entries to `_log.md` if the page already exists and is being enriched.

4. **Frontmatter Relations:**
   - For every page, maintain typed frontmatter relations:
   ```yaml
   ---
   title: ""
   tags: []
   last_updated: YYYY-MM-DD
   sources: []          # direct source files (<source_path> or repos/<name>/README.md) this page was derived from
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
   - Verify `<wiki_dir>/index.md` contains the link to the page with a concise 1-line summary next to each link (e.g. `- [Auth Flow](./auth-flow.md): JWT validation and token rotation`) so agents pinpoint target pages in a single read.

7. **Update Hot Cache (Optional Local Cache, Bounded ~500-Word Ceiling):**
   - When `hot_file: true` (default), update `<wiki_dir>/hot.md` with compact rolling orientation summaries (`<= 55-75` chars per line, at most 8 recent ingests) across 3 sections:
     1. Architecture & Member Repo Map (with direct links: `- **[<repo>](./repo-<slug>.md)** (\`<rel_path>\`): <summary>`)
     2. Current Focus & Recent Ingests (with direct links: `- **[<title>](./<slug>.md)** (\`<src_rel>\`): <summary>`)
     3. Key Contracts & Boundaries
   - `hot.md` is a local git-ignored file and has zero relation to `_log.md` (never reference `hot.md` in `_log.md` or `mentioned_in`).

8. **Audit Verification:**
   - Run `rnex plugin karpathy-llm lint` to verify that link paths, frontmatter schema, and word boundaries conform to wiki invariants.
