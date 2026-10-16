# Hot Context (Rolling ~500-Word Cache)

> Fast orientation cache for AI agents. Read this file first for immediate domain context without loading the full wiki index. Strictly bounded under ~500 words.

## 1. Architecture & Member Repo Map
* **Workspace Overview:** Karpathy LLM Wiki initialized.
* **Member Repositories:** Map each member repo to its core responsibility and main entry point once active.

## 2. Current Focus & Recent Ingests
* **Active Tasks:** Wiki initialization complete.
* **Recent Ingests:** None yet. Deposit source documents into `{raw_dir}/` and run `rnex-karpathy-llm-wiki-ingest`.

## 3. Key Contracts & Boundaries
* **Atomic Pages:** Concepts live in discrete files with frontmatter relations (`sources`, `related`, `extends`, `mentioned_in`).
* **Deep Knowledge:** For detailed RFCs, data contracts, and secondary concepts, consult `{wiki_dir}/index.md` on demand.
