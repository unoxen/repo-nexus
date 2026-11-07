#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/btree_helpers.sh
# Architectural Layer: Domain-Aware B-Tree Index Helpers (helpers/)
# Single Responsibility: Compile sorted B-Tree leaf shards in wiki/_index/*.md
# strictly for Concepts (Nexus-level general docs) and Repositories (>= 1 shard
# for Nexus repo and >= 1 shard per Member repo), and generate bounded root
# router at wiki/_index.md.
# Patterns Applied: Builder Pattern, Strategy Pattern (shard partitioning).
# Dependencies: config.sh, utils.sh, graph_helpers.sh
# Security (OWASP A03): Shard identifiers originate from normalize_slug_id;
# file mutations are executed via staging directories and atomic renames.
# =============================================================================

# -----------------------------------------------------------------------------
# resolve_shard_description
# Summary: Maps a canonical shard prefix to a concise architectural description
#          for the B-Tree Root routing table in wiki/_index.md.
# @param $1: shard_name - Name of the shard (e.g., "concepts", "repos-backend").
# @returns: Human-readable description string on stdout.
# @pure
# -----------------------------------------------------------------------------
resolve_shard_description() {
    case "$1" in
        concepts*)    printf 'General Nexus Repo concepts & architecture' ;;
        repos-nexus*) printf 'Nexus repository documentation' ;;
        repos-*)      printf 'Member repository documentation (%s)' "$1" ;;
        *)            printf 'Domain knowledge shard (%s)' "$1" ;;
    esac
}

# -----------------------------------------------------------------------------
# ensure_baseline_repo_shards
# Summary: Ensures wiki/_index/ always has at least one concepts.md shard,
#          at least one repos-nexus.md shard, and at least one
#          repos-<member_repo>.md shard for every enabled member repository.
# @param $1: target_dir - Directory containing shard markdown files (defaults to RNEX_WIKI_BTREE_DIR).
# @returns: 0 on success; 1 on filesystem error.
# @sideEffects: Creates baseline shard files in target_dir if no matching shards exist.
# -----------------------------------------------------------------------------
ensure_baseline_repo_shards() {
    _target_dir="${1:-$RNEX_WIKI_BTREE_DIR}"
    mkdir -p "$_target_dir" "$RNEX_WIKI_CONCEPTS_DIR" "${RNEX_WIKI_REPOS_DIR}/nexus" || return 1

    # 1. Baseline Nexus-level Concepts shard if no concepts* shard was emitted
    _has_concepts=0
    for _cf in "$_target_dir"/concepts*.md; do
        [ -f "$_cf" ] && { _has_concepts=1; break; }
    done
    if [ "$_has_concepts" -eq 0 ]; then
        cat <<'EOF' > "${_target_dir}/concepts.md"
# Wiki Index Shard: concepts (Nexus Repo General Docs)

- *(No concept pages compiled yet. Run `rnex plugin karpathy-llm ingest` to populate.)*
EOF
    fi

    # 2. Baseline Nexus repo index shard if no repos-nexus* shard was emitted
    _has_nexus=0
    for _rf in "$_target_dir"/repos-nexus*.md; do
        [ -f "$_rf" ] && { _has_nexus=1; break; }
    done
    if [ "$_has_nexus" -eq 0 ]; then
        cat <<'EOF' > "${_target_dir}/repos-nexus.md"
# Wiki Repository Index: nexus (Nexus Repository)

- *(No repository pages compiled for `nexus` yet. Run `rnex plugin karpathy-llm ingest` to populate.)*
EOF
    fi

    # 3. At least one repository index shard per enabled Member Repo
    for _member_repo in $(discover_enabled_member_repos); do
        _repo_slug="$(normalize_slug_id "$_member_repo")" || continue
        mkdir -p "${RNEX_WIKI_REPOS_DIR}/${_repo_slug}" || continue
        _has_member=0
        for _mrf in "$_target_dir"/repos-"${_repo_slug}"*.md; do
            [ -f "$_mrf" ] && { _has_member=1; break; }
        done
        if [ "$_has_member" -eq 0 ]; then
            cat <<EOF > "${_target_dir}/repos-${_repo_slug}.md"
# Wiki Repository Index: ${_member_repo} (Member Repository)

- *(No repository pages compiled for member repo \`${_member_repo}\` yet. Run \`rnex plugin karpathy-llm ingest\` to populate.)*
EOF
        fi
    done
    return 0
}

# -----------------------------------------------------------------------------
# rebalance_btree_shards_and_compile_root
# Summary: Compiles wiki/_index/concepts*.md and wiki/_index/repos-*.md
#          from nodes.tsv, splits oversized shards automatically into multiple
#          per-repo or concept shards, and writes the bounded root router at
#          wiki/_index.md (with zero entities, overview, or sources sections).
# @returns: 0 on success; 1 on I/O failure.
# @sideEffects: Rebuilds wiki/_index/*.md and wiki/_index.md deterministically.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2016
rebalance_btree_shards_and_compile_root() {
    if [ -z "${RNEX_WIKI_BTREE_DIR:-}" ] || [ -z "${RNEX_WIKI_INDEX_FILE:-}" ]; then
        printf 'Error [btree]: Wiki config contract not loaded (call load_karpathy_wiki_config).\n' >&2
        return 1
    fi

    init_wiki_graph_store || return 1
    mkdir -p "$RNEX_WIKI_BTREE_DIR" || return 1

    # Staging directory for atomic shard swap
    _stage="${RNEX_WIKI_BTREE_DIR}.stage.$$"
    rm -rf "${_stage:?}"
    mkdir -p "$_stage" || return 1

    # Purge legacy wiki/index.md and hot.md if present
    if [ -f "${RNEX_WIKI_ROOT}/index.md" ] && [ "$RNEX_WIKI_INDEX_FILE" != "${RNEX_WIKI_ROOT}/index.md" ]; then
        rm -f "${RNEX_WIKI_ROOT}/index.md"
    fi
    rm -f "${RNEX_WIKI_ROOT}/hot.md"

    # Step 1: Discover distinct non-legacy shards from nodes.tsv
    _shards="$(LC_ALL=C awk -F '\t' '
        NF >= 5 && $2 != "" {
            # Skip legacy categories (overview, entities, sources)
            if ($2 !~ /^overview/ && $2 !~ /^entities/ && $2 !~ /^sources/) {
                print $2
            }
        }
    ' "$RNEX_WIKI_NODES_TSV" 2>/dev/null | LC_ALL=C sort -u)"

    # Step 2: Compile each shard into staging, splitting oversized shards
    for _shard in $_shards; do
        _count="$(LC_ALL=C awk -F '\t' -v s="$_shard" '$2 == s { c++ } END { print c+0 }' "$RNEX_WIKI_NODES_TSV")"
        if [ "$_count" -gt "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" ]; then
            # Split into multiple range-partitioned index files for this repo or concept
            for _rng in "a-m" "n-z"; do
                _sub_shard="${_shard}-${_rng}"
                _out_file="${_stage}/${_sub_shard}.md"
                printf '# Wiki Index Shard: %s\n\n' "$_sub_shard" > "$_out_file"
                LC_ALL=C awk -F '\t' -v s="$_shard" -v rng="$_rng" '
                    $2 == s {
                        ch = substr($1, 1, 1)
                        in_am = (ch >= "a" && ch <= "m")
                        if ((rng == "a-m" && in_am) || (rng == "n-z" && !in_am)) {
                            printf "- [[%s]] — **%s**: %s (`%s`)\n", $1, $4, $5, $3
                            n++
                        }
                    }
                    END {
                        if (n == 0) {
                            print "- *(No pages in this key range yet.)*"
                        }
                    }
                ' "$RNEX_WIKI_NODES_TSV" >> "$_out_file"
            done
        else
            _out_file="${_stage}/${_shard}.md"
            case "$_shard" in
                repos-*) printf '# Wiki Repository Index: %s\n\n' "${_shard#repos-}" > "$_out_file" ;;
                *)       printf '# Wiki Index Shard: %s\n\n' "$_shard" > "$_out_file" ;;
            esac
            LC_ALL=C awk -F '\t' -v s="$_shard" '
                $2 == s {
                    printf "- [[%s]] — **%s**: %s (`%s`)\n", $1, $4, $5, $3
                    n++
                }
                END {
                    if (n == 0) {
                        print "- *(No pages compiled in this shard yet.)*"
                    }
                }
            ' "$RNEX_WIKI_NODES_TSV" >> "$_out_file"
        fi
    done

    # Step 3: Guarantee baseline concepts, repos-nexus, and per-member-repo shards exist
    ensure_baseline_repo_shards "$_stage" || { rm -rf "${_stage:?}"; return 1; }

    # Step 4: Swap staged shards into place
    rm -f "${RNEX_WIKI_BTREE_DIR:?}"/*.md
    for _sf in "$_stage"/*.md; do
        [ -f "$_sf" ] || continue
        mv "$_sf" "$RNEX_WIKI_BTREE_DIR/" || { rm -rf "${_stage:?}"; return 1; }
    done
    rm -rf "${_stage:?}"

    # Step 5: Compile bounded B-Tree Root Router at wiki/_index.md
    _root_tmp="${RNEX_WIKI_INDEX_FILE}.tmp.$$"
    _total_nodes="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_NODES_TSV" 2>/dev/null || printf '0')"
    _total_edges="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_EDGES_OUT_TSV" 2>/dev/null || printf '0')"

    {
        cat <<EOF
# Wiki Index (\`wiki/_index.md\`)

B-Tree Root Router for the Repo Nexus Karpathy LLM Wiki. Follow the target shard in \`_index/\` or traverse relationships via \`_graph/\`.

## 1. Concepts (Nexus Repo General Documentation)

| Shard Index File | Key Range (\`LC_ALL=C\`) | Entries | Scope |
| :--- | :--- | :--- | :--- |
EOF

        for _c_file in "${RNEX_WIKI_BTREE_DIR}"/concepts*.md; do
            [ -f "$_c_file" ] || continue
            _c_name="$(basename "$_c_file" .md)"
            _c_stats="$(LC_ALL=C awk '
                /^- \[\[/ {
                    key = $0
                    sub(/^- \[\[/, "", key)
                    sub(/\]\].*$/, "", key)
                    if (n == 0) min = key
                    max = key
                    n++
                }
                END { printf "%d\t%s\t%s", n + 0, min, max }
            ' "$_c_file")"
            _c_cnt="$(printf '%s' "$_c_stats" | cut -f 1)"
            if [ "$_c_cnt" -gt 0 ]; then
                _min="$(printf '%s' "$_c_stats" | cut -f 2)"
                _max="$(printf '%s' "$_c_stats" | cut -f 3)"
                _rng="\`${_min}\` .. \`${_max}\`"
            else
                _rng="*(empty)*"
            fi
            printf '| [`_index/%s.md`](_index/%s.md) | %s | %s | General Nexus Repo concepts & architecture |\n' \
                "$_c_name" "$_c_name" "$_rng" "$_c_cnt"
        done

        cat <<EOF

## 2. Repositories (Nexus Repo & Member Repositories)

| Repo Index File | Repository / Sub-Scope | Key Range (\`LC_ALL=C\`) | Entries |
| :--- | :--- | :--- | :--- |
EOF

        for _r_file in "${RNEX_WIKI_BTREE_DIR}"/repos-*.md; do
            [ -f "$_r_file" ] || continue
            _r_name="$(basename "$_r_file" .md)"
            _repo_scope="${_r_name#repos-}"
            _r_stats="$(LC_ALL=C awk '
                /^- \[\[/ {
                    key = $0
                    sub(/^- \[\[/, "", key)
                    sub(/\]\].*$/, "", key)
                    if (n == 0) min = key
                    max = key
                    n++
                }
                END { printf "%d\t%s\t%s", n + 0, min, max }
            ' "$_r_file")"
            _r_cnt="$(printf '%s' "$_r_stats" | cut -f 1)"
            if [ "$_r_cnt" -gt 0 ]; then
                _min="$(printf '%s' "$_r_stats" | cut -f 2)"
                _max="$(printf '%s' "$_r_stats" | cut -f 3)"
                _rng="\`${_min}\` .. \`${_max}\`"
            else
                _rng="*(empty)*"
            fi
            printf '| [`_index/%s.md`](_index/%s.md) | `%s` | %s | %s |\n' \
                "$_r_name" "$_r_name" "$_repo_scope" "$_rng" "$_r_cnt"
        done

        cat <<EOF

## 3. Property Graph Store (\`_graph/\`)

- **Nodes Indexed:** ${_total_nodes} (\`_graph/nodes.tsv\`)
- **Directed Edges:** ${_total_edges} (\`_graph/edges_out.tsv\` & \`_graph/edges_in.tsv\`)
EOF
    } > "$_root_tmp" || { rm -f "$_root_tmp"; return 1; }

    mv "$_root_tmp" "$RNEX_WIKI_INDEX_FILE" || return 1

    # Step 6: Verify bounded root line invariant
    _root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_INDEX_FILE")"
    if [ "$_root_lines" -gt "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ]; then
        printf 'Warning [btree]: wiki/_index.md exceeds %s lines (%s lines).\n' \
            "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" "$_root_lines" >&2
    fi
    return 0
}

# -----------------------------------------------------------------------------
# init_wiki_btree_store
# Summary: Creates wiki/_index/ and compiles initial B-Tree shards and root
#          router at wiki/_index.md. Delegates to rebalance builder.
# @returns: 0 on success; 1 on failure.
# @sideEffects: Creates _index/*.md and wiki/_index.md.
# -----------------------------------------------------------------------------
init_wiki_btree_store() {
    if [ -z "${RNEX_WIKI_ROOT:-}" ]; then
        printf 'Error [btree]: Wiki config contract not loaded (call load_karpathy_wiki_config).\n' >&2
        return 1
    fi
    mkdir -p "$RNEX_WIKI_ROOT" || return 1
    rebalance_btree_shards_and_compile_root
}
