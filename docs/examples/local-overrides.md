---
title: Workstation Local Overrides
description: How to customize your local developer environment with .local.rnex.yaml without polluting team-wide configuration.
---

# Workstation Local Overrides

In large multi-repo workspaces, not every engineer needs all repositories cloned, nor do all developers use the same IDE. Repo Nexus solves this using `.local.rnex.yaml`.

---

## Scenario: Resource-Constrained Laptop

Your team's `rnex.yaml` declares 6 services including a heavy analytics pipeline and machine learning models. You are working exclusively on the frontend and user auth API.

### Creating `.local.rnex.yaml`

Create `.local.rnex.yaml` in your workspace root (it is gitignored automatically):

```yaml
repos:
  # Disable repositories you do not need
  ml-service:
    enabled: false
  analytics-pipeline:
    enabled: false
  big-data-spark:
    enabled: false

  # Pin your personal active branch for backend
  backend:
    branch: feature/auth-refactor

plugins:
  # Enable your personal editor preference
  cursor:
    rules: true
```

### Apply the Overrides

Run `rnex sync` to reconcile your local configuration:

```bash
rnex sync
```

```text
[rnex] Reconciling configuration...
[rnex] Loaded team configuration: rnex.yaml
[rnex] Applied local overrides: .local.rnex.yaml
[rnex] 3 repositories active, 3 disabled.
[rnex] Updated workspace.code-workspace.
```

---

## Toggling via CLI

You can also set local overrides directly from the CLI using the `--local` flag:

```bash
# Disable a repository locally
rnex repo set analytics-pipeline --disable --local

# Enable a personal plugin locally
rnex plugin enable --local gemini
```

Both commands update `.local.rnex.yaml`, leaving team-wide `rnex.yaml` completely untouched for Git commits.
