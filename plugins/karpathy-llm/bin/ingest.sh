#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/bin/ingest.sh
# Architectural Layer: Public Plugin CLI Command (ingest)
# Single Responsibility: Ingest workspace source documentation directly in place
# into wiki/_graph/*.tsv and wiki/_index/*.md with zero symlinks.
# =============================================================================

set -e

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=plugins/karpathy-llm/lib/config.sh
. "${PLUGIN_ROOT}/lib/config.sh"
# shellcheck source=plugins/karpathy-llm/lib/utils.sh
. "${PLUGIN_ROOT}/lib/utils.sh"
# shellcheck source=plugins/karpathy-llm/lib/source_helpers.sh
. "${PLUGIN_ROOT}/lib/source_helpers.sh"
# shellcheck source=plugins/karpathy-llm/lib/graph_helpers.sh
. "${PLUGIN_ROOT}/lib/graph_helpers.sh"
# shellcheck source=plugins/karpathy-llm/lib/btree_helpers.sh
. "${PLUGIN_ROOT}/lib/btree_helpers.sh"
# shellcheck source=plugins/karpathy-llm/lib/agent_query_helpers.sh
. "${PLUGIN_ROOT}/lib/agent_query_helpers.sh"

load_karpathy_wiki_config "${NEXUS_DIR:-${RNEX_ROOT:-${RNEX_WORKSPACE_ROOT:-$(pwd)}}}"

ensure_wiki_initialized

TARGET_FILE=""
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --file|-f|--source|-s)
            shift
            [ $# -gt 0 ] || { printf 'Error [ingest]: Missing argument for --file/--source\n' >&2; exit 1; }
            TARGET_FILE="$1"
            shift
            ;;
        --repo|-r)
            shift
            [ $# -gt 0 ] || { printf 'Error [ingest]: Missing argument for --repo\n' >&2; exit 1; }
            # Repo scope is parsed into target manifest
            shift
            ;;
        --quiet|-q)
            QUIET=1
            shift
            ;;
        --help|-h)
            printf 'Usage: rnex plugin karpathy-llm ingest [<file_path>] [--file <path>] [--quiet]\n'
            exit 0
            ;;
        -*)
            printf 'Error [ingest]: Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            TARGET_FILE="$1"
            shift
            ;;
    esac
done

if [ -n "$TARGET_FILE" ]; then
    if [ -d "$TARGET_FILE" ]; then
        printf 'Error [ingest]: Expected a file path, but "%s" is a directory.\n' "$TARGET_FILE" >&2
        exit 1
    fi
    if [ ! -f "$TARGET_FILE" ] || [ -L "$TARGET_FILE" ]; then
        printf 'Error [ingest]: Target file not found or is a symlink: %s\n' "$TARGET_FILE" >&2
        exit 1
    fi
    sync_wiki_indexes_and_graph "$TARGET_FILE"
    append_wiki_log_entry "ingest" "Ingested single source file \`${TARGET_FILE}\` in place."
    [ "$QUIET" = "1" ] || printf 'Successfully indexed %s into wiki.\n' "$TARGET_FILE"
    exit 0
fi

# Full configured sources indexing
sync_wiki_indexes_and_graph
_total="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_NODES_TSV" 2>/dev/null || printf '0')"
append_wiki_log_entry "ingest" "Indexed ${_total} configured source files across workspace in place."
[ "$QUIET" = "1" ] || printf 'Completed wiki ingest (%s sources indexed in place).\n' "$_total"
