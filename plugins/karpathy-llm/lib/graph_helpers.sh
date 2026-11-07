#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/graph_helpers.sh
# Architectural Layer: Domain-Aware Graph Helpers (helpers/)
# Single Responsibility: Compile and maintain sorted TSV property graph tables
# (nodes.tsv, edges_out.tsv, edges_in.tsv) across authoritative workspace
# source files using a deterministic Two-Pass Graph Compilation algorithm.
# Patterns Applied: Builder Pattern (Two-Pass Graph Compilation), Information
# Expert (GRASP).
# Dependencies: config.sh, utils.sh, source_helpers.sh
# Security (OWASP A03): All node metadata fields are sanitized via
# sanitize_tsv_field and slugs normalized via normalize_slug_id before storage.
# =============================================================================

# -----------------------------------------------------------------------------
# init_wiki_graph_store
# Summary: Ensures wiki/_graph/ and its three sorted TSV tables exist.
# @param: None (reads RNEX_WIKI_GRAPH_DIR and RNEX_WIKI_*_TSV contracts).
# @returns: 0 on success; 1 on directory or file creation failure.
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
# extract_all_links_from_markdown
# Summary: Extracts internal link targets from a Markdown document outside of
#          code fences, supporting [[wikilink]] syntax and standard relative
#          [text](relative.md) Markdown links.
# @param $1: markdown_file - Absolute or relative path to Markdown file.
# @returns: Canonical target slug candidates (one per line) on stdout.
# @pure
# -----------------------------------------------------------------------------
extract_all_links_from_markdown() {
    _md_file="$1"
    [ -f "$_md_file" ] || return 1

    LC_ALL=C awk '
        /^```/ { in_fence = !in_fence; next }
        !in_fence {
            line = $0
            while (match(line, /\[\[[^][]+\]\]/)) {
                raw = substr(line, RSTART + 2, RLENGTH - 4)
                print raw
                line = substr(line, RSTART + RLENGTH)
            }
            line2 = $0
            while (match(line2, /\[[^][]+\]\([^()]+\)/)) {
                full = substr(line2, RSTART, RLENGTH)
                sub(/^\[[^][]+\]\(/, "", full)
                sub(/\)$/, "", full)
                sub(/[[:space:]].*$/, "", full)
                print full
                line2 = substr(line2, RSTART + RLENGTH)
            }
        }
    ' "$_md_file" | while IFS= read -r _candidate; do
        case "$_candidate" in
            ''|\#*|http://*|https://*|mailto:*|ftp:*|data:*)
                continue
                ;;
        esac
        canonicalize_link_target "$_candidate" || true
        case "$_candidate" in
            */*)
                _base_cand="$(printf '%s' "$_candidate" | sed 's/|.*$//; s/#.*$//; s#^.*/##')"
                canonicalize_link_target "$_base_cand" || true
                ;;
        esac
    done | LC_ALL=C sort -u
}

# -----------------------------------------------------------------------------
# extract_wikilinks_from_markdown
# Summary: Backwards-compatible alias delegating to extract_all_links_from_markdown.
# @param $1: markdown_file - Path to the Markdown document.
# @returns: Unique canonical target slugs on stdout.
# @pure
# -----------------------------------------------------------------------------
extract_wikilinks_from_markdown() {
    extract_all_links_from_markdown "$@"
}

# -----------------------------------------------------------------------------
# rebuild_full_wiki_graph
# Summary: Executes a deterministic Two-Pass scan over all workspace sources
#          (from build_workspace_source_manifest) to populate nodes.tsv,
#          edges_out.tsv, and edges_in.tsv directly in place.
# @param $1: single_file_opt - Optional specific file path to prioritize.
# @returns: 0 on success; 1 on I/O error.
# @sideEffects: Rewrites wiki/_graph/nodes.tsv, edges_out.tsv, and edges_in.tsv.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2094
rebuild_full_wiki_graph() {
    _single_opt="${1:-}"
    mkdir -p "$RNEX_WIKI_GRAPH_DIR" || return 1

    _manifest="${RNEX_WIKI_GRAPH_DIR}/.sources_manifest.tmp.$$"
    _nodes_tmp="${RNEX_WIKI_NODES_TSV}.tmp.$$"
    _out_tmp="${RNEX_WIKI_EDGES_OUT_TSV}.tmp.$$"
    _in_tmp="${RNEX_WIKI_EDGES_IN_TSV}.tmp.$$"
    : > "$_nodes_tmp"
    : > "$_out_tmp"
    : > "$_in_tmp"

    build_workspace_source_manifest "$_manifest" "$_single_opt" || {
        rm -f "$_manifest"
        return 1
    }

    # -------------------------------------------------------------------------
    # PASS 1: Register every configured source file in nodes.tsv
    # -------------------------------------------------------------------------
    while IFS= read -r _m_line; do
        [ -n "$_m_line" ] || continue
        _repo_scope="$(printf '%s' "$_m_line" | cut -f1)"
        _sub_scope="$(printf '%s' "$_m_line" | cut -f2)"
        _rel_path="$(printf '%s' "$_m_line" | cut -f3)"
        _abs_path="$(printf '%s' "$_m_line" | cut -f4)"

        [ -n "$_abs_path" ] && [ -f "$_abs_path" ] || continue

        if [ -n "$_sub_scope" ]; then
            _top_sub="$(printf '%s' "$_sub_scope" | cut -d'-' -f1)"
            _shard_id="${_repo_scope}-${_top_sub}"
        else
            _shard_id="$_repo_scope"
        fi

        _stem="$(basename "$_abs_path" | sed 's/\.[^.]*$//')"
        _scope_short="${_repo_scope#repos-}"
        _stem_slug="$(normalize_slug_id "$_stem")" || continue
        if [ "$_stem_slug" = "readme" ] || [ "$_stem_slug" = "index" ]; then
            if [ -n "$_sub_scope" ]; then
                _node_id="$(normalize_slug_id "${_scope_short}-${_sub_scope}")"
            else
                _node_id="$(normalize_slug_id "${_scope_short}-${_stem_slug}")"
            fi
        else
            _node_id="$(normalize_slug_id "${_scope_short}-${_stem_slug}")"
        fi

        _title="$(LC_ALL=C awk '/^# / { sub(/^# +/, ""); print; exit }' "$_abs_path" < /dev/null)"
        [ -n "$_title" ] || _title="${_scope_short}: ${_stem}"

        _summary="$(LC_ALL=C awk '
            /^#/ || /^$/ || /^---/ || /^```/ || /^- \*\*/ || /^\|/ { next }
            { print; exit }
        ' "$_abs_path" < /dev/null)"
        [ -n "$_summary" ] || _summary="Source documentation at ${_rel_path}"

        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$_node_id" \
            "$_shard_id" \
            "$(sanitize_tsv_field "$_rel_path")" \
            "$(sanitize_tsv_field "$_title")" \
            "$(sanitize_tsv_field "$_summary")" >> "$_nodes_tmp"
    done < "$_manifest"

    # Preserve committed entries for uncloned member repos if repo is enabled
    if [ -f "$RNEX_WIKI_NODES_TSV" ]; then
        LC_ALL=C awk -F '\t' '
            $2 ~ /^repos-/ {
                split($2, parts, "-")
                m_repo = parts[2]
                print $0 "\t" m_repo
            }
        ' "$RNEX_WIKI_NODES_TSV" | while IFS="$(printf '\t')" read -r _nid _sid _rpath _ttl _sum _mrepo; do
            [ -n "$_mrepo" ] || continue
            _m_dir="${RNEX_WORKSPACE_ROOT}/${RNEX_CFG_REPOS_DIR:-repos}/${_mrepo}"
            if [ ! -d "$_m_dir" ] && is_repo_enabled "$_mrepo"; then
                printf '%s\t%s\t%s\t%s\t%s\n' "$_nid" "$_sid" "$_rpath" "$_ttl" "$_sum" >> "$_nodes_tmp"
            fi
        done
    fi

    LC_ALL=C sort -u "$_nodes_tmp" > "$RNEX_WIKI_NODES_TSV"
    rm -f "$_nodes_tmp" "$_manifest"

    # -------------------------------------------------------------------------
    # PASS 2: Extract Outbound & Inbound Edges Across Registered Nodes
    # -------------------------------------------------------------------------
    while IFS="$(printf '\t')" read -r _src_id _src_shard _src_rel _src_title _src_sum; do
        [ -n "$_src_id" ] || continue
        _src_abs="${RNEX_WORKSPACE_ROOT}/${_src_rel}"
        [ -f "$_src_abs" ] || continue

        extract_all_links_from_markdown "$_src_abs" < /dev/null | while IFS= read -r _raw_target; do
            [ -n "$_raw_target" ] || continue

            _resolved_target="$(LC_ALL=C awk -F '\t' -v t="$_raw_target" '
                $1 == t || $1 ~ ("-" t "$") { print $1; found=1; exit }
                END { if (!found) print t }
            ' "$RNEX_WIKI_NODES_TSV" < /dev/null)"

            if [ -n "$_resolved_target" ] && [ "$_resolved_target" != "$_src_id" ]; then
                printf '%s\tlinks_to\t%s\n' "$_src_id" "$_resolved_target" >> "$_out_tmp"
                printf '%s\tlinks_to\t%s\n' "$_resolved_target" "$_src_id" >> "$_in_tmp"
            fi
        done
    done < "$RNEX_WIKI_NODES_TSV"

    LC_ALL=C sort -u "$_out_tmp" > "$RNEX_WIKI_EDGES_OUT_TSV"
    LC_ALL=C sort -u "$_in_tmp" > "$RNEX_WIKI_EDGES_IN_TSV"
    rm -f "$_out_tmp" "$_in_tmp"
    return 0
}
