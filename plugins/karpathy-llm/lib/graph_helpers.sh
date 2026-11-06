#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/graph_helpers.sh
# Architectural Layer: Domain-Aware Graph Helpers (helpers/)
# Single Responsibility: Manage the zero-dependency sorted TSV property graph
# (nodes.tsv, edges_out.tsv, edges_in.tsv) and execute O(log N) neighborhood
# traversals for AI agents.
# Extension Points: Custom edge relation predicates and multi-hop ego-subgraph
# expansion depth (RNEX_WIKI_GRAPH_DEFAULT_DEPTH).
# Patterns Applied: Facade Pattern (unified graph store operations), Information
# Expert (GRASP).
# Dependencies: plugins/karpathy-llm/lib/config.sh, plugins/karpathy-llm/lib/utils.sh
# Security (OWASP A03): All node metadata fields are sanitized via
# sanitize_tsv_field and slugs normalized via normalize_slug_id before storage.
# =============================================================================

# -----------------------------------------------------------------------------
# init_wiki_graph_store
# Summary: Ensures wiki/_graph/ and its three sorted TSV tables exist.
# @param: None (reads RNEX_WIKI_GRAPH_DIR and RNEX_WIKI_*_TSV contracts).
# @returns: 0 on success; 1 on directory or file creation failure.
# @throws: Returns 1 if filesystem permissions prevent creating graph tables.
# @sideEffects: Creates _graph/ directory and empty TSV files if missing.
# -----------------------------------------------------------------------------
init_wiki_graph_store() {
    if [ -z "${RNEX_WIKI_GRAPH_DIR:-}" ]; then
        return 1
    fi
    mkdir -p "$RNEX_WIKI_GRAPH_DIR" || return 1
    for _tsv in "$RNEX_WIKI_NODES_TSV" "$RNEX_WIKI_EDGES_OUT_TSV" "$RNEX_WIKI_EDGES_IN_TSV"; do
        if [ ! -f "$_tsv" ]; then
            : > "$_tsv" || return 1
        fi
    done
    return 0
}

# -----------------------------------------------------------------------------
# extract_wikilinks_from_markdown
# Summary: Extracts all [[target]] and [[target|label]] wikilinks from a
#          Markdown file outside of fenced code blocks.
# @param $1: markdown_file - Path to the source Markdown document.
# @returns: Unique, LC_ALL=C sorted target node slugs (one per line) on stdout.
# @throws: Returns 1 if markdown_file is empty or does not exist.
# @pure
# -----------------------------------------------------------------------------
extract_wikilinks_from_markdown() {
    _md_file="$1"
    if [ -z "$_md_file" ] || [ ! -f "$_md_file" ]; then
        return 1
    fi

    # Ignore fenced code blocks (``` ... ```) while extracting [[...]] tokens.
    # Strip optional display aliases (|Label), heading anchors (#section),
    # relative directory prefixes (shard/), and .md extensions before normalizing.
    LC_ALL=C awk '
        /^```/ { in_fence = !in_fence; next }
        !in_fence {
            line = $0
            while (match(line, /\[\[[^][]+\]\]/)) {
                raw_link = substr(line, RSTART + 2, RLENGTH - 4)
                sub(/\|.*$/, "", raw_link)
                sub(/#.*$/, "", raw_link)
                sub(/^.*\//, "", raw_link)
                sub(/\.md$/, "", raw_link)
                if (length(raw_link) > 0) {
                    print raw_link
                }
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "$_md_file" | while IFS= read -r _raw_target; do
        normalize_slug_id "$_raw_target" || true
    done | LC_ALL=C sort -u
    return 0
}

# -----------------------------------------------------------------------------
# upsert_graph_node_and_edges
# Summary: Registers or updates a node record in nodes.tsv and synchronizes its
#          outbound and inbound edges in edges_out.tsv and edges_in.tsv.
# @param $1: node_id   - Canonical slug of the wiki page.
# @param $2: shard_id  - Target B-Tree shard name (e.g., "concepts", "entities").
# @param $3: rel_path  - Wiki-relative path to the Markdown file.
# @param $4: title     - Human-readable document title.
# @param $5: summary   - Concise one-line node summary.
# @param $6: md_file   - Absolute path to the Markdown file for link extraction.
# @returns: 0 on success; 1 on validation or I/O failure.
# @throws: Returns 1 if node_id or shard_id normalizes to an empty string.
# @sideEffects: Atomically updates nodes.tsv, edges_out.tsv, and edges_in.tsv.
# -----------------------------------------------------------------------------
upsert_graph_node_and_edges() {
    _node_id="$(normalize_slug_id "$1")" || return 1
    _shard_id="$(normalize_slug_id "$2")" || return 1
    _rel_path="$(sanitize_tsv_field "$3")"
    _title="$(sanitize_tsv_field "$4")"
    _summary="$(sanitize_tsv_field "$5")"
    _md_file="${6:-}"

    init_wiki_graph_store || return 1
    _tab="$(printf '\t')"

    # Step 1: Remove any prior record for _node_id in nodes.tsv, then append new row
    _nodes_tmp="${RNEX_WIKI_NODES_TSV}.tmp.$$"
    LC_ALL=C awk -F '\t' -v id="$_node_id" '$1 != id { print $0 }' "$RNEX_WIKI_NODES_TSV" > "$_nodes_tmp"
    printf '%s\t%s\t%s\t%s\t%s\n' "$_node_id" "$_shard_id" "$_rel_path" "$_title" "$_summary" >> "$_nodes_tmp"
    mv "$_nodes_tmp" "$RNEX_WIKI_NODES_TSV"
    atomic_sort_unique_file "$RNEX_WIKI_NODES_TSV" || return 1

    # Step 2: Remove stale outbound edges originating from _node_id in edges_out.tsv
    #         and corresponding reverse edges in edges_in.tsv
    _out_tmp="${RNEX_WIKI_EDGES_OUT_TSV}.tmp.$$"
    _in_tmp="${RNEX_WIKI_EDGES_IN_TSV}.tmp.$$"
    LC_ALL=C awk -F '\t' -v src="$_node_id" '$1 != src { print $0 }' "$RNEX_WIKI_EDGES_OUT_TSV" > "$_out_tmp"
    LC_ALL=C awk -F '\t' -v src="$_node_id" '$3 != src { print $0 }' "$RNEX_WIKI_EDGES_IN_TSV" > "$_in_tmp"

    # Step 3: Extract current [[wikilinks]] and append dual forward/reverse edge records
    _link_files=""
    [ -n "$_md_file" ] && [ -f "$_md_file" ] && _link_files="$_md_file"
    _src_extra="${7:-}"
    if [ -n "$_src_extra" ] && [ -f "$_src_extra" ] && [ "$_src_extra" != "$_md_file" ]; then
        _link_files="${_link_files:+$_link_files }$_src_extra"
    fi

    if [ -n "$_link_files" ]; then
        for _lf in $_link_files; do
            extract_wikilinks_from_markdown "$_lf"
        done | LC_ALL=C sort -u | while IFS= read -r _target_id; do
            if [ -n "$_target_id" ] && [ "$_target_id" != "$_node_id" ]; then
                printf '%s%slinks_to%s%s\n' "$_node_id" "$_tab" "$_tab" "$_target_id" >> "$_out_tmp"
                printf '%s%slinks_to%s%s\n' "$_target_id" "$_tab" "$_tab" "$_node_id" >> "$_in_tmp"
            fi
        done
    fi

    mv "$_out_tmp" "$RNEX_WIKI_EDGES_OUT_TSV"
    mv "$_in_tmp" "$RNEX_WIKI_EDGES_IN_TSV"
    atomic_sort_unique_file "$RNEX_WIKI_EDGES_OUT_TSV" || return 1
    atomic_sort_unique_file "$RNEX_WIKI_EDGES_IN_TSV" || return 1
    return 0
}

# -----------------------------------------------------------------------------
# query_node_ego_subgraph
# Summary: Performs O(log N) binary search lookups in nodes.tsv, edges_out.tsv,
#          and edges_in.tsv to output the ego-subgraph for a target node.
# @param $1: target_node_id - Canonical slug of the queried node.
# @param $2: max_depth      - Traversal depth (1 or 2; defaults to config contract).
# @returns: Structured Markdown/TSV neighborhood summary on stdout.
# @throws: Returns 1 if target_node_id is empty or invalid.
# @pure
# -----------------------------------------------------------------------------
# shellcheck disable=SC2016
query_node_ego_subgraph() {
    _query_id="$(normalize_slug_id "$1")" || return 1
    _depth="${2:-${RNEX_WIKI_GRAPH_DEFAULT_DEPTH:-1}}"
    case "$_depth" in
        ''|*[!0-9]*) _depth="${RNEX_WIKI_GRAPH_DEFAULT_DEPTH:-1}" ;;
    esac
    _tab="$(printf '\t')"

    printf '### Node Metadata (`%s`)\n' "$_query_id"
    _node_row="$(binary_search_sorted_prefix "${_query_id}${_tab}" "$RNEX_WIKI_NODES_TSV")"
    if [ -n "$_node_row" ]; then
        _nshard="$(printf '%s' "$_node_row" | cut -f 2)"
        _act_shard="$_nshard"
        if [ -n "${RNEX_WIKI_BTREE_DIR:-}" ] && [ -f "${RNEX_WIKI_BTREE_DIR}/${_nshard}-a-m.md" ]; then
            _first="$(printf '%.1s' "$_query_id" | tr '[:upper:]' '[:lower:]')"
            case "$_first" in
                [a-m]) _act_shard="${_nshard}-a-m" ;;
                *)     _act_shard="${_nshard}-n-z" ;;
            esac
        fi
        printf '%s\n' "$_node_row" | LC_ALL=C awk -F '\t' -v s="$_act_shard" '{
            printf "- **Title:** %s\n- **Shard:** `_index/%s.md`\n- **Path:** `%s`\n- **Summary:** %s\n", $4, s, $3, $5
        }'
    else
        printf -- '- *(Node `%s` is referenced via wikilinks but has no compiled page yet.)*\n' "$_query_id"
    fi

    printf '\n### Outbound Dependencies (1-Hop `edges_out.tsv`)\n'
    _out_rows="$(binary_search_sorted_prefix "${_query_id}${_tab}" "$RNEX_WIKI_EDGES_OUT_TSV")"
    if [ -n "$_out_rows" ]; then
        printf '%s\n' "$_out_rows" | LC_ALL=C awk -F '\t' '{ printf "- `%s` --[%s]--> `[[%s]]`\n", $1, $2, $3 }'
    else
        printf -- '- *(None)*\n'
    fi

    printf '\n### Inbound Backlinks (1-Hop `edges_in.tsv`)\n'
    _in_rows="$(binary_search_sorted_prefix "${_query_id}${_tab}" "$RNEX_WIKI_EDGES_IN_TSV")"
    if [ -n "$_in_rows" ]; then
        printf '%s\n' "$_in_rows" | LC_ALL=C awk -F '\t' '{ printf "- `[[%s]]` --[%s]--> `%s`\n", $3, $2, $1 }'
    else
        printf -- '- *(None)*\n'
    fi

    # Optional 2-Hop expansion over outbound targets
    if [ "$_depth" -ge 2 ] && [ -n "$_out_rows" ]; then
        printf '\n### 2-Hop Outbound Reachability\n'
        printf '%s\n' "$_out_rows" | LC_ALL=C awk -F '\t' '{ print $3 }' | while IFS= read -r _hop1_target; do
            _hop2_rows="$(binary_search_sorted_prefix "${_hop1_target}${_tab}" "$RNEX_WIKI_EDGES_OUT_TSV")"
            if [ -n "$_hop2_rows" ]; then
                printf '%s\n' "$_hop2_rows" | LC_ALL=C awk -F '\t' '{ printf "- `%s` --[%s]--> `[[%s]]`\n", $1, $2, $3 }'
            fi
        done
    fi
    return 0
}
