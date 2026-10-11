# Hot Context (Rolling ~500-Word Cache)

> A compact overview of the most active and immediately relevant domain context. Agents read this file first for quick orientation without needing to parse the full wiki.

## Active Focus & System State
* **Current State:** Karpathy LLM Wiki initialized.
* **Recent Ingests:** None yet. Place raw sources into `/{raw_dir}/` and trigger `wiki-ingest`.
* **Key Directives:**
  1. Maintain atomic pages with typed frontmatter relations.
  2. Update `/{wiki_dir}/index.md` and this hot cache upon new ingests.
  3. Run `wiki-lint` workflow to audit and maintain graph integrity.
