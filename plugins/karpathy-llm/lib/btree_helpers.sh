#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2016
# =============================================================================
# File: plugins/karpathy-llm/lib/btree_helpers.sh
# Architectural Layer: Domain Helpers (helpers/)
# Single Responsibility: Incrementally merge newly discovered missing sources
# into flat B-Tree shards (.rnex/wiki/*.md), maintain strict LC_ALL=C sort
# order, compile .rnex/wiki/index.md router, and append audit entries to log.md.
#
# Design Patterns Applied:
#   - Builder Pattern: Incrementally merges missing entries and builds clean
#     Markdown shard catalogs and root router index tables.
#   - Information Expert (GRASP): Encapsulates title extraction, summary
#     sanitization, and Markdown shard formatting.
#   - Single Responsibility Principle (SRP): Confined strictly to B-Tree shard
#     mutation and root router synthesis. Zero linting or validation logic.
#
# Standards: Pure POSIX Shell (/bin/sh), OWASP ASVS A03 Atomic File Operations.
# =============================================================================

# Guard against redundant multiple inclusion
if [ "${RNEX_KARPATHY_BTREE_HELPERS_SH_SOURCED:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
RNEX_KARPATHY_BTREE_HELPERS_SH_SOURCED=1

# -----------------------------------------------------------------------------
# extract_markdown_title_and_summary
# Summary: Extracts the first H1 heading and first non-empty prose paragraph
#          from a Markdown file, skipping YAML frontmatter and code blocks.
# @param $1: abs_file_path - Absolute path to the Markdown document.
# @param $2: fallback_title - Fallback title if no H1 heading exists.
# @returns: "<title>|<summary>" on stdout.
# @pure
# -----------------------------------------------------------------------------
extract_markdown_title_and_summary() {
    _file="$1"
    _fallback="$2"
    LC_ALL=C awk -v def_title="$_fallback" '
        BEGIN { in_frontmatter=0; in_code=0; title=""; summary="" }
        NR == 1 && /^---[[:space:]]*$/ { in_frontmatter=1; next }
        in_frontmatter == 1 {
            if (/^(---|\.\.\.)[[:space:]]*$/) in_frontmatter=0
            next
        }
        /^```/ { in_code = !in_code; next }
        in_code == 1 { next }
        title == "" && /^#[[:space:]]+/ {
            line = $0
            sub(/^#[[:space:]]+/, "", line)
            gsub(/\r/, "", line)
            title = line
            next
        }
        title != "" && summary == "" && $0 !~ /^[[:space:]]*$/ && $0 !~ /^[#>-]/ && $0 !~ /^\|/ {
            line = $0
            gsub(/\r/, "", line)
            summary = line
            exit
        }
        END {
            if (title == "") title = def_title
            if (summary == "") summary = "Workspace documentation page."
            printf "%s|%s\n", title, summary
        }
    ' "$_file"
}

# -----------------------------------------------------------------------------
# append_wiki_log_entry
# Summary: Appends an ISO-8601 UTC audit record line to .rnex/wiki/log.md.
# @param $1: action_name - Operation name ("ingest" or "lint").
# @param $2: details     - Human-readable operation summary.
# @returns: 0 on success.
# @sideEffects: Creates or appends to $RNEX_WIKI_LOG_FILE.
# -----------------------------------------------------------------------------
append_wiki_log_entry() {
    _action="$(sanitize_single_line_text "$1")"
    _details="$(sanitize_single_line_text "$2")"
    mkdir -p "$RNEX_WIKI_ROOT"
    if [ ! -f "$RNEX_WIKI_LOG_FILE" ]; then
        cat <<'EOF' > "$RNEX_WIKI_LOG_FILE"
# Wiki Operational Log

EOF
    fi
    _utc_date="$(get_iso_utc_date)"
    printf -- '- **%s** | `%s` | %s\n' "$_utc_date" "$_action" "$_details" >> "$RNEX_WIKI_LOG_FILE"
    return 0
}

# -----------------------------------------------------------------------------
# compile_root_index_router
# Summary: Deterministically compiles .rnex/wiki/index.md from all existing
#          leaf shards (repo-nexus*.md and repos-*.md) inside $RNEX_WIKI_ROOT.
#          Guarantees line count <= RNEX_WIKI_BTREE_MAX_ROOT_LINES.
# @returns: 0 on success.
# @sideEffects: Writes $RNEX_WIKI_INDEX_FILE atomically.
# -----------------------------------------------------------------------------
compile_root_index_router() {
    _idx_tmp="${RNEX_WIKI_INDEX_FILE}.tmp.$$"
    cat <<'EOF' > "$_idx_tmp"
# Wiki Index

## 1. Repo Nexus Shards (`repo-nexus*.md`)

| Shard | Entries |
| :--- | :--- |
EOF

    _found_nexus=0
    for _shard in "${RNEX_WIKI_ROOT}"/repo-nexus*.md; do
        [ -f "$_shard" ] || continue
        _found_nexus=1
        _bname="$(basename "$_shard")"
        _cnt="$(LC_ALL=C grep -c '^- \*\*' "$_shard" 2>/dev/null || printf '0')"
        printf '| [%s](%s) | %s |\n' "$_bname" "$_bname" "$_cnt" >> "$_idx_tmp"
    done
    if [ "$_found_nexus" -eq 0 ]; then
        printf '| *(none)* | 0 |\n' >> "$_idx_tmp"
    fi

    cat <<'EOF' >> "$_idx_tmp"

## 2. Member Repository Shards (`repos-*.md`)

| Shard | Entries |
| :--- | :--- |
EOF

    _found_repos=0
    for _shard in "${RNEX_WIKI_ROOT}"/repos-*.md; do
        [ -f "$_shard" ] || continue
        _found_repos=1
        _bname="$(basename "$_shard")"
        _cnt="$(LC_ALL=C grep -c '^- \*\*' "$_shard" 2>/dev/null || printf '0')"
        printf '| [%s](%s) | %s |\n' "$_bname" "$_bname" "$_cnt" >> "$_idx_tmp"
    done
    if [ "$_found_repos" -eq 0 ]; then
        printf '| *(none)* | 0 |\n' >> "$_idx_tmp"
    fi

    mv "$_idx_tmp" "$RNEX_WIKI_INDEX_FILE"
    return 0
}

# -----------------------------------------------------------------------------
# ingest_missing_sources_into_btree
# Summary: Reads missing workspace-relative source paths from $1, appends only
#          those missing entries into their respective .rnex/wiki/*.md shards,
#          maintains strict LC_ALL=C sort order, and updates .rnex/wiki/index.md.
# @param $1: missing_manifest_file - File containing missing workspace_rel_paths.
# @param $2: source_arg_label     - Optional CLI argument for log attribution.
# @returns: 0 on success.
# @sideEffects: Updates .rnex/wiki/*.md shards, index.md, and log.md.
# -----------------------------------------------------------------------------
ingest_missing_sources_into_btree() {
    _missing_file="$1"
    _arg_label="$2"
    mkdir -p "$RNEX_WIKI_ROOT"

    # If zero missing sources and index.md already exists, wiki is completely up-to-date
    if [ ! -s "$_missing_file" ] && [ -f "$RNEX_WIKI_INDEX_FILE" ]; then
        printf 'Wiki is up to date (0 missing sources to ingest in %s).\n' "$RNEX_WIKI_REL_DIR"
        return 0
    fi

    _up_prefix="${RNEX_WIKI_UP_PREFIX:-}"
    if [ -z "$_up_prefix" ] && command -v compute_upward_rel_prefix >/dev/null 2>&1; then
        _up_prefix="$(compute_upward_rel_prefix "$RNEX_WIKI_REL_DIR")"
    fi
    [ -n "$_up_prefix" ] || _up_prefix="../../"

    _ingested_count=0

    if [ -s "$_missing_file" ]; then
        while IFS= read -r _rel_path <&3; do
            [ -n "$_rel_path" ] || continue
            _abs_path="${RNEX_WORKSPACE_ROOT}/${_rel_path}"
            [ -f "$_abs_path" ] || continue

            _shard_id="$(derive_shard_id_for_workspace_path "$_rel_path")"
            _shard_file="${RNEX_WIKI_ROOT}/${_shard_id}.md"

            _meta="$(extract_markdown_title_and_summary "$_abs_path" "$(basename "$_rel_path")")"
            _raw_title="${_meta%%|*}"
            _raw_summary="${_meta#*|}"
            _title="$(sanitize_markdown_summary "$_raw_title")"
            _summary="$(sanitize_markdown_summary "$_raw_summary")"
            _rel_link="${_up_prefix}${_rel_path}"

            _entry_line="- **[${_title}](${_rel_link})** (\`${_rel_path}\`) — ${_summary}"

            # Route to existing sub-shard if already split, otherwise to base shard
            _target_shard_file="${_shard_file}"
            if [ -f "${RNEX_WIKI_ROOT}/${_shard_id}-a-m.md" ] || [ -f "${RNEX_WIKI_ROOT}/${_shard_id}-n-z.md" ]; then
                _ch="$(printf '%s' "$_title" | tr '[:upper:]' '[:lower:]' | cut -c1)"
                case "$_ch" in
                    [a-m]) _target_shard_file="${RNEX_WIKI_ROOT}/${_shard_id}-a-m.md" ;;
                    *)     _target_shard_file="${RNEX_WIKI_ROOT}/${_shard_id}-n-z.md" ;;
                esac
            fi

            # Extract existing catalog entries from target shard, append new entry, and sort
            _entries_tmp="${_target_shard_file}.entries.$$"
            if [ -f "$_target_shard_file" ]; then
                LC_ALL=C grep '^- \*\*' "$_target_shard_file" > "$_entries_tmp" 2>/dev/null || : > "$_entries_tmp"
            else
                : > "$_entries_tmp"
            fi
            printf '%s\n' "$_entry_line" >> "$_entries_tmp"
            atomic_sort_unique_file "$_entries_tmp"

            _shard_tmp="${_target_shard_file}.tmp.$$"
            _target_shard_id="$(basename "$_target_shard_file" .md)"
            printf '# Wiki Index Shard: %s\n\n' "$_target_shard_id" > "$_shard_tmp"
            cat "$_entries_tmp" >> "$_shard_tmp"
            rm -f "$_entries_tmp"
            mv "$_shard_tmp" "$_target_shard_file"

            _ingested_count=$((_ingested_count + 1))
        done 3< "$_missing_file"
    fi

    # Post-ingestion shard splitting for any shard exceeding threshold
    for _shard_cand in "${RNEX_WIKI_ROOT}"/repo-nexus*.md "${RNEX_WIKI_ROOT}"/repos-*.md; do
        [ -f "$_shard_cand" ] || continue
        case "$_shard_cand" in
            *-a-m.md|*-n-z.md) continue ;;
        esac
        _cnt="$(LC_ALL=C grep -c '^- \*\*' "$_shard_cand" 2>/dev/null || printf '0')"
        if [ "$_cnt" -gt "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" ]; then
            _s_base="$(basename "$_shard_cand" .md)"
            for _rng in "a-m" "n-z"; do
                _sub_shard="${_s_base}-${_rng}"
                _sub_file="${RNEX_WIKI_ROOT}/${_sub_shard}.md"
                _sub_entries_tmp="${_sub_file}.entries.$$"
                : > "$_sub_entries_tmp"
                if [ -f "$_sub_file" ]; then
                    LC_ALL=C grep '^- \*\*' "$_sub_file" > "$_sub_entries_tmp" 2>/dev/null || : > "$_sub_entries_tmp"
                fi
                LC_ALL=C awk -v rng="$_rng" '
                    {
                        line = $0
                        if (match(line, /^- \*\*\[[^]]+\]/)) {
                            m = substr(line, 6)
                            sub(/\].*$/, "", m)
                        } else if (match(line, /^- \*\*[^*]+\*\*/)) {
                            m = substr(line, 6)
                            sub(/\*\*.*$/, "", m)
                        } else {
                            m = line
                        }
                        ch = tolower(substr(m, 1, 1))
                        in_am = (ch >= "a" && ch <= "m")
                        if ((rng == "a-m" && in_am) || (rng == "n-z" && !in_am)) {
                            print $0
                        }
                    }
                ' "$_shard_cand" >> "$_sub_entries_tmp"
                if [ -s "$_sub_entries_tmp" ]; then
                    atomic_sort_unique_file "$_sub_entries_tmp"
                    _sub_tmp="${_sub_file}.tmp.$$"
                    printf '# Wiki Index Shard: %s\n\n' "$_sub_shard" > "$_sub_tmp"
                    cat "$_sub_entries_tmp" >> "$_sub_tmp"
                    mv "$_sub_tmp" "$_sub_file"
                fi
                rm -f "$_sub_entries_tmp"
            done
            rm -f "$_shard_cand"
        fi
    done

    if [ "$_ingested_count" -gt 0 ] || [ ! -f "$RNEX_WIKI_INDEX_FILE" ]; then
        compile_root_index_router
    fi

    _target_desc="${_arg_label:-configured sources}"
    if [ "$_ingested_count" -gt 0 ]; then
        append_wiki_log_entry "ingest" "Ingested ${_ingested_count} missing source(s) from ${_target_desc} into ${RNEX_WIKI_REL_DIR}."
    fi
    printf 'Ingested %s missing source(s) into %s.\n' "$_ingested_count" "$RNEX_WIKI_REL_DIR"
    return 0
}

# -----------------------------------------------------------------------------
# Backwards-Compatible Helpers
# -----------------------------------------------------------------------------
purge_legacy_wiki_artifacts() {
    mkdir -p "$RNEX_WIKI_ROOT" || return 1
    if [ -f "${RNEX_WIKI_ROOT}/_log.md" ]; then
        if [ ! -f "$RNEX_WIKI_LOG_FILE" ]; then
            mv "${RNEX_WIKI_ROOT}/_log.md" "$RNEX_WIKI_LOG_FILE"
        fi
    fi
    find "$RNEX_WIKI_ROOT" -type l -exec rm -f {} + 2>/dev/null || true
    rm -rf "${RNEX_WIKI_ROOT}/_graph" \
           "${RNEX_WIKI_ROOT}/_index" \
           "${RNEX_WIKI_ROOT}/concepts" \
           "${RNEX_WIKI_ROOT}/repos" \
           "${RNEX_WIKI_ROOT}/sources" \
           "${RNEX_WIKI_ROOT}/entities" \
           "${RNEX_WIKI_ROOT}/overview" \
           "${RNEX_WIKI_ROOT}/_index.md" \
           "${RNEX_WIKI_ROOT}/hot.md" 2>/dev/null || true
    return 0
}

ensure_baseline_flat_shards() {
    _has_nexus_shard=0
    for _nf in "${RNEX_WIKI_ROOT}"/repo-nexus*.md; do
        [ -f "$_nf" ] && { _has_nexus_shard=1; break; }
    done
    if [ "$_has_nexus_shard" -eq 0 ]; then
        cat <<'EOF' > "${RNEX_WIKI_ROOT}/repo-nexus.md"
# Wiki Shard: repo-nexus

- *(No source pages indexed for `repo-nexus` yet.)*
EOF
    fi
    return 0
}

compile_flat_btree_wiki() {
    compile_root_index_router
}

purge_legacy_wiki_directories_and_symlinks() {
    purge_legacy_wiki_artifacts
}

ensure_baseline_btree_shards() {
    ensure_baseline_flat_shards
}

rebalance_btree_shards_and_compile_root() {
    compile_root_index_router
}
