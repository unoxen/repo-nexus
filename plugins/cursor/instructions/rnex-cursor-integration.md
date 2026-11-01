# Cursor IDE Integration for Repo Nexus

This workspace has the Repo Nexus `cursor` plugin enabled.

## Operating Principles
- **Cursor Rules (`.cursorrules` & `.cursor/rules/repo-nexus.mdc`)**: Synthesizes workspace routing protocol between `<!-- REPO-NEXUS:START -->` and `<!-- REPO-NEXUS:END -->`, supporting both legacy `.cursorrules` and modern Cursor MDC rules format (`alwaysApply: true`).
- **User Skills (`.cursor/rules/rnex-*.md`)**: Zero-logic user skill pointers linking directly to core skills (`.rnex/skills/`) and active plugins' skills (`.rnex/plugins/<name>/skills/`).
- **Codebase Indexing Un-Ignore (`.cursorignore`)**: Un-ignores member repositories (`!repos/*`) so Cursor's semantic indexing engine indexes code across member repositories, while workspace Git continues to ignore them.
- **Decoupled Cross-Plugin Discovery**: The `cursor` provider discovers and registers user skills from whatever Repo Nexus plugins are currently active.
