---
title: "Example: Automated LLM Wiki Setup | Meta Repo & Nexus Repository"
description: Concrete copy-pasteable setup for the LLM Wiki architecture in a Repo Nexus meta repository (meta repo) and nexus repository (nexus repo).
head:
  - - meta
    - name: keywords
      content: nexus repository, meta repository, nexus repo, meta repo, llm wiki, ai knowledge graph, rnex
---

# Automated LLM Wiki Setup

## Manifest (`rnex.yaml`)

```yaml
version: "1"
name: "research-wiki"
repos_dir: "./repos"

git:
  ignore:
    - "repos/"
    - "**/.rnex*"
    - "**/rnex*"
    - "!rnex.yaml"
    - "!**/rnex.yaml"
  hooks:
    pre-commit:
      - "rnex plugin llm-wiki lint"
    pre-push:
      - "rnex plugin llm-wiki lint --strict"

rnex_hooks:
  after_sync:
    - "rnex plugin llm-wiki ingest --quiet"

repos:
  core-engine:
    url: "git@github.com:acme/core-engine.git"
    branch: "main"
    enabled: true
    readonly: false

plugins:
  llm-wiki:
    wiki_dir: "wiki"
    sources:
      - "docs"
      - "specs"
      - "repos/**/README.md"
```

## Setup Sequence

```bash
# 1. Initialize workspace
rnex init -y

# 2. Add member repository
rnex repo add git@github.com:acme/core-engine.git --name core-engine

# 3. Enable LLM Wiki plugin
rnex plugin enable llm-wiki

# 4. Synchronize workspace to generate wiki/ templates and git hooks
rnex sync
```

## Wiki Ingest & Integrity Verification

```bash
# Ingest all intake sources and member repository documentation in place
rnex plugin llm-wiki ingest

# Ingest a specific research document or design spec in place
rnex plugin llm-wiki ingest specs/architecture.md
# Or using the --file flag
rnex plugin llm-wiki ingest --file specs/architecture.md

# Validate wiki structure, line budget, and zero-symlink invariants
rnex plugin llm-wiki lint
```

## Knowledge Base Navigation Architecture

The curated wiki maintains a deterministic flat B-Tree structure directly in `wiki/`:
- **`wiki/index.md`**: B-Tree Root Router ($\le 80$ lines) organizing flat leaf shards.
- **`wiki/repo-nexus*.md` & `wiki/repos-*.md`**: Flat lexicographically sorted leaf shards (`repo-nexus.md`, `repos-core-engine.md`) residing directly under `wiki/` with zero `_graph/` and zero `_index/` subdirectories.
- **`wiki/log.md`**: Chronological audit trail recording all ingest and lint operations.
- **In-Place Documentation**: Authoritative documents (`README.md`, `docs/*.md`, `repos/<member-repo>/**/*.md`) are indexed directly where they reside, with zero redundant copies and zero symbolic links.

> [!NOTE]
> Autonomous AI coding agents navigate this structure using the 3-step retrieval protocol: Root Router (`wiki/index.md`) $\to$ Leaf Shard (`wiki/<shard>.md`) $\to$ Target Source Document in place. Cross-references and backlinks are queried using standard workspace search tools (`grep`, `ripgrep`).
