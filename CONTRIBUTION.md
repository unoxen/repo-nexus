# Contributing to Repo Nexus (`rnex`)

Thank you for your interest in contributing to **Repo Nexus**! We welcome contributions that maintain the simplicity, performance, and purity of our zero-dependency Virtual Meta-Repo architecture.

---

## 1. Architecture & Coding Standards

### Pure POSIX Shell Compliance
- All executable code in `./rnex`, `lib/*.sh`, `lib/commands/*.sh`, `scripts/`, `tests/`, and plugin hooks must be strictly **POSIX `/bin/sh` compliant**.
- **Zero Runtime Dependencies**: Never introduce dependencies on external interpreters (Python, Node.js, Ruby, Go) or non-standard binaries. Rely only on standard POSIX system utilities (`awk`, `sed`, `grep`, `cat`, `mkdir`, `cp`, `rm`, `cksum`, `git`).
- Avoid bashisms (such as `[[ ... ]]`, `function foo()`, arrays `arr=(...)`, `<<<`, `source`, `export VAR=val` on non-POSIX shells, or `${var//pattern/replace}`).
- Scripts must explicitly include the POSIX shebang and shellcheck header:
  ```sh
  #!/bin/sh
  # shellcheck shell=sh
  ```

### ShellCheck Linting
All shell scripts must pass [ShellCheck](https://www.shellcheck.net/) with **zero warnings**:
- **SC2016 (Quoting in single quotes)**: Ensure variables intended for literal output in scripts/heredocs are intentionally quoted, or use double quotes when expansion is expected.
- **SC2129 (Multiple redirections)**: Group consecutive redirections into a single block:
  ```sh
  # Correct (SC2129 compliant):
  {
    printf 'Header\n'
    cat "$body_file"
    printf 'Footer\n'
  } > "$output_file"
  ```
- **SC2115 (Guarded deletion)**: Always guard variable expansions in recursive removals (`rm -rf "${var:?}/subdir"`).
- Run ShellCheck before submitting your pull request:
  ```sh
  shellcheck -s sh rnex lib/*.sh lib/commands/*.sh scripts/*.sh tests/*.sh
  ```

### Strict Encapsulation & Agnostic Core
- **Encapsulation**: All internal state, compiled context, sync stamps, and installed hooks must reside exclusively in `.rnex/` at the workspace root, or `repos/<name>/.rnex/` within member repositories. Never create or leave internal files in the workspace root or member repo source trees.
- **Agnostic Core**: The core `./rnex` binary and core libraries in `lib/` must remain **100% plugin-agnostic**. Never hardcode plugin names, provider-specific prompts, or domain-specific logic into `./rnex`. All domain extensions belong inside `toolkit/plugins/<name>/`.

---

## 2. Local Development & Testing Setup

### Maintainer Git Hooks
When developing Repo Nexus locally, enable the maintainer Git hooks located in `scripts/githooks/`:
```sh
git config core.hooksPath scripts/githooks
# or via npm:
npm run prepare
```
These maintainer hooks automatically:
- Verify staged commits and ShellCheck compliance.
- Detect version bumps in `package.json` upon commit and generate the matching annotated Git tag (`vX.Y.Z`) automatically via `scripts/githooks/post-commit`.

### Running the Test Suite
Before opening a pull request, run the full automated CLI test suite:
```sh
./tests/test_cli.sh
```
The test suite executes isolated end-to-end tests across all commands, plugins, Git hooks, two-level configurations, and auto-sync behaviors.

You can also run individual modular test suites located under `tests/suites/`:
```sh
# Run a specific suite by name or number prefix:
./tests/test_cli.sh 01
./tests/test_cli.sh 06
```

### Adding Tests for New Features
Whenever you add a new command, flag, or hook behavior:
1. Add corresponding test assertions to the relevant suite under `tests/suites/` (or create a new suite).
2. Verify that your tests pass locally via `./tests/test_cli.sh`.
3. Ensure CI passes on `.github/workflows/ci.yml`.

---

## 3. Authoring Plugins (`toolkit/plugins/<name>/`)

Plugins provide specialized agent guidelines, workflows, skills, subagents, and scaffolding templates.

### Directory Structure & Contract
```
toolkit/plugins/<name>/
├── plugin.yaml                  # Required: Plugin manifest & configuration schema
├── instructions.md              # Optional: Markdown context compiled into .rnex/ai-instructions.md
├── README.md                    # Optional: Plugin documentation & recipes
├── hooks/                       # Optional: Lifecycle & Git event hooks
│   ├── before_<cmd>.sh          # Executed before mutating command <cmd>
│   ├── after_<cmd>.sh           # Executed after mutating command <cmd>
│   ├── git_post-merge.sh        # Executed on Git post-merge events
│   └── git_pre-commit.sh        # Executed on Git pre-commit events
├── rules/                       # Optional: Coding rules (*.md)
├── skills/                      # Optional: Plugin-owned agentic skills (*.md)
├── agents/                      # Optional: Autonomous subagent declarations (*.agent.md)
└── templates/                   # Optional: Functional templates copied during rnex sync
```

### Plugin Manifest (`plugin.yaml`)
```yaml
name: my-plugin
version: 1.0.0
description: Organization guidelines, workflows, and automated hooks
author: Your Name <dev@example.com>
homepage: https://github.com/my-org/my-plugin
config:
  custom_option: default_value
templates:
  - templates/config.sample: .config-file
```

### Lifecycle Hooks Contract
Plugins can define executable POSIX `/bin/sh` scripts under `hooks/` to intercept mutating CLI commands:
- **Available Commands**: `init`, `install`, `add`, `clone`, `exec`, `remove`, `enable`, `disable`, `rnex-dir`, `sync`, `update`, `hooks`, `plugin`.
- Read-only commands (`status`, `list`, `completion`) bypass lifecycle hooks.
- **Hook Environment Variables**:
  - `RNEX_ROOT`: Absolute path to the workspace root.
  - `RNEX_CONFIG_MERGED`: Path to the merged `rnex.yaml`.
  - `RNEX_PLUGIN_DIR`: Path to the active plugin directory (`.rnex/plugins/<name>/`).
  - `RNEX_CMD`: Name of the command being executed.
  - `RNEX_ARGS`: Arguments passed to the command.
  - `RNEX_QUIET`: Set to `1` if `--quiet` / `-q` is active, otherwise `0`.

### AI Instructions Fragment (`instructions.md`)
If provided, `instructions.md` is automatically concatenated into `.rnex/ai-instructions.md` during `rnex sync` whenever the plugin is enabled.

---

## 4. Authoring Skills (Two-Tier Skills Architecture)

Repo Nexus enforces strict separation of skill ownership across two tiers:

### 1. Core Workspace Agentic Skills (`toolkit/skills/`)
Core skills provide fundamental meta-repo workflows and workspace automation:
- Placed directly in `toolkit/skills/<skill-name>.md` (e.g. `clone-sync.md`, `batch-exec.md`, `workspace-status.md`).
- During `rnex sync`, core skills are copied to `.rnex/skills/<skill-name>.md`.
- Never place plugin-specific skills in `toolkit/skills/` or `.rnex/skills/`.

### 2. Plugin-Owned Agentic Skills (`toolkit/plugins/<plugin>/skills/`)
Functional plugins encapsulate their own agentic skills:
- Placed in `toolkit/plugins/<plugin>/skills/<skill-name>.md` (e.g. `wiki-ingest.md`, `wiki-lint.md`).
- During `rnex sync`, copied exclusively to `.rnex/plugins/<plugin>/skills/<skill-name>.md`.

### 3. User Skill Generator & Plugin Contract API
- **Zero-Logic User Skills**: Generated on the fly in active AI provider directories (`.cursor/rules/`, `.claude/skills/`, `.gemini/skills/`, `.windsurf/rules/`) with mandatory `rnex-` prefix (`rnex-<skill-name>.md`). They contain zero operational instructions—only a direct reference link to the underlying agentic skill inside `.rnex/`.
- **Plugin Contract Helper Functions**:
  - `rnex_register_user_skill <skill_name> <target_path_in_rnex>`: Called in `after_sync.sh` to generate the User Skill pointer.
  - `rnex_unregister_user_skill <skill_name>`: Called in `before_plugin_disable.sh` to remove the User Skill pointer before plugin deactivation.

---

## 5. Commit Conventions & Release Process

### Conventional Commits
Commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:
- `feat:` New features or commands
- `fix:` Bug fixes
- `fix(tests):` Test suite fixes and adjustments
- `fix(lint):` Code style and ShellCheck lint fixes
- `feat(githooks):` Maintainer Git hooks enhancements
- `refactor:` Code refactoring without behavior changes
- `docs:` Documentation additions or updates
- `test:` Test additions or restructuring

### Versioning & Release Process
1. **Single Source of Truth**: `package.json` (`version` field) is the single version source of truth for the entire project.
2. When releasing a new version or changing CLI behavior:
   - Increment `version` in `package.json`.
   - Update `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/) standards.
   - Update `README.md` and `docs/CLI.md` if command syntax, flags, or configuration options changed.
   - Committing the bumped `package.json` with the maintainer hooks enabled will automatically create the corresponding Git tag `vX.Y.Z`.
