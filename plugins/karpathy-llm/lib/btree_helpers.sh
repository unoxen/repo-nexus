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
# trim_wiki_log_records
# Summary: Enforces the maximum record ceiling on the operational log file
#          by pruning the oldest bullet records ('^- \*\*') while preserving
#          the markdown header block intact.
#
# Design Patterns & Principles:
#   - Single Responsibility Principle (SRP): Confined strictly to record
#     capacity trimming on markdown log files.
#   - Fail-Safe & Atomic (OWASP A03): Atomic replacement via temporary file;
#     retains header block and the most recent N records.
#
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
# resolve_target_btree_shard_file
# Summary: Resolves the appropriate destination shard file for a document based
#          on the base shard ID and document title. If the base shard has been
#          split into sub-shards, matches the title'\''s leading character against
#          the available range/part shards.
#
# Design Patterns & Architecture:
#   - Information Expert (GRASP): Uses document title and existing shard
#     topology to determine the exact target file path.
#   - Protected Variations (GRASP): Shields callers from whether a shard is
#     unsplit or deeply partitioned.
#
# @param $1: shard_id - Base shard identifier (e.g. "repos-test-repo-packages").
# @param $2: title    - Document title string.
# @returns: Absolute file path to target shard on stdout.
# @pure
# -----------------------------------------------------------------------------
resolve_target_btree_shard_file() {
    _s_id="$1"
    _doc_title="$2"
    _doc_path="${3:-}"
    _base_file="${RNEX_WIKI_ROOT}/${_s_id}.md"

    # Find existing shard candidate files for this shard ID
    _cand_files="$(find "$RNEX_WIKI_ROOT" -maxdepth 1 -name "${_s_id}*.md" 2>/dev/null | LC_ALL=C sort)"

    # If no files exist yet, target is the base shard file
    if [ -z "$_cand_files" ]; then
        printf '%s\n' "$_base_file"
        return 0
    fi

    # If base shard file exists and no sub-shards exist, target is base shard file
    if [ -f "$_base_file" ]; then
        _has_sub=0
        for _f in $_cand_files; do
            if [ "$_f" != "$_base_file" ]; then
                _has_sub=1
                break
            fi
        done
        if [ "$_has_sub" -eq 0 ]; then
            printf '%s\n' "$_base_file"
            return 0
        fi
    fi

    _base_exists=0
    [ -f "$_base_file" ] && _base_exists=1

    # Sub-shards exist; route title to the most appropriate sub-shard via awk
    printf '%s\n' "$_cand_files" | LC_ALL=C awk \
        -v sid="$_s_id" \
        -v title="$_doc_title" \
        -v path="$_doc_path" \
        -v def_file="$_base_file" \
        -v base_exists="$_base_exists" '
        function clean_alpha_key(str,   res, i, c, d) {
            res = ""
            for (i = 1; i <= length(str); i++) {
                c = substr(str, i, 1)
                if (c >= "a" && c <= "z") {
                    res = res c
                } else if (c >= "A" && c <= "Z") {
                    res = res tolower(c)
                } else if (c >= "0" && c <= "9") {
                    d = c + 0
                    if (d == 0) res = res "zero"
                    else if (d == 1) res = res "one"
                    else if (d == 2) res = res "two"
                    else if (d == 3) res = res "three"
                    else if (d == 4) res = res "four"
                    else if (d == 5) res = res "five"
                    else if (d == 6) res = res "six"
                    else if (d == 7) res = res "seven"
                    else if (d == 8) res = res "eight"
                    else if (d == 9) res = res "nine"
                }
            }
            return res
        }
        BEGIN {
            kt = clean_alpha_key(title)
            kp = clean_alpha_key(path)
            if (kt != "") t = kt kp
            else if (kp != "") t = kp
            else t = "untitled"

            prefix = sid "-"
            first_child = ""
            last_child = ""
            matched_child = ""
            max_match_k = -1
        }
        {
            f = $0
            if (f == "" || f == def_file) next
            sub_id = f
            sub(/^.*\//, "", sub_id)
            sub(/\.md$/, "", sub_id)
            if (index(sub_id, prefix) != 1) next
            sub_suffix = substr(sub_id, length(prefix) + 1)

            # Strictly require valid alphabetic range or prefix (ignore legacy numeric shards)
            if (!match(sub_suffix, /^[a-z]+-[a-z]+$/) && !match(sub_suffix, /^[a-z]+$/)) next

            if (first_child == "" || f < first_child) first_child = f
            if (last_child == "" || f > last_child) last_child = f

            # Range suffix: e.g. "a-m", "n-s", "pa-pm", "paa-pam"
            if (match(sub_suffix, /^[a-z]+-[a-z]+$/)) {
                dash_pos = index(sub_suffix, "-")
                s_part = substr(sub_suffix, 1, dash_pos - 1)
                e_part = substr(sub_suffix, dash_pos + 1)
                if (length(s_part) == length(e_part)) {
                    K = length(s_part)
                    pfx = substr(t, 1, K)
                    if (pfx >= s_part && pfx <= e_part) {
                        if (K > max_match_k) {
                            max_match_k = K
                            matched_child = f
                        }
                    }
                }
            } else if (match(sub_suffix, /^[a-z]+$/)) {
                K = length(sub_suffix)
                pfx = substr(t, 1, K)
                if (pfx == sub_suffix) {
                    if (K > max_match_k) {
                        max_match_k = K
                        matched_child = f
                    }
                }
            }
        }
        END {
            if (matched_child != "") {
                print matched_child
            } else if (t < "a" && first_child != "") {
                print first_child
            } else if (t > "z" && last_child != "") {
                print last_child
            } else if (base_exists == 1 || first_child == "") {
                print def_file
            } else {
                if (first_child != "") {
                    print first_child
                } else {
                    print def_file
                }
            }
        }
    '
    return 0
}

# -----------------------------------------------------------------------------
# derive_base_id_for_shard
# Summary: Identifies the root base shard ID for any wiki shard file, shielding
#          sub-shards from premature truncation and ensuring accurate prefix
#          tracking across arbitrary B-Tree depth.
#
# @param $1: shard_id - Shard identifier (e.g. "repos-test-repo-packages-n-z").
# @returns: Base shard ID on stdout (e.g. "repos-test-repo-packages").
# @pure
# -----------------------------------------------------------------------------
derive_base_id_for_shard() {
    _sid="$1"
    _shard_path="${RNEX_WIKI_ROOT}/${_sid}.md"

    # 1. Read embedded metadata tag if present
    if [ -f "$_shard_path" ]; then
        _meta_base="$(sed -n 's/^<!-- base: \(.*\) -->$/\1/p' "$_shard_path" 2>/dev/null | head -n 1)"
        if [ -n "$_meta_base" ]; then
            printf '%s\n' "$_meta_base"
            return 0
        fi
    fi

    # 2. Check repo-nexus top-level directories
    case "$_sid" in
        repo-nexus-*)
            _after_rn="${_sid#repo-nexus-}"
            _dir_cand="${_after_rn%%-*}"
            if [ -d "${RNEX_WORKSPACE_ROOT}/${_dir_cand}" ]; then
                printf 'repo-nexus-%s\n' "$_dir_cand"
                return 0
            fi
            printf 'repo-nexus\n'
            return 0
            ;;
        repo-nexus)
            printf 'repo-nexus\n'
            return 0
            ;;
        repos-*)
            _after_rep="${_sid#repos-}"
            _rep_dir="${RNEX_CFG_REPOS_DIR:-repos}"
            for _m_dir in "${RNEX_WORKSPACE_ROOT}/${_rep_dir}"/*; do
                [ -d "$_m_dir" ] || continue
                _m_slug="$(normalize_slug_id "$(basename "$_m_dir")")"
                case "$_after_rep" in
                    "${_m_slug}"|"${_m_slug}-"*)
                        _longest_base="repos-${_m_slug}"
                        for _sub_dir in "$_m_dir"/*; do
                            [ -d "$_sub_dir" ] || continue
                            _sub_slug="$(normalize_slug_id "$(basename "$_sub_dir")")"
                            case "$_after_rep" in
                                "${_m_slug}-${_sub_slug}"|"${_m_slug}-${_sub_slug}-"*)
                                    _longest_base="repos-${_m_slug}-${_sub_slug}"
                                    break
                                    ;;
                            esac
                        done
                        printf '%s\n' "$_longest_base"
                        return 0
                        ;;
                esac
            done
            ;;
    esac

    # 3. Fallback: strip range or numeric suffix using sed
    _stripped="$(printf '%s' "$_sid" | sed 's/-[a-z]\{1,\}-[a-z]\{1,\}$//; s/-[0-9]\{1,\}$//')"
    if [ "$_stripped" != "$_sid" ] && [ -n "$_stripped" ]; then
        printf '%s\n' "$_stripped"
        return 0
    fi

    printf '%s\n' "$_sid"
    return 0
}

# -----------------------------------------------------------------------------
# split_oversized_btree_shards
# Summary: Recursively inspects all leaf shards in $RNEX_WIKI_ROOT (excluding
#          index.md and log.md) and subdivides any shard whose record count
#          exceeds RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES into balanced sub-shards.
#          Appends audit entries ("created: ...", "deleted: ...") to log.md.
#
# Design Patterns & Principles:
#   - Single Responsibility Principle (SRP): Confined strictly to B-Tree shard
#     decomposition and capacity boundary maintenance.
#   - Fail-Safe & Atomic (OWASP A03): Atomic replacement via temporary files.
#   - Information Expert (GRASP): Extracts title keys and partitions entries.
#
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

                # Extract all entries from oversized shard
                _entries_all="${_shard_cand}.all.$$"
                LC_ALL=C grep '^- \*\*' "$_shard_cand" > "$_entries_all" 2>/dev/null || : > "$_entries_all"

                if [ ! -s "$_entries_all" ]; then
                    rm -f "$_entries_all"
                    continue
                fi

                # Partition entries using awk into Child 1 and Child 2
                _part1_tmp="${RNEX_WIKI_ROOT}/.part1.$$"
                _part2_tmp="${RNEX_WIKI_ROOT}/.part2.$$"
                : > "$_part1_tmp"
                : > "$_part2_tmp"

                _child_names="$(LC_ALL=C awk \
                    -v shard_id="$_s_id" \
                    -v base_id="$_base_id" \
                    -v part1_file="$_part1_tmp" \
                    -v part2_file="$_part2_tmp" '
                    function get_title(line,   m) {
                        if (match(line, /^- \*\*\[[^]]+\]/)) {
                            m = substr(line, 6)
                            sub(/\].*$/, "", m)
                            return m
                        } else if (match(line, /^- \*\*[^*]+\*\*/)) {
                            m = substr(line, 5)
                            sub(/\*\*.*$/, "", m)
                            return m
                        }
                        return ""
                    }
                    function get_path(line,   m) {
                        if (match(line, /\(`[^`]+`\)/)) {
                            m = substr(line, RSTART + 2, RLENGTH - 4)
                            return m
                        } else if (match(line, /\]\([^)]+\)/)) {
                            m = substr(line, RSTART + 2, RLENGTH - 3)
                            return m
                        }
                        return ""
                    }
                    function clean_alpha_key(str,   res, i, c, d) {
                        res = ""
                        for (i = 1; i <= length(str); i++) {
                            c = substr(str, i, 1)
                            if (c >= "a" && c <= "z") {
                                res = res c
                            } else if (c >= "A" && c <= "Z") {
                                res = res tolower(c)
                            } else if (c >= "0" && c <= "9") {
                                d = c + 0
                                if (d == 0) res = res "zero"
                                else if (d == 1) res = res "one"
                                else if (d == 2) res = res "two"
                                else if (d == 3) res = res "three"
                                else if (d == 4) res = res "four"
                                else if (d == 5) res = res "five"
                                else if (d == 6) res = res "six"
                                else if (d == 7) res = res "seven"
                                else if (d == 8) res = res "eight"
                                else if (d == 9) res = res "nine"
                            }
                        }
                        return res
                    }
                    BEGIN {
                        alpha = "abcdefghijklmnopqrstuvwxyz"
                        lines_count = 0
                    }
                    {
                        lines_count++
                        lines[lines_count] = $0
                        t = tolower(get_title($0))
                        p = tolower(get_path($0))
                        titles[lines_count] = (t != "") ? t : "untitled"
                        paths[lines_count] = (p != "") ? p : ("item" lines_count)
                    }
                    END {
                        if (lines_count == 0) exit 0

                        # Build sorting keys: title + unique path
                        for (i = 1; i <= lines_count; i++) {
                            kt = clean_alpha_key(titles[i])
                            kp = clean_alpha_key(paths[i])
                            if (kt != "") {
                                keys[i] = kt kp
                            } else {
                                keys[i] = (kp != "") ? kp : ("entry" clean_alpha_key(i))
                            }
                        }

                        # Suffix of shard_id relative to base_id
                        if (shard_id == base_id) {
                            suffix = ""
                        } else {
                            suffix = substr(shard_id, length(base_id) + 2)
                        }

                        # Determine initial S, E, K
                        if (suffix == "") {
                            S = "a"; E = "z"; K = 1
                        } else if (match(suffix, /^[a-z]+-[a-z]+$/)) {
                            dash_pos = index(suffix, "-")
                            s_part = substr(suffix, 1, dash_pos - 1)
                            e_part = substr(suffix, dash_pos + 1)
                            if (length(s_part) == length(e_part)) {
                                S = s_part; E = e_part; K = length(s_part)
                            } else {
                                S = "a"; E = "z"; K = 1
                            }
                        } else if (match(suffix, /^[a-z]+$/)) {
                            S = suffix; E = suffix; K = length(suffix)
                        } else {
                            S = "a"; E = "z"; K = 1
                        }

                        loop_limit = 0
                        while (loop_limit++ < 60) {
                            # Advance past characters shared by all keys in this shard
                            min_c = substr(keys[1], K, 1)
                            max_c = substr(keys[lines_count], K, 1)
                            if (min_c == max_c && min_c >= "a" && min_c <= "z") {
                                P = (K > 1) ? substr(S, 1, K - 1) : ""
                                S = P min_c
                                E = P min_c
                                K = K + 1
                                S = S "a"
                                E = E "z"
                                continue
                            }

                            if (S != E) {
                                P = (K > 1) ? substr(S, 1, K - 1) : ""
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

                                    sfx1 = (r1_s == r1_e) ? r1_s : (r1_s "-" r1_e)
                                    sfx2 = (r2_s == r2_e) ? r2_s : (r2_s "-" r2_e)

                                    c1_name = base_id "-" sfx1
                                    c2_name = base_id "-" sfx2

                                    cnt1 = 0
                                    cnt2 = 0
                                    for (i = 1; i <= lines_count; i++) {
                                        pfx = substr(keys[i], 1, K)
                                        if ((r1_s == (P "a") && pfx < r1_s) || (pfx <= r1_e)) {
                                            cnt1++
                                        } else {
                                            cnt2++
                                        }
                                    }

                                    if (cnt1 > 0 && cnt2 > 0) {
                                        for (i = 1; i <= lines_count; i++) {
                                            pfx = substr(keys[i], 1, K)
                                            if ((r1_s == (P "a") && pfx < r1_s) || (pfx <= r1_e)) {
                                                print lines[i] >> part1_file
                                            } else {
                                                print lines[i] >> part2_file
                                            }
                                        }
                                        printf "%s|%s\n", c1_name, c2_name
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
                                S = P "a"
                                E = P "z"
                                continue
                            }
                        }

                        # Pure alphabetical fallback: find first character position where the two halves differ
                        half_idx = int((lines_count + 1) / 2)
                        diff_pos = 1
                        while (substr(keys[half_idx], diff_pos, 1) == substr(keys[half_idx + 1], diff_pos, 1) && diff_pos < length(keys[half_idx])) {
                            diff_pos++
                        }

                        k1_start = substr(keys[1], 1, diff_pos)
                        k1_end = substr(keys[half_idx], 1, diff_pos)
                        k2_start = substr(keys[half_idx + 1], 1, diff_pos)
                        k2_end = substr(keys[lines_count], 1, diff_pos)

                        sfx1 = (k1_start == k1_end) ? k1_start : (k1_start "-" k1_end)
                        sfx2 = (k2_start == k2_end) ? k2_start : (k2_start "-" k2_end)

                        c1_name = base_id "-" sfx1
                        c2_name = base_id "-" sfx2

                        for (i = 1; i <= lines_count; i++) {
                            if (i <= half_idx) {
                                print lines[i] >> part1_file
                            } else {
                                print lines[i] >> part2_file
                            }
                        }
                        printf "%s|%s\n", c1_name, c2_name
                    }
                ' "$_entries_all")"

                rm -f "$_entries_all"

                _c1_id="${_child_names%%|*}"
                _c2_id="${_child_names#*|}"

                # Safety guard: reject self-split or identical child names
                if [ -z "$_c1_id" ] || [ -z "$_c2_id" ] || [ "$_c1_id" = "$_c2_id" ] || [ "$_c1_id" = "$_s_id" ] || [ "$_c2_id" = "$_s_id" ]; then
                    rm -f "$_part1_tmp" "$_part2_tmp"
                    continue
                fi

                _wrote_any=0

                # Write Child 1 if part1 has entries
                if [ -n "$_c1_id" ] && [ -s "$_part1_tmp" ]; then
                    _c1_file="${RNEX_WIKI_ROOT}/${_c1_id}.md"
                    _c1_existed=0
                    [ -f "$_c1_file" ] && _c1_existed=1
                    _c1_merged="${_c1_file}.mrg.$$"
                    : > "$_c1_merged"
                    if [ "$_c1_existed" -eq 1 ]; then
                        LC_ALL=C grep '^- \*\*' "$_c1_file" >> "$_c1_merged" 2>/dev/null || true
                    fi
                    cat "$_part1_tmp" >> "$_c1_merged"
                    atomic_sort_unique_file "$_c1_merged"
                    _c1_tmp="${_c1_file}.tmp.$$"
                    printf '# Wiki Index Shard: %s\n<!-- base: %s -->\n\n' "$_c1_id" "$_base_id" > "$_c1_tmp"
                    cat "$_c1_merged" >> "$_c1_tmp"
                    mv "$_c1_tmp" "$_c1_file"
                    rm -f "$_c1_merged"
                    if [ "$_c1_existed" -eq 1 ]; then
                        append_wiki_log_entry "$_action" "updated: \`${_c1_id}.md\` (split sub-shard)"
                    else
                        append_wiki_log_entry "$_action" "created: \`${_c1_id}.md\` (split sub-shard)"
                    fi
                    _wrote_any=1
                fi

                # Write Child 2 if part2 has entries
                if [ -n "$_c2_id" ] && [ -s "$_part2_tmp" ]; then
                    _c2_file="${RNEX_WIKI_ROOT}/${_c2_id}.md"
                    _c2_existed=0
                    [ -f "$_c2_file" ] && _c2_existed=1
                    _c2_merged="${_c2_file}.mrg.$$"
                    : > "$_c2_merged"
                    if [ "$_c2_existed" -eq 1 ]; then
                        LC_ALL=C grep '^- \*\*' "$_c2_file" >> "$_c2_merged" 2>/dev/null || true
                    fi
                    cat "$_part2_tmp" >> "$_c2_merged"
                    atomic_sort_unique_file "$_c2_merged"
                    _c2_tmp="${_c2_file}.tmp.$$"
                    printf '# Wiki Index Shard: %s\n<!-- base: %s -->\n\n' "$_c2_id" "$_base_id" > "$_c2_tmp"
                    cat "$_c2_merged" >> "$_c2_tmp"
                    mv "$_c2_tmp" "$_c2_file"
                    rm -f "$_c2_merged"
                    if [ "$_c2_existed" -eq 1 ]; then
                        append_wiki_log_entry "$_action" "updated: \`${_c2_id}.md\` (split sub-shard)"
                    else
                        append_wiki_log_entry "$_action" "created: \`${_c2_id}.md\` (split sub-shard)"
                    fi
                    _wrote_any=1
                fi

                # If at least one child was written, remove oversized parent shard
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
# @param $2: source_arg_label     - Optional CLI argument for log attribution.
# @returns: 0 on success.
# @sideEffects: Updates .rnex/wiki/*.md shards, index.md, and log.md.
# -----------------------------------------------------------------------------
ingest_missing_sources_into_btree() {
    _missing_file="$1"
    _arg_label="$2"
    mkdir -p "$RNEX_WIKI_ROOT"
    ensure_baseline_flat_shards

    # If zero missing sources, inspect existing shards for any needed splits before declaring up-to-date
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

            # Route dynamically to existing leaf sub-shard or base shard
            _target_shard_file="$(resolve_target_btree_shard_file "$_shard_id" "$_title" "$_rel_path")"

            _shard_existed=0
            [ -f "$_target_shard_file" ] && _shard_existed=1

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
            printf '# Wiki Index Shard: %s\n<!-- base: %s -->\n\n' "$_target_shard_id" "$_shard_id" > "$_shard_tmp"
            cat "$_entries_tmp" >> "$_shard_tmp"
            rm -f "$_entries_tmp"
            mv "$_shard_tmp" "$_target_shard_file"

            _ingested_count=$((_ingested_count + 1))
            append_wiki_log_entry "ingest" "created: \`${_rel_path}\` (indexed into \`${_target_shard_id}.md\`)"
            if [ "$_shard_existed" -eq 0 ]; then
                append_wiki_log_entry "ingest" "created: \`${_target_shard_id}.md\` (new shard)"
            else
                append_wiki_log_entry "ingest" "updated: \`${_target_shard_id}.md\` (appended entry)"
            fi
        done 3< "$_missing_file"
    fi

    # Post-ingestion recursive shard splitting for any shard exceeding threshold
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
