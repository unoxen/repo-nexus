---
title: "Example: Full-Stack AI Context Mirroring"
description: Concrete copy-pasteable setup for multi-provider AI context synchronization across frontend and backend repos.
---

# Full-Stack AI Context Mirroring

## Manifest (`rnex.yaml`)

```yaml
version: "1"
name: "fullstack-ai"
repos_dir: "./repos"
code_workspace: "fullstack.code-workspace"

git:
  ignore:
    - "repos/"
    - "**/.rnex*/"
    - "**/rnex*/"
  hooks:
    post-merge:
      - "rnex sync --quiet"

rnex_hooks:
  after_sync:
    - "echo 'AI context reconciled across all providers'"

repos:
  frontend:
    url: "git@github.com:acme/web-app.git"
    branch: "main"
    enabled: true
    readonly: false
  backend:
    url: "git@github.com:acme/api-core.git"
    branch: "main"
    enabled: true
    readonly: false

plugins:
  claude:
    skills: true
  cursor:
    skills: true
  codex:
    skills: true
```

## Setup Sequence

```bash
# 1. Initialize workspace with Claude, Cursor, and Codex support
rnex init -y --claude --cursor --codex --code-workspace fullstack.code-workspace

# 2. Add frontend and backend services
rnex repo add git@github.com:acme/web-app.git --name frontend
rnex repo add git@github.com:acme/api-core.git --name backend

# 3. Clone repositories
rnex clone

# 4. Synchronize AI routing blocks and proxy skills
rnex sync
```

## Verification

```bash
# Inspect generated routing rules and proxy skills
head -n 25 AGENTS.md
head -n 25 CLAUDE.md
head -n 25 CODEX.md

# Verify provider user skills
ls -la .claude/skills/
ls -la .cursor/rules/
ls -la .codex/skills/
```
