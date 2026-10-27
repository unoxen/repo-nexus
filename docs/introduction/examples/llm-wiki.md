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

## Wiki Ingest & Lint Operations

```bash
# Ingest all intake sources and member repository READMEs
rnex plugin karpathy-llm ingest

# Ingest a specific research document or design spec
rnex plugin karpathy-llm ingest --source specs/architecture.md

# Validate wiki schema, link integrity, and bounded word counts
rnex plugin karpathy-llm lint

# Run strict verification before release
rnex plugin karpathy-llm lint --strict
```
