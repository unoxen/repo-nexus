#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/source_helpers.sh
# Architectural Layer: Domain-Aware Source Discovery Helpers (helpers/)
# Single Responsibility: Resolve and expand workspace source declarations into
# concrete regular Markdown files in place, supporting recursive glob patterns
# ("**/*.md") portably in pure POSIX /bin/sh without symlinks or Bashisms.
# Standards: POSIX Shell (/bin/sh), OWASP A03 Input Sanitization, SRP.
# Patterns: Iterator Pattern, Information Expert (GRASP), Adapter Pattern.
# Dependencies: config.sh, utils.sh
# =============================================================================

# -----------------------------------------------------------------------------
# extract_base_dir_from_pattern
# Summary: Extracts the static leading directory component of a path pattern
#          before any wildcard characters (*, ?, [) appear.
# @param $1: pattern - Configured path pattern (e.g., "repos/**/README.md").
# @returns: Leading static directory path on stdout (e.g., "repos").
# @pure
# -----------------------------------------------------------------------------
extract_base_dir_from_pattern() {
    _pat="$1"
    _dir="$(dirname "$_pat")"

    case "$_dir" in
        *\**|*\?*|*\[*)
            _curr="$_pat"
            while [ "$_curr" != "." ] && [ "$_curr" != "/" ]; do
                _curr="$(dirname "$_curr")"
                case "$_curr" in
                    *\**|*\?*|*\[*) continue ;;
                    *) _dir="$_curr"; break ;;
                esac
            done
            ;;
    esac

    if [ -z "$_dir" ] || [ "$_dir" = "." ] || [ "$_dir" = "/" ]; then
        _dir="."
    fi
    printf '%s\n' "$_dir"
}

# -----------------------------------------------------------------------------
# match_globstar_path
# Summary: Tests whether a relative path matches a pattern containing `**`
#          using standard POSIX string pattern matching.
# @param $1: rel_path - Workspace-relative candidate path.
# @param $2: pattern  - Configured glob pattern (e.g., "repos/**/README.md").
# @returns: 0 if matched, 1 if not matched.
# @pure
# -----------------------------------------------------------------------------
match_globstar_path() {
    _candidate_path="$1"
    _target_pat="$2"

    # Strip any enclosing quotes or whitespace
    _candidate_path="$(printf '%s' "$_candidate_path" | tr -d '"'\''' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    _target_pat="$(printf '%s' "$_target_pat" | tr -d '"'\''' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    # Strip leading ./ if present
    while [ "${_candidate_path#./}" != "$_candidate_path" ]; do _candidate_path="${_candidate_path#./}"; done
    while [ "${_target_pat#./}" != "$_target_pat" ]; do _target_pat="${_target_pat#./}"; done

    # If candidate path was provided with absolute prefix matching workspace root, strip it
    if [ -n "${RNEX_WORKSPACE_ROOT:-}" ]; then
        _candidate_path="${_candidate_path#"${RNEX_WORKSPACE_ROOT}/"}"
    fi

    # Exact equality shortcut
    if [ "$_candidate_path" = "$_target_pat" ]; then
        return 0
    fi

    # Evaluate recursive '**/' globbing via portable POSIX case expansion
    case "$_target_pat" in
        *\*\**)
            _prefix="${_target_pat%%\*\**}" # substring before first '**'
            _suffix="${_target_pat##*\*\*}" # substring after last '**'
            _suffix="${_suffix#/}"          # strip leading separator if present

            # Validate prefix alignment and suffix matching
            # shellcheck disable=SC2254
            case "$_candidate_path" in
                "$_prefix"*$_suffix)
                    _expected_filename="$(basename "$_suffix")"
                    _actual_filename="$(basename "$_candidate_path")"
                    if [ -n "$_expected_filename" ] && [ "$_expected_filename" != "*" ]; then
                        case "$_actual_filename" in
                            $_expected_filename) return 0 ;;
                            *) return 1 ;;
                        esac
                    fi
                    return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        *)
            # Single-level shell pattern match
            _c_dir="$(dirname "$_candidate_path")"
            _p_dir="$(dirname "$_target_pat")"
            [ "$_c_dir" = "$_p_dir" ] || return 1

            _c_base="$(basename "$_candidate_path")"
            _p_base="$(basename "$_target_pat")"
            # shellcheck disable=SC2254
            case "$_c_base" in
                $_p_base) return 0 ;;
                *) return 1 ;;
            esac
            ;;
    esac
}

# -----------------------------------------------------------------------------
# parse_yaml_sources_for_scope
# Summary: Extracts configured source paths for either the root "repo-nexus"
#          scope (under plugins.karpathy-llm.sources or top-level sources) or a
#          specific member repository (under repos.<repo_name>.sources).
#          Supports both YAML block lists (- item) and inline arrays ([a, b]).
# @param $1: yaml_file  - Path to rnex.yaml or .local.rnex.yaml.
# @param $2: scope_type - "nexus" or "repo".
# @param $3: repo_name  - Member repository name when scope_type="repo".
# @returns: Normalized relative source paths (one per line) on stdout.
# @pure
# -----------------------------------------------------------------------------
parse_yaml_sources_for_scope() {
    _yaml_file="$1"
    _scope_type="$2"
    _target_repo="$3"

    [ -f "$_yaml_file" ] || return 0

    LC_ALL=C awk -v scope="$_scope_type" -v repo="$_target_repo" '
        function clean_token(val) {
            sub(/#.*$/, "", val)
            gsub(/^[ \t"'\''\[\]]+|[ \t"'\''\[\]\r]+$/, "", val)
            sub(/^\.\//, "", val)
            return val
        }
        function emit_inline_array(raw,   n, i, arr, tok) {
            gsub(/^\[|\]$/, "", raw)
            n = split(raw, arr, ",")
            for (i = 1; i <= n; i++) {
                tok = clean_token(arr[i])
                if (length(tok) > 0) print tok
            }
        }
        /^[ \t]*#/ || /^[ \t]*$/ { next }
        {
            match($0, /^[ ]*/)
            indent = RLENGTH
            line = substr($0, indent + 1)

            if (indent == 0) {
                in_repos = (line ~ /^repos:[ \t]*$/)
                in_plugins = (line ~ /^plugins:[ \t]*$/)
                in_target_repo = 0
                in_karpathy = 0
                in_sources_list = 0
                if (scope == "nexus" && line ~ /^sources:[ \t]*/) {
                    rest = line; sub(/^sources:[ \t]*/, "", rest)
                    if (rest ~ /^\[/) emit_inline_array(rest)
                    else { in_sources_list = 1; sources_indent = indent }
                }
                next
            }

            if (scope == "nexus" && in_plugins) {
                if (line ~ /^karpathy-llm:[ \t]*$/ || line ~ /^-[ \t]*name:[ \t]*karpathy-llm/) {
                    in_karpathy = 1
                    karpathy_indent = indent
                    in_sources_list = 0
                    next
                }
                if (in_karpathy && indent <= karpathy_indent && line !~ /^sources:/) {
                    in_karpathy = 0
                    in_sources_list = 0
                }
                if (in_karpathy && line ~ /^sources:[ \t]*/) {
                    rest = line; sub(/^sources:[ \t]*/, "", rest)
                    if (rest ~ /^\[/) emit_inline_array(rest)
                    else { in_sources_list = 1; sources_indent = indent }
                    next
                }
            }

            if (scope == "repo" && in_repos) {
                if (line ~ ("^" repo ":[ \t]*$") || line ~ ("^-[ \t]*name:[ \t]*[\"'\'']?" repo "[\"'\'']?[ \t]*$")) {
                    in_target_repo = 1
                    repo_indent = indent
                    in_sources_list = 0
                    next
                }
                if (in_target_repo && indent <= repo_indent && line !~ /^sources:/) {
                    in_target_repo = 0
                    in_sources_list = 0
                }
                if (in_target_repo && line ~ /^sources:[ \t]*/) {
                    rest = line; sub(/^sources:[ \t]*/, "", rest)
                    if (rest ~ /^\[/) emit_inline_array(rest)
                    else { in_sources_list = 1; sources_indent = indent }
                    next
                }
            }

            if (in_sources_list) {
                if (indent > sources_indent && line ~ /^-[ \t]+/) {
                    item = line
                    sub(/^-[ \t]+/, "", item)
                    item = clean_token(item)
                    if (length(item) > 0) print item
                } else if (indent <= sources_indent) {
                    in_sources_list = 0
                }
            }
        }
    ' "$_yaml_file"
}

# -----------------------------------------------------------------------------
# expand_source_entry_to_files
# Summary: Resolves a single source declaration (file, directory, or recursive
#          glob pattern) to absolute paths of existing regular files (-type f).
#          Strictly excludes symbolic links for Windows/MSYS2 portable safety.
# @param $1: workspace_root - Absolute path to workspace or repository root.
# @param $2: source_entry   - Path, folder, or glob from configuration.
# @returns: Absolute file paths (one per line) on stdout.
# @sideEffects: Traverses filesystem using find.
# -----------------------------------------------------------------------------
expand_source_entry_to_files() {
    _ws_root="$1"
    _entry="${2#./}"

    # OWASP A03: Reject empty values, upward path traversal, or absolute paths
    case "$_entry" in
        ''|*..*|/*) return 0 ;;
    esac

    _full_target="${_ws_root}/${_entry}"

    # 1. Exact regular file (NOT a symlink)
    if [ -f "$_full_target" ] && [ ! -L "$_full_target" ]; then
        printf '%s\n' "$_full_target"
        return 0
    fi

    # 2. Directory -> find all Markdown files strictly within this directory
    if [ -d "$_full_target" ] && [ ! -L "$_full_target" ]; then
        find "$_full_target" -type f \( -name '*.md' -o -name '*.mdx' \) \
            ! -path '*/.git/*' \
            ! -path '*/.rnex/*' \
            ! -path '*/node_modules/*' \
            ! -path "${_ws_root}/wiki/*" 2>/dev/null | LC_ALL=C sort
        return 0
    fi

    # 3. Glob pattern (e.g., "repos/**/README.md" or "docs/**/*.md")
    _base_rel="$(extract_base_dir_from_pattern "$_entry")"
    if [ "$_base_rel" = "." ]; then
        _search_dir="$_ws_root"
    else
        _search_dir="${_ws_root}/${_base_rel}"
    fi

    [ -d "$_search_dir" ] || return 0

    _leaf_name="$(basename "$_entry")"
    case "$_leaf_name" in
        *\**|*\?*|*\[*)
            find "$_search_dir" -type f \( -name '*.md' -o -name '*.mdx' \) \
                ! -path '*/.git/*' \
                ! -path '*/.rnex/*' \
                ! -path '*/node_modules/*' \
                ! -path "${_ws_root}/wiki/*" 2>/dev/null | LC_ALL=C sort | while IFS= read -r _abs_cand; do
                [ -n "$_abs_cand" ] || continue
                _rel_cand="${_abs_cand#"${_ws_root}/"}"
                if match_globstar_path "$_rel_cand" "$_entry"; then
                    printf '%s\n' "$_abs_cand"
                fi
            done
            ;;
        *)
            find "$_search_dir" -type f -name "$_leaf_name" \
                ! -path '*/.git/*' \
                ! -path '*/.rnex/*' \
                ! -path '*/node_modules/*' \
                ! -path "${_ws_root}/wiki/*" 2>/dev/null | LC_ALL=C sort | while IFS= read -r _abs_cand; do
                [ -n "$_abs_cand" ] || continue
                _rel_cand="${_abs_cand#"${_ws_root}/"}"
                if match_globstar_path "$_rel_cand" "$_entry"; then
                    printf '%s\n' "$_abs_cand"
                fi
            done
            ;;
    esac
}

# -----------------------------------------------------------------------------
# append_source_file_to_btree_records
# Summary: Extracts metadata (title, summary, slug, shard assignment) from an
#          authoritative Markdown file in place and appends a 5-column TSV record:
#          <shard_id>\t<entry_slug>\t<rel_ws_path>\t<title>\t<summary>
# @param $1: abs_file - Absolute path to target Markdown file.
# @param $2: out_tmp  - Target output file descriptor/path for batch appending.
# @sideEffects: Appends record line to target file.
# -----------------------------------------------------------------------------
append_source_file_to_btree_records() {
    _abs_file="$1"
    _out_tmp="$2"

    [ -f "$_abs_file" ] && [ ! -L "$_abs_file" ] || return 0

    _rel_ws="${_abs_file#"${RNEX_WORKSPACE_ROOT}/"}"

    case "$_rel_ws" in
        repos/*)
            _member="$(printf '%s' "$_rel_ws" | cut -d'/' -f2)"
            if command -v is_repo_enabled >/dev/null 2>&1; then
                is_repo_enabled "$_member" || return 0
            fi
            _rel_in_repo="${_rel_ws#"repos/${_member}/"}"
            _sub_dir="$(printf '%s' "$_rel_in_repo" | cut -d'/' -f1)"
            _member_slug="$(normalize_slug_id "$_member")"

            if [ "$_sub_dir" != "$_rel_in_repo" ] && [ -n "$_sub_dir" ]; then
                _shard_id="repos-${_member_slug}-$(normalize_slug_id "$_sub_dir")"
            else
                _shard_id="repos-${_member_slug}"
            fi
            ;;
        *)
            _first_dir="$(printf '%s' "$_rel_ws" | cut -d'/' -f1)"
            if [ "$_first_dir" != "$_rel_ws" ] && [ "$_first_dir" != "docs" ]; then
                _shard_id="repo-nexus-$(normalize_slug_id "$_first_dir")"
            else
                _shard_id="repo-nexus"
            fi
            ;;
    esac

    _stem="$(basename "$_abs_file" | sed 's/\.[^.]*$//')"
    _entry_slug="$(normalize_slug_id "$_stem")" || _entry_slug="doc"

    _title="$(LC_ALL=C awk '/^# / { sub(/^# +/, ""); print; exit }' "$_abs_file" < /dev/null)"
    [ -n "$_title" ] || _title="$_stem"

    _summary="$(LC_ALL=C awk '
        /^#/ || /^$/ || /^---/ || /^```/ || /^- \*\*/ || /^\|/ { next }
        { print; exit }
    ' "$_abs_file" < /dev/null)"
    [ -n "$_summary" ] || _summary="Source documentation at ${_rel_ws}"

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$_shard_id" \
        "$_entry_slug" \
        "$_rel_ws" \
        "$(sanitize_single_line_text "$_title")" \
        "$(sanitize_single_line_text "$_summary")" >> "$_out_tmp"
}

# -----------------------------------------------------------------------------
# build_workspace_btree_records
# Summary: Enumerates all configured sources across repo-nexus and member repos
#          in place without symlinks, extracting titles and summaries, and
#          compiling a sorted, deduplicated 5-column intermediate manifest:
#          <shard_id>\t<entry_slug>\t<rel_ws_path>\t<title>\t<summary>
# @param $1: records_out - Destination filepath for compiled TSV records.
# @param $2: single_opt  - Optional specific file path to ingest or prioritize.
# @returns: 0 on success, 1 on error.
# @sideEffects: Creates records_out atomically using sort -u.
# -----------------------------------------------------------------------------
build_workspace_btree_records() {
    _records_out="$1"
    _single_opt="${2:-}"
    _raw_tmp="${_records_out}.tmp.$$"
    : > "$_raw_tmp"

    # Priority 1 (.local.rnex.yaml) + Priority 2 (rnex.yaml)
    _sources="$(
        {
            parse_yaml_sources_for_scope "${RNEX_WORKSPACE_ROOT}/.local.rnex.yaml" "nexus" ""
            parse_yaml_sources_for_scope "${RNEX_WORKSPACE_ROOT}/rnex.yaml" "nexus" ""
        } | LC_ALL=C awk '!seen[$0]++'
    )"

    _top_sources_configured=1
    if [ -z "$_sources" ]; then
        _top_sources_configured=0
        _sources="$(printf 'README.md\nAGENTS.md\ndocs\n')"
    fi

    # Expand top-level declared sources
    printf '%s\n' "$_sources" | while IFS= read -r _entry; do
        [ -n "$_entry" ] || continue
        expand_source_entry_to_files "$RNEX_WORKSPACE_ROOT" "$_entry" | while IFS= read -r _abs_file; do
            [ -n "$_abs_file" ] || continue
            append_source_file_to_btree_records "$_abs_file" "$_raw_tmp"
        done
    done

    # Member repositories resolution
    _repos_dir="${RNEX_WORKSPACE_ROOT}/${RNEX_CFG_REPOS_DIR:-repos}"
    for _member in $(discover_enabled_member_repos < /dev/null); do
        _member_root="${_repos_dir}/${_member}"
        [ -d "$_member_root" ] || continue

        _member_sources="$(
            {
                parse_yaml_sources_for_scope "${RNEX_WORKSPACE_ROOT}/.local.rnex.yaml" "repo" "$_member"
                parse_yaml_sources_for_scope "${RNEX_WORKSPACE_ROOT}/rnex.yaml" "repo" "$_member"
            } | LC_ALL=C awk '!seen[$0]++'
        )"

        if [ -n "$_member_sources" ]; then
            printf '%s\n' "$_member_sources" | while IFS= read -r _m_entry; do
                [ -n "$_m_entry" ] || continue
                expand_source_entry_to_files "$_member_root" "$_m_entry" | while IFS= read -r _abs_mf; do
                    [ -n "$_abs_mf" ] || continue
                    append_source_file_to_btree_records "$_abs_mf" "$_raw_tmp"
                done
            done
        elif [ "$_top_sources_configured" -eq 0 ]; then
            if [ -f "${_member_root}/README.md" ] && [ ! -L "${_member_root}/README.md" ]; then
                append_source_file_to_btree_records "${_member_root}/README.md" "$_raw_tmp"
            fi
        fi
    done

    # Optional single file inclusion if supplied and valid
    if [ -n "$_single_opt" ]; then
        case "$_single_opt" in
            /*) _s_abs="$_single_opt" ;;
            *)  _s_abs="${RNEX_WORKSPACE_ROOT}/${_single_opt}" ;;
        esac
        append_source_file_to_btree_records "$_s_abs" "$_raw_tmp"
    fi

    LC_ALL=C sort -u "$_raw_tmp" > "$_records_out"
    rm -f "$_raw_tmp"
    return 0
}

# -----------------------------------------------------------------------------
# build_workspace_source_manifest
# Summary: Adapter maintaining compatibility for 4-column source manifests:
#          <shard_id>\t<sub_scope>\t<workspace_rel_path>\t<abs_file_path>
# @param $1: manifest_out - Output manifest filepath.
# @param $2: single_opt   - Optional specific file path.
# -----------------------------------------------------------------------------
build_workspace_source_manifest() {
    _manifest_out="$1"
    _single_opt="${2:-}"
    _btree_tmp="${_manifest_out}.btree.$$"
    build_workspace_btree_records "$_btree_tmp" "$_single_opt" || return 1
    awk -F '\t' -v ws="$RNEX_WORKSPACE_ROOT" '{
        split($1, parts, "-")
        sub_scope = (length(parts) > 2) ? parts[length(parts)] : ""
        printf "%s\t%s\t%s\t%s/%s\n", $1, sub_scope, $3, ws, $3
    }' "$_btree_tmp" > "$_manifest_out"
    rm -f "$_btree_tmp"
    return 0
}
