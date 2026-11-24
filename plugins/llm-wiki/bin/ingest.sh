#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/llm-wiki/bin/ingest.sh
# Architectural Layer: Plugin CLI Entrypoint (ingest)
# Single Responsibility: Ingest Markdown documentation sources into the
# encapsulated .rnex/wiki/ B-Tree store.
#
# Constraints & Principles:
#   - Single Responsibility Principle (SRP): Confined strictly to source
#     ingestion. Performs zero linting or graph operations.
#   - Strategy Pattern: By default ingests ONLY missing sources (preserving
#     existing entries). With `--force` (`-f`), re-indexes existing entries
#     matched by the positional path or configured sources.
#   - POSIX Compliance: Standard /bin/sh syntax without bashisms.
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

# -----------------------------------------------------------------------------
# main_ingest
# Summary: Entrypoint for the `rnex plugin llm-wiki ingest` CLI command.
#          Parses CLI arguments, loads the wiki configuration contract,
#          resolves missing (or forced candidate) source files from a
#          positional file/directory/glob path or configured sources, and
#          ingests them into B-Tree shards.
# @param $@: CLI arguments ([<source_path>], --force/-f, --rewrite-links,
#            --strip-links, --quiet/-q, --help/-h).
# @returns: 0 on successful ingestion; 1 on configuration or source error.
# @sideEffects: Mutates configured wikiDir shards, indexFile, and logFile.
# -----------------------------------------------------------------------------
main_ingest() {
    _ws_root="${RNEX_WORKSPACE_ROOT:-${RNEX_ROOT:-$(pwd)}}"
    load_wiki_config_contract "$_ws_root" || exit 1

    _source_arg=""
    _force=0
    _quiet=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f)
                _force=1
                shift
                ;;
            --quiet|-q)
                _quiet=1
                shift
                ;;
            --rewrite-links)
                RNEX_WIKI_RELATIVE_LINKS="rewrite"
                export RNEX_WIKI_RELATIVE_LINKS
                shift
                ;;
            --strip-links|--delete-links)
                RNEX_WIKI_RELATIVE_LINKS="strip"
                export RNEX_WIKI_RELATIVE_LINKS
                shift
                ;;
            --help|-h)
                printf 'Usage: rnex plugin llm-wiki ingest [<source_path>] [--force|-f] [--rewrite-links] [--strip-links] [--quiet|-q]\n'
                exit 0
                ;;
            -*)
                printf 'Error [ingest]: Unknown option "%s". Usage: rnex plugin llm-wiki ingest [<source_path>] [--force|-f] [--rewrite-links] [--strip-links] [--quiet|-q]\n' "$1" >&2
                exit 1
                ;;
            *)
                if [ -n "$_source_arg" ]; then
                    printf 'Error [ingest]: Unexpected extra argument "%s". Pass at most one <source_path>.\n' "$1" >&2
                    exit 1
                fi
                _source_arg="$1"
                shift
                ;;
        esac
    done

    mkdir -p "$RNEX_WIKI_ROOT"
    _manifest="${RNEX_WIKI_ROOT}/.ingest_sources.$$"
    trap 'rm -f "$_manifest"' EXIT INT TERM
    _rc=0
    if [ "$_force" -eq 1 ]; then
        if ! resolve_candidate_sources "$_source_arg" "$_manifest"; then
            rm -f "$_manifest"
            exit 1
        fi
        if [ "$_quiet" -eq 1 ]; then
            force_reingest_sources_into_btree "$_manifest" "$_source_arg" >/dev/null || _rc=$?
        else
            force_reingest_sources_into_btree "$_manifest" "$_source_arg" || _rc=$?
        fi
    else
        if ! resolve_missing_sources_to_ingest "$_source_arg" "$_manifest"; then
            rm -f "$_manifest"
            exit 1
        fi
        if [ "$_quiet" -eq 1 ]; then
            ingest_missing_sources_into_btree "$_manifest" "$_source_arg" >/dev/null || _rc=$?
        else
            ingest_missing_sources_into_btree "$_manifest" "$_source_arg" || _rc=$?
        fi
    fi
    rm -f "$_manifest"
    exit "$_rc"
}

main_ingest "$@"
