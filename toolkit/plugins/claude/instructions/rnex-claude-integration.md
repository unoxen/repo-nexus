# Anthropic Claude Code Integration for Repo Nexus

This workspace has the Repo Nexus `claude` plugin enabled.

## Operating Principles
- **Claude Instructions (`CLAUDE.md`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, preserving any manual user instructions outside those markers. This serves as the primary instructions file for Anthropic Claude Code CLI and Claude Desktop.
- **User Skills (`.claude/skills/rnex-*.md`)**: Zero-logic user skill pointers linking directly to core skills (`.rnex/skills/`) and active plugins' skills (`.rnex/plugins/<name>/skills/`).
- **Decoupled Cross-Plugin Discovery**: The `claude` provider discovers and registers user skills from whatever Repo Nexus plugins are currently active.
