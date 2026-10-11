---
name: rnex-workspace-audit
description: Audit workspace configuration integrity, member repository git statuses, and active plugin states.
---

# Repo Nexus Workspace Audit Skill

Use this skill when auditing workspace health, validating multi-repository git status, or verifying configuration consistency.

## Key Rules
1. **Health Audit**: Run `rnex status` to inspect configuration, AGENTS.md, code-workspace, gitignore, hooks, and active plugins.
2. **Git Status Audit**: Check working tree cleanliness across member repos (`rnex exec git status -s`) and branch tracking (`rnex exec git status -uno`).
3. **Reconciliation**: Run `rnex fix` for configuration and asset reconciliation; run `rnex clone` for missing member repository clones.
