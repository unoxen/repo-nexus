# GitHub Copilot Integration for Repo Nexus

This workspace has the Repo Nexus `copilot` plugin enabled.

## Operating Principles
- **Instructions Integration**: GitHub Copilot natively reads `.github/copilot-instructions.md` and root `AGENTS.md` for workspace routing and active plugin guidelines between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`. Custom instructions outside these markers are strictly preserved.
- **User Skills**: Standardized Repo Nexus core skills and active plugin skills can be accessed via `.github/skills/rnex-*/SKILL.md` when `skills: true`.
