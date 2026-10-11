---
name: rnex-cross-repo-feature
description: Guide the planning, execution, and verification of features spanning multiple member repositories in a Repo Nexus workspace.
---

# Cross-Repository Feature Implementation Skill

Use this skill when planning, coordinating, or executing changes across multiple member repositories in a Repo Nexus workspace.

## Key Rules
1. **Discovery**: Inspect `.local.rnex.yaml` and `rnex.yaml` to identify active member repositories in `repos/<name>/`. Inspect `repos/<name>/.rnex/` for repository-specific context and constraints.
2. **Staged Execution**: Order repository changes by dependency hierarchy (shared models/backend first, consumer/frontend second).
3. **Targeted Verification**: Verify changes within each modified repository using `rnex exec <test-command>` or directory-targeted commands.
4. **Git Hygiene**: Commit changes independently within each member repository root (`repos/<name>/`). Never commit member repository code directly to the workspace root.
