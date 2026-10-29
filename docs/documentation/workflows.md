---
title: Workflows & Automation
description: Master everyday multi-repo routines, batch execution with rnex exec, automated Git hooks, and CI/CD pipeline integration.
---

# Workflows & Automation

This guide covers practical routines for daily engineering, cross-repository task execution, Git hook automation, and CI/CD integration using Repo Nexus.

## Developer Onboarding

Onboarding a new developer onto a multi-repo workspace requires only two commands:

```bash
# 1. Clone the meta-repo
git clone git@github.com:my-org/developer-workspace.git
cd developer-workspace

# 2. Clone all member repositories declared in rnex.yaml
rnex clone
```

All member repositories are automatically cloned into `<repos_dir>/` (default `./repos/`), plugins are synchronized, and multi-root workspace files are prepared.

---

## Batch Execution with `rnex exec`

The `rnex exec` command runs arbitrary shell commands sequentially across every active member repository in `<repos_dir>/` (default `./repos/`).

### Checking Git Status Across All Repositories

```bash
rnex exec git status -s
```

```text
==> [backend] (./repos/backend)
 M src/api/auth.ts
?? tests/auth_test.ts

==> [frontend] (./repos/frontend)
On branch main (working tree clean)
```

### Pulling Latest Changes Everywhere

```bash
rnex exec git pull --ff-only
```

### Running Test Suites Sequentially

```bash
rnex exec npm test
```

::: tip Exit Code Bubbling
If a command fails in any repository, `rnex exec` exits immediately with that command's non-zero exit code and displays the failing repository, halting downstream execution unless explicitly handled.
:::

---

## Git Hooks Automation

Repo Nexus configures Git hooks declaratively through the `git.hooks` block in `rnex.yaml` (with optional workstation-specific overrides in `.local.rnex.yaml`). Dispatcher wrappers in `.git/hooks/` are installed and kept in sync automatically during `rnex init` and `rnex sync`.

### Configuration

```yaml
git:
  hooks:
    post-merge:
      - "rnex sync --quiet"
    post-checkout:
      - "rnex sync --quiet"
    pre-commit:
      - "rnex plugin karpathy-llm lint"
    pre-push:
      - "rnex plugin karpathy-llm lint --strict"
```

### Automated Lifecycle Events
1. **`post-merge`**: When you pull updates to the meta-repo (`git pull`), the hook automatically executes `rnex sync --quiet` if `rnex.yaml` changed, reconciling repositories, instructions, and plugins.
2. **`post-checkout`**: Ensures workspace state reflects branch transitions.
3. **`pre-commit` & `pre-push`**: Run automated verifications before commits or pushes, such as `rnex plugin karpathy-llm lint`.

---

## Single-Repository Operations (`rnex repo`)

Manage individual member repositories without affecting the rest of the workspace:

```bash
# Add a new repository
rnex repo add git@github.com:my-org/analytics.git --name analytics --branch v1

# Toggle state locally or globally
rnex repo set analytics --disable --local
rnex repo set analytics --readonly --global

# Inspect status of a single repository
rnex repo status analytics

# Execute a command in a single repository
rnex repo exec analytics npm run build

# Remove a repository
rnex repo remove analytics --purge
```
