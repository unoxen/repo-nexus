#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/bin/lint.sh
# Architectural Layer: Public Plugin CLI Command (lint)
# Single Responsibility: Auto-heal wiki structure, remove legacy artifacts,
# verify index line count bounds, and assert zero symlinks.
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
# shellcheck source=plugins/karpathy-llm/lib/btree_helpers.sh
. "${PLUGIN_ROOT}/lib/btree_helpers.sh"

load_karpathy_wiki_config "${RNEX_WORKSPACE_ROOT:-$(pwd)}"

QUIET=0
STRICT=0

while [ $# -gt 0 ]; do
    case "$1" in
        --strict)
            STRICT=1
            shift
            ;;
        --quiet|-q)
            QUIET=1
            shift
            ;;
        --help|-h)
            printf 'Usage: rnex plugin karpathy-llm lint [--strict] [--quiet]\n'
            exit 0
            ;;
        -*)
            shift
            ;;
        *)
            shift
            ;;
    esac
done

compile_flat_btree_wiki

# Invariant 1: Assert zero symlinks in wiki/
if [ -n "$(find "$RNEX_WIKI_ROOT" -type l 2>/dev/null)" ]; then
    printf 'Error [lint]: Found forbidden symbolic links in wiki directory.\n' >&2
    exit 1
fi

# Invariant 2: Assert no legacy _graph/ or _index/ directories
if [ -d "${RNEX_WIKI_ROOT}/_graph" ] || [ -d "${RNEX_WIKI_ROOT}/_index" ]; then
    printf 'Error [lint]: Found deprecated _graph/ or _index/ directories.\n' >&2
    exit 1
fi

# Invariant 3: Verify root router bounds (<= 80 lines)
_root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_INDEX_FILE" 2>/dev/null || printf '0')"
if [ "$_root_lines" -gt "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ]; then
    printf 'Error [lint]: wiki/index.md exceeds %s lines (%s lines)\n' \
        "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" "$_root_lines" >&2
    exit 1
fi

append_wiki_log_entry "lint" "Verified flat wiki B-Tree shards (0 symlinks, root is ${_root_lines} lines)."
[ "$QUIET" = "1" ] || printf 'Wiki lint passed: 0 symlinks, 0 graphs, root index.md is %s lines.\n' "$_root_lines"
