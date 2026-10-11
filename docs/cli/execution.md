---
title: Batch Execution (rnex exec)
description: Master sequential multi-repo task automation with rnex exec, argument escaping, and exit code bubbling.
---

# Batch Execution (`rnex exec`)

`rnex exec` runs arbitrary shell commands sequentially across every active (enabled) member repository in `./repos/`.

---

## Syntax

```sh
rnex exec <command...>
```

Repo Nexus automatically navigates into each enabled repository directory (`./repos/<name>`), runs the command in a subshell, prefixes output with repository headings, and checks exit codes.

---

## Behavior & Execution Model

### Sequential Execution
Commands execute one repository at a time in the order declared in `rnex.yaml`. This ensures predictable output logs and avoids parallel resource contention during intensive builds or test suites.

### Exit Code Bubbling
If a command produces a non-zero exit code in any member repository:
1. `rnex exec` immediately prints an error header highlighting the failed repository.
2. Downstream repositories are aborted.
3. `rnex exec` exits with the failed command's exit code (`exit 1` or specific error code).

::: tip Continuous Execution
To continue through repositories regardless of errors, chain with a shell fallback:
```bash
rnex exec sh -c "npm test || true"
```
:::

---

## Common Use Cases & Examples

### 1. Multi-Repo Git Status

Inspect working tree changes across all repositories:

```bash
rnex exec git status -s
```

```text
=== [backend] ===
 M src/routes.ts
?? test/new-test.ts

=== [frontend] ===
On branch main (working tree clean)
```

### 2. Fast-Forward Pull Across Repositories

Pull upstream changes cleanly:

```bash
rnex exec git pull --ff-only
```

### 3. Running Lints or Formatting

```bash
rnex exec npm run lint
```

### 4. Running Custom Shell Pipelines

For commands involving pipes, redirects, or complex variables, invoke them inside `sh -c`:

```bash
rnex exec sh -c "git branch --show-current && git log -1 --oneline"
```
