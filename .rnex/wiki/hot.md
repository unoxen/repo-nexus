# Hot Context (Rolling ~500-Word Cache)

> Fast orientation cache for AI agents. Read this file first for immediate domain context without loading the full wiki index. Strictly bounded under ~500 words.

## 1. Architecture & Member Repo Map
* **Virtual Meta-Repo Architecture:** Unites independent Git repositories under `repos/<name>/` without Git submodules or symlink hierarchies.
* **Workspace Isolation:** Workspace tools, plugins, prompts, and hooks live in `.rnex/`. Member repositories maintain autonomous git histories, origins, and branches.
* **Configuration:** Base configuration in `rnex.yaml` with developer overrides in `.local.rnex.yaml` taking highest precedence.

## 2. Current Focus & Recent Ingests
* **Knowledge Database Ingestion:** Ingested core architectural documentation into atomic wiki pages with typed frontmatter relations.
* **Decoupled Prompt Routing:** Operational prompts (`rnex-cross-repo-feature`, `rnex-workspace-audit`, `rnex-wiki-ingest`, `rnex-wiki-lint`) decoupled to route directly to `.rnex/skills/` and `.rnex/workflows/`.
* **Plugin Prefixes:** Plugin prompts and workflows strictly retain domain prefixes (`rnex-wiki-`).

## 3. Key Contracts & Boundaries
* **Session Startup Gate:** AI assistants must consult `.rnex/ai-instructions.md` and configuration first before accessing `repos/`. Blind codebase searches across `repos/` are prohibited.
* **Atomic Wiki Pages:** Every page maintains typed frontmatter (`sources`, `related`, `extends`, `contradicts`, `mentioned_in`). Agents query frontmatter graph relations rather than body prose.
* **Git Operations:** Commits, branches, and code changes occur strictly within individual member repository roots (`repos/<name>/`). The workspace root never commits member code.
