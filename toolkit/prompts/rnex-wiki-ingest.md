# Operational Task: Karpathy LLM Wiki Ingestion

You are tasked with executing the knowledge ingestion and atomic decomposition workflow for the Karpathy LLM Wiki.

## Context & Inputs
- Target Scope: Curated wiki directory (`wiki_dir`, default: `.rnex/wiki/`)
- Intake Sources: Configured raw intake directory (`raw_dir`, default: `./docs`) and synchronized member repository READMEs
- Workspace Manifest: `rnex.yaml` and `.local.rnex.yaml`
- AI Instructions: `.rnex/ai-instructions.md`

## Skill & Workflow Router
1. Read the operational skill requirements in `.rnex/plugins/karpathy-llm/skills/rnex-wiki-ingest/SKILL.md`.
2. Follow the atomic decomposition and ingestion protocol strictly in `.rnex/plugins/karpathy-llm/workflows/rnex-wiki-ingest.md`.
3. Follow architectural and behavioral constraints in `.rnex/plugins/karpathy-llm/rules/rnex-behavioral.md`.
4. Adhere to mandatory session startup, routing protocols, and global rules in `.rnex/ai-instructions.md`.
5. Do NOT invent new frontmatter schemas, skip atomic decomposition, or alter source materials directly.

Decompose intake documents into atomic, interlinked wiki pages with typed frontmatter relations. Update the master index and append a timestamped entry to the operation log.
