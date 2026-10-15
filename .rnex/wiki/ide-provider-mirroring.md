---
title: "IDE Provider Prompts & Instructions Mirroring"
tags: [ide, providers, claude, cursor, copilot, gemini, windsurf]
last_updated: 2026-10-15
sources: ["docs/plugins/claude.md", "docs/plugins/copilot.md", "docs/plugins/cursor.md", "docs/plugins/gemini.md", "docs/plugins/windsurf.md"]
related: ["plugin-system.md", "context-engineering.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# IDE Provider Prompts & Instructions Mirroring

## Summary
Repo Nexus integrates with leading AI developer tools by mirroring operational prompts, workflows, and instructions into tool-native directory structures while maintaining `.rnex/` as the single source of truth.

## Key Facts & Insights
* **Supported AI Providers:**
  - **Claude Code**: `.claude/commands/` and `.claude/prompts/`
  - **GitHub Copilot**: `.github/prompts/*.prompt.md`
  - **Cursor**: `.cursor/prompts/*.md` and `.cursorrules`
  - **Gemini Code Assist**: `.gemini/prompts/*.prompt.md` and `GEMINI.md`
  - **Windsurf**: `.windsurf/prompts/*.md` and `.windsurfrules`
* **Autonomous Synchronization:** `rnex sync` reconciles active provider directories based on configuration options (`prompts: true`, `instructions: true`).
* **Zero Leakage:** When an AI provider plugin is disabled, all mirrored prompts and command files are purged cleanly.

## Contextual Links
* See [Context Engineering](./context-engineering.md) for workspace routing directives.
* See [Plugin Architecture](./plugin-system.md) for provider plugin specifications.
