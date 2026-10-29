# Agent Instructions: Repo Nexus (`rnex`)

Instructions and operational constraints for AI agents working within the `repo-nexus` codebase.

## 1. Core Constraints & Coding Standards
- **Pure POSIX `/bin/sh` Best Practices**: All shell code in `./rnex`, `lib/`, `scripts/`, and `tests/` must adhere strictly to POSIX-compliant standards and best practices. Never use bashisms (no `[[ ... ]]`, `function foo()`, arrays `arr=(...)`, `<<<`, or `${var//pat/replace}`). Quote expansions reliably, guard variable deletions (`rm -rf "${var:?}/..."`), and adhere to ShellCheck clean idioms.
- **Zero Runtime Dependencies**: No runtime dependencies on Node.js, Python, or external binaries. Rely solely on standard POSIX utilities (`awk`, `sed`, `grep`, `cat`, `mkdir`, `cp`, `rm`, `cksum`, `git`).
- **DRY & Reusable Utilities**: Strictly avoid copy-paste. Implement solutions by extracting reusable helpers, library functions, and shared utilities into `lib/`.
- **Modularity, Contracts & Loose Coupling**: Keep the codebase modular with minimal hard coupling between components. Work through well-defined contracts and open interfaces, applying established design patterns.
- **Plugin-Agnostic Core**: The core CLI (`./rnex`) and `lib/` must remain completely vendor- and plugin-agnostic. Provider- and domain-specific integrations belong in `toolkit/plugins/<name>/`.
- **Strict Encapsulation**: Internal state, generated caches, and sync metadata must reside strictly within `.rnex/`. Member repositories remain 100% clean and untouched with zero `.rnex/` folders inside member trees. Never pollute the repository root or member repository trees.

## 2. Testing & Verification Workflow
Before proposing or committing changes:
- **Linting**: Ensure shell scripts comply with ShellCheck:
  ```sh
  shellcheck -s sh rnex lib/*.sh lib/commands/*.sh scripts/*.sh tests/*.sh
  ```
- **CLI Test Suite**: Run the automated test suite to ensure tests pass:
  ```sh
  ./tests/test_cli.sh           # Run entire test suite
  ./tests/test_cli.sh <suite>    # Run specific suite (e.g., ./tests/test_cli.sh 01)
  ```
- **Documentation**: When updating docs or specs, verify the VitePress build:
  ```sh
  npm run docs:build
  ```
