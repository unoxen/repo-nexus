---
title: Fullstack Multi-Repo Workspace
description: Real-world example of structuring a fullstack architecture (frontend, API backend, shared contracts) with Repo Nexus.
---

# Fullstack Multi-Repo Workspace

A common modern architecture splits applications into dedicated repositories for frontend clients, backend APIs, and shared schemas or contracts. This example demonstrates configuring and managing this pattern using Repo Nexus.

---

## Workspace Architecture

```text
my-fullstack-app/
├── rnex.yaml
├── .local.rnex.yaml
├── workspace.code-workspace
└── repos/
    ├── web-client/        (React/Vite app -> git@github.com:my-org/web-client.git)
    ├── api-server/        (Go / Node microservice -> git@github.com:my-org/api-server.git)
    └── contracts/         (OpenAPI / Protocol Buffers -> git@github.com:my-org/contracts.git)
```

---

## Configuration (`rnex.yaml`)

```yaml
version: 0.5.13
repos_dir: ./repos
code_workspace: fullstack.code-workspace
git_hooks: true

repos:
  contracts:
    url: git@github.com:my-org/contracts.git
    branch: main
    enabled: true

  api-server:
    url: git@github.com:my-org/api-server.git
    branch: main
    enabled: true

  web-client:
    url: git@github.com:my-org/web-client.git
    branch: main
    enabled: true

plugins:
  claude:
    skills: true
  cursor:
    skills: true
```

---

## Step-by-Step Setup

### 1. Initialize and Register Repositories

```bash
# In an empty umbrella directory:
rnex init -y --code-workspace fullstack.code-workspace

# Register member repositories
rnex add contracts git@github.com:my-org/contracts.git
rnex add api-server git@github.com:my-org/api-server.git
rnex add web-client git@github.com:my-org/web-client.git
```

### 2. Open in VS Code or Cursor

Launch the unified multi-root workspace:

```bash
code fullstack.code-workspace
# or for Cursor:
cursor fullstack.code-workspace
```

Your file explorer will display all three repositories as primary roots, while language servers resolve imports across the workspace.

---

## Everyday Cross-Cutting Routines

### Pull Latest Changes Across All Services
```bash
rnex exec git pull --ff-only
```

### Re-Generate Shared Types / Contracts
```bash
# Generate types in contracts repo, then build backend and frontend
cd repos/contracts && npm run generate
rnex exec npm test
```
