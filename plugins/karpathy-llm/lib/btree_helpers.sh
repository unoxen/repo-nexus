#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/btree_helpers.sh
# Architectural Layer: Domain-Aware B-Tree Index Helpers (helpers/)
# Single Responsibility: Maintain lexicographically sorted B-Tree leaf shards
# in wiki/_index/*.md, split oversized shards automatically, and compile the
# bounded (<= RNEX_WIKI_BTREE_MAX_ROOT_LINES) B-Tree Root router at wiki/index.md.
# Extension Points: resolve_shard_description (new shard domains), split range
# table in _btree_compile_shard (additional key-range partitions).
# Patterns Applied: Builder Pattern (deterministic shard & root compilation),
# Template Method (invariant init -> partition -> write -> route skeleton).
# Dependencies: config.sh (RNEX_WIKI_* contracts), utils.sh, graph_helpers.sh
# Data Source: nodes.tsv is the single source of truth (DRY); shard files and
# index.md are derived, fully regenerable build artifacts.
# Security (OWASP A03): Shard names originate from normalize_slug_id-validated
# TSV fields; destructive cleanup is guarded with ${var:?} expansions.
# =============================================================================

# Default base shards always present, even in a freshly initialized wiki.
# Space-separated slug list (POSIX sh has no arrays).
RNEX_WIKI_BTREE_BASE_SHARDS="overview concepts entities sources"

# -----------------------------------------------------------------------------
# resolve_shard_description
# Summary: Maps a canonical shard prefix to a concise architectural description
#          for the B-Tree Root routing table in wiki/index.md.
# @param $1: shard_name - Name of the shard (e.g., "concepts", "entities-a-m").
# @returns: Human-readable description string on stdout.
# @throws: None.
# @pure
# -----------------------------------------------------------------------------
resolve_shard_description() {
    case "$1" in
        overview*)  printf 'High-level workspace architecture and system summaries' ;;
        concepts*)  printf 'Core domain concepts, patterns, and design protocols' ;;
        entities*)  printf 'Concrete modules, services, CLI binaries, and components' ;;
        sources*)   printf 'Ingested raw source document summaries and provenance' ;;
        repos-*)    printf 'Scoped member repository knowledge shard (%s)' "$1" ;;
        *)          printf 'Domain knowledge shard (%s)' "$1" ;;
    esac
}

# -----------------------------------------------------------------------------
# _btree_count_shard_nodes
# Summary: Counts node rows in nodes.tsv belonging to a given base shard.
# @param $1: shard_name - Base shard slug (column 2 of nodes.tsv).
# @param $2: nodes_tsv  - Path to the sorted nodes.tsv table.
# @returns: Non-negative integer count on stdout.
# @throws: None (missing file yields awk error suppressed as 0).
# @pure
# -----------------------------------------------------------------------------
_btree_count_shard_nodes() {
    LC_ALL=C awk -F '\t' -v s="$1" '$2 == s { c++ } END { print c + 0 }' "$2" 2>/dev/null || printf '0\n'
}

# -----------------------------------------------------------------------------
# _btree_compile_shard
# Summary: Writes a single sorted leaf shard file for a base shard, optionally
#          restricted to a first-character key range ("a-m" or "n-z").
#          Because nodes.tsv is LC_ALL=C sorted by node_id, emitted entries are
#          already in strict byte order without an additional sort pass.
# @param $1: base_shard  - Base shard slug (column 2 of nodes.tsv).
# @param $2: range       - "" (no split), "a-m", or "n-z" (n-z also absorbs
#                          digits and any non a-m leading byte).
# @param $3: output_file - Destination Markdown shard path.
# @param $4: nodes_tsv   - Path to the sorted nodes.tsv table.
# @returns: 0 on success; 1 on write failure.
# @throws: Returns 1 if output_file cannot be written.
# @sideEffects: Creates/overwrites output_file.
# -----------------------------------------------------------------------------
_btree_compile_shard() {
    _bcs_base="$1"
    _bcs_range="$2"
    _bcs_out="$3"
    _bcs_nodes="$4"

    # Shard title reflects sub-shard name when a key range is applied
    _bcs_name="$_bcs_base"
    [ -n "$_bcs_range" ] && _bcs_name="${_bcs_base}-${_bcs_range}"

    # Render entries; emit a placeholder when the range is empty so that every
    # shard file remains a valid, non-empty Markdown document.
    # shellcheck disable=SC2016
    LC_ALL=C awk -F '\t' -v s="$_bcs_base" -v rng="$_bcs_range" -v name="$_bcs_name" '
        BEGIN { printf "# Wiki Index Shard: %s\n\n", name; n = 0 }
        $2 == s {
            first_char = substr($1, 1, 1)
            in_am = (first_char >= "a" && first_char <= "m")
            # Range filter: "" accepts all; "a-m" accepts a..m; "n-z" accepts rest
            if (rng == "" || (rng == "a-m" && in_am) || (rng == "n-z" && !in_am)) {
                printf "- [[%s]] — **%s**: %s (`%s`)\n", $1, $4, $5, $3
                n++
            }
        }
        END { if (n == 0) print "- *(No pages compiled in this shard yet.)*" }
    ' "$_bcs_nodes" > "$_bcs_out" || return 1
    return 0
}

# -----------------------------------------------------------------------------
# _btree_render_root_row
# Summary: Renders one Markdown table row for the B-Tree Root routing table,
#          including exact LC_ALL=C key range and entry count of a shard file.
# @param $1: shard_path - Path to a compiled wiki/_index/<shard>.md file.
# @returns: Single Markdown table row on stdout.
# @throws: None.
# @pure (Read-only over the shard file)
# -----------------------------------------------------------------------------
# shellcheck disable=SC2016
_btree_render_root_row() {
    _brr_path="$1"
    _brr_name="$(basename "$_brr_path" .md)"

    # Single awk pass: count "- [[key]]" entries and capture first/last keys.
    # Entries are emitted in sorted order, so first == min and last == max.
    _brr_stats="$(LC_ALL=C awk '
        /^- \[\[/ {
            key = $0
            sub(/^- \[\[/, "", key)
            sub(/\]\].*$/, "", key)
            if (n == 0) min = key
            max = key
            n++
        }
        END { printf "%d\t%s\t%s", n + 0, min, max }
    ' "$_brr_path")"

    _brr_count="$(printf '%s' "$_brr_stats" | cut -f 1)"
    if [ "$_brr_count" -gt 0 ]; then
        _brr_min="$(printf '%s' "$_brr_stats" | cut -f 2)"
        _brr_max="$(printf '%s' "$_brr_stats" | cut -f 3)"
        _brr_range="\`${_brr_min}\` .. \`${_brr_max}\`"
    else
        _brr_range="*(empty)*"
    fi

    _brr_desc="$(resolve_shard_description "$_brr_name")"
    printf '| [`_index/%s.md`](_index/%s.md) | %s | %s | %s |\n' \
        "$_brr_name" "$_brr_name" "$_brr_range" "$_brr_count" "$_brr_desc"
}

# -----------------------------------------------------------------------------
# rebalance_btree_shards_and_compile_root
# Summary: Compiles sorted wiki/_index/<shard>.md leaf files from nodes.tsv,
#          splits any shard whose count exceeds RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES
#          into key-range sub-shards (<shard>-a-m.md / <shard>-n-z.md), and
#          renders the bounded B-Tree Root routing table in wiki/index.md.
# @param: None (reads RNEX_WIKI_* configuration contracts).
# @returns: 0 on success; 1 on I/O or contract failure.
# @throws: Returns 1 if config contract is not loaded or writes fail; emits a
#          stderr warning when the compiled root exceeds the line ceiling.
# @sideEffects: Rebuilds wiki/_index/*.md and wiki/index.md deterministically
#               via a staging directory and atomic renames.
# -----------------------------------------------------------------------------
rebalance_btree_shards_and_compile_root() {
    # Fail-fast: contract must be loaded before any filesystem mutation
    if [ -z "${RNEX_WIKI_BTREE_DIR:-}" ] || [ -z "${RNEX_WIKI_INDEX_FILE:-}" ]; then
        printf 'Error [btree]: Wiki config contract not loaded (call load_wiki_config_contract).\n' >&2
        return 1
    fi

    init_wiki_graph_store || return 1
    mkdir -p "$RNEX_WIKI_BTREE_DIR" || return 1

    # Build into a sibling staging dir so readers never observe a half-built index
    _rb_stage="${RNEX_WIKI_BTREE_DIR}.stage.$$"
    rm -rf "${_rb_stage:?}"
    mkdir -p "$_rb_stage" || return 1

    # Step 1: Union of baseline shards and all shards discovered in nodes.tsv.
    # Shard slugs were normalized on write, so word-splitting is safe here.
    _rb_shards="$( {
        for _rb_b in $RNEX_WIKI_BTREE_BASE_SHARDS; do printf '%s\n' "$_rb_b"; done
        LC_ALL=C awk -F '\t' 'NF >= 5 && $2 != "" { print $2 }' "$RNEX_WIKI_NODES_TSV"
    } | LC_ALL=C sort -u )"

    # Step 2: Compile each shard, splitting when it exceeds the threshold
    for _rb_shard in $_rb_shards; do
        _rb_count="$(_btree_count_shard_nodes "$_rb_shard" "$RNEX_WIKI_NODES_TSV")"
        if [ "$_rb_count" -gt "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" ]; then
            # Split into two alphabetical key-range sub-shards: [a-m] and [n-z0-9...]
            for _rb_range in "a-m" "n-z"; do
                _btree_compile_shard "$_rb_shard" "$_rb_range" \
                    "${_rb_stage}/${_rb_shard}-${_rb_range}.md" "$RNEX_WIKI_NODES_TSV" \
                    || { rm -rf "${_rb_stage:?}"; return 1; }
            done
        else
            _btree_compile_shard "$_rb_shard" "" \
                "${_rb_stage}/${_rb_shard}.md" "$RNEX_WIKI_NODES_TSV" \
                || { rm -rf "${_rb_stage:?}"; return 1; }
        fi
    done

    # Step 3: Swap staged shards into place (remove stale shards, move new ones)
    rm -f "${RNEX_WIKI_BTREE_DIR:?}"/*.md
    for _rb_f in "$_rb_stage"/*.md; do
        [ -f "$_rb_f" ] || continue
        mv "$_rb_f" "$RNEX_WIKI_BTREE_DIR/" || { rm -rf "${_rb_stage:?}"; return 1; }
    done
    rm -rf "${_rb_stage:?}"

    # Step 4: Compile bounded B-Tree Root index.md (zero YAML frontmatter)
    _rb_root_tmp="${RNEX_WIKI_INDEX_FILE}.tmp.$$"
    _rb_nodes_total="$(LC_ALL=C awk 'END { print NR + 0 }' "$RNEX_WIKI_NODES_TSV")"
    _rb_edges_total="$(LC_ALL=C awk 'END { print NR + 0 }' "$RNEX_WIKI_EDGES_OUT_TSV")"
    _rb_index_rel="$(basename "$RNEX_WIKI_BTREE_DIR")"
    _rb_graph_rel="$(basename "$RNEX_WIKI_GRAPH_DIR")"

    {
        cat <<EOF
# Wiki Index (B-Tree Root Router)

Compact root routing table for the Karpathy LLM Wiki. Do not list individual pages here; follow the matching B-Tree shard in \`${_rb_index_rel}/\` or query the sorted TSV graph in \`${_rb_graph_rel}/\`.

## 1. B-Tree Domain Shards (\`${_rb_index_rel}/\`)

| Shard File | Key Range (\`LC_ALL=C\`) | Entries | Domain Scope |
| :--- | :--- | :--- | :--- |
EOF
        # Glob order depends on the caller's locale; re-sort shard names in
        # strict LC_ALL=C byte order for deterministic, Git-stable rows.
        # Shard names are validated slugs, so word-splitting is safe.
        _rb_names="$(for _rb_sp in "${RNEX_WIKI_BTREE_DIR}"/*.md; do
            [ -f "$_rb_sp" ] && basename "$_rb_sp" .md
        done | LC_ALL=C sort)"
        for _rb_n in $_rb_names; do
            _btree_render_root_row "${RNEX_WIKI_BTREE_DIR}/${_rb_n}.md"
        done
        cat <<EOF

## 2. Sorted TSV Property Graph (\`${_rb_graph_rel}/\`)

- **Total Indexed Nodes:** ${_rb_nodes_total} (\`${_rb_graph_rel}/nodes.tsv\`)
- **Total Directed Edges:** ${_rb_edges_total} (\`${_rb_graph_rel}/edges_out.tsv\` & \`${_rb_graph_rel}/edges_in.tsv\`)
- **Fast Prefix Search:** \`rnex plugin karpathy-llm search <prefix>\`
- **Subgraph Traversal:** \`rnex plugin karpathy-llm graph <node_id> --depth 1\`
- **Recent Audit History:** \`tail -n 20 _log.md\`
EOF
    } > "$_rb_root_tmp" || { rm -f "$_rb_root_tmp"; return 1; }

    mv "$_rb_root_tmp" "$RNEX_WIKI_INDEX_FILE" || return 1

    # Step 5: Enforce the bounded-root invariant (reported, enforced by lint)
    _rb_root_lines="$(LC_ALL=C awk 'END { print NR + 0 }' "$RNEX_WIKI_INDEX_FILE")"
    if [ "$_rb_root_lines" -gt "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ]; then
        printf 'Warning [btree]: Root index.md has %s lines (limit %s).\n' \
            "$_rb_root_lines" "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" >&2
    fi
    return 0
}

# -----------------------------------------------------------------------------
# init_wiki_btree_store
# Summary: Creates wiki/_index/ with the default sorted base shards
#          (overview, concepts, entities, sources) and compiles the initial
#          B-Tree Root wiki/index.md. Delegates to the rebalance builder (DRY).
# @param: None (reads RNEX_WIKI_* configuration contracts).
# @returns: 0 on success; 1 on I/O or contract failure.
# @throws: Propagates failures from rebalance_btree_shards_and_compile_root.
# @sideEffects: Creates wiki/, wiki/_index/, wiki/_graph/ and root index.md.
# -----------------------------------------------------------------------------
init_wiki_btree_store() {
    if [ -z "${RNEX_WIKI_ROOT:-}" ]; then
        printf 'Error [btree]: Wiki config contract not loaded (call load_wiki_config_contract).\n' >&2
        return 1
    fi
    mkdir -p "$RNEX_WIKI_ROOT" || return 1
    rebalance_btree_shards_and_compile_root
}
