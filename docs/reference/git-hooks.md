---
title: Git Hooks & Ignore Rules
description: Complete reference for git.hooks and git.ignore configuration, wrapper architecture, and .gitignore reconciliation.
---

# Git Hooks & Ignore Rules

Repo Nexus manages Git integration through the declarative `git:` block in `rnex.yaml` and `.local.rnex.yaml`.

---

## Configuration Schema

```yaml
git:
  ignore:
    - "repos/"
    - "**/.rnex*/"
    - "**/rnex*/"
    - "*.log"
    - ".env.local"
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

---

## Git Ignore Management (`git.ignore`)

During `rnex init` and `rnex sync`, Repo Nexus deterministically reconciles `.gitignore`:

1. **Deterministic Recursive Patterns**:
   Generated runtime assets are ignored recursively across all directories using trailing-slash directory patterns:
   * `**/.rnex*/`
   * `**/rnex*/`
   * `repos/`

   ::: tip Trailing Slashes Protect Root Executables
   Because the patterns explicitly end with `/`, Git matches only directories. The root CLI binary `rnex` and configuration files `rnex.yaml` or `.local.rnex.yaml` are never ignored.
   :::

2. **Custom Patterns**:
   Any patterns defined in `git.ignore` (in either `rnex.yaml` or `.local.rnex.yaml`) are appended to `.gitignore`.

3. **Search Tool Un-Ignore (`.ignore`)**:
   Repo Nexus maintains `.ignore` (and `.cursorignore`, `.geminiignore`) with `!repos/*` so search tools (ripgrep) and AI indexers can navigate member code without Git tracking.

---

## Git Hooks Architecture (`git.hooks`)

### Hook Wrappers (`.git/hooks/*`)
When `git.hooks` is configured, `rnex sync` installs lightweight executable POSIX shell wrappers in `.git/hooks/` (e.g. `.git/hooks/post-merge`, `.git/hooks/pre-commit`).

Each wrapper:
1. Sources `rnex` configuration and libraries.
2. Reads the command list from `git.hooks.<hook-name>` (prioritizing `.local.rnex.yaml` over `rnex.yaml`).
3. Executes each command sequentially, failing fast if any command returns a non-zero exit code.
4. Chains to existing pre-existing Git hooks or `scripts/githooks/` if present.

### Two-Level Precedence
* **Team Defaults**: Configured in `rnex.yaml`.
* **Workstation Overrides**: Defined in `.local.rnex.yaml`. If `.local.rnex.yaml` contains `git.hooks.<hook-name>`, its command list takes precedence on that machine.
