#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/agent_query_helpers.sh
# Architectural Layer: Internal AI Agent Retrieval Helpers (helpers/)
# Single Responsibility: Internal O(log N) prefix search (_search) and
# ego-subgraph traversal (_graph) for AI coding agents.
# Dependencies: config.sh, utils.sh, source_helpers.sh, graph_helpers.sh, btree_helpers.sh
# Security (OWASP A03): Input queries normalized via normalize_slug_id;
# audit log entries sanitized before appending.
# =============================================================================

# -----------------------------------------------------------------------------
# ensure_wiki_initialized
# Summary: Idempotently bootstraps wiki directories, _log.md, _graph/*.tsv,
#          _index/*.md, and wiki/_index.md so no standalone `init` command is
#          ever needed.
# @returns: 0 on success; 1 on filesystem error.
# @sideEffects: Creates missing wiki directories and baseline files.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2016
ensure_wiki_initialized() {
    mkdir -p "$RNEX_WIKI_BTREE_DIR" "$RNEX_WIKI_GRAPH_DIR" || return 1

    for _tsv in "$RNEX_WIKI_NODES_TSV" "$RNEX_WIKI_EDGES_OUT_TSV" "$RNEX_WIKI_EDGES_IN_TSV"; do
        [ -f "$_tsv" ] || : > "$_tsv"
    done

    if [ ! -f "$RNEX_WIKI_LOG_FILE" ]; then
        _today="$(get_iso_utc_date)"
        cat <<EOF > "$RNEX_WIKI_LOG_FILE"
# Wiki Operational Log (\`wiki/_log.md\`)

Append-only record of wiki ingestions and lint passes.

- **${_today}** | \`init\` | Initialized Karpathy LLM Wiki structure.
EOF
    fi

    if [ ! -f "$RNEX_WIKI_INDEX_FILE" ]; then
        sync_wiki_indexes_and_graph || return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# sync_wiki_indexes_and_graph
# Summary: Internal pipeline step that rebuilds the Two-Pass TSV Property Graph
#          and rebalances all B-Tree shards and wiki/_index.md.
# @param $1: single_file_opt - Optional file path to prioritize.
# @returns: 0 on success; 1 on failure.
# @sideEffects: Updates _graph/*.tsv, _index/*.md, and wiki/_index.md.
# -----------------------------------------------------------------------------
sync_wiki_indexes_and_graph() {
    _single_opt="${1:-}"
    purge_legacy_wiki_directories_and_symlinks
    rebuild_full_wiki_graph "$_single_opt" || return 1
    rebalance_btree_shards_and_compile_root || return 1
    return 0
}

# -----------------------------------------------------------------------------
# append_wiki_log_entry
# Summary: Appends a sanitized ISO-8601 UTC operational event to wiki/_log.md.
# @param $1: operation_type - Tag ("ingest" or "lint").
# @param $2: summary_text   - Single-line operational description.
# @returns: 0 on success.
# @sideEffects: Appends one line to wiki/_log.md.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2016
append_wiki_log_entry() {
    _op="$(sanitize_tsv_field "$1")"
    _msg="$(sanitize_tsv_field "$2")"
    _today="$(get_iso_utc_date)"
    printf -- '- **%s** | `%s` | %s\n' "$_today" "$_op" "$_msg" >> "$RNEX_WIKI_LOG_FILE"
}

# -----------------------------------------------------------------------------
# agent_internal_search (_search)
# Summary: Internal O(log N) prefix and substring search over nodes.tsv for AI
#          agents. Not exposed as a user CLI command.
# @param $1: query_term - Prefix or keyword slug to search.
# @returns: Matching TSV rows on stdout.
# @pure
# -----------------------------------------------------------------------------
agent_internal_search() {
    _q="$(normalize_slug_id "$1")" || return 1
    [ -f "$RNEX_WIKI_NODES_TSV" ] || return 1

    _exact="$(binary_search_sorted_prefix "$_q" "$RNEX_WIKI_NODES_TSV")"
    if [ -n "$_exact" ]; then
        printf '%s\n' "$_exact"
    else
        LC_ALL=C grep -i "$_q" "$RNEX_WIKI_NODES_TSV" 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# agent_internal_graph (_graph)
# Summary: Internal O(log N) ego-subgraph query returning outbound dependencies
#          (edges_out.tsv) and inbound backlinks (edges_in.tsv) for a node_id.
# @param $1: node_id - Target wiki node slug.
# @returns: Formatted Markdown neighborhood summary on stdout.
# @pure
# -----------------------------------------------------------------------------
# shellcheck disable=SC2016
agent_internal_graph() {
    _node="$(normalize_slug_id "$1")" || return 1
    _tab="$(printf '\t')"

    printf '### Graph Neighborhood: `%s`\n\n' "$_node"
    printf '#### Outbound Links (`edges_out.tsv`)\n'
    binary_search_sorted_prefix "${_node}${_tab}" "$RNEX_WIKI_EDGES_OUT_TSV" \
        | LC_ALL=C awk -F '\t' '{ printf "- `%s` --[%s]--> [[%s]]\n", $1, $2, $3 }'
    printf '\n#### Inbound Backlinks (`edges_in.tsv`)\n'
    binary_search_sorted_prefix "${_node}${_tab}" "$RNEX_WIKI_EDGES_IN_TSV" \
        | LC_ALL=C awk -F '\t' '{ printf "- [[%s]] --[%s]--> `%s`\n", $3, $2, $1 }'
}

# Short aliases for internal agent context traversal
_search() {
    agent_internal_search "$@"
}

_graph() {
    agent_internal_graph "$@"
}
