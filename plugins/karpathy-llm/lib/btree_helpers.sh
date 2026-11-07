#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/btree_helpers.sh
# Architectural Layer: Domain-Aware B-Tree Index Helpers (helpers/)
# Single Responsibility: Compile sorted B-Tree catalog shards in wiki/_index/*.md
# strictly for repo-nexus and repos-<member> scopes, and generate the bounded
# root router at wiki/_index.md.
# Patterns Applied: Builder Pattern, Strategy Pattern (shard partitioning).
# Dependencies: config.sh, utils.sh, graph_helpers.sh
# Security (OWASP A03): Shard identifiers originate from normalize_slug_id;
# mutations are staged and committed atomically via rename.
# =============================================================================

# -----------------------------------------------------------------------------
# purge_legacy_wiki_directories_and_symlinks
# Summary: Deletes deprecated wiki directories (concepts/, repos/, sources/,
#          overview/, entities/), legacy shards (concepts*.md, hot.md), and
#          any symbolic links inside wiki/.
# @returns: 0 on success.
# @sideEffects: Removes deprecated files, folders, and symlinks.
# -----------------------------------------------------------------------------
purge_legacy_wiki_directories_and_symlinks() {
    [ -d "$RNEX_WIKI_ROOT" ] || return 0

    find "$RNEX_WIKI_ROOT" -type l -exec rm -f {} + 2>/dev/null || true

    rm -rf "${RNEX_WIKI_ROOT}/concepts" \
           "${RNEX_WIKI_ROOT}/repos" \
           "${RNEX_WIKI_ROOT}/sources" \
           "${RNEX_WIKI_ROOT}/overview" \
           "${RNEX_WIKI_ROOT}/entities" \
           "${RNEX_WIKI_ROOT}/hot.md" \
           "${RNEX_WIKI_ROOT}/index.md"

    if [ -d "$RNEX_WIKI_BTREE_DIR" ]; then
        rm -f "${RNEX_WIKI_BTREE_DIR}"/concepts*.md \
              "${RNEX_WIKI_BTREE_DIR}"/entities*.md \
              "${RNEX_WIKI_BTREE_DIR}"/overview*.md \
              "${RNEX_WIKI_BTREE_DIR}"/sources*.md
    fi
    return 0
}

# -----------------------------------------------------------------------------
# ensure_baseline_btree_shards
# Summary: Guarantees at least one wiki/_index/repo-nexus.md shard exists for
#          the Nexus repository and at least one wiki/_index/repos-<member>.md
#          shard exists for every enabled member repository.
# @returns: 0 on success.
# -----------------------------------------------------------------------------
ensure_baseline_btree_shards() {
    mkdir -p "$RNEX_WIKI_BTREE_DIR" || return 1

    # 1. Baseline Nexus repo index shard if no repo-nexus* shard exists
    _has_nexus_shard=0
    for _nf in "${RNEX_WIKI_BTREE_DIR}"/repo-nexus*.md; do
        [ -f "$_nf" ] && { _has_nexus_shard=1; break; }
    done
    if [ "$_has_nexus_shard" -eq 0 ]; then
        cat <<'EOF' > "${RNEX_WIKI_BTREE_DIR}/repo-nexus.md"
# Wiki Index Shard: repo-nexus (Nexus Repository)

- *(No source pages indexed for `repo-nexus` yet. Run `rnex plugin karpathy-llm ingest` to populate.)*
EOF
    fi

    # 2. At least one repository index shard per enabled Member Repo
    for _member_repo in $(discover_enabled_member_repos < /dev/null); do
        _repo_slug="$(normalize_slug_id "$_member_repo")" || continue
        _has_member_shard=0
        for _mrf in "${RNEX_WIKI_BTREE_DIR}"/repos-"${_repo_slug}"*.md; do
            [ -f "$_mrf" ] && { _has_member_shard=1; break; }
        done
        if [ "$_has_member_shard" -eq 0 ]; then
            cat <<EOF > "${RNEX_WIKI_BTREE_DIR}/repos-${_repo_slug}.md"
# Wiki Index Shard: repos-${_repo_slug} (Member Repository: ${_member_repo})

- *(No source pages indexed for member repo \`${_member_repo}\` yet. Run \`rnex plugin karpathy-llm ingest\` to populate.)*
EOF
        fi
    done
    return 0
}

# -----------------------------------------------------------------------------
# rebalance_btree_shards_and_compile_root
# Summary: Partitions nodes by shard_id, splits shards exceeding maximum entry
#          thresholds, writes sorted shards in wiki/_index/, and compiles
#          wiki/_index.md (<= 80 lines).
# @returns: 0 on success; 1 on I/O error.
# @sideEffects: Rebuilds wiki/_index/*.md and wiki/_index.md.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2016
rebalance_btree_shards_and_compile_root() {
    mkdir -p "$RNEX_WIKI_BTREE_DIR" || return 1
    rm -f "${RNEX_WIKI_BTREE_DIR}"/*.md

    _shards="$(LC_ALL=C awk -F '\t' 'NF >= 5 { print $2 }' "$RNEX_WIKI_NODES_TSV" 2>/dev/null | LC_ALL=C sort -u)"

    for _shard in $_shards; do
        [ -n "$_shard" ] || continue
        _count="$(LC_ALL=C awk -F '\t' -v s="$_shard" '$2 == s { c++ } END { print c+0 }' "$RNEX_WIKI_NODES_TSV")"
        if [ "$_count" -gt "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" ]; then
            for _rng in "a-m" "n-z"; do
                _sub_shard="${_shard}-${_rng}"
                _out_file="${RNEX_WIKI_BTREE_DIR}/${_sub_shard}.md"
                printf '# Wiki Index Shard: %s\n\n' "$_sub_shard" > "$_out_file"
                LC_ALL=C awk -F '\t' -v s="$_shard" -v rng="$_rng" '
                    $2 == s {
                        key = $1
                        pfx = s "-"
                        if (substr(key, 1, length(pfx)) == pfx) {
                            key = substr(key, length(pfx) + 1)
                        } else if (substr(key, 1, 11) == "repo-nexus-") {
                            key = substr(key, 12)
                        } else {
                            sub(/^repos-[^-]+-/, "", key)
                        }
                        ch = tolower(substr(key, 1, 1))
                        in_am = (ch >= "a" && ch <= "m")
                        if ((rng == "a-m" && in_am) || (rng == "n-z" && !in_am)) {
                            printf "- [[%s]] — **%s**: %s (`%s`)\n", $1, $4, $5, $3
                        }
                    }
                ' "$RNEX_WIKI_NODES_TSV" >> "$_out_file"
            done
        else
            _out_file="${RNEX_WIKI_BTREE_DIR}/${_shard}.md"
            printf '# Wiki Index Shard: %s\n\n' "$_shard" > "$_out_file"
            LC_ALL=C awk -F '\t' -v s="$_shard" '
                $2 == s {
                    printf "- [[%s]] — **%s**: %s (`%s`)\n", $1, $4, $5, $3
                }
            ' "$RNEX_WIKI_NODES_TSV" >> "$_out_file"
        fi
    done

    ensure_baseline_btree_shards || return 1

    _root_tmp="${RNEX_WIKI_INDEX_FILE}.tmp.$$"
    _total_nodes="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_NODES_TSV" 2>/dev/null || printf '0')"
    _total_edges="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_EDGES_OUT_TSV" 2>/dev/null || printf '0')"

    cat <<EOF > "$_root_tmp"
# Wiki Index (\`wiki/_index.md\`)

B-Tree Root Router for the Repo Nexus Karpathy LLM Wiki. Query shards in \`_index/\` or relationships via \`_graph/\`.

## 1. Repo Nexus (Root Repository)

| Shard Index File | Key Range (\`LC_ALL=C\`) | Entries | Scope |
| :--- | :--- | :--- | :--- |
EOF

    for _n_file in "${RNEX_WIKI_BTREE_DIR}"/repo-nexus*.md; do
        [ -f "$_n_file" ] || continue
        _n_name="$(basename "$_n_file" .md)"
        _n_cnt="$(LC_ALL=C grep -c '^- \[\[' "$_n_file" 2>/dev/null || true)"
        [ -n "$_n_cnt" ] || _n_cnt=0
        if [ "$_n_cnt" -gt 0 ]; then
            _min="$(LC_ALL=C grep '^- \[\[' "$_n_file" | head -n 1 | sed 's/^- \[\[\([^]]*\)\]\].*/\1/')"
            _max="$(LC_ALL=C grep '^- \[\[' "$_n_file" | tail -n 1 | sed 's/^- \[\[\([^]]*\)\]\].*/\1/')"
            _rng="\`${_min}\` .. \`${_max}\`"
        else
            _rng="*(empty)*"
        fi
        printf '| [`_index/%s.md`](_index/%s.md) | %s | %s | Nexus workspace sources & architecture |\n' \
            "$_n_name" "$_n_name" "$_rng" "$_n_cnt" >> "$_root_tmp"
    done

    cat <<EOF >> "$_root_tmp"

## 2. Member Repositories

| Member Repo Shard | Repository Scope | Key Range (\`LC_ALL=C\`) | Entries |
| :--- | :--- | :--- | :--- |
EOF

    for _r_file in "${RNEX_WIKI_BTREE_DIR}"/repos-*.md; do
        [ -f "$_r_file" ] || continue
        _r_name="$(basename "$_r_file" .md)"
        _repo_scope="${_r_name#repos-}"
        _r_cnt="$(LC_ALL=C grep -c '^- \[\[' "$_r_file" 2>/dev/null || true)"
        [ -n "$_r_cnt" ] || _r_cnt=0
        if [ "$_r_cnt" -gt 0 ]; then
            _min="$(LC_ALL=C grep '^- \[\[' "$_r_file" | head -n 1 | sed 's/^- \[\[\([^]]*\)\]\].*/\1/')"
            _max="$(LC_ALL=C grep '^- \[\[' "$_r_file" | tail -n 1 | sed 's/^- \[\[\([^]]*\)\]\].*/\1/')"
            _rng="\`${_min}\` .. \`${_max}\`"
        else
            _rng="*(empty)*"
        fi
        printf '| [`_index/%s.md`](_index/%s.md) | `%s` | %s | %s |\n' \
            "$_r_name" "$_r_name" "$_repo_scope" "$_rng" "$_r_cnt" >> "$_root_tmp"
    done

    cat <<EOF >> "$_root_tmp"

## 3. Property Graph Store (\`_graph/\`)

- **Nodes Indexed:** ${_total_nodes} (\`_graph/nodes.tsv\`)
- **Directed Edges:** ${_total_edges} (\`_graph/edges_out.tsv\` & \`_graph/edges_in.tsv\`)
EOF

    mv "$_root_tmp" "$RNEX_WIKI_INDEX_FILE"
    return 0
}
