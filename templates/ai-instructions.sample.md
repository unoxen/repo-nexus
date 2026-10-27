# Repo Nexus Workspace Instructions (rnex v<version>)

> Reference sample only. `rnex sync` / `rnex init` generate `.rnex/ai-instructions.md` from the merged workspace configuration (`.local.rnex.yaml` > `rnex.yaml`); this file is not read at runtime.

## 1. Strict Operating Constraints
- **NO CONFIG READS**: DO NOT read or search for rnex.yaml or .local.rnex.yaml. The complete merged configuration is embedded in Section 2.
- **READ FILES ONCE**: Read each file at most once per session. Never re-read a file already in context.
- **NO BLIND SCANS**: Never run broad directory scans or unbounded searches across `repos/`.

## 2. Merged Workspace Configuration
- **Workspace**: `<name>`
- **Repositories Root**: `repos/`
- **Enabled Plugins**: `<plugin>`, ...

### Active Member Repositories
| Repository | Path | Branch | Mode | Description |
| :--- | :--- | :--- | :--- | :--- |
| `<repo>` | `repos/<repo>/` | `main` | `READ-WRITE` | <description> |

- **Disabled Repositories (Do Not Access)**: `<repo>`

## 3. Mandatory Execution Sequence
Execute these steps in strict order:
1. **Step 1 — Targeted Repository Access**: Inspect or modify only the specific files in active `repos/<name>/` required for the task. Never modify or commit inside `READ-ONLY` repositories.
2. **Step 2 — Git & Maintenance**: Commit and push inside `repos/<name>/`. Run `rnex sync` if workspace state changes.

## 4. Coding & Wiki Directives
- **Skills**: `.rnex/skills/` (load a skill only when its task applies).
