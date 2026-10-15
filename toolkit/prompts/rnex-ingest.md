# Operational Task: Ingest New Material

You are tasked with executing the ingestion and atomic break-down workflow.

## Context & Inputs
- Source files location: `.rnex/wiki/raw/` (inclusive of active member repo `README_*.md` files)
- Goal: Deconstruct files into individual interlinked pages in `.rnex/wiki/`.

## Workflow & Guidelines Router
1. Read the strict ingest steps and verification metrics only from `.rnex/plugins/karpathy-llm/workflows/wiki-ingest.md`.
2. Follow styling, structural, and behavioral constraints inside `.rnex/plugins/karpathy-llm/rules/behavioral.md`.
3. Adhere to global instruction patterns in `.rnex/ai-instructions.md`.

Transform unmodified raw documents on ingestion following exactly the referenced workflow. Do not use inline logic or generate outside explicit instructions. Run 'wiki-lint' upon completion to review accuracy. Update Operation Log (`.rnex/wiki/_log.md`).
