# Agentic Skill: wiki-query

Query and retrieve curated workspace knowledge using the flat Karpathy LLM Wiki B-Tree index.

---

## Capabilities & Context

Use this skill when answering questions about the architecture, services, components, and workflows in the Repo Nexus workspace with zero token bloat.

## Agent Context Retrieval Protocol

AI coding agents navigate wiki context using the 3-step zero-token-bloat protocol:
1. **Root Router:** Read `.rnex/wiki/index.md` ($\le 80$ lines) to locate the relevant shard file (`.rnex/wiki/repo-nexus*.md` or `.rnex/wiki/repos-<member>*.md`).
2. **Shard Read:** Read the target shard directly in `.rnex/wiki/` to find the exact workspace file path and summary.
3. **In-Place Access:** Open the authoritative source file directly in place. To locate cross-references or backlinks, use native workspace search tools (`grep`, `ripgrep`).

## Rules

- Never guess file paths; consult `.rnex/wiki/index.md` first.
- Only load the single leaf shard needed for your query.
- Read source documents in place without copying them into the wiki.
