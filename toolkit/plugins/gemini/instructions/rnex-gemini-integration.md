# Google Gemini & Antigravity Integration for Repo Nexus

This workspace has the Repo Nexus `gemini` plugin enabled.

## Operating Principles
- **Gemini Instructions (`GEMINI.md`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, preserving any manual user instructions outside those markers. This serves as the primary instructions file for Google Gemini CLI and Google Antigravity.
- **User Skills (`.agents/skills/rnex-*/SKILL.md`)**: Zero-logic user skill pointers linking directly to core skills (`.rnex/skills/`) and active plugins' skills (`.rnex/plugins/<name>/skills/`).
- **File Discovery Un-Ignore (`.geminiignore`)**: Un-ignores member repositories (`!repos/*`) so Gemini CLI and Google Antigravity can discover and access member repository files, while workspace Git continues to ignore them.
- **Decoupled Cross-Plugin Discovery**: The `gemini` provider discovers and registers user skills from whatever Repo Nexus plugins are currently active.
