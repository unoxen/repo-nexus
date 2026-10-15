# Operational Task: Karpathy LLM Wiki Lint & Graph Audit

You are tasked with auditing graph integrity, validating bidirectional relations, and repairing links for the Karpathy LLM Wiki.

## Context & Inputs
- Target Scope: Curated wiki directory (`wiki_dir`, default: `.rnex/wiki/`)
- Workspace Manifest: `rnex.yaml` and `.local.rnex.yaml`
- AI Instructions: `.rnex/ai-instructions.md`

## Skill & Workflow Router
1. Read the operational skill requirements in `.rnex/plugins/karpathy-llm/skills/rnex-wiki-lint/SKILL.md`.
2. Follow the multi-step audit and graph reconciliation protocol in `.rnex/plugins/karpathy-llm/workflows/rnex-wiki-lint.md`.
3. Follow architectural and behavioral constraints in `.rnex/plugins/karpathy-llm/rules/rnex-behavioral.md`.
4. Adhere to mandatory session startup, routing protocols, and global rules in `.rnex/ai-instructions.md`.
5. Do NOT invent new lint checks or execute uncompiled heuristic instructions.

Execute the referenced lint workflow across all wiki pages. Validate frontmatter relation filepaths, recompute `mentioned_in` backlinks, identify orphan pages, reconcile the master index, and record findings in the operation log.
