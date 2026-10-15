# Operational Task: Workspace Configuration & Health Audit

You are tasked with executing a comprehensive audit of the Repo Nexus workspace configuration, member repository git statuses, and active plugin states.

## Context & Inputs
- Target Scope: Root workspace configuration, `.rnex/`, and active member repositories in `repos/<name>/`
- Workspace Manifest: `rnex.yaml` and `.local.rnex.yaml`
- AI Instructions: `.rnex/ai-instructions.md`

## Skill & Workflow Router
1. Read the operational skill requirements in `.rnex/skills/rnex-workspace-audit/SKILL.md`.
2. Follow the multi-step audit and remediation protocol in `.rnex/workflows/rnex-workspace-audit.md`.
3. Adhere to mandatory session startup, routing protocols, and member repo boundary rules in `.rnex/ai-instructions.md`.
4. Do NOT execute uncompiled heuristics or alter workspace configuration outside the referenced workflow.

Execute the audit according to the referenced workflow and report configuration integrity, working tree cleanliness, and active plugin health.
