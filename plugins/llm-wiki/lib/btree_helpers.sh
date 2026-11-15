#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2016
# =============================================================================
# File: plugins/llm-wiki/lib/btree_helpers.sh
# Architectural Layer: Domain Helpers (helpers/)
# Single Responsibility: Incrementally merge newly discovered missing sources
# into flat B-Tree shards (.rnex/wiki/*.md), maintain strict LC_ALL=C sort
# order, split oversized shards recursively, compile .rnex/wiki/index.md router,
# and append audit entries to log.md.
#
# Design Patterns Applied:
#   - Builder Pattern: Incrementally merges missing entries and builds clean
#     Markdown shard catalogs and root router index tables.
#   - Information Expert (GRASP): Encapsulates title extraction, summary
#     sanitization, B-Tree shard routing, and Markdown shard formatting.
#   - Don't Repeat Yourself (DRY): Centralizes atomic shard file writing
#     (write_btree_shard_entries), entry link-depth healing
#     (heal_entry_title_link_depth), and entry re-routing (reroute_wiki_entry_line),
#     and reuses RNEX_WIKI_AWK_LIB from utils.sh.
#
# Standards: Pure POSIX Shell (/bin/sh), OWASP ASVS A03 Atomic File Operations.
# =============================================================================

# Guard against redundant multiple inclusion
if [ "${RNEX_LLM_WIKI_BTREE_HELPERS_SH_SOURCED:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
RNEX_LLM_WIKI_BTREE_HELPERS_SH_SOURCED=1

# -----------------------------------------------------------------------------
# ensure_baseline_flat_shards
# Summary: Ensures at least the baseline repo-nexus.md shard exists inside
#          $RNEX_WIKI_ROOT when no repo-nexus* shards have been created yet.
# @returns: 0 on success.
# @sideEffects: Creates ${RNEX_WIKI_ROOT}/repo-nexus.md if no repo-nexus* shard exists.
# -----------------------------------------------------------------------------
ensure_baseline_flat_shards() {
    mkdir -p "$RNEX_WIKI_ROOT"
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

# -----------------------------------------------------------------------------
# write_btree_shard_entries
# Summary: Atomically writes or merges catalog entries into a target B-Tree
#          shard file with canonical header and embedded base shard metadata,
#          maintaining strict LC_ALL=C unique sort order.
# @param $1: target_shard_file - Absolute path to target .md shard file.
# @param $2: base_shard_id     - Canonical base shard ID for metadata comment.
# @param $3: entries_source    - File path containing entries OR single entry line.
# @param $4: is_file_source    - "1" if $3 is a file path, "0" if $3 is a single line.
# @returns: 0 on success.
# @sideEffects: Atomically creates or updates $1 in sorted unique order.
# -----------------------------------------------------------------------------
write_btree_shard_entries() {
    _wb_file="$1"
    _wb_base_id="$2"
    _wb_source="$3"
    _wb_is_file="${4:-0}"

    _wb_sid="$(basename "$_wb_file" .md)"
    _wb_merged="${_wb_file}.mrg.$$"
    : > "$_wb_merged"

    if [ -f "$_wb_file" ]; then
        LC_ALL=C grep '^- \*\*' "$_wb_file" >> "$_wb_merged" 2>/dev/null || true
    fi

    if [ "$_wb_is_file" = "1" ]; then
        [ -f "$_wb_source" ] && cat "$_wb_source" >> "$_wb_merged"
    else
        [ -n "$_wb_source" ] && printf '%s\n' "$_wb_source" >> "$_wb_merged"
    fi

    atomic_sort_unique_file "$_wb_merged" || true

    _wb_tmp="${_wb_file}.tmp.$$"
    printf '# Wiki Index Shard: %s\n<!-- base: %s -->\n\n' "$_wb_sid" "$_wb_base_id" > "$_wb_tmp"
    cat "$_wb_merged" >> "$_wb_tmp"
    rm -f "$_wb_merged"
    mv "$_wb_tmp" "$_wb_file"
    return 0
}

# -----------------------------------------------------------------------------
# heal_entry_title_link_depth
# Summary: Ensures a catalog entry's title Markdown link target uses the current
#          RNEX_WIKI_UP_PREFIX depth when the referenced workspace file exists.
# @param $1: entry_line - Catalog bullet line ('- **[Title](target)** (`path`) — ...').
# @param $2: doc_rel    - Workspace-relative document path.
# @returns: Healed (or unchanged) entry line on stdout; returns 0 if modified, 1 if unchanged.
# @pure
# -----------------------------------------------------------------------------
heal_entry_title_link_depth() {
    _hl_line="$1"
    _hl_rel="$2"
    if [ -n "$_hl_rel" ] && [ -f "${RNEX_WORKSPACE_ROOT}/${_hl_rel}" ]; then
        _hl_expected="${RNEX_WIKI_UP_PREFIX:-../../}${_hl_rel}"
        _hl_curr="$(printf '%s\n' "$_hl_line" | sed -n 's/^- \*\*\[[^]]*\](\([^)]*\)).*/\1/p')"
        if [ -n "$_hl_curr" ] && [ "$_hl_curr" != "$_hl_expected" ]; then
            _hl_title="$(extract_entry_title "$_hl_line")"
            _hl_rest="${_hl_line#*\*\* (\`"${_hl_rel}"\`)}"
            printf -- '- **[%s](%s)** (`%s`)%s\n' "$_hl_title" "$_hl_expected" "$_hl_rel" "$_hl_rest"
            return 0
        fi
    fi
    printf '%s\n' "$_hl_line"
    return 1
}

# -----------------------------------------------------------------------------
# reroute_wiki_entry_line
# Summary: Parses a displaced wiki catalog entry line, heals its link depth,
#          resolves its canonical destination B-Tree shard file, and merges it
#          into that shard in sorted order.
# @param $1: entry_line       - Catalog entry line to re-route.
# @param $2: fallback_base_id - Fallback base shard ID if entry lacks a path.
# @returns: "<target_shard_id>|<title>" on stdout.
# @sideEffects: Merges entry into resolved target shard file.
# -----------------------------------------------------------------------------
reroute_wiki_entry_line() {
    _rr_line="$1"
    _rr_fallback_base="$2"

    _rr_rel="$(extract_entry_rel_path "$_rr_line")"
    _rr_title="$(extract_entry_title "$_rr_line")"

    if [ -n "$_rr_rel" ]; then
        _rr_base_id="$(derive_shard_id_for_workspace_path "$_rr_rel")"
    else
        _rr_base_id="$_rr_fallback_base"
    fi

    _rr_line="$(heal_entry_title_link_depth "$_rr_line" "$_rr_rel" || true)"
    _rr_target_file="$(resolve_target_btree_shard_file "$_rr_base_id" "$_rr_title" "$_rr_rel")"
    _rr_target_id="$(basename "$_rr_target_file" .md)"

    write_btree_shard_entries "$_rr_target_file" "$_rr_base_id" "$_rr_line" "0"
    printf '%s|%s\n' "$_rr_target_id" "$_rr_title"
    return 0
}

# -----------------------------------------------------------------------------
# extract_markdown_title_and_summary
# Summary: Extracts the first H1 heading and first non-empty prose paragraph
#          from a Markdown file, skipping YAML frontmatter and code blocks.
# @param $1: abs_file_path  - Absolute path to the Markdown document.
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
            gsub(/[|*]/, " ", line)
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
# trim_wiki_log_records
# Summary: Enforces the maximum record ceiling on the operational log file
#          by pruning the oldest bullet records ('^- \*\*') while preserving
#          the markdown header block intact.
# @param $1: log_file    - Absolute path to log.md.
# @param $2: max_records - Maximum allowed record count (default: 1000).
# @returns: 0 on success.
# @sideEffects: Replaces $1 atomically via a temporary file if pruning is needed.
# -----------------------------------------------------------------------------
trim_wiki_log_records() {
    _log_path="$1"
    _max_rec="${2:-1000}"
    [ -f "$_log_path" ] || return 0

    _rec_count="$(LC_ALL=C grep -c '^- \*\*' "$_log_path" 2>/dev/null || true)"
    [ -n "$_rec_count" ] || _rec_count=0
    if [ "$_rec_count" -gt "$_max_rec" ]; then
        _to_skip=$((_rec_count - _max_rec))
        _log_tmp="${_log_path}.trim.$$"
        LC_ALL=C awk -v to_skip="$_to_skip" '
            BEGIN { skipped = 0 }
            /^- \*\*/ {
                if (skipped < to_skip) {
                    skipped++
                    next
                }
            }
            { print }
        ' "$_log_path" > "$_log_tmp" && mv "$_log_tmp" "$_log_path"
        rm -f "$_log_tmp"
    fi
    return 0
}

# -----------------------------------------------------------------------------
# append_wiki_log_entry
# Summary: Appends an ISO-8601 UTC audit record line to .rnex/wiki/log.md
#          and trims the log file to maintain at most RNEX_WIKI_LOG_MAX_RECORDS
#          (default: 1000), cutting oldest records first while preserving header.
# @param $1: action_name - Operation name ("ingest" or "lint").
# @param $2: details     - Human-readable operation summary or document action.
# @returns: 0 on success.
# @sideEffects: Creates, appends to, and prunes $RNEX_WIKI_LOG_FILE.
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
    trim_wiki_log_records "$RNEX_WIKI_LOG_FILE" "${RNEX_WIKI_LOG_MAX_RECORDS:-1000}"
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
    ensure_baseline_flat_shards
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
        _cnt="$(LC_ALL=C grep -c '^- \*\*' "$_shard" 2>/dev/null || true)"
        [ -n "$_cnt" ] || _cnt=0
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
        _cnt="$(LC_ALL=C grep -c '^- \*\*' "$_shard" 2>/dev/null || true)"
        [ -n "$_cnt" ] || _cnt=0
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
# @param $1: raw_summary     - Unsanitized single-line summary string.
# @param $2: source_rel_path - Workspace-relative path to source file (e.g., "docs/guide.md").
# @param $3: workspace_root  - Absolute path to workspace root.
# @param $4: up_prefix       - Upward prefix from wiki directory to workspace root (e.g., "../../").
# @param $5: mode            - Link strategy: "rewrite" (default) or "strip"/"delete".
# @param $6: from_wiki       - "1" if input is already from a wiki shard, "0" otherwise.
# @returns: Rewritten or stripped summary string on stdout.
# @sideEffects: Verifies target file existence via [ -e ... ] against workspace root.
# -----------------------------------------------------------------------------
rewrite_markdown_links_in_summary() {
    _raw_sum="$1"
    _source_rel="$2"
    _ws_root="$3"
    _up_prefix="${4:-../../}"
    _mode="${5:-rewrite}"
    _from_wiki="${6:-0}"

    [ -n "$_raw_sum" ] || return 0

    case "$_source_rel" in
        */*) _source_dir="${_source_rel%/*}" ;;
        *)   _source_dir="" ;;
    esac

    _out=""

    _tokens="$(printf '%s\n' "$_raw_sum" | LC_ALL=C awk '
        BEGIN { RS = ""; FS = "\n" }
        function emit(type, a, b) {
            gsub(/\t/, " ", a)
            gsub(/\t/, " ", b)
            printf "%s\t%s\t%s\n", type, a, b
        }
        {
            str = $0
            while (match(str, /!\[[^][]+\]\([^()]+\)/)) {
                alt_txt = substr(str, RSTART + 2, RLENGTH - 2)
                sub(/\]\([^()]*\)$/, "", alt_txt)
                str = substr(str, 1, RSTART - 1) alt_txt substr(str, RSTART + RLENGTH)
            }
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

                p_close = index(substr(rem, 2), "]")
                if (p_close > 0 && substr(rem, 1 + p_close, 2) == "](") {
                    text = substr(rem, 2, p_close - 1)
                    if (index(text, "[") == 0) {
                        p3 = index(substr(rem, 1 + p_close + 2), ")")
                        if (p3 > 0) {
                            target = substr(rem, 1 + p_close + 2, p3 - 1)
                            if (is_img) {
                                emit("I", text, target)
                            } else {
                                emit("L", text, target)
                            }
                            rem = substr(rem, 1 + p_close + 2 + p3)
                            continue
                        }
                    }
                }

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
            T|I)
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

                if [ -z "$_target" ]; then
                    _out="${_out}${_text}"
                    continue
                fi

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

                case "$_target" in
                    http://*|https://*|mailto:*|ftp://*|//*)
                        _out="${_out}[${_text}](${_target})"
                        ;;
                    \#*)
                        _out="${_out}[${_text}](${_up_prefix}${_source_rel}${_target})"
                        ;;
                    *)
                        _target_path="${_target%%[#?]*}"
                        _target_extra="${_target#"$_target_path"}"
                        _resolved=""

                        if [ "$_from_wiki" = "1" ]; then
                            case "$_target_path" in
                                "${_up_prefix}"*)
                                    _rel_from_up="${_target_path#"$_up_prefix"}"
                                    if _norm_up="$(normalize_relative_path "" "$_rel_from_up")"; then
                                        if [ -e "${_ws_root}/${_norm_up}" ]; then
                                            _resolved="$_norm_up"
                                        elif [ -e "${_ws_root}/${_norm_up}.md" ]; then
                                            _resolved="${_norm_up}.md"
                                        elif [ -e "${_ws_root}/${_norm_up}/README.md" ]; then
                                            _resolved="${_norm_up}/README.md"
                                        fi
                                    fi
                                    ;;
                            esac
                        fi

                        if [ -z "$_resolved" ]; then
                            if _norm_rel="$(normalize_relative_path "$_source_dir" "$_target_path")"; then
                                if [ -e "${_ws_root}/${_norm_rel}" ]; then
                                    _resolved="$_norm_rel"
                                elif [ -e "${_ws_root}/${_norm_rel}.md" ]; then
                                    _resolved="${_norm_rel}.md"
                                elif [ -e "${_ws_root}/${_norm_rel}/README.md" ]; then
                                    _resolved="${_norm_rel}/README.md"
                                fi
                            fi
                        fi

                        if [ -z "$_resolved" ] && [ "$_from_wiki" != "1" ]; then
                            case "$_target_path" in
                                "${_up_prefix}"*)
                                    _rel_from_up="${_target_path#"$_up_prefix"}"
                                    if _norm_up="$(normalize_relative_path "" "$_rel_from_up")"; then
                                        if [ -e "${_ws_root}/${_norm_up}" ]; then
                                            _resolved="$_norm_up"
                                        elif [ -e "${_ws_root}/${_norm_up}.md" ]; then
                                            _resolved="${_norm_up}.md"
                                        elif [ -e "${_ws_root}/${_norm_up}/README.md" ]; then
                                            _resolved="${_norm_up}/README.md"
                                        fi
                                    fi
                                    ;;
                            esac
                        fi

                        if [ -n "$_resolved" ]; then
                            _out="${_out}[${_text}](${_up_prefix}${_resolved}${_target_extra})"
                        else
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
# resolve_target_btree_shard_file
# Summary: Resolves the appropriate destination shard file for a document based
#          on the base shard ID, document title, and document path. If the base
#          shard has been split into sub-shards, matches the entry's composite
#          sort key against available range/prefix sub-shards.
# @param $1: shard_id - Base shard identifier (e.g. "repos-test-repo-packages").
# @param $2: title    - Document title string.
# @param $3: path     - Optional workspace-relative path tie-breaker.
# @returns: Absolute file path to target shard on stdout.
# @pure
# -----------------------------------------------------------------------------
resolve_target_btree_shard_file() {
    _s_id="$1"
    _doc_title="$2"
    _doc_path="${3:-}"
    _base_file="${RNEX_WIKI_ROOT}/${_s_id}.md"

    # Find existing sub-shard files whose canonical base shard ID equals $_s_id
    _cand_files=""
    for _f in "${RNEX_WIKI_ROOT}/${_s_id}-"*.md; do
        [ -f "$_f" ] || continue
        _f_sid="$(basename "$_f" .md)"
        _f_base="$(derive_base_id_for_shard "$_f_sid")"
        if [ "$_f_base" = "$_s_id" ]; then
            _cand_files="${_cand_files}${_f}
"
        fi
    done

    if [ -z "$_cand_files" ]; then
        printf '%s\n' "$_base_file"
        return 0
    fi

    printf '%s' "$_cand_files" | LC_ALL=C awk \
        -v sid="$_s_id" \
        -v title="$_doc_title" \
        -v path="$_doc_path" \
        -v def_file="$_base_file" "
        ${RNEX_WIKI_AWK_LIB}
        BEGIN {
            kt = clean_alpha_key(title)
            kp = clean_alpha_key(path)
            if (kt != \"\") t = kt kp
            else if (kp != \"\") t = kp
            else t = \"untitled\"

            prefix = sid \"-\"
            matched_child = \"\"
            max_match_k = -1
        }
        {
            f = \$0
            if (f == \"\" || f == def_file) next
            sub_id = f
            sub(/^.*\//, \"\", sub_id)
            sub(/\.md\$/, \"\", sub_id)
            if (index(sub_id, prefix) != 1) next
            sub_suffix = substr(sub_id, length(prefix) + 1)

            if (!match(sub_suffix, /^[a-z]+-[a-z]+\$/) && !match(sub_suffix, /^[a-z]+\$/)) next

            if (match(sub_suffix, /^[a-z]+-[a-z]+\$/)) {
                dash_pos = index(sub_suffix, \"-\")
                s_part = substr(sub_suffix, 1, dash_pos - 1)
                e_part = substr(sub_suffix, dash_pos + 1)
                if (length(s_part) == length(e_part) && s_part <= e_part) {
                    K = length(s_part)
                    pfx = substr(t, 1, K)
                    while (length(pfx) < K) pfx = pfx \"a\"
                    if ((s_part == \"a\" && pfx < s_part) || (pfx >= s_part && (e_part == \"z\" || pfx <= e_part))) {
                        if (K > max_match_k) {
                            max_match_k = K
                            matched_child = f
                        }
                    }
                }
            } else if (match(sub_suffix, /^[a-z]+\$/)) {
                K = length(sub_suffix)
                pfx = substr(t, 1, K)
                while (length(pfx) < K) pfx = pfx \"a\"
                if (pfx == sub_suffix) {
                    if (K > max_match_k) {
                        max_match_k = K
                        matched_child = f
                    }
                }
            }
        }
        END {
            if (matched_child != \"\") {
                print matched_child
            } else {
                print def_file
            }
        }
    "
    return 0
}

# -----------------------------------------------------------------------------
# derive_base_id_for_shard
# Summary: Identifies the root base shard ID for any wiki shard file, shielding
#          sub-shards from premature truncation and ensuring accurate prefix
#          tracking across arbitrary B-Tree depth.
# @param $1: shard_id - Shard identifier (e.g. "repos-test-repo-packages-n-z").
# @returns: Base shard ID on stdout (e.g. "repos-test-repo-packages").
# @pure
# -----------------------------------------------------------------------------
derive_base_id_for_shard() {
    _sid="$1"
    _shard_path="${RNEX_WIKI_ROOT}/${_sid}.md"

    # 1. Check workspace directory structure first (finding longest matching base)
    case "$_sid" in
        repo-nexus)
            printf 'repo-nexus\n'
            return 0
            ;;
        repo-nexus-*)
            _after_rn="${_sid#repo-nexus-}"
            _best_rn_base=""
            for _top_d in "${RNEX_WORKSPACE_ROOT}"/* "${RNEX_WORKSPACE_ROOT}"/.[!.]* "${RNEX_WORKSPACE_ROOT}"/..?*; do
                [ -d "$_top_d" ] || continue
                _top_bname="$(basename "$_top_d")"
                case "$_top_bname" in
                    .git|.rnex|"${RNEX_CFG_REPOS_DIR:-repos}") continue ;;
                esac
                _top_slug="$(normalize_slug_id "$_top_bname")"
                case "$_after_rn" in
                    "${_top_slug}"|"${_top_slug}-"*)
                        _cand_base="repo-nexus-${_top_slug}"
                        if [ "${#_cand_base}" -gt "${#_best_rn_base}" ]; then
                            _best_rn_base="$_cand_base"
                        fi
                        ;;
                esac
            done
            if [ -n "$_best_rn_base" ]; then
                printf '%s\n' "$_best_rn_base"
                return 0
            fi
            ;;
        repos-*)
            _after_rep="${_sid#repos-}"
            _rep_dir="${RNEX_CFG_REPOS_DIR:-repos}"
            _best_rep_base=""
            for _m_dir in "${RNEX_WORKSPACE_ROOT}/${_rep_dir}"/*; do
                [ -d "$_m_dir" ] || continue
                _m_slug="$(normalize_slug_id "$(basename "$_m_dir")")"
                case "$_after_rep" in
                    "${_m_slug}"|"${_m_slug}-"*)
                        _cand_base="repos-${_m_slug}"
                        if [ "${#_cand_base}" -gt "${#_best_rep_base}" ]; then
                            _best_rep_base="$_cand_base"
                        fi
                        for _sub_dir in "$_m_dir"/* "$_m_dir"/.[!.]* "$_m_dir"/..?*; do
                            [ -d "$_sub_dir" ] || continue
                            _sub_bname="$(basename "$_sub_dir")"
                            case "$_sub_bname" in
                                .git|.rnex) continue ;;
                            esac
                            _sub_slug="$(normalize_slug_id "$_sub_bname")"
                            case "$_after_rep" in
                                "${_m_slug}-${_sub_slug}"|"${_m_slug}-${_sub_slug}-"*)
                                    _cand_sub="repos-${_m_slug}-${_sub_slug}"
                                    if [ "${#_cand_sub}" -gt "${#_best_rep_base}" ]; then
                                        _best_rep_base="$_cand_sub"
                                    fi
                                    ;;
                            esac
                        done
                        ;;
                esac
            done
            if [ -n "$_best_rep_base" ]; then
                printf '%s\n' "$_best_rep_base"
                return 0
            fi
            ;;
    esac

    # 2. Read embedded metadata tag if present (for synthetic/unmounted test shards)
    if [ -f "$_shard_path" ]; then
        _meta_base="$(sed -n 's/^<!-- base: \(.*\) -->$/\1/p' "$_shard_path" 2>/dev/null | head -n 1)"
        if [ -n "$_meta_base" ]; then
            printf '%s\n' "$_meta_base"
            return 0
        fi
    fi

    # 3. Fallback: strip valid equal-length alphabetical range suffix (e.g. -a-m, -pa-pm)
    _stripped="$(printf '%s\n' "$_sid" | LC_ALL=C awk '
        {
            s = $0
            if (match(s, /-[a-z]+-[a-z]+$/)) {
                sfx = substr(s, RSTART + 1)
                base = substr(s, 1, RSTART - 1)
                dash = index(sfx, "-")
                sp = substr(sfx, 1, dash - 1)
                ep = substr(sfx, dash + 1)
                if (length(sp) == length(ep) && sp <= ep && base != "repo" && base != "repos") {
                    print base
                    next
                }
            }
            print s
        }
    ')"
    printf '%s\n' "${_stripped:-$_sid}"
    return 0
}

# -----------------------------------------------------------------------------
# split_oversized_btree_shards
# Summary: Recursively inspects all leaf shards in $RNEX_WIKI_ROOT (excluding
#          index.md and log.md) and subdivides any shard whose record count
#          exceeds RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES into balanced sub-shards.
#          Appends audit entries ("created: ...", "deleted: ...") to log.md.
# @param $1: action_name - Context label for audit log ("ingest" or "lint").
# @returns: Total count of shards split on stdout.
# @sideEffects: Replaces oversized shard files with sub-shards and mutates log.md.
# -----------------------------------------------------------------------------
split_oversized_btree_shards() {
    _action="$1"
    _max_entries="${RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES:-100}"
    _max_iterations=500
    _iteration=0
    _split_occurred=1
    _total_splits=0

    while [ "$_split_occurred" -eq 1 ] && [ "$_iteration" -lt "$_max_iterations" ]; do
        _split_occurred=0
        _iteration=$((_iteration + 1))

        for _shard_cand in "${RNEX_WIKI_ROOT}"/repo-nexus*.md "${RNEX_WIKI_ROOT}"/repos-*.md; do
            [ -f "$_shard_cand" ] || continue
            _s_bname="$(basename "$_shard_cand")"
            case "$_s_bname" in
                index.md|log.md) continue ;;
            esac

            _cnt="$(LC_ALL=C grep -c '^- \*\*' "$_shard_cand" 2>/dev/null || true)"
            [ -n "$_cnt" ] || _cnt=0
            if [ "$_cnt" -gt "$_max_entries" ]; then
                _s_id="$(basename "$_shard_cand" .md)"
                _base_id="$(derive_base_id_for_shard "$_s_id")"

                _entries_all="${_shard_cand}.all.$$"
                LC_ALL=C grep '^- \*\*' "$_shard_cand" > "$_entries_all" 2>/dev/null || : > "$_entries_all"

                if [ ! -s "$_entries_all" ]; then
                    rm -f "$_entries_all"
                    continue
                fi

                _part1_tmp="${RNEX_WIKI_ROOT}/.part1.$$"
                _part2_tmp="${RNEX_WIKI_ROOT}/.part2.$$"
                : > "$_part1_tmp"
                : > "$_part2_tmp"

                _child_names="$(LC_ALL=C awk \
                    -v shard_id="$_s_id" \
                    -v base_id="$_base_id" \
                    -v part1_file="$_part1_tmp" \
                    -v part2_file="$_part2_tmp" "
                    ${RNEX_WIKI_AWK_LIB}
                    BEGIN {
                        alpha = \"abcdefghijklmnopqrstuvwxyz\"
                        lines_count = 0
                    }
                    {
                        lines_count++
                        lines[lines_count] = \$0
                        t = tolower(get_title(\$0))
                        p = tolower(get_path(\$0))
                        titles[lines_count] = (t != \"\") ? t : \"untitled\"
                        paths[lines_count] = (p != \"\") ? p : (\"item\" lines_count)
                    }
                    END {
                        if (lines_count == 0) exit 0

                        for (i = 1; i <= lines_count; i++) {
                            kt = clean_alpha_key(titles[i])
                            kp = clean_alpha_key(paths[i])
                            if (kt != \"\") {
                                keys[i] = kt kp
                            } else {
                                keys[i] = (kp != \"\") ? kp : (\"entry\" clean_alpha_key(i))
                            }
                        }

                        if (shard_id == base_id) {
                            suffix = \"\"
                        } else {
                            suffix = substr(shard_id, length(base_id) + 2)
                        }

                        if (suffix == \"\") {
                            S = \"a\"; E = \"z\"; K = 1
                        } else if (match(suffix, /^[a-z]+-[a-z]+\$/)) {
                            dash_pos = index(suffix, \"-\")
                            s_part = substr(suffix, 1, dash_pos - 1)
                            e_part = substr(suffix, dash_pos + 1)
                            if (length(s_part) == length(e_part)) {
                                S = s_part; E = e_part; K = length(s_part)
                            } else {
                                S = \"a\"; E = \"z\"; K = 1
                            }
                        } else if (match(suffix, /^[a-z]+\$/)) {
                            S = suffix; E = suffix; K = length(suffix)
                        } else {
                            S = \"a\"; E = \"z\"; K = 1
                        }

                        loop_limit = 0
                        while (loop_limit++ < 120) {
                            min_c = \"\"
                            max_c = \"\"
                            for (i = 1; i <= lines_count; i++) {
                                c = substr(keys[i], K, 1)
                                if (c < \"a\" || c > \"z\") c = \"a\"
                                if (min_c == \"\" || c < min_c) min_c = c
                                if (max_c == \"\" || c > max_c) max_c = c
                            }

                            if (min_c == max_c && min_c >= \"a\" && min_c <= \"z\") {
                                P = (K > 1) ? substr(S, 1, K - 1) : \"\"
                                S = P min_c
                                E = P min_c
                                K = K + 1
                                S = S \"a\"
                                E = E \"z\"
                                continue
                            }

                            if (S != E) {
                                P = (K > 1) ? substr(S, 1, K - 1) : \"\"
                                c_S = substr(S, K, 1)
                                c_E = substr(E, K, 1)
                                ord_S = index(alpha, c_S)
                                ord_E = index(alpha, c_E)
                                len = ord_E - ord_S + 1
                                if (len >= 2) {
                                    half = int(len / 2)
                                    mid = ord_S + half - 1
                                    c_M1 = substr(alpha, mid, 1)
                                    c_M2 = substr(alpha, mid + 1, 1)

                                    r1_s = S
                                    r1_e = P c_M1
                                    r2_s = P c_M2
                                    r2_e = E

                                    sfx1 = (r1_s == r1_e) ? r1_s : (r1_s \"-\" r1_e)
                                    sfx2 = (r2_s == r2_e) ? r2_s : (r2_s \"-\" r2_e)

                                    c1_name = base_id \"-\" sfx1
                                    c2_name = base_id \"-\" sfx2

                                    cnt1 = 0
                                    cnt2 = 0
                                    for (i = 1; i <= lines_count; i++) {
                                        pfx = substr(keys[i], 1, K)
                                        while (length(pfx) < K) pfx = pfx \"a\"
                                        if ((r1_s == (P \"a\") && pfx < r1_s) || (pfx <= r1_e)) {
                                            cnt1++
                                        } else {
                                            cnt2++
                                        }
                                    }

                                    if (cnt1 > 0 && cnt2 > 0) {
                                        for (i = 1; i <= lines_count; i++) {
                                            pfx = substr(keys[i], 1, K)
                                            while (length(pfx) < K) pfx = pfx \"a\"
                                            if ((r1_s == (P \"a\") && pfx < r1_s) || (pfx <= r1_e)) {
                                                print lines[i] >> part1_file
                                            } else {
                                                print lines[i] >> part2_file
                                            }
                                        }
                                        printf \"%s|%s\n\", c1_name, c2_name
                                        exit 0
                                    } else if (cnt1 == lines_count) {
                                        S = r1_s; E = r1_e
                                        continue
                                    } else if (cnt2 == lines_count) {
                                        S = r2_s; E = r2_e
                                        continue
                                    } else {
                                        break
                                    }
                                } else {
                                    S = S; E = S
                                }
                            }

                            if (S == E) {
                                P = S
                                K = K + 1
                                S = P \"a\"
                                E = P \"z\"
                                continue
                            }
                        }
                    }
                " "$_entries_all")"

                rm -f "$_entries_all"

                _c1_id="${_child_names%%|*}"
                _c2_id="${_child_names#*|}"

                if [ -z "$_c1_id" ] || [ -z "$_c2_id" ] || [ "$_c1_id" = "$_c2_id" ] || [ "$_c1_id" = "$_s_id" ] || [ "$_c2_id" = "$_s_id" ]; then
                    rm -f "$_part1_tmp" "$_part2_tmp"
                    continue
                fi

                _wrote_any=0

                if [ -n "$_c1_id" ] && [ -s "$_part1_tmp" ]; then
                    _c1_file="${RNEX_WIKI_ROOT}/${_c1_id}.md"
                    _c1_existed=0
                    [ -f "$_c1_file" ] && _c1_existed=1
                    write_btree_shard_entries "$_c1_file" "$_base_id" "$_part1_tmp" "1"
                    if [ "$_c1_existed" -eq 1 ]; then
                        append_wiki_log_entry "$_action" "updated: \`${_c1_id}.md\` (split sub-shard)"
                    else
                        append_wiki_log_entry "$_action" "created: \`${_c1_id}.md\` (split sub-shard)"
                    fi
                    _wrote_any=1
                fi

                if [ -n "$_c2_id" ] && [ -s "$_part2_tmp" ]; then
                    _c2_file="${RNEX_WIKI_ROOT}/${_c2_id}.md"
                    _c2_existed=0
                    [ -f "$_c2_file" ] && _c2_existed=1
                    write_btree_shard_entries "$_c2_file" "$_base_id" "$_part2_tmp" "1"
                    if [ "$_c2_existed" -eq 1 ]; then
                        append_wiki_log_entry "$_action" "updated: \`${_c2_id}.md\` (split sub-shard)"
                    else
                        append_wiki_log_entry "$_action" "created: \`${_c2_id}.md\` (split sub-shard)"
                    fi
                    _wrote_any=1
                fi

                if [ "$_wrote_any" -eq 1 ]; then
                    rm -f "$_shard_cand"
                    append_wiki_log_entry "$_action" "deleted: \`${_s_id}.md\` (split into sub-shards)"
                    _split_occurred=1
                    _total_splits=$((_total_splits + 1))
                fi

                rm -f "$_part1_tmp" "$_part2_tmp"
            fi
        done
    done

    printf '%s\n' "$_total_splits"
    return 0
}

# -----------------------------------------------------------------------------
# ingest_missing_sources_into_btree
# Summary: Reads missing workspace-relative source paths from $1, appends only
#          those missing entries into their respective .rnex/wiki/*.md shards,
#          maintains strict LC_ALL=C sort order, and updates .rnex/wiki/index.md.
# @param $1: missing_manifest_file - File containing missing workspace_rel_paths.
# @param $2: source_arg_label      - Optional CLI argument for log attribution.
# @returns: 0 on success.
# @sideEffects: Updates .rnex/wiki/*.md shards, index.md, and log.md.
# -----------------------------------------------------------------------------
ingest_missing_sources_into_btree() {
    _missing_file="$1"
    _arg_label="$2"
    mkdir -p "$RNEX_WIKI_ROOT"
    ensure_baseline_flat_shards

    if [ ! -s "$_missing_file" ] && [ -f "$RNEX_WIKI_INDEX_FILE" ]; then
        _pre_splits="$(split_oversized_btree_shards "ingest")"
        if [ -z "$_pre_splits" ] || [ "$_pre_splits" -eq 0 ]; then
            printf 'Wiki is up to date (0 missing sources to ingest in %s).\n' "$RNEX_WIKI_REL_DIR"
            return 0
        fi
        compile_root_index_router
        append_wiki_log_entry "ingest" "updated: \`index.md\` (recompiled root router table)"
        printf 'Ingested 0 missing source(s) into %s (rebalanced %s oversized shard(s)).\n' "$RNEX_WIKI_REL_DIR" "$_pre_splits"
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
            _meta="$(extract_markdown_title_and_summary "$_abs_path" "$(basename "$_rel_path")")"
            _raw_title="${_meta%%|*}"
            _raw_summary="${_meta#*|}"
            _title="$(sanitize_markdown_summary "$(strip_markdown_links "$_raw_title")")"
            _title="$(printf '%s' "$_title" | tr -d '[]*')"
            [ -n "$_title" ] || _title="$(basename "$_rel_path")"
            _summary_rewritten="$(rewrite_markdown_links_in_summary \
                "$_raw_summary" \
                "$_rel_path" \
                "$RNEX_WORKSPACE_ROOT" \
                "$_up_prefix" \
                "${RNEX_WIKI_RELATIVE_LINKS:-rewrite}")"
            _summary="$(sanitize_markdown_summary "$_summary_rewritten")"
            _rel_link="${_up_prefix}${_rel_path}"

            _entry_line="- **[${_title}](${_rel_link})** (\`${_rel_path}\`) — ${_summary}"

            _target_shard_file="$(resolve_target_btree_shard_file "$_shard_id" "$_title" "$_rel_path")"
            _target_shard_id="$(basename "$_target_shard_file" .md)"

            _shard_existed=0
            [ -f "$_target_shard_file" ] && _shard_existed=1

            write_btree_shard_entries "$_target_shard_file" "$_shard_id" "$_entry_line" "0"

            _ingested_count=$((_ingested_count + 1))
            append_wiki_log_entry "ingest" "created: \`${_rel_path}\` (indexed into \`${_target_shard_id}.md\`)"
            if [ "$_shard_existed" -eq 0 ]; then
                append_wiki_log_entry "ingest" "created: \`${_target_shard_id}.md\` (new shard)"
            else
                append_wiki_log_entry "ingest" "updated: \`${_target_shard_id}.md\` (appended entry)"
            fi
        done 3< "$_missing_file"
    fi

    _splits_count="$(split_oversized_btree_shards "ingest")"

    if [ "$_ingested_count" -gt 0 ] || [ "${_splits_count:-0}" -gt 0 ] || [ ! -f "$RNEX_WIKI_INDEX_FILE" ]; then
        _idx_existed=0
        [ -f "$RNEX_WIKI_INDEX_FILE" ] && _idx_existed=1
        compile_root_index_router
        if [ "$_idx_existed" -eq 1 ]; then
            append_wiki_log_entry "ingest" "updated: \`index.md\` (recompiled root router table)"
        else
            append_wiki_log_entry "ingest" "created: \`index.md\` (root router table)"
        fi
    fi

    _target_desc="${_arg_label:-configured sources}"
    if [ "$_ingested_count" -gt 0 ]; then
        append_wiki_log_entry "ingest" "Ingested ${_ingested_count} missing source(s) from ${_target_desc} into ${RNEX_WIKI_REL_DIR}."
    fi
    printf 'Ingested %s missing source(s) into %s.\n' "$_ingested_count" "$RNEX_WIKI_REL_DIR"
    return 0
}
