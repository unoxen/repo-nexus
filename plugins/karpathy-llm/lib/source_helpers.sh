#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/source_helpers.sh
# Architectural Layer: Domain-Aware Source Discovery Helpers (helpers/)
# Single Responsibility: Resolve and expand workspace source declarations into
# concrete regular Markdown files in place, supporting recursive glob patterns
# ("**/*.md") portably in pure POSIX /bin/sh without symlinks or Bashisms.
# Standards: POSIX Shell (/bin/sh), OWASP A03 Input Sanitization, SRP.
# Patterns: Iterator Pattern, Information Expert (GRASP).
# =============================================================================

# -----------------------------------------------------------------------------
# extract_base_dir_from_pattern
# Summary: Extracts the static leading directory component of a path before any
#          wildcard characters (*, ?, [) appear.
# @param $1: pattern - Configured path pattern (e.g., "repos/**/README.md").
# @returns: Leading static directory path on stdout (e.g., "repos").
# @pure
# -----------------------------------------------------------------------------
extract_base_dir_from_pattern() {
    _pat="$1"
    # Take directory portion
    _dir="$(dirname "$_pat")"

    # If the directory itself contains wildcards, strip back to the root
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

    # Default to current directory if pattern starts immediately with a wildcard
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

    # If candidate path was provided as an absolute path matching workspace root, strip it
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
            # Convert 'prefix/**/suffix' pattern matching into multi-depth validation
            _prefix="${_target_pat%%\*\**}" # substring before first '**'
            _suffix="${_target_pat##*\*\*}" # substring after last '**'
            _suffix="${_suffix#/}"          # strip leading separator if present

            # Validate prefix and suffix alignment
            # shellcheck disable=SC2254
            case "$_candidate_path" in
                "$_prefix"*$_suffix)
                    # Check filename constraint when suffix specifies an exact name (e.g., "README.md")
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
            # Single-level shell pattern match: directory must match, basename matches pattern
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
# Summary: Extracts all configured source paths for either the root "repo-nexus"
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
# @param $1: workspace_root - Absolute path to workspace or repo root.
# @param $2: source_entry   - Path, folder, or glob from configuration.
# @returns: Absolute file paths (one per line) on stdout.
# -----------------------------------------------------------------------------
expand_source_entry_to_files() {
    _ws_root="$1"
    _entry="$2"

    # OWASP A03: Reject empty values or upward path traversals
    case "$_entry" in
        ''|*..*|/*) return 0 ;;
    esac

    # Normalize entry
    _entry="${_entry#./}"
    _full_target="${_ws_root}/${_entry}"

    # Case 1: Exact regular file
    if [ -f "$_full_target" ] && [ ! -L "$_full_target" ]; then
        printf '%s\n' "$_full_target"
        return 0
    fi

    # Case 2: Exact directory -> Ingest Markdown files strictly within this directory
    if [ -d "$_full_target" ] && [ ! -L "$_full_target" ]; then
        find "$_full_target" -type f \( -name '*.md' -o -name '*.mdx' \) \
            ! -path '*/.git/*' \
            ! -path '*/.rnex/*' \
            ! -path '*/node_modules/*' \
            ! -path "${_ws_root}/wiki/*" 2>/dev/null | LC_ALL=C sort
        return 0
    fi

    # Case 3: Glob pattern (e.g., "repos/**/README.md" or "*.md")
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
# build_workspace_source_manifest
# Summary: Enumerates all configured sources into a tab-separated manifest:
#          <shard_id>\t<sub_scope>\t<workspace_rel_path>\t<abs_file_path>
#          without injecting arbitrary member repository defaults.
# @param $1: manifest_out   - Output manifest filepath.
# @param $2: single_file_opt - Optional specific file path to prioritize.
# -----------------------------------------------------------------------------
build_workspace_source_manifest() {
    _manifest_out="$1"
    _single_opt="${2:-}"
    _raw_tmp="${_manifest_out}.tmp.$$"
    : > "$_raw_tmp"

    # Collect configured top-level sources (Priority 1: .local.rnex.yaml, Priority 2: rnex.yaml)
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

    # Expand each configured entry
    printf '%s\n' "$_sources" | while IFS= read -r _entry; do
        [ -n "$_entry" ] || continue
        expand_source_entry_to_files "$RNEX_WORKSPACE_ROOT" "$_entry" | while IFS= read -r _abs_file; do
            [ -n "$_abs_file" ] || continue
            _rel_ws="${_abs_file#"${RNEX_WORKSPACE_ROOT}/"}"

            # Map shard attribution based on repository path
            case "$_rel_ws" in
                repos/*/*)
                    # Belongs to a member repo: repos/<repo-name>/...
                    _member="$(printf '%s' "$_rel_ws" | cut -d'/' -f2)"
                    if command -v is_repo_enabled >/dev/null 2>&1; then
                        is_repo_enabled "$_member" || continue
                    fi
                    _rel_in_repo="${_rel_ws#"repos/${_member}/"}"
                    _dir_in_repo="$(dirname "$_rel_in_repo")"
                    if [ -n "$_dir_in_repo" ] && [ "$_dir_in_repo" != "." ]; then
                        if command -v normalize_slug_id >/dev/null 2>&1; then
                            _m_sub="$(normalize_slug_id "$_dir_in_repo")"
                        else
                            _m_sub="$(printf '%s' "$_dir_in_repo" | tr '/' '-')"
                        fi
                    else
                        _m_sub=""
                    fi
                    if command -v normalize_slug_id >/dev/null 2>&1; then
                        _shard_id="repos-$(normalize_slug_id "$_member")"
                    else
                        _shard_id="repos-${_member}"
                    fi
                    ;;
                *)
                    # Belongs to the Nexus repo
                    _dir_in_nexus="$(dirname "$_rel_ws")"
                    if [ -n "$_dir_in_nexus" ] && [ "$_dir_in_nexus" != "." ]; then
                        if command -v normalize_slug_id >/dev/null 2>&1; then
                            _m_sub="$(normalize_slug_id "$_dir_in_nexus")"
                        else
                            _m_sub="$(printf '%s' "$_dir_in_nexus" | tr '/' '-')"
                        fi
                    else
                        _m_sub=""
                    fi
                    _shard_id="repo-nexus"
                    ;;
            esac

            printf '%s\t%s\t%s\t%s\n' "$_shard_id" "$_m_sub" "$_rel_ws" "$_abs_file" >> "$_raw_tmp"
        done
    done

    # Member repositories resolution
    _repos_dir="${RNEX_WORKSPACE_ROOT}/${RNEX_CFG_REPOS_DIR:-repos}"
    for _member in $(discover_enabled_member_repos < /dev/null); do
        _member_root="${_repos_dir}/${_member}"
        [ -d "$_member_root" ] || continue

        # Check for explicit per-repository sources
        _member_sources="$(
            {
                parse_yaml_sources_for_scope "${RNEX_WORKSPACE_ROOT}/.local.rnex.yaml" "repo" "$_member"
                parse_yaml_sources_for_scope "${RNEX_WORKSPACE_ROOT}/rnex.yaml" "repo" "$_member"
            } | LC_ALL=C awk '!seen[$0]++'
        )"

        if [ -n "$_member_sources" ]; then
            # Explicit per-member sources configured: expand them
            printf '%s\n' "$_member_sources" | while IFS= read -r _m_entry <&0; do
                [ -n "$_m_entry" ] || continue
                expand_source_entry_to_files "$_member_root" "$_m_entry" < /dev/null | while IFS= read -r _abs_mf; do
                    [ -n "$_abs_mf" ] || continue
                    _rel_ws="${_abs_mf#"${RNEX_WORKSPACE_ROOT}/"}"
                    _rel_in_repo="${_abs_mf#"${_member_root}/"}"
                    _dir_in_repo="$(dirname "$_rel_in_repo")"
                    if [ -n "$_dir_in_repo" ] && [ "$_dir_in_repo" != "." ]; then
                        if command -v normalize_slug_id >/dev/null 2>&1; then
                            _m_sub="$(normalize_slug_id "$_dir_in_repo")"
                        else
                            _m_sub="$(printf '%s' "$_dir_in_repo" | tr '/' '-')"
                        fi
                    else
                        _m_sub=""
                    fi
                    if command -v normalize_slug_id >/dev/null 2>&1; then
                        _m_shard="repos-$(normalize_slug_id "$_member")"
                    else
                        _m_shard="repos-${_member}"
                    fi
                    printf '%s\t%s\t%s\t%s\n' "$_m_shard" "$_m_sub" "$_rel_ws" "$_abs_mf" >> "$_raw_tmp"
                done
            done
        elif [ "$_top_sources_configured" -eq 0 ]; then
            # Top-level sources were NOT configured at all in rnex.yaml.
            # Default fallback for member repo: only its README.md if present
            if [ -f "${_member_root}/README.md" ] && [ ! -L "${_member_root}/README.md" ]; then
                _abs_mf="${_member_root}/README.md"
                _rel_ws="${_abs_mf#"${RNEX_WORKSPACE_ROOT}/"}"
                if command -v normalize_slug_id >/dev/null 2>&1; then
                    _m_shard="repos-$(normalize_slug_id "$_member")"
                else
                    _m_shard="repos-${_member}"
                fi
                printf '%s\t\t%s\t%s\n' "$_m_shard" "$_rel_ws" "$_abs_mf" >> "$_raw_tmp"
            fi
        fi
        # When _top_sources_configured == 1 and member has no explicit sources,
        # we strictly avoid synthesizing arbitrary docs/ member fallbacks.
    done

    # Explicit single file inclusion if provided and not yet present
    if [ -n "$_single_opt" ]; then
        case "$_single_opt" in
            /*) _single_abs="$_single_opt" ;;
            *)  _single_abs="${RNEX_WORKSPACE_ROOT}/${_single_opt}" ;;
        esac
        if [ -f "$_single_abs" ] && [ ! -L "$_single_abs" ]; then
            _s_rel="${_single_abs#"${RNEX_WORKSPACE_ROOT}/"}"
            case "$_s_rel" in
                repos/*/*)
                    _s_after_repos="${_s_rel#repos/}"
                    _s_repo="$(printf '%s' "$_s_after_repos" | cut -d'/' -f1)"
                    if command -v is_repo_enabled >/dev/null 2>&1; then
                        is_repo_enabled "$_s_repo" || _s_repo=""
                    fi
                    if [ -n "$_s_repo" ]; then
                        _s_in_repo="${_s_after_repos#"${_s_repo}/"}"
                        _dir_in_repo="$(dirname "$_s_in_repo")"
                        if [ -n "$_dir_in_repo" ] && [ "$_dir_in_repo" != "." ]; then
                            if command -v normalize_slug_id >/dev/null 2>&1; then
                                _s_sub="$(normalize_slug_id "$_dir_in_repo")"
                            else
                                _s_sub="$(printf '%s' "$_dir_in_repo" | tr '/' '-')"
                            fi
                        else
                            _s_sub=""
                        fi
                        if command -v normalize_slug_id >/dev/null 2>&1; then
                            _s_shard="repos-$(normalize_slug_id "$_s_repo")"
                        else
                            _s_shard="repos-${_s_repo}"
                        fi
                        printf '%s\t%s\t%s\t%s\n' "$_s_shard" "$_s_sub" "$_s_rel" "$_single_abs" >> "$_raw_tmp"
                    fi
                    ;;
                *)
                    _dir_in_nexus="$(dirname "$_s_rel")"
                    if [ -n "$_dir_in_nexus" ] && [ "$_dir_in_nexus" != "." ]; then
                        if command -v normalize_slug_id >/dev/null 2>&1; then
                            _s_sub="$(normalize_slug_id "$_dir_in_nexus")"
                        else
                            _s_sub="$(printf '%s' "$_dir_in_nexus" | tr '/' '-')"
                        fi
                    else
                        _s_sub=""
                    fi
                    printf 'repo-nexus\t%s\t%s\t%s\n' "$_s_sub" "$_s_rel" "$_single_abs" >> "$_raw_tmp"
                    ;;
            esac
        fi
    fi

    LC_ALL=C sort -u "$_raw_tmp" > "$_manifest_out"
    rm -f "$_raw_tmp"
    return 0
}
