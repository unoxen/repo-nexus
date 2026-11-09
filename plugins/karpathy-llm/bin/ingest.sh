#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/bin/ingest.sh
# Architectural Layer: Plugin CLI Entrypoint (ingest)
# Single Responsibility: Ingest ONLY missing Markdown documentation sources into
# the encapsulated .rnex/wiki/ B-Tree store.
#
# Constraints & Principles:
#   - Single Responsibility Principle (SRP): Confined strictly to missing-source
#     ingestion. Performs zero linting or graph operations.
#   - Idempotency & Missing-Only: Never overwrites already-indexed sources;
#     processes only missing sources discovered via CLI argument or configured
#     sources in .local.rnex.yaml / rnex.yaml.
#   - POSIX Compliance: Standard /bin/sh syntax without bashisms.
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

main_ingest() {
    _ws_root="${RNEX_WORKSPACE_ROOT:-${RNEX_ROOT:-$(pwd)}}"
    load_wiki_config_contract "$_ws_root" || exit 1

    _source_arg=""
    _quiet=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --file|-f|--source|-s)
                shift
                _source_arg="${1:-}"
                if [ -z "$_source_arg" ]; then
                    printf 'Error [ingest]: Missing path argument after flag.\n' >&2
                    exit 1
                fi
                shift
                ;;
            --repo|-r)
                # Accepted for backwards compatibility
                shift
                [ $# -gt 0 ] && shift
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
                printf 'Usage: rnex plugin karpathy-llm ingest [<source_path>] [--file <path>] [--rewrite-links] [--strip-links] [--quiet]\n'
                exit 0
                ;;
            -*)
                printf 'Error [ingest]: Unknown option "%s". Usage: rnex plugin karpathy-llm ingest [<source_path>]\n' "$1" >&2
                exit 1
                ;;
            *)
                _source_arg="$1"
                shift
                ;;
        esac
    done

    mkdir -p "$RNEX_WIKI_ROOT"
    _missing_manifest="${RNEX_WIKI_ROOT}/.missing_sources.$$"
    if ! resolve_missing_sources_to_ingest "$_source_arg" "$_missing_manifest"; then
        rm -f "$_missing_manifest"
        exit 1
    fi

    if [ "$_quiet" -eq 1 ]; then
        ingest_missing_sources_into_btree "$_missing_manifest" "$_source_arg" >/dev/null
    else
        ingest_missing_sources_into_btree "$_missing_manifest" "$_source_arg"
    fi
    _rc=$?
    rm -f "$_missing_manifest"
    exit "$_rc"
}

main_ingest "$@"
