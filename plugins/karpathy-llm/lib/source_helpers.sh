#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/source_helpers.sh
# Architectural Layer: Domain-Aware Source Discovery Helpers (helpers/)
# Single Responsibility: Resolve and enumerate 100% of configured documentation
# sources across the root Nexus repository ("repo-nexus") and enabled member
# repositories ("repos/<member>") directly in place—with ZERO symlinks.
# Patterns Applied: Iterator Pattern (manifest-backed iteration to prevent
# POSIX pipe stdin starvation), Information Expert (GRASP).
# Security (OWASP A03): Rejects path traversal ("..") escaping workspace root
# and never follows or creates symbolic links (-type f and [ ! -L ] only).
# =============================================================================

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
# Summary: Expands a configured source entry (file, directory, or glob) within
#          a repository root into regular Markdown files (-type f).
#          Never creates or follows symbolic links (Windows & Git safe).
# @param $1: base_dir     - Path to the repo root (workspace root or ./repos/<name>).
# @param $2: source_entry - Configured path or glob (e.g., "README.md", "docs").
# @returns: Absolute paths to regular files (one per line) on stdout.
# @pure
# -----------------------------------------------------------------------------
expand_source_entry_to_files() {
    _base_dir="$1"
    _entry="$2"

    case "$_entry" in
        ''|*..*|/*) return 0 ;;
    esac

    _target="${_base_dir}/${_entry}"

    # 1. Exact regular file (NOT a symlink)
    if [ -f "$_target" ] && [ ! -L "$_target" ]; then
        printf '%s\n' "$_target"
        return 0
    fi

    # 2. Directory -> find all regular .md / .mdx files (excluding metadata dirs)
    if [ -d "$_target" ] && [ ! -L "$_target" ]; then
        find "$_target" -type f \( -name '*.md' -o -name '*.mdx' \) \
            ! -path '*/.git/*' \
            ! -path '*/.rnex/*' \
            ! -path '*/node_modules/*' \
            ! -path "${RNEX_WIKI_ROOT:-${_base_dir}/wiki}/*" \
            ! -path "${_base_dir}/${RNEX_CFG_REPOS_DIR:-repos}/*" 2>/dev/null | LC_ALL=C sort
        return 0
    fi

    # 3. Shell glob pattern (only if entry contains glob metacharacters)
    case "$_entry" in
        *'*'*|*'?'*)
            _parent_dir="$(dirname "$_target")"
            _glob_pat="$(basename "$_target")"
            if [ -d "$_parent_dir" ] && [ ! -L "$_parent_dir" ]; then
                find "$_parent_dir" -type f -name "$_glob_pat" \
                    ! -path '*/.git/*' \
                    ! -path '*/.rnex/*' \
                    ! -path '*/node_modules/*' \
                    ! -path "${RNEX_WIKI_ROOT:-${_base_dir}/wiki}/*" \
                    ! -path "${_base_dir}/${RNEX_CFG_REPOS_DIR:-repos}/*" 2>/dev/null | LC_ALL=C sort
            fi
            ;;
    esac
    return 0
}

# -----------------------------------------------------------------------------
# build_workspace_source_manifest
# Summary: Resolves ALL configured sources for "repo-nexus" and every enabled
#          member repository into a tab-separated manifest:
#          <repo_scope>\t<sub_scope>\t<workspace_rel_path>\t<abs_file_path>
# @param $1: manifest_out_file - Path to write the resolved manifest.
# @param $2: single_file_opt   - Optional single file path to explicitly include.
# @returns: 0 on success.
# @sideEffects: Writes resolved source records to manifest_out_file.
# -----------------------------------------------------------------------------
build_workspace_source_manifest() {
    _manifest_out="$1"
    _single_opt="${2:-}"
    _raw_tmp="${_manifest_out}.raw.$$"
    : > "$_raw_tmp"

    # 1. Sources for the Root Nexus Repo ("repo-nexus")
    _nexus_sources="$(
        {
            parse_yaml_sources_for_scope "${RNEX_WORKSPACE_ROOT}/.local.rnex.yaml" "nexus" ""
            parse_yaml_sources_for_scope "${RNEX_WORKSPACE_ROOT}/rnex.yaml" "nexus" ""
        } | LC_ALL=C awk '!seen[$0]++'
    )"
    if [ -z "$_nexus_sources" ]; then
        _nexus_sources="$(printf 'README.md\nAGENTS.md\ndocs\n')"
    fi

    printf '%s\n' "$_nexus_sources" | while IFS= read -r _src_entry <&0; do
        [ -n "$_src_entry" ] || continue
        expand_source_entry_to_files "$RNEX_WORKSPACE_ROOT" "$_src_entry" < /dev/null | while IFS= read -r _abs_f; do
            [ -n "$_abs_f" ] || continue
            _rel_f="${_abs_f#"${RNEX_WORKSPACE_ROOT}/"}"
            _first_seg="$(printf '%s' "$_rel_f" | cut -d'/' -f1)"
            _second_seg="$(printf '%s' "$_rel_f" | cut -d'/' -f2)"
            if [ -n "$_second_seg" ] && [ "$_first_seg" != "$_rel_f" ]; then
                _sub_scope="$(normalize_slug_id "$_first_seg")"
            else
                _sub_scope=""
            fi
            printf 'repo-nexus\t%s\t%s\t%s\n' "$_sub_scope" "$_rel_f" "$_abs_f" >> "$_raw_tmp"
        done
    done

    # 2. Sources for every enabled Member Repository
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
        if [ -z "$_member_sources" ]; then
            _member_sources="$(printf 'README.md\ndocs\n')"
        fi

        printf '%s\n' "$_member_sources" | while IFS= read -r _m_entry <&0; do
            [ -n "$_m_entry" ] || continue
            expand_source_entry_to_files "$_member_root" "$_m_entry" < /dev/null | while IFS= read -r _abs_mf; do
                [ -n "$_abs_mf" ] || continue
                _rel_ws="${_abs_mf#"${RNEX_WORKSPACE_ROOT}/"}"
                _rel_in_repo="${_abs_mf#"${_member_root}/"}"
                _m_first="$(printf '%s' "$_rel_in_repo" | cut -d'/' -f1)"
                _m_second="$(printf '%s' "$_rel_in_repo" | cut -d'/' -f2)"
                if [ -n "$_m_second" ] && [ "$_m_first" != "$_rel_in_repo" ]; then
                    _m_sub="$(normalize_slug_id "$_m_first")"
                else
                    _m_sub=""
                fi
                printf 'repos-%s\t%s\t%s\t%s\n' "$(normalize_slug_id "$_member")" "$_m_sub" "$_rel_ws" "$_abs_mf" >> "$_raw_tmp"
            done
        done
    done

    # 3. Explicit single file inclusion if provided and not yet present
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
                    _s_in_repo="${_s_after_repos#"${_s_repo}/"}"
                    _s_first="$(printf '%s' "$_s_in_repo" | cut -d'/' -f1)"
                    _s_second="$(printf '%s' "$_s_in_repo" | cut -d'/' -f2)"
                    if [ -n "$_second" ] && [ "$_s_first" != "$_s_in_repo" ]; then
                        _s_sub="$(normalize_slug_id "$_s_first")"
                    else
                        _s_sub=""
                    fi
                    printf 'repos-%s\t%s\t%s\t%s\n' "$(normalize_slug_id "$_s_repo")" "$_s_sub" "$_s_rel" "$_single_abs" >> "$_raw_tmp"
                    ;;
                *)
                    _s_first="$(printf '%s' "$_s_rel" | cut -d'/' -f1)"
                    _s_second="$(printf '%s' "$_s_rel" | cut -d'/' -f2)"
                    if [ -n "$_s_second" ] && [ "$_s_first" != "$_s_rel" ]; then
                        _s_sub="$(normalize_slug_id "$_s_first")"
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
