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
# rewrite_markdown_links_in_summary
# Summary: Resolves and rewrites relative Markdown links, anchors, and wikilinks
#          inside an extracted documentation summary line so they point accurately
#          from the destination wiki shard back to the workspace target, or
#          strips them down to plain text if the target cannot be resolved
#          or if "strip" mode is selected.
#
# Design Patterns & Architecture:
#   - Information Expert (GRASP): Knows the source document location and
#     relative path hierarchy to determine the exact workspace destination.
#   - Strategy Pattern (GoF): Operates under "rewrite" (default) or "strip" mode.
#   - Security (OWASP A03): Traversal validation through normalize_relative_path;
#     avoids command execution or unsafe subshells.
#
# @param $1: raw_summary      - Unsanitized single-line summary string.
# @param $2: source_rel_path  - Workspace-relative path to source file (e.g., "docs/guide.md").
# @param $3: workspace_root   - Absolute path to workspace root.
# @param $4: up_prefix        - Upward prefix from wiki directory to workspace root (e.g., "../../").
# @param $5: mode             - Link strategy: "rewrite" (default) or "strip"/"delete".
# @returns: Rewritten or stripped summary string on stdout.
# @sideEffects: Verifies target file existence via [ -e ... ] against workspace root.
# -----------------------------------------------------------------------------
rewrite_markdown_links_in_summary() {
    _raw_sum="$1"
    _source_rel="$2"
    _ws_root="$3"
    _up_prefix="${4:-../../}"
    _mode="${5:-rewrite}"

    [ -n "$_raw_sum" ] || return 0

    case "$_source_rel" in
        */*) _source_dir="${_source_rel%/*}" ;;
        *)   _source_dir="" ;;
    esac

    _out=""

    # Tokenize input text into atomic segment types:
    #   T = literal text segment
    #   L = standard markdown link [text](target)
    #   W = wikilink [[target|label]] or [[target]]
    #   I = markdown image ![alt](target)
    _tokens="$(printf '%s\n' "$_raw_sum" | LC_ALL=C awk '
        BEGIN { RS = ""; FS = "\n" }
        function emit(type, a, b) {
            gsub(/\t/, " ", a)
            gsub(/\t/, " ", b)
            printf "%s\t%s\t%s\n", type, a, b
        }
        {
            str = $0
            rem = str
            while (rem != "") {
                p = index(rem, "[")
                if (p == 0) {
                    emit("T", rem, "")
                    break
                }
                is_img = 0
                if (p > 1 && substr(rem, p - 1, 1) == "!") {
                    before = substr(rem, 1, p - 2)
                    is_img = 1
                } else {
                    before = substr(rem, 1, p - 1)
                }
                if (before != "") {
                    emit("T", before, "")
                }
                rem = substr(rem, p)

                # Check for wikilink format [[target|label]] or [[target]]
                if (substr(rem, 1, 2) == "[[") {
                    p2 = index(rem, "]]")
                    if (p2 > 0) {
                        content = substr(rem, 3, p2 - 3)
                        p3 = index(content, "|")
                        if (p3 > 0) {
                            target = substr(content, 1, p3 - 1)
                            label = substr(content, p3 + 1)
                        } else {
                            target = content
                            label = content
                        }
                        emit("W", target, label)
                        rem = substr(rem, p2 + 2)
                        continue
                    }
                }

                # Check for markdown link [text](target)
                p2 = index(rem, "](")
                if (p2 > 0) {
                    text = substr(rem, 2, p2 - 2)
                    p3 = index(substr(rem, p2 + 2), ")")
                    if (p3 > 0) {
                        target = substr(rem, p2 + 2, p3 - 1)
                        if (is_img) {
                            emit("I", text, target)
                        } else {
                            emit("L", text, target)
                        }
                        rem = substr(rem, p2 + 2 + p3)
                        continue
                    }
                }

                # Not a link, retain bracket literal
                if (is_img) {
                    emit("T", "![", "")
                } else {
                    emit("T", "[", "")
                }
                rem = substr(rem, 2)
            }
        }
    ')"

    while IFS="$(printf '\t')" read -r _type _a _b; do
        case "$_type" in
            T)
                _out="${_out}${_a}"
                ;;
            I)
                # Strip image markup to plain alternative text
                _out="${_out}${_a}"
                ;;
            W)
                _w_target="$_a"
                _w_label="$_b"
                if [ "$_mode" = "strip" ] || [ "$_mode" = "delete" ] || [ "$_mode" = "unlink" ]; then
                    _out="${_out}${_w_label}"
                elif [ -f "${_ws_root}/${RNEX_WIKI_REL_DIR:-.rnex/wiki}/${_w_target}.md" ]; then
                    _out="${_out}[[${_w_target}|${_w_label}]]"
                elif [ -f "${_ws_root}/${_w_target}.md" ]; then
                    _out="${_out}[${_w_label}](${_up_prefix}${_w_target}.md)"
                else
                    _out="${_out}${_w_label}"
                fi
                ;;
            L)
                _text="$_a"
                _target="$_b"

                # Empty target: strip to plain label
                if [ -z "$_target" ]; then
                    _out="${_out}${_text}"
                    continue
                fi

                # Strip mode: preserve absolute/external URLs, strip relative links to plain text
                if [ "$_mode" = "strip" ] || [ "$_mode" = "delete" ] || [ "$_mode" = "unlink" ]; then
                    case "$_target" in
                        http://*|https://*|mailto:*|ftp://*|//*)
                            _out="${_out}[${_text}](${_target})"
                            ;;
                        *)
                            _out="${_out}${_text}"
                            ;;
                    esac
                    continue
                fi

                # Rewrite mode: evaluate and resolve link target
                case "$_target" in
                    http://*|https://*|mailto:*|ftp://*|//*)
                        # External absolute URL; preserve untouched
                        _out="${_out}[${_text}](${_target})"
                        ;;
                    \#*)
                        # Fragment anchor referring to current source document
                        _out="${_out}[${_text}](${_up_prefix}${_source_rel}${_target})"
                        ;;
                    *)
                        # Relative workspace link
                        _target_path="${_target%%[#?]*}"
                        _target_extra="${_target#"$_target_path"}"
                        if _norm_rel="$(normalize_relative_path "$_source_dir" "$_target_path")"; then
                            _resolved=""
                            if [ -e "${_ws_root}/${_norm_rel}" ]; then
                                _resolved="$_norm_rel"
                            elif [ -e "${_ws_root}/${_norm_rel}.md" ]; then
                                _resolved="${_norm_rel}.md"
                            elif [ -e "${_ws_root}/${_norm_rel}/README.md" ]; then
                                _resolved="${_norm_rel}/README.md"
                            fi

                            if [ -n "$_resolved" ]; then
                                # Target exists in workspace; rewrite relative to wiki destination
                                _out="${_out}[${_text}](${_up_prefix}${_resolved}${_target_extra})"
                            else
                                # Dead/broken relative target; strip link markup to avoid broken wiki links
                                _out="${_out}${_text}"
                            fi
                        else
                            # Path traversal or invalid segment; strip link markup
                            _out="${_out}${_text}"
                        fi
                        ;;
                esac
                ;;
        esac
    done <<EOF
$_tokens
EOF

    printf '%s\n' "$_out"
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
            _title="$(sanitize_markdown_summary "$(strip_markdown_links "$_raw_title")")"
            _summary_rewritten="$(rewrite_markdown_links_in_summary \
                "$_raw_summary" \
                "$_rel_path" \
                "$RNEX_WORKSPACE_ROOT" \
                "$_up_prefix" \
                "${RNEX_WIKI_RELATIVE_LINKS:-rewrite}")"
            _summary="$(sanitize_markdown_summary "$_summary_rewritten")"
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
