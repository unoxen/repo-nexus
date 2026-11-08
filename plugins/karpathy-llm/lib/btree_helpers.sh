#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2016
# =============================================================================
# File: plugins/karpathy-llm/lib/btree_helpers.sh
# Architectural Layer: Domain-Aware B-Tree Index Helpers (helpers/)
# Single Responsibility: Compile sorted B-Tree Markdown shards directly inside
# wiki/ (wiki/repo-nexus*.md and wiki/repos-*.md), split oversized shards,
# compile the bounded (<= 80 lines) root router at wiki/index.md, and maintain
# the chronological audit log at wiki/log.md.
# Patterns Applied: Builder Pattern, Strategy Pattern (range splitting).
# Dependencies: config.sh, utils.sh, source_helpers.sh
# Security (OWASP A03): Atomic file overwrites; safe variable bounds; zero symlinks.
# =============================================================================

# -----------------------------------------------------------------------------
# purge_legacy_wiki_artifacts
# Summary: Deletes deprecated wiki directories (_graph/, _index/, concepts/,
#          repos/, sources/, overview/, entities/), legacy files (_index.md, hot.md),
#          and all symbolic links inside wiki/. Migrates _log.md to log.md.
# @returns: 0 on success; 1 on directory creation error.
# @sideEffects: Removes deprecated files, folders, and symlinks.
# -----------------------------------------------------------------------------
purge_legacy_wiki_artifacts() {
    mkdir -p "$RNEX_WIKI_ROOT" || return 1

    # Preserve historical audit log entries if migrating from legacy _log.md -> log.md
    if [ -f "${RNEX_WIKI_ROOT}/_log.md" ]; then
        if [ ! -f "$RNEX_WIKI_LOG_FILE" ]; then
            mv "${RNEX_WIKI_ROOT}/_log.md" "$RNEX_WIKI_LOG_FILE"
        else
            _merged_log_tmp="${RNEX_WIKI_LOG_FILE}.mig.$$"
            cat "${RNEX_WIKI_ROOT}/_log.md" "$RNEX_WIKI_LOG_FILE" > "$_merged_log_tmp"
            mv "$_merged_log_tmp" "$RNEX_WIKI_LOG_FILE"
            rm -f "${RNEX_WIKI_ROOT}/_log.md"
        fi
    fi

    # Remove all symbolic links inside wiki/ (Windows & Git safety)
    find "$RNEX_WIKI_ROOT" -type l -exec rm -f {} + 2>/dev/null || true

    # Delete deprecated _graph/, _index/, and legacy category directories
    rm -rf "${RNEX_WIKI_ROOT}/_graph" \
           "${RNEX_WIKI_ROOT}/_index" \
           "${RNEX_WIKI_ROOT}/concepts" \
           "${RNEX_WIKI_ROOT}/repos" \
           "${RNEX_WIKI_ROOT}/sources" \
           "${RNEX_WIKI_ROOT}/entities" \
           "${RNEX_WIKI_ROOT}/overview" \
           "${RNEX_WIKI_ROOT}/_index.md" \
           "${RNEX_WIKI_ROOT}/hot.md"

    return 0
}

# -----------------------------------------------------------------------------
# ensure_baseline_flat_shards
# Summary: Guarantees at least one baseline wiki/repo-nexus.md shard exists
#          for the root Nexus repository and at least one wiki/repos-<member>.md
#          shard exists for every enabled member repository.
# @returns: 0 on success.
# @sideEffects: Writes initial placeholder shard files if missing.
# -----------------------------------------------------------------------------
ensure_baseline_flat_shards() {
    # 1. Ensure baseline repo-nexus shard if no repo-nexus*.md exists
    _has_nexus_shard=0
    for _nf in "${RNEX_WIKI_ROOT}"/repo-nexus*.md; do
        [ -f "$_nf" ] && { _has_nexus_shard=1; break; }
    done
    if [ "$_has_nexus_shard" -eq 0 ]; then
        cat <<'EOF' > "${RNEX_WIKI_ROOT}/repo-nexus.md"
# Wiki Shard: repo-nexus (Nexus Repository)

- *(No source pages indexed for `repo-nexus` yet. Run `rnex plugin karpathy-llm ingest` to populate.)*
EOF
    fi

    # 2. Ensure baseline shard per enabled member repository
    for _member_repo in $(discover_enabled_member_repos < /dev/null); do
        _repo_slug="$(normalize_slug_id "$_member_repo")" || continue
        _has_member_shard=0
        for _mrf in "${RNEX_WIKI_ROOT}/repos-${_repo_slug}"*.md; do
            [ -f "$_mrf" ] && { _has_member_shard=1; break; }
        done
        if [ "$_has_member_shard" -eq 0 ]; then
            cat <<EOF > "${RNEX_WIKI_ROOT}/repos-${_repo_slug}.md"
# Wiki Shard: repos-${_repo_slug} (Member Repository: ${_member_repo})

- *(No source pages indexed for member repo \`${_member_repo}\` yet. Run \`rnex plugin karpathy-llm ingest\` to populate.)*
EOF
        fi
    done
    return 0
}

# -----------------------------------------------------------------------------
# append_wiki_log_entry
# Summary: Appends a single formatted audit record to the append-only log.md.
# @param $1: operation - Short operational tag (e.g., "ingest", "lint").
# @param $2: message   - Informative human-readable description.
# @sideEffects: Appends ISO-8601 UTC timestamped line to RNEX_WIKI_LOG_FILE.
# -----------------------------------------------------------------------------
append_wiki_log_entry() {
    _op="$(sanitize_single_line_text "$1")"
    _msg="$(sanitize_single_line_text "$2")"
    _today="$(get_iso_utc_date)"

    if [ ! -f "$RNEX_WIKI_LOG_FILE" ]; then
        printf '# Wiki Operational Audit Log\n\n' > "$RNEX_WIKI_LOG_FILE"
    fi
    printf -- '- **%s** | `%s` | %s\n' "$_today" "$_op" "$_msg" >> "$RNEX_WIKI_LOG_FILE"
}

# -----------------------------------------------------------------------------
# compile_flat_btree_wiki
# Summary: Complete compiler pipeline for the flat B-Tree engine. Purges legacy
#          directories, compiles sorted shards directly in wiki/ (*.md),
#          splits oversized shards into alphabetical ranges (a-m / n-z), and
#          writes the bounded root router at wiki/index.md (<= 80 lines).
# @returns: 0 on success; 1 on failure.
# @sideEffects: Rebuilds wiki/*.md shards and wiki/index.md atomically.
# -----------------------------------------------------------------------------
compile_flat_btree_wiki() {
    purge_legacy_wiki_artifacts || return 1

    _records_tmp="${RNEX_WIKI_ROOT}/.btree_records.tmp.$$"
    build_workspace_btree_records "$_records_tmp" || {
        rm -f "$_records_tmp"
        return 1
    }

    # Remove previous generated shard files in wiki/ (preserving index.md & log.md)
    rm -f "${RNEX_WIKI_ROOT}"/repo-nexus*.md "${RNEX_WIKI_ROOT}"/repos-*.md

    # Discover all unique shard IDs in sorted order
    _shards="$(LC_ALL=C awk -F '\t' 'NF >= 5 { print $1 }' "$_records_tmp" | LC_ALL=C sort -u)"

    for _shard in $_shards; do
        [ -n "$_shard" ] || continue
        _count="$(LC_ALL=C awk -F '\t' -v s="$_shard" '$1 == s { c++ } END { print c+0 }' "$_records_tmp")"

        if [ "$_count" -gt "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" ]; then
            for _rng in "a-m" "n-z"; do
                _sub_shard="${_shard}-${_rng}"
                _shard_file="${RNEX_WIKI_ROOT}/${_sub_shard}.md"
                printf '# Wiki Shard: %s\n\n' "$_sub_shard" > "$_shard_file"
                LC_ALL=C awk -F '\t' -v s="$_shard" -v rng="$_rng" '
                    $1 == s {
                        ch = tolower(substr($2, 1, 1))
                        in_am = (ch >= "a" && ch <= "m")
                        if ((rng == "a-m" && in_am) || (rng == "n-z" && !in_am)) {
                            printf "- **%s** (`%s`) — %s: %s\n", $2, $3, $4, $5
                        }
                    }
                ' "$_records_tmp" >> "$_shard_file"
            done
        else
            _shard_file="${RNEX_WIKI_ROOT}/${_shard}.md"
            printf '# Wiki Shard: %s\n\n' "$_shard" > "$_shard_file"
            LC_ALL=C awk -F '\t' -v s="$_shard" '
                $1 == s {
                    printf "- **%s** (`%s`) — %s: %s\n", $2, $3, $4, $5
                }
            ' "$_records_tmp" >> "$_shard_file"
        fi
    done

    rm -f "$_records_tmp"
    ensure_baseline_flat_shards || return 1

    # Compile bounded B-Tree Root Router at wiki/index.md (<= 80 lines)
    _root_tmp="${RNEX_WIKI_INDEX_FILE}.tmp.$$"
    cat <<'EOF' > "$_root_tmp"
# Wiki Index (`wiki/index.md`)

B-Tree Root Router for the Repo Nexus Karpathy LLM Wiki. Open the target shard file below to browse indexed documentation in place.

## 1. Repo Nexus (`repo-nexus*.md`)

| Shard File | Key Range (`LC_ALL=C`) | Entries | Scope |
| :--- | :--- | :--- | :--- |
EOF

    for _nx_file in "${RNEX_WIKI_ROOT}"/repo-nexus*.md; do
        [ -f "$_nx_file" ] || continue
        _nx_base="$(basename "$_nx_file")"
        _nx_cnt="$(LC_ALL=C grep -c '^- \*\*' "$_nx_file" 2>/dev/null || true)"
        [ -n "$_nx_cnt" ] || _nx_cnt=0
        if [ "$_nx_cnt" -gt 0 ]; then
            _min="$(LC_ALL=C grep '^- \*\*' "$_nx_file" | head -n 1 | sed 's/^- \*\*\([^*]*\)\*\*.*/\1/')"
            _max="$(LC_ALL=C grep '^- \*\*' "$_nx_file" | tail -n 1 | sed 's/^- \*\*\([^*]*\)\*\*.*/\1/')"
            _rng="\`${_min}\` .. \`${_max}\`"
        else
            _rng="*(empty)*"
        fi
        printf '| [`%s`](%s) | %s | %s | Root Nexus Repository documentation |\n' \
            "$_nx_base" "$_nx_base" "$_rng" "$_nx_cnt" >> "$_root_tmp"
    done

    cat <<'EOF' >> "$_root_tmp"

## 2. Member Repositories (`repos-*.md`)

| Shard File | Repository / Sub-Scope | Key Range (`LC_ALL=C`) | Entries |
| :--- | :--- | :--- | :--- |
EOF

    for _rp_file in "${RNEX_WIKI_ROOT}"/repos-*.md; do
        [ -f "$_rp_file" ] || continue
        _rp_base="$(basename "$_rp_file")"
        _rp_name="${_rp_base%.md}"
        _rp_scope="${_rp_name#repos-}"
        _rp_cnt="$(LC_ALL=C grep -c '^- \*\*' "$_rp_file" 2>/dev/null || true)"
        [ -n "$_rp_cnt" ] || _rp_cnt=0
        if [ "$_rp_cnt" -gt 0 ]; then
            _min="$(LC_ALL=C grep '^- \*\*' "$_rp_file" | head -n 1 | sed 's/^- \*\*\([^*]*\)\*\*.*/\1/')"
            _max="$(LC_ALL=C grep '^- \*\*' "$_rp_file" | tail -n 1 | sed 's/^- \*\*\([^*]*\)\*\*.*/\1/')"
            _rng="\`${_min}\` .. \`${_max}\`"
        else
            _rng="*(empty)*"
        fi
        printf '| [`%s`](%s) | `%s` | %s | %s |\n' \
            "$_rp_base" "$_rp_base" "$_rp_scope" "$_rng" "$_rp_cnt" >> "$_root_tmp"
    done

    mv "$_root_tmp" "$RNEX_WIKI_INDEX_FILE"
    return 0
}

# -----------------------------------------------------------------------------
# Backwards-Compatible Aliases
# -----------------------------------------------------------------------------
purge_legacy_wiki_directories_and_symlinks() {
    purge_legacy_wiki_artifacts
}

ensure_baseline_btree_shards() {
    ensure_baseline_flat_shards
}

rebalance_btree_shards_and_compile_root() {
    compile_flat_btree_wiki
}
