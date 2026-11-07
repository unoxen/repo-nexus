#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/bin/lint.sh
# Architectural Layer: Public Plugin CLI Command (lint)
# Single Responsibility: Auto-heal legacy wiki directories (migrating legacy
# overview/, entities/, and sources/ into concepts/ and repos/), rebuild and
# verify B-Tree shards (_index/*.md) and TSV graph tables (_graph/*.tsv), and
# validate graph edge symmetry and root index bounds.
# Patterns Applied: Command Pattern, Linter / Verifier.
# =============================================================================

set -e

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=plugins/karpathy-llm/lib/config.sh
. "${PLUGIN_ROOT}/lib/config.sh"
# shellcheck source=plugins/karpathy-llm/lib/utils.sh
. "${PLUGIN_ROOT}/lib/utils.sh"
# shellcheck source=plugins/karpathy-llm/lib/graph_helpers.sh
. "${PLUGIN_ROOT}/lib/graph_helpers.sh"
# shellcheck source=plugins/karpathy-llm/lib/btree_helpers.sh
. "${PLUGIN_ROOT}/lib/btree_helpers.sh"
# shellcheck source=plugins/karpathy-llm/lib/agent_query_helpers.sh
. "${PLUGIN_ROOT}/lib/agent_query_helpers.sh"

load_karpathy_wiki_config "${NEXUS_DIR:-${RNEX_WORKSPACE_ROOT:-$(pwd)}}"

# -----------------------------------------------------------------------------
# migrate_and_purge_legacy_wiki_artifacts
# Summary: Migrates any Markdown files from legacy overview/, entities/, or
#          sources/ directories into concepts/ or repos/, and removes deprecated
#          files (hot.md, index.md, _index/overview*, _index/entities*, _index/sources*).
# @returns: 0 on success.
# @sideEffects: Moves legacy content files and deletes deprecated directories.
# -----------------------------------------------------------------------------
migrate_and_purge_legacy_wiki_artifacts() {
    # 1. Migrate legacy wiki/overview/*.md -> wiki/concepts/
    if [ -d "${RNEX_WIKI_ROOT}/overview" ]; then
        mkdir -p "$RNEX_WIKI_CONCEPTS_DIR"
        find "${RNEX_WIKI_ROOT}/overview" -type f -name '*.md' 2>/dev/null | while IFS= read -r _f; do
            [ -f "$_f" ] || continue
            mv "$_f" "${RNEX_WIKI_CONCEPTS_DIR}/$(basename "$_f")"
        done
        rm -rf "${RNEX_WIKI_ROOT}/overview"
    fi

    # 2. Migrate legacy wiki/entities/*.md -> wiki/repos/nexus/
    if [ -d "${RNEX_WIKI_ROOT}/entities" ]; then
        mkdir -p "${RNEX_WIKI_REPOS_DIR}/nexus"
        find "${RNEX_WIKI_ROOT}/entities" -type f -name '*.md' 2>/dev/null | while IFS= read -r _f; do
            [ -f "$_f" ] || continue
            mv "$_f" "${RNEX_WIKI_REPOS_DIR}/nexus/$(basename "$_f")"
        done
        rm -rf "${RNEX_WIKI_ROOT}/entities"
    fi

    # 3. Migrate legacy wiki/sources/ -> wiki/repos/
    if [ -d "${RNEX_WIKI_ROOT}/sources" ]; then
        mkdir -p "${RNEX_WIKI_REPOS_DIR}/nexus"
        for _item in "${RNEX_WIKI_ROOT}/sources"/*; do
            [ -e "$_item" ] || continue
            if [ -d "$_item" ]; then
                _scope="$(basename "$_item")"
                mkdir -p "${RNEX_WIKI_REPOS_DIR}/${_scope}"
                cp -R "$_item"/. "${RNEX_WIKI_REPOS_DIR}/${_scope}/"
            elif [ -f "$_item" ]; then
                mv "$_item" "${RNEX_WIKI_REPOS_DIR}/nexus/$(basename "$_item")"
            fi
        done
        rm -rf "${RNEX_WIKI_ROOT}/sources"
    fi

    # 4. Purge deprecated hot.md and legacy root index.md
    rm -f "${RNEX_WIKI_ROOT}/hot.md" "${RNEX_WIKI_ROOT}/index.md"
    return 0
}

# 1. Parse arguments (--strict, --quiet, -q, etc.)
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

# 2. Ensure structure & migrate legacy directories
ensure_wiki_initialized
migrate_and_purge_legacy_wiki_artifacts

# 3. Rebuild and synchronize _graph/*.tsv, _index/*.md, and wiki/_index.md
sync_wiki_indexes_and_graph

# 4. Verify LC_ALL=C sort invariants on all 3 TSV graph tables
for _tsv in "$RNEX_WIKI_NODES_TSV" "$RNEX_WIKI_EDGES_OUT_TSV" "$RNEX_WIKI_EDGES_IN_TSV"; do
    if [ -f "$_tsv" ] && [ -s "$_tsv" ]; then
        if ! LC_ALL=C sort -c "$_tsv" 2>/dev/null; then
            printf 'Error [lint]: TSV file is not sorted in LC_ALL=C order: %s\n' "$_tsv" >&2
            exit 1
        fi
    fi
done

# 5. Verify edge symmetry between edges_out.tsv and edges_in.tsv
_out_cnt="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_EDGES_OUT_TSV")"
_in_cnt="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_EDGES_IN_TSV")"
if [ "$_out_cnt" -ne "$_in_cnt" ]; then
    printf 'Error [lint]: Asymmetric edge tables (edges_out=%s, edges_in=%s)\n' "$_out_cnt" "$_in_cnt" >&2
    exit 1
fi

# 6. Verify root router line count bound
_root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_INDEX_FILE")"
if [ "$_root_lines" -gt "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ]; then
    printf 'Error [lint]: wiki/_index.md exceeds %s lines (%s lines)\n' \
        "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" "$_root_lines" >&2
    exit 1
fi

# 7. Check for broken internal [[wikilinks]] and frontmatter sources if --strict is requested
if [ "$STRICT" -eq 1 ]; then
    _broken_tmp="${RNEX_WIKI_GRAPH_DIR}/broken.tmp.$$"
    rm -f "$_broken_tmp"

    find "$RNEX_WIKI_CONCEPTS_DIR" "$RNEX_WIKI_REPOS_DIR" -type f -name '*.md' 2>/dev/null | while IFS= read -r _f; do
        [ -f "$_f" ] || continue
        _src_id="$(normalize_slug_id "$(basename "$_f" .md)")" || continue

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
        ' "$_f" | while IFS= read -r _s_path; do
            [ -n "$_s_path" ] || continue
            if [ ! -e "${RNEX_WORKSPACE_ROOT}/${_s_path}" ] && [ ! -e "$_s_path" ]; then
                printf 'Warning [lint]: Broken source reference "%s" in %s\n' "$_s_path" "$_f" >&2
                echo "1" >> "$_broken_tmp"
            fi
        done

        # Check internal wikilinks
        extract_all_links_from_markdown "$_f" | while IFS= read -r _target; do
            [ -n "$_target" ] || continue
            if ! LC_ALL=C awk -F '\t' -v t="$_target" '
                $1 == t || $1 ~ ("-" t "$") { found=1; exit }
                END { exit !found }
            ' "$RNEX_WIKI_NODES_TSV"; then
                printf 'Warning [lint]: Broken link target [[%s]] referenced in %s\n' "$_target" "$_src_id" >&2
                echo "1" >> "$_broken_tmp"
            fi
        done
    done

    if [ -f "$_broken_tmp" ]; then
        _broken_cnt="$(LC_ALL=C awk 'END { print NR+0 }' "$_broken_tmp")"
        rm -f "$_broken_tmp"
        printf 'Error [lint]: Found %s unresolved reference(s).\n' "$_broken_cnt" >&2
        exit 1
    fi
fi

append_wiki_log_entry "lint" "Verified B-Tree shards (_index/) and symmetric graph tables (${_out_cnt} edges)."
[ "$QUIET" = "1" ] || printf 'Wiki lint passed: %s edges verified, root _index.md is %s lines.\n' "$_out_cnt" "$_root_lines"
