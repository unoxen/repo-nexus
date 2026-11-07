---
title: "Example: Automated Karpathy LLM Wiki Setup | Meta Repo & Nexus Repository"
description: Concrete copy-pasteable setup for Andrej Karpathy's LLM Wiki architecture in a Repo Nexus meta repository (meta repo) and nexus repository (nexus repo).
head:
  - - meta
    - name: keywords
      content: nexus repository, meta repository, nexus repo, meta repo, karpathy llm wiki, ai knowledge graph, rnex
---

# Automated Karpathy LLM Wiki Setup

## Manifest (`rnex.yaml`)

```yaml
version: "1"
name: "research-wiki"
repos_dir: "./repos"

git:
  ignore:
    - "repos/"
    - "**/.rnex*/"
    - "**/rnex*/"
  hooks:
    pre-commit:
      - "rnex plugin karpathy-llm lint"
    pre-push:
      - "rnex plugin karpathy-llm lint --strict"

rnex_hooks:
  after_sync:
    - "rnex plugin karpathy-llm ingest --quiet"

repos:
  core-engine:
    url: "git@github.com:acme/core-engine.git"
    branch: "main"
    enabled: true
    readonly: false

plugins:
  karpathy-llm:
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

# 3. Enable Karpathy LLM Wiki plugin
rnex plugin enable karpathy-llm

# 4. Synchronize workspace to generate wiki/ templates and git hooks
rnex sync
```

## Wiki Ingest & Integrity Verification

```bash
# Ingest all intake sources and member repository READMEs (automatically builds index and graph)
rnex plugin karpathy-llm ingest

# Ingest a specific research document or design spec in place
rnex plugin karpathy-llm ingest --source specs/architecture.md

# Ingest a specific member repository README
rnex plugin karpathy-llm ingest --repo core-engine

# Validate wiki schema, sort invariants, and wikilink integrity
rnex plugin karpathy-llm lint

# Run strict verification before release or in CI/CD pre-push hooks
rnex plugin karpathy-llm lint --strict
```

## Knowledge Base Navigation Architecture

The curated wiki maintains a deterministic 2-level B-Tree and graph structure:
- **`wiki/_index.md`**: B-Tree Root Router ($\le 80$ lines) organizing index shards.
- **`wiki/_index/`**: Lexicographically sorted leaf shards (`repo-nexus.md`, `repos-core-engine.md`).
- **`wiki/_graph/`**: Sorted TSV property graph (`nodes.tsv`, `edges_out.tsv`, `edges_in.tsv`) supporting fast $O(\log N)$ traversal.
- **In-Place Documentation**: Authoritative documents (`README.md`, `docs/*.md`, `repos/<member-repo>/**/*.md`) are indexed directly where they reside, with zero redundant copies and zero symbolic links.

> [!NOTE]
> Autonomous AI coding agents navigate this structure using internal binary search lookup (`_search`) and ego-subgraph traversal (`_graph`) helpers without requiring manual indexing commands.
