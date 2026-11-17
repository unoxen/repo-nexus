#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/llm-wiki/bin/lint.sh
# Architectural Layer: Plugin CLI Entrypoint (lint)
# Single Responsibility: Validate and auto-heal existing documentation and
# references inside .rnex/wiki/. Does NOT inspect rnex config `sources` and
# does NOT ingest missing documents.
#
# Design Patterns & Principles:
#   - Single Responsibility Principle (SRP): Confined strictly to existing
#     wiki verification and auto-healing. Zero missing-source ingestion.
#   - Strategy Pattern: Deep content validation by default (refreshes stale
#     entry titles and summaries from authoritative sources); `--shallow`
#     validates and heals links and B-Tree structure only without reading
#     document content.
#   - Fail-Fast Principle: Exits with non-zero status on unresolvable errors.
#
# Standards: Pure POSIX Shell (/bin/sh), zero external runtime dependencies.
# =============================================================================

set -e

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
case "$PLUGIN_ROOT" in
    */.rnex/plugins/llm-wiki)
        if [ -n "${RNEX_PLUGINS_DIR:-}" ] && [ -d "${RNEX_PLUGINS_DIR}/llm-wiki/lib" ]; then
            PLUGIN_ROOT="${RNEX_PLUGINS_DIR}/llm-wiki"
        fi
        ;;
esac

# shellcheck source=plugins/llm-wiki/lib/utils.sh
. "${PLUGIN_ROOT}/lib/utils.sh"
# shellcheck source=plugins/llm-wiki/lib/config.sh
. "${PLUGIN_ROOT}/lib/config.sh"
# shellcheck source=plugins/llm-wiki/lib/source_helpers.sh
. "${PLUGIN_ROOT}/lib/source_helpers.sh"
# shellcheck source=plugins/llm-wiki/lib/btree_helpers.sh
. "${PLUGIN_ROOT}/lib/btree_helpers.sh"
# shellcheck source=plugins/llm-wiki/lib/lint_helpers.sh
. "${PLUGIN_ROOT}/lib/lint_helpers.sh"

# -----------------------------------------------------------------------------
# main_lint
# Summary: Entrypoint for the `rnex plugin llm-wiki lint` CLI command.
#          Parses CLI arguments, loads configuration, and delegates to
#          lint_existing_wiki_directory.
# @param $@: CLI arguments (--shallow, --quiet/-q, --help/-h).
# @returns: 0 on successful validation/healing; 1 on any unresolvable error.
# -----------------------------------------------------------------------------
main_lint() {
    _ws_root="${RNEX_WORKSPACE_ROOT:-${RNEX_ROOT:-$(pwd)}}"
    load_wiki_config_contract "$_ws_root" || exit 1

    _shallow=0
    _quiet=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --shallow)
                _shallow=1
                shift
                ;;
            --quiet|-q)
                _quiet=1
                shift
                ;;
            --help|-h)
                printf 'Usage: rnex plugin llm-wiki lint [--shallow] [--quiet|-q]\n'
                printf '\n'
                printf 'Validates and auto-heals existing wiki documentation, headers, B-Tree shards, and references.\n'
                printf 'Use --shallow to validate only links and structure without reading source document content.\n'
                exit 0
                ;;
            -*)
                printf 'Error [lint]: Unknown option "%s".\n' "$1" >&2
                printf 'Usage: rnex plugin llm-wiki lint [--shallow] [--quiet|-q]\n' >&2
                exit 1
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ "$_quiet" -eq 1 ]; then
        lint_existing_wiki_directory "$_shallow" "$_quiet" >/dev/null
    else
        lint_existing_wiki_directory "$_shallow" "$_quiet"
    fi
}

main_lint "$@"
