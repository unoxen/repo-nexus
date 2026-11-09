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

### 2. Search tools or AI assistants cannot find files inside configured repository directory (`<repos_dir>/`)
* **Cause**: Some indexers respect `.gitignore` by default and skip `<repos_dir>/` (default `repos/`).
* **Solution**: Repo Nexus automatically generates `.ignore`, `.cursorignore`, and `.geminiignore` containing `!<repos_dir>/*`. Run `rnex sync` to restore these un-ignore files.

### 3. A repository failed to clone during `rnex clone`
* **Cause**: SSH key authentication error or network interruption.
* **Solution**: Verify access via standard Git (`git ls-remote <url>`), then retry `rnex repo clone <name>` or `rnex clone`.

### 4. How do I temporarily disable a repository on my machine without affecting teammates?
* **Solution**: Run `rnex repo set <name> --disable --local`. This writes `enabled: false` into `.local.rnex.yaml` without touching the shared `rnex.yaml`.

### 5. Repository directory mismatch or unexpected clone location
* **Cause**: A custom `repos_dir` setting in `.local.rnex.yaml` overrides `rnex.yaml`, or a custom directory was provided during `rnex init --repos-dir <dir>`.
* **Solution**: Run `rnex status` to inspect active workspace configuration, and check `repos_dir:` in `.local.rnex.yaml` vs `rnex.yaml`.

### 6. `rnex exec` reports a non-zero exit code across member repositories
* **Cause**: `rnex exec <command...>` executes your command sequentially across all active, enabled repositories. It does not halt on the first error; instead, it runs through the full set of repositories, logs `[✓] <name> succeeded` or `[✗] <name> failed (exit <code>)` for each, and returns the exit code of the last failing repository.
* **Solution**: Inspect the console output to find which repository reported `[✗]`. Navigate into that repository (`cd repos/<name>`) to troubleshoot and resolve the issue, or temporarily disable the failing repository locally if it is not relevant to your current workflow (`rnex repo set <name> --disable --local`).

### 7. A member repository is skipped during `rnex clone` or `rnex exec`
* **Cause**: The repository is marked as disabled in your local `.local.rnex.yaml` or in the team manifest `rnex.yaml`.
* **Solution**: Run `rnex status` to view current repository states. Re-enable the repository using `rnex repo set <name> --enable --local` (or `--global`) and run `rnex sync`.

### 8. `rnex plugin karpathy-llm ingest <file>` reports path validation errors
* **Cause**: Single-file ingestion validates that the target argument is a valid, readable regular file (`[ -f ]` and `! -L`). It explicitly rejects non-existent paths, directories, and symbolic links.
* **Solution**: Pass an existing file path (e.g. `rnex plugin karpathy-llm ingest docs/spec.md` or `rnex plugin karpathy-llm ingest --file docs/spec.md`). To ingest all configured workspace sources, run `rnex plugin karpathy-llm ingest` with no arguments.

### 9. Legacy `_index.md`, `_graph/`, `_index/`, or `hot.md` in wiki directory
* **Cause**: The workspace was initialized using an older wiki layout version containing `_index.md`, `_graph/`, `_index/`, `hot.md`, or legacy category directories (`overview/`, `entities/`, `sources/`, `concepts/`, `repos/`).
* **Solution**: Run `rnex plugin karpathy-llm lint` (or `rnex plugin karpathy-llm ingest`). The automated routine purges obsolete legacy folders (`_graph/`, `_index/`, `concepts/`, `repos/`, `overview/`, `entities/`, `sources/`), purges legacy `hot.md` and `_index.md` files, migrates historical audit entries from `_log.md` to `log.md`, asserts zero symbolic links, compiles the bounded root router `.rnex/wiki/index.md` ($\le 80$ lines), and rebuilds the flat B-Tree leaf shards (`.rnex/wiki/repo-nexus*.md`, `.rnex/wiki/repos-*.md`).

### 10. Existing local Git hook was overwritten or not running
* **Cause**: Repo Nexus manages Git hooks via non-destructive wrapper scripts in `.git/hooks/`. When installing wrappers, any pre-existing custom hook script is automatically backed up to `<hook>.user` (e.g. `.git/hooks/pre-commit.user`) and invoked by the wrapper during Git operations.
* **Solution**: Verify that `.git/hooks/<hook>.user` exists and has executable permissions (`chmod +x .git/hooks/<hook>.user`).

### 11. `Permission denied` when running `./rnex`
* **Cause**: Git checkout or archive extraction may not have preserved executable file mode bits.
* **Solution**: Make the CLI entrypoint executable: `chmod +x ./rnex`.

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

All repositories are now cloned into your configured member repository directory (`<repos_dir>/`, default `./repos/`) as independent Git repositories. No submodule pointers are tracked in the umbrella repository.
