---
title: "Example: Selective Checkout & Read-Only Contracts"
description: Concrete copy-pasteable setup for local machine overrides, selective checkout, and read-only repositories.
---

# Selective Checkout & Read-Only Contracts

## Team Manifest (`rnex.yaml`)

```yaml
version: "1"
name: "distributed-platform"
repos_dir: "./repos"

git:
  ignore:
    - "repos/"
    - "**/.rnex*/"
    - "**/rnex*/"

repos:
  frontend:
    url: "git@github.com:acme/web-app.git"
    branch: "main"
    enabled: true
    readonly: false
  auth-api:
    url: "git@github.com:acme/auth-api.git"
    branch: "main"
    enabled: true
    readonly: false
  payment-api:
    url: "git@github.com:acme/payment-api.git"
    branch: "main"
    enabled: true
    readonly: false
  contracts:
    url: "git@github.com:acme/contracts.git"
    branch: "v2"
    enabled: true
    readonly: true
```

## Machine Overrides (`.local.rnex.yaml`)

```yaml
repos:
  payment-api:
    enabled: false
  auth-api:
    enabled: false
```

## Setup Sequence

```bash
# 1. Initialize workspace
rnex init -y

# 2. Disable payment-api locally on this machine
rnex repo set payment-api --disable --local

# 3. Mark contracts repository as read-only
rnex repo set contracts --readonly --global

# 4. Clone only enabled repositories (skips payment-api and auth-api)
rnex clone

# 5. Check status to confirm local overrides
rnex status
```

## Status Verification

```text
Member Repositories:
  ● frontend           [main] git@github.com:acme/web-app.git
  ● contracts          [v2] [readonly] git@github.com:acme/contracts.git
  ○ auth-api           [disabled] - git@github.com:acme/auth-api.git
  ○ payment-api        [disabled] - git@github.com:acme/payment-api.git
```
