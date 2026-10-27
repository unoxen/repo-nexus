---
title: "Example: Multi-Repo Microservices Setup | Meta Repo & Nexus Repository"
description: Concrete copy-pasteable meta repository (meta repo) and nexus repository (nexus repo) setup for multi-repo microservices architectures with Repo Nexus.
head:
  - - meta
    - name: keywords
      content: nexus repository, meta repository, nexus repo, meta repo, microservices, multi-repo architecture, rnex
---

# Multi-Repo Microservices Setup

## Manifest (`rnex.yaml`)

```yaml
version: "1"
name: "acme-microservices"
repos_dir: "./repos"
code_workspace: "microservices.code-workspace"

git:
  ignore:
    - "repos/"
    - "**/.rnex*/"
    - "**/rnex*/"
    - "*.log"
  hooks:
    post-merge:
      - "rnex sync --quiet"
    post-checkout:
      - "rnex sync --quiet"

rnex_hooks:
  after_clone:
    - "rnex exec make setup"
  after_sync:
    - "echo 'Workspace reconciled'"

repos:
  auth-service:
    url: "git@github.com:acme/auth-service.git"
    branch: "main"
    enabled: true
    readonly: false
  billing-service:
    url: "git@github.com:acme/billing-service.git"
    branch: "main"
    enabled: true
    readonly: false
  api-gateway:
    url: "git@github.com:acme/api-gateway.git"
    branch: "main"
    enabled: true
    readonly: false
  shared-contracts:
    url: "git@github.com:acme/shared-contracts.git"
    branch: "v2"
    enabled: true
    readonly: true

plugins:
  claude:
    skills: true
  cursor:
    skills: true
```

## Setup Sequence

```bash
# 1. Initialize workspace with multi-root workspace file
rnex init -y --code-workspace microservices.code-workspace

# 2. Add member repositories
rnex repo add git@github.com:acme/auth-service.git --name auth-service
rnex repo add git@github.com:acme/billing-service.git --name billing-service
rnex repo add git@github.com:acme/api-gateway.git --name api-gateway
rnex repo add git@github.com:acme/shared-contracts.git --name shared-contracts --readonly

# 3. Clone all member repositories
rnex clone

# 4. Check workspace status
rnex status
```

## Daily Operations

```bash
# Pull changes across all active services
rnex exec git pull --ff-only

# Run integration tests across all microservices
rnex exec make test

# Inspect Git status across all repositories
rnex exec git status -s
```
