#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/bin/lint.sh
# Architectural Layer: Plugin CLI Entrypoint (lint)
# Single Responsibility: Lint ONLY existing documentation and references inside
# .rnex/wiki/. Does NOT inspect rnex config `sources` and does NOT run ingestion.
#
# Design Patterns & Principles:
#   - Single Responsibility Principle (SRP): Confined strictly to read-only
#     structural and link verification. Zero compilation or mutation.
#   - Fail-Fast Principle: Exits with non-zero status on the first invariant failure.
#
# Standards: Pure POSIX Shell (/bin/sh), zero external runtime dependencies.
# =============================================================================

set -e

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=plugins/karpathy-llm/lib/utils.sh
. "${PLUGIN_ROOT}/lib/utils.sh"
# shellcheck source=plugins/karpathy-llm/lib/config.sh
. "${PLUGIN_ROOT}/lib/config.sh"
# shellcheck source=plugins/karpathy-llm/lib/source_helpers.sh
. "${PLUGIN_ROOT}/lib/source_helpers.sh"
# shellcheck source=plugins/karpathy-llm/lib/btree_helpers.sh
. "${PLUGIN_ROOT}/lib/btree_helpers.sh"
# shellcheck source=plugins/karpathy-llm/lib/lint_helpers.sh
. "${PLUGIN_ROOT}/lib/lint_helpers.sh"

# -----------------------------------------------------------------------------
# main_lint
# Summary: Entrypoint for the `rnex plugin karpathy-llm lint` CLI command.
#          Parses CLI arguments, loads configuration, and delegates to the
#          pure lint helper.
# @param $@: CLI arguments (--strict, --quiet/-q, --help/-h).
# @returns: 0 on successful validation; 1 on any structural or reference error.
# -----------------------------------------------------------------------------
main_lint() {
    _ws_root="${RNEX_WORKSPACE_ROOT:-${RNEX_ROOT:-$(pwd)}}"
    load_wiki_config_contract "$_ws_root" || exit 1

    _quiet=0
    _strict=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --strict)
                _strict=1
                shift
                ;;
            --quiet|-q)
                _quiet=1
                shift
                ;;
            --help|-h)
                printf 'Usage: rnex plugin karpathy-llm lint [--strict] [--quiet]\n'
                printf '\n'
                printf 'Validates existing wiki documentation, B-Tree shard links, and references.\n'
                printf 'Does not inspect workspace sources or trigger ingestion.\n'
                exit 0
                ;;
            -*)
                printf 'Error [lint]: Unknown option "%s".\n' "$1" >&2
                printf 'Usage: rnex plugin karpathy-llm lint [--strict] [--quiet]\n' >&2
                exit 1
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ "$_quiet" -eq 1 ]; then
        lint_existing_wiki_directory "$_strict" "$_quiet" >/dev/null
    else
        lint_existing_wiki_directory "$_strict" "$_quiet"
    fi
}

main_lint "$@"
