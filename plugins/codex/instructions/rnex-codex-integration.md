# OpenAI Codex Integration for Repo Nexus

This workspace has the Repo Nexus `codex` plugin enabled.

## Operating Principles
- **Codex Instructions (`CODEX.md`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, preserving any manual user instructions outside those markers. This serves as the primary instructions file for OpenAI Codex and ChatGPT.
- **User Skills (`.codex/skills/rnex-*.md`)**: Zero-logic user skill pointers linking directly to core skills (`.rnex/skills/`) and active plugins' skills (`.rnex/plugins/<name>/skills/`).
- **Decoupled Cross-Plugin Discovery**: The `codex` provider discovers and registers user skills from whatever Repo Nexus plugins are currently active.
