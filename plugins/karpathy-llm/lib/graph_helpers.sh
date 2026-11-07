#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/graph_helpers.sh
# Architectural Layer: Domain-Aware Graph Helpers (helpers/)
# Single Responsibility: Compile and maintain the sorted TSV property graph
# (nodes.tsv, edges_out.tsv, edges_in.tsv) across wiki/concepts/ and
# wiki/repos/ using a deterministic Two-Pass Graph Compilation algorithm.
# Patterns Applied: Builder Pattern (Two-Pass Graph Compilation), Information
# Expert (GRASP), Facade Pattern.
# Dependencies: plugins/karpathy-llm/lib/config.sh, plugins/karpathy-llm/lib/utils.sh
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
# derive_shard_id_from_rel_path
# Summary: Maps a wiki-relative file path strictly to the 2-Pillar Taxonomy:
#          "concepts[-<group>]" or "repos-<repo_name>[-<subscope>]".
# @param $1: rel_path - Wiki-relative file path (e.g., "repos/backend/api/rest.md").
# @returns: Canonical shard prefix (e.g., "concepts", "repos-backend",
#           or "repos-backend-api") on stdout.
# @pure
# -----------------------------------------------------------------------------
derive_shard_id_from_rel_path() {
    _rel="$1"
    case "$_rel" in
        concepts/*)
            _sub="$(printf '%s' "$_rel" | cut -d'/' -f2)"
            _leaf="$(printf '%s' "$_rel" | cut -d'/' -f3)"
            if [ -n "$_leaf" ]; then
                _grp_slug="$(normalize_slug_id "$_sub")"
                printf 'concepts-%s\n' "$_grp_slug"
            else
                printf 'concepts\n'
            fi
            ;;
        repos/*)
            # Format: repos/<repo_name>[/<subscope>]/<file>.md
            _repo_seg="$(printf '%s' "$_rel" | cut -d'/' -f2)"
            _third_seg="$(printf '%s' "$_rel" | cut -d'/' -f3)"
            _fourth_seg="$(printf '%s' "$_rel" | cut -d'/' -f4)"
            _repo_slug="$(normalize_slug_id "${_repo_seg:-nexus}")"
            if [ -n "$_fourth_seg" ]; then
                # Multi-shard per repo: repos/<repo>/<subscope>/<file>.md
                _scope_slug="$(normalize_slug_id "$_third_seg")"
                printf 'repos-%s-%s\n' "$_repo_slug" "$_scope_slug"
            else
                printf 'repos-%s\n' "$_repo_slug"
            fi
            ;;
        *)
            printf 'repos-nexus\n'
            ;;
    esac
}

# -----------------------------------------------------------------------------
# extract_all_links_from_markdown
# Summary: Extracts all outbound internal link candidates from a Markdown file,
#          supporting both [[wikilink]] syntax and standard [text](relative.md)
#          Markdown links outside of fenced code blocks.
# @param $1: markdown_file - Path to the Markdown document.
# @returns: Unique canonical target slug candidates (one per line) on stdout.
# @pure
# -----------------------------------------------------------------------------
extract_all_links_from_markdown() {
    _md_file="$1"
    [ -n "$_md_file" ] && [ -f "$_md_file" ] || return 1

    LC_ALL=C awk '
        /^```/ { in_fence = !in_fence; next }
        !in_fence {
            # 1. Extract [[wikilink]] tokens
            line = $0
            while (match(line, /\[\[[^][]+\]\]/)) {
                raw = substr(line, RSTART + 2, RLENGTH - 4)
                print raw
                line = substr(line, RSTART + RLENGTH)
            }
            # 2. Extract standard relative Markdown links [label](target)
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
        # Ignore external URLs, mailto, and in-page anchor-only links
        case "$_candidate" in
            ''|\#*|http://*|https://*|mailto:*|ftp:*|data:*)
                continue
                ;;
        esac

        canonicalize_link_target "$_candidate" || true
        # Also emit basename slug if candidate contained path segments
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
# Summary: Executes a deterministic Two-Pass scan over wiki/concepts/ and
#          wiki/repos/ to populate nodes.tsv, edges_out.tsv, and edges_in.tsv.
#          Guarantees edges_out.tsv and edges_in.tsv are populated, symmetric,
#          and sorted.
# @returns: 0 on success; 1 on filesystem error.
# @sideEffects: Rewrites wiki/_graph/nodes.tsv, edges_out.tsv, and edges_in.tsv.
# -----------------------------------------------------------------------------
rebuild_full_wiki_graph() {
    mkdir -p "$RNEX_WIKI_GRAPH_DIR" "$RNEX_WIKI_CONCEPTS_DIR" "$RNEX_WIKI_REPOS_DIR" || return 1

    _nodes_tmp="${RNEX_WIKI_NODES_TSV}.tmp.$$"
    _raw_edges_tmp="${RNEX_WIKI_GRAPH_DIR}/raw_edges.tmp.$$"
    _out_tmp="${RNEX_WIKI_EDGES_OUT_TSV}.tmp.$$"
    _in_tmp="${RNEX_WIKI_EDGES_IN_TSV}.tmp.$$"
    : > "$_nodes_tmp"
    : > "$_raw_edges_tmp"
    : > "$_out_tmp"
    : > "$_in_tmp"

    # -------------------------------------------------------------------------
    # PASS 1: Scan all Markdown files in wiki/concepts/ and wiki/repos/
    # -------------------------------------------------------------------------
    find "$RNEX_WIKI_CONCEPTS_DIR" "$RNEX_WIKI_REPOS_DIR" -type f -name '*.md' 2>/dev/null \
        | LC_ALL=C sort | while IFS= read -r _abs_md; do
        [ -n "$_abs_md" ] && [ -f "$_abs_md" ] || continue
        _rel_path="${_abs_md#"${RNEX_WIKI_ROOT}/"}"
        _shard_id="$(derive_shard_id_from_rel_path "$_rel_path")"
        _base_name="$(basename "$_abs_md" .md)"
        _node_id="$(normalize_slug_id "$_base_name")" || continue
        if [ "$_node_id" = "readme" ]; then
            case "$_shard_id" in
                repos-*) _node_id="${_shard_id#repos-}-readme" ;;
                *)       _node_id="${_shard_id}-readme" ;;
            esac
        fi

        # Extract H1 title (or fallback to slug) and first descriptive paragraph line
        _title="$(LC_ALL=C awk '/^# / { sub(/^# +/, ""); print; exit }' "$_abs_md")"
        [ -n "$_title" ] || _title="$_node_id"
        _summary="$(LC_ALL=C awk '
            /^#/ || /^$/ || /^---/ || /^```/ || /^- \*\*/ || /^\|/ { next }
            { print; exit }
        ' "$_abs_md")"
        [ -n "$_summary" ] || _summary="Compiled wiki node (${_rel_path})"

        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$_node_id" \
            "$_shard_id" \
            "$(sanitize_tsv_field "$_rel_path")" \
            "$(sanitize_tsv_field "$_title")" \
            "$(sanitize_tsv_field "$_summary")" >> "$_nodes_tmp"

        # Collect raw links for Pass 2
        extract_all_links_from_markdown "$_abs_md" | while IFS= read -r _target; do
            [ -n "$_target" ] && [ "$_target" != "$_node_id" ] || continue
            printf '%s\t%s\n' "$_node_id" "$_target" >> "$_raw_edges_tmp"
        done
    done

    LC_ALL=C sort -u "$_nodes_tmp" > "$RNEX_WIKI_NODES_TSV"
    rm -f "$_nodes_tmp"

    # -------------------------------------------------------------------------
    # PASS 2: Resolve Target Nodes & Materialize Symmetric Edges
    # -------------------------------------------------------------------------
    LC_ALL=C awk -F '\t' -v out_f="$_out_tmp" -v in_f="$_in_tmp" '
        NR == FNR {
            if ($1 != "") {
                nodes[$1] = 1
                node_list[++n_cnt] = $1
            }
            next
        }
        {
            src = $1
            raw_t = $2
            if (src == "" || raw_t == "") next
            resolved = ""
            if (nodes[raw_t]) {
                resolved = raw_t
            } else if (nodes[raw_t "-readme"]) {
                resolved = raw_t "-readme"
            } else {
                t_len = length(raw_t)
                for (i = 1; i <= n_cnt; i++) {
                    cand = node_list[i]
                    c_len = length(cand)
                    if (c_len > t_len && substr(cand, c_len - t_len) == ("-" raw_t)) {
                        resolved = cand
                        break
                    }
                }
                if (resolved == "") resolved = raw_t
            }
            if (resolved != "" && resolved != src) {
                printf "%s\tlinks_to\t%s\n", src, resolved >> out_f
                printf "%s\tlinks_to\t%s\n", resolved, src >> in_f
            }
        }
    ' "$RNEX_WIKI_NODES_TSV" "$_raw_edges_tmp"
    rm -f "$_raw_edges_tmp"

    LC_ALL=C sort -u "$_out_tmp" > "$RNEX_WIKI_EDGES_OUT_TSV"
    LC_ALL=C sort -u "$_in_tmp" > "$RNEX_WIKI_EDGES_IN_TSV"
    rm -f "$_out_tmp" "$_in_tmp"
    return 0
}

# -----------------------------------------------------------------------------
# upsert_graph_node_and_edges
# Summary: Registers or updates a single node record in nodes.tsv and synchronizes
#          its forward and reverse edges in edges_out.tsv and edges_in.tsv.
# @param $1: node_id   - Canonical slug of the wiki page.
# @param $2: shard_id  - Target B-Tree shard name (e.g., "concepts", "repos-nexus").
# @param $3: rel_path  - Wiki-relative path to the Markdown file.
# @param $4: title     - Human-readable document title.
# @param $5: summary   - Concise one-line node summary.
# @param $6: md_file   - Absolute path to the Markdown file for link extraction.
# @returns: 0 on success; 1 on validation or I/O failure.
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

    # Step 1: Remove prior record for _node_id in nodes.tsv, then append new row
    _nodes_tmp="${RNEX_WIKI_NODES_TSV}.tmp.$$"
    LC_ALL=C awk -F '\t' -v id="$_node_id" '$1 != id { print $0 }' "$RNEX_WIKI_NODES_TSV" > "$_nodes_tmp"
    printf '%s\t%s\t%s\t%s\t%s\n' "$_node_id" "$_shard_id" "$_rel_path" "$_title" "$_summary" >> "$_nodes_tmp"
    mv "$_nodes_tmp" "$RNEX_WIKI_NODES_TSV"
    atomic_sort_unique_file "$RNEX_WIKI_NODES_TSV" || return 1

    # Step 2: Remove stale outbound and inbound edges connected to _node_id
    _out_tmp="${RNEX_WIKI_EDGES_OUT_TSV}.tmp.$$"
    _in_tmp="${RNEX_WIKI_EDGES_IN_TSV}.tmp.$$"
    LC_ALL=C awk -F '\t' -v src="$_node_id" '$1 != src { print $0 }' "$RNEX_WIKI_EDGES_OUT_TSV" > "$_out_tmp"
    LC_ALL=C awk -F '\t' -v src="$_node_id" '$3 != src { print $0 }' "$RNEX_WIKI_EDGES_IN_TSV" > "$_in_tmp"

    # Step 3: Extract links and append dual forward/reverse edges
    _link_files=""
    [ -n "$_md_file" ] && [ -f "$_md_file" ] && _link_files="$_md_file"
    _src_extra="${7:-}"
    if [ -n "$_src_extra" ] && [ -f "$_src_extra" ] && [ "$_src_extra" != "$_md_file" ]; then
        _link_files="${_link_files:+$_link_files }$_src_extra"
    fi

    if [ -n "$_link_files" ]; then
        for _lf in $_link_files; do
            extract_all_links_from_markdown "$_lf"
        done | LC_ALL=C sort -u | while IFS= read -r _target_id; do
            if [ -n "$_target_id" ] && [ "$_target_id" != "$_node_id" ]; then
                printf '%s\tlinks_to\t%s\n' "$_node_id" "$_target_id" >> "$_out_tmp"
                printf '%s\tlinks_to\t%s\n' "$_target_id" "$_node_id" >> "$_in_tmp"
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
# @returns: Structured Markdown neighborhood summary on stdout.
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
