#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/bin/lint.sh
# Architectural Layer: Public Plugin CLI Command (lint)
# Single Responsibility: Auto-heal wiki structure, remove legacy symlinks and
# directories, verify LC_ALL=C sort order, edge symmetry, and root bounds.
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

ensure_wiki_initialized
purge_legacy_wiki_directories_and_symlinks
sync_wiki_indexes_and_graph

# Invariant 1: Assert zero symlinks in wiki/
if [ -n "$(find "$RNEX_WIKI_ROOT" -type l 2>/dev/null)" ]; then
    printf 'Error [lint]: Found forbidden symbolic links in wiki directory.\n' >&2
    exit 1
fi

# Invariant 2: Verify LC_ALL=C sort order on TSV tables
for _tsv in "$RNEX_WIKI_NODES_TSV" "$RNEX_WIKI_EDGES_OUT_TSV" "$RNEX_WIKI_EDGES_IN_TSV"; do
    if [ -f "$_tsv" ] && [ -s "$_tsv" ]; then
        if ! LC_ALL=C sort -c "$_tsv" 2>/dev/null; then
            printf 'Error [lint]: TSV file is not sorted in LC_ALL=C order: %s\n' "$_tsv" >&2
            exit 1
        fi
    fi
done

# Invariant 3: Verify edge symmetry
_out_cnt="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_EDGES_OUT_TSV" 2>/dev/null || printf '0')"
_in_cnt="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_EDGES_IN_TSV" 2>/dev/null || printf '0')"
if [ "$_out_cnt" -ne "$_in_cnt" ]; then
    printf 'Error [lint]: Asymmetric edge tables (edges_out=%s, edges_in=%s)\n' "$_out_cnt" "$_in_cnt" >&2
    exit 1
fi

# Invariant 4: Verify root router bounds
_root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_INDEX_FILE" 2>/dev/null || printf '0')"
if [ "$_root_lines" -gt "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ]; then
    printf 'Error [lint]: wiki/_index.md exceeds %s lines (%s lines)\n' \
        "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" "$_root_lines" >&2
    exit 1
fi

# Invariant 5: If --strict is requested, detect broken wikilinks or missing frontmatter sources
if [ "$STRICT" -eq 1 ]; then
    _broken_tmp="${RNEX_WIKI_GRAPH_DIR}/.broken.tmp.$$"
    rm -f "$_broken_tmp"

    # shellcheck disable=SC2094
    while IFS="$(printf '\t')" read -r _src_id _src_shard _src_rel _src_title _src_sum; do
        [ -n "$_src_rel" ] || continue
        _src_abs="${RNEX_WORKSPACE_ROOT}/${_src_rel}"
        [ -f "$_src_abs" ] || continue

        # Check frontmatter sources: [...]
        LC_ALL=C awk '
            BEGIN { in_fm=0 }
            /^---/ { in_fm = !in_fm; if (!in_fm) exit; next }
            in_fm && /^[ ]*sources:[ ]*\[/ {
                line = $0
                sub(/^[ ]*sources:[ ]*\[/, "", line)
                sub(/\].*$/, "", line)
                n = split(line, items, ",")
                for (i=1; i<=n; i++) {
                    gsub(/^[ "\x27]+|[ "\x27]+$/, "", items[i])
                    if (items[i] != "") print items[i]
                }
            }
        ' "$_src_abs" < /dev/null | while IFS= read -r _s_path; do
            [ -n "$_s_path" ] || continue
            if [ ! -e "${RNEX_WORKSPACE_ROOT}/${_s_path}" ] && [ ! -e "$_s_path" ]; then
                printf 'Warning [lint]: Broken source reference "%s" in %s\n' "$_s_path" "$_src_rel" >&2
                echo "1" >> "$_broken_tmp"
            fi
        done

        # Check internal wikilinks
        extract_all_links_from_markdown "$_src_abs" < /dev/null | while IFS= read -r _target; do
            [ -n "$_target" ] || continue
            if ! LC_ALL=C awk -F '\t' -v t="$_target" '
                $1 == t || $1 ~ ("-" t "$") { found=1; exit }
                END { exit !found }
            ' "$RNEX_WIKI_NODES_TSV" < /dev/null; then
                printf 'Warning [lint]: Broken link target [[%s]] referenced in %s\n' "$_target" "$_src_rel" >&2
                echo "1" >> "$_broken_tmp"
            fi
        done
    done < "$RNEX_WIKI_NODES_TSV"

    if [ -f "$_broken_tmp" ]; then
        _broken_cnt="$(LC_ALL=C awk 'END { print NR+0 }' "$_broken_tmp")"
        rm -f "$_broken_tmp"
        printf 'Error [lint]: Found %s unresolved reference(s).\n' "$_broken_cnt" >&2
        exit 1
    fi
fi

append_wiki_log_entry "lint" "Verified B-Tree shards and symmetric graph (${_out_cnt} edges, 0 symlinks)."
[ "$QUIET" = "1" ] || printf 'Wiki lint passed: %s edges verified, 0 symlinks, root is %s lines.\n' "$_out_cnt" "$_root_lines"
