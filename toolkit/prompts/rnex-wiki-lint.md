# Operational Task: Workspace Wiki Lint & Audit

You are tasked with executing the Workspace Wiki Lint workflow.

## Context & Inputs
- Target Scope: `.rnex/wiki/` (including `.rnex/wiki/raw/` and synchronized member READMEs)
- Custom Rules & Workflows loaded: `.rnex/plugins/karpathy-llm/`
- Current Workspace Manifest: `rnex.yaml` and `.local.rnex.yaml`

## Verification Rule Router
1. Locate and parse your validation instructions exclusively from `.rnex/plugins/karpathy-llm/workflows/wiki-lint.md`.
2. Evaluate adherence based on the agent behavior standards described in `.rnex/plugins/karpathy-llm/rules/behavioral.md` and compiled rules in `.rnex/ai-instructions.md`.
3. Do NOT invent new lint checks or execute uncompiled heuristic instructions.

Execute the 10-step protocol defined strictly within the referenced workflow. Audit `raw_dir` items, link paths, index categorization, and relational YAML frontmatter. Provide your structured audit and write feedback output to the Audit trail in `.rnex/wiki/_log.md`.
