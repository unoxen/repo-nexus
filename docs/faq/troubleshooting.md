---
title: Troubleshooting
description: Practical troubleshooting guidance, resolving configuration drift, and migrating away from Git submodules.
---

# Troubleshooting

Practical diagnostic guidance and step-by-step solutions for everyday multi-repository scenarios.

---

## Troubleshooting Common Issues

### 1. "Configuration drift detected" or "Run rnex sync"
* **Cause**: `rnex.yaml` or `.local.rnex.yaml` was modified, but the workspace harness (`.rnex/`), AI instructions, or Git hook dispatchers have not been reconciled.
* **Solution**: Run `rnex sync` (or `rnex sync -y` to auto-confirm schema upgrades).

### 2. Search tools or AI assistants cannot find files inside `repos/`
* **Cause**: Some indexers respect `.gitignore` by default and skip `repos/`.
* **Solution**: Repo Nexus automatically generates `.ignore`, `.cursorignore`, and `.geminiignore` containing `!repos/*`. Run `rnex sync` to restore these un-ignore files.

### 3. A repository failed to clone during `rnex clone`
* **Cause**: SSH key authentication error or network interruption.
* **Solution**: Verify access via standard Git (`git ls-remote <url>`), then retry `rnex repo clone <name>` or `rnex clone`.

### 4. How do I temporarily disable a repository on my machine without affecting teammates?
* **Solution**: Run `rnex repo set <name> --disable --local`. This writes `enabled: false` into `.local.rnex.yaml` without touching the shared `rnex.yaml`.

---

## Migrating from Git Submodules to Repo Nexus

If your existing project uses Git submodules, migrating to Repo Nexus eliminates detached HEAD issues and pointer desynchronization:

### Step 1: De-register Existing Submodules
Inside your umbrella repository, de-register each submodule:

```bash
git submodule deinit -f --all
rm -rf .git/modules/*
git rm -f --cached <path/to/submodule>
rm -rf <path/to/submodule>
rm -f .gitmodules
git commit -m "chore: remove git submodules"
```

### Step 2: Initialize Repo Nexus
```bash
rnex init -y
```

### Step 3: Register Member Repositories
Add the repositories using their standard Git URLs:

```bash
rnex repo add git@github.com:my-org/backend.git --name backend
rnex repo add git@github.com:my-org/frontend.git --name frontend
```

### Step 4: Clone All Repositories
```bash
rnex clone
```

All repositories are now cloned into `./repos/` as independent Git repositories. No submodule pointers are tracked in the umbrella repository.
