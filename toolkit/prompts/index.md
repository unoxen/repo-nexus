# Repo Nexus Prompts & Workflows Index

This catalog indexes standard operational prompts and agent workflows available in this workspace.
When an AI assistant is assigned a cross-repo or workspace-wide task, consult the relevant prompt below.

## Available Prompts & Workflows

1. **[`rnex-cross-repo-feature.md`](./rnex-cross-repo-feature.md)**
   - **Purpose**: End-to-end planning and execution of features spanning multiple member repositories.
   - **When to use**: Adding cross-cutting functionality, shared data contracts, API integrations, or multi-repo refactoring.

2. **[`rnex-workspace-audit.md`](./rnex-workspace-audit.md)**
   - **Purpose**: Cross-repository health, git status, branch tracking, and configuration validation.
   - **When to use**: Auditing workspace status, verifying uncommitted changes, or syncing member repositories before releases.

3. **[`rnex-ingest.md`](./rnex-ingest.md)** (alias: [`rnex-wiki-ingest.md`](./rnex-wiki-ingest.md))
   - **Purpose**: Autonomous ingestion of intake materials from configured raw intake directory into atomic Karpathy LLM Wiki pages.
   - **When to use**: Decomposing research papers, documentation, transcripts, or specifications into the knowledge base.

4. **[`rnex-lint.md`](./rnex-lint.md)** (alias: [`rnex-wiki-lint.md`](./rnex-wiki-lint.md))
   - **Purpose**: Deterministic graph audit, dead link validation, `mentioned_in` backlink reconciliation, and index rebuild.
   - **When to use**: Routine wiki maintenance, pre-commit validation, or after adding/renaming wiki pages.
