---
title: Monorepo Coexistence
description: How to orchestrate Turborepo, Nx, or Cargo monorepos alongside external independent repositories using Repo Nexus.
---

# Monorepo Coexistence

Many engineering teams operate an existing monorepo (such as Turborepo, Nx, or Cargo) for web applications, but maintain separate repositories for infrastructure (Terraform), mobile applications, or compliance tooling.

Repo Nexus seamlessly orchestrates monorepos alongside external repositories without invasive migrations.

---

## Architecture

```text
umbrella-workspace/
├── rnex.yaml
└── repos/
    ├── core-monorepo/          (Turborepo / Nx monorepo with 12 packages)
    │   ├── turbo.json
    │   ├── apps/
    │   └── packages/
    ├── terraform-infra/        (Autonomous infra repo -> infra.git)
    └── mobile-app/             (Autonomous Flutter / Swift repo -> mobile.git)
```

---

## Configuration (`rnex.yaml`)

```yaml
version: 0.8.0
repos_dir: ./repos
code_workspace: umbrella.code-workspace

repos:
  core-monorepo:
    url: git@github.com:my-org/core-monorepo.git
    branch: main
    enabled: true

  terraform-infra:
    url: git@github.com:my-org/terraform-infra.git
    branch: main
    enabled: true

  mobile-app:
    url: git@github.com:my-org/mobile-app.git
    branch: main
    enabled: true

plugins:
  claude:
    skills: true
```

---

## Managing Monorepo Commands

Repo Nexus does not replace monorepo build tools; it coordinates around them:

### Running Monorepo Builds
You can continue using standard Turborepo or Nx commands directly within the member clone:

```bash
cd repos/core-monorepo
pnpm turbo build
```

### Running Cross-Cutting Git Audits
Audit status across both the monorepo and external satellite repositories simultaneously:

```bash
rnex exec git status -s
```

### Selective AI Context
The `copilot` and `claude` plugins automatically mirror workspace instructions so that AI models understand when code lives inside the Turborepo packages vs the external mobile app.
