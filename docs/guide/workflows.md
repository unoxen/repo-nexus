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

All member repositories are automatically cloned into `./repos/`, plugins are synchronized, and multi-root workspace files are prepared.

---

## Batch Execution with `rnex exec`

The `rnex exec` command runs arbitrary shell commands sequentially across every active member repository in `./repos/`.

### Checking Git Status Across All Repositories

```bash
rnex exec git status -s
```

```text
=== [backend] ===
 M src/api/auth.ts
?? tests/auth_test.ts

=== [frontend] ===
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
    pre-push: []
```

### Automated Lifecycle Events
1. **`post-merge`**: When you pull updates to the meta-repo (`git pull`), the hook automatically executes `rnex sync --quiet` if `rnex.yaml` changed, reconciling repositories, instructions, and plugins.
2. **`post-checkout`**: Ensures workspace state reflects branch transitions.
3. **`pre-commit` & `pre-push`**: Run automated verifications before commits or pushes, such as `rnex plugin karpathy-llm lint`.

---

## CI/CD Integration

Repo Nexus integrates cleanly into GitHub Actions, GitLab CI, or CircleCI pipelines.

### Example: Running Cross-Repo Lints in GitHub Actions

```yaml
name: Workspace Lint

on:
  pull_request:
    branches: [ main ]

jobs:
  lint-all:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Meta-Repo
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 22

      - name: Install Repo Nexus
        run: npm install -g repo-nexus

      - name: Clone Shallow Repositories
        run: rnex clone

      - name: Run Linters Across All Repos
        run: rnex exec npm run lint
```
