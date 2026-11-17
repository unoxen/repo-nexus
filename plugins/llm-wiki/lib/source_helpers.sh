#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2016
# =============================================================================
# File: plugins/llm-wiki/lib/source_helpers.sh
# Architectural Layer: Domain Helpers (helpers/)
# Single Responsibility: Discover candidate Markdown source files from an
# explicit CLI source argument or configured `plugins.llm-wiki.sources` in
# rnex YAML configs, and optionally filter them against existing wiki shards.
#
# Design Patterns & Principles:
#   - Information Expert (GRASP): Encapsulates knowledge of source file
#     discovery, glob matching, member repository enablement filtering, and
#     shard ID derivation.
#   - Strategy Pattern (GoF): Supports multiple source discovery strategies
#     (explicit file, directory scan, globstar recursion, YAML configuration).
#   - Filter Pipeline: Candidate paths are discovered via
#     resolve_candidate_sources (used directly by `ingest --force`) and
#     filtered via filter_missing_sources using set difference (`comm -23`)
#     for default missing-only ingestion.
#
# Security & Standards:
#   - Pure POSIX Shell (/bin/sh): No bashisms, fully quoted expansions.
#   - OWASP ASVS A03: Strict validation against path traversal (".."),
#     absolute paths, and symbolic links.
# =============================================================================

# Guard against redundant multiple inclusion
if [ "${RNEX_LLM_WIKI_SOURCE_HELPERS_SH_SOURCED:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
RNEX_LLM_WIKI_SOURCE_HELPERS_SH_SOURCED=1

# -----------------------------------------------------------------------------
# parse_configured_workspace_sources
# Summary: Parses the `plugins.llm-wiki.sources` list from .local.rnex.yaml
#          (Priority 1) or rnex.yaml (Priority 2). Supports both YAML block
#          sequences (`- item`) and inline arrays (`sources: [...]`).
#          Falls back to default sources when unconfigured.
# @param $1: workspace_root - Absolute path to workspace root.
# @returns: Newline-delimited source specifications on stdout.
# @pure (Read-only configuration inspection)
# -----------------------------------------------------------------------------
parse_configured_workspace_sources() {
    _ws_root="$1"
    _found_sources=""

    for _cfg_file in "${_ws_root}/.local.rnex.yaml" "${_ws_root}/rnex.yaml"; do
        [ -f "$_cfg_file" ] || continue
        _extracted="$(LC_ALL=C awk '
            function clean_token(s) {
                gsub(/\r/, "", s)
                sub(/[[:space:]]+#.*$/, "", s)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
                if ((s ~ /^".*"$/) || (s ~ /^'\''[^'\'']*'\''$/)) {
                    s = substr(s, 2, length(s) - 2)
                }
                return s
            }
            function emit_inline(raw,   n, i, parts, tok) {
                sub(/^[[:space:]]*\[/, "", raw)
                sub(/\][[:space:]]*$/, "", raw)
                n = split(raw, parts, ",")
                for (i = 1; i <= n; i++) {
                    tok = clean_token(parts[i])
                    if (tok != "") print tok
                }
            }
            /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
            {
                match($0, /^[ ]*/)
                indent = RLENGTH
                line = substr($0, indent + 1)

                if (indent == 0) {
                    in_plugins = (line ~ /^plugins:[[:space:]]*$/)
                    in_llm_wiki = 0
                    in_llm_wiki_sources = 0
                    next
                }
                if (in_plugins) {
                    if (indent == 2 && line ~ /^[^[:space:]-][^:]*:/) {
                        in_llm_wiki = (line ~ /^llm-wiki:[[:space:]]*$/)
                        in_llm_wiki_sources = 0
                        next
                    }
                    if (in_llm_wiki) {
                        if (line ~ /^sources:[[:space:]]*\[.*\][[:space:]]*$/) {
                            sub(/^sources:[[:space:]]*/, "", line)
                            emit_inline(line)
                            in_llm_wiki_sources = 0
                        } else if (line ~ /^sources:[[:space:]]*$/) {
                            in_llm_wiki_sources = 1
                        } else if (in_llm_wiki_sources && line ~ /^-[[:space:]]+/) {
                            sub(/^-[[:space:]]+/, "", line)
                            tok = clean_token(line)
                            if (tok != "") print tok
                        } else if (line !~ /^-[[:space:]]+/) {
                            in_llm_wiki_sources = 0
                        }
                    }
                }
            }
        ' "$_cfg_file")"
        if [ -n "$_extracted" ]; then
            _found_sources="$_extracted"
            break
        fi
    done

    # Fall back to default candidate sources defined in plugin.yaml config_defaults
    if [ -z "$_found_sources" ]; then
        _repos_dir="${RNEX_CFG_REPOS_DIR:-repos}"
        _repos_dir="${_repos_dir%/}"
        _found_sources="README.md
docs
${_repos_dir}/**/README.md"
    fi

    printf '%s\n' "$_found_sources"
    return 0
}

# -----------------------------------------------------------------------------
# _is_workspace_source_enabled
# Summary: Verifies whether a candidate workspace-relative file path belongs
#          to an enabled member repository (or root workspace). Rejects paths
#          under disabled member repositories (`enabled: false`).
# @param $1: workspace_rel_path - Normalized workspace-relative file path.
# @returns: 0 if allowed; 1 if inside a disabled member repository.
# @pure
# -----------------------------------------------------------------------------
_is_workspace_source_enabled() {
    _cand_rel="$1"
    _rdir="${RNEX_CFG_REPOS_DIR:-repos}"
    _rdir="${_rdir%/}"
    case "$_cand_rel" in
        "${_rdir}/"*)
            _after_r="${_cand_rel#"${_rdir}/"}"
            _m_repo="${_after_r%%/*}"
            if [ -n "$_m_repo" ] && command -v is_repo_enabled >/dev/null 2>&1; then
                is_repo_enabled "$_m_repo" || return 1
            fi
            ;;
    esac
    return 0
}

# -----------------------------------------------------------------------------
# extract_already_indexed_paths
# Summary: Scans all existing B-Tree leaf shards (repo-nexus*.md and repos-*.md)
#          inside $RNEX_WIKI_ROOT and outputs all already-indexed workspace-
#          relative file paths in sorted LC_ALL=C order.
# @param $1: out_indexed_file - File path to write sorted indexed paths.
# @returns: 0 on success.
# @sideEffects: Writes sorted workspace-relative paths to $1.
# -----------------------------------------------------------------------------
extract_already_indexed_paths() {
    _out_idx="$1"
    : > "$_out_idx"
    [ -d "$RNEX_WIKI_ROOT" ] || return 0

    for _shard_file in "${RNEX_WIKI_ROOT}"/repo-nexus*.md "${RNEX_WIKI_ROOT}"/repos-*.md; do
        [ -f "$_shard_file" ] || continue
        LC_ALL=C awk '/^- \*\*/ && match($0, /\*\* \(`[^`]+`\)/) { print substr($0, RSTART + 5, RLENGTH - 7) }' "$_shard_file" >> "$_out_idx"
    done

    atomic_sort_unique_file "$_out_idx" || true
    return 0
}

# -----------------------------------------------------------------------------
# derive_shard_id_for_workspace_path
# Summary: Deterministically maps a workspace-relative file path to its flat
#          B-Tree shard identifier ("repo-nexus[-<scope>]" or "repos-<member>[-<scope>]").
# @param $1: workspace_rel_path - Normalized workspace-relative file path.
# @returns: Deterministic shard ID string on stdout.
# @pure
# -----------------------------------------------------------------------------
derive_shard_id_for_workspace_path() {
    _rel="$1"
    _repos_dir="${RNEX_CFG_REPOS_DIR:-repos}"
    _repos_dir="${_repos_dir%/}"

    case "$_rel" in
        "${_repos_dir}/"*)
            _after_repos="${_rel#"${_repos_dir}/"}"
            _member_name="$(printf '%s' "$_after_repos" | cut -d'/' -f1)"
            _second_seg="$(printf '%s' "$_after_repos" | cut -d'/' -f2)"
            _third_seg="$(printf '%s' "$_after_repos" | cut -d'/' -f3)"
            _member_slug="$(normalize_slug_id "$_member_name")"
            if [ -n "$_third_seg" ]; then
                _scope_slug="$(normalize_slug_id "$_second_seg")"
                printf 'repos-%s-%s\n' "$_member_slug" "$_scope_slug"
            else
                printf 'repos-%s\n' "$_member_slug"
            fi
            ;;
        */*)
            _top_dir="$(printf '%s' "$_rel" | cut -d'/' -f1)"
            _top_slug="$(normalize_slug_id "$_top_dir")"
            printf 'repo-nexus-%s\n' "$_top_slug"
            ;;
        *)
            printf 'repo-nexus\n'
            ;;
    esac
}

# -----------------------------------------------------------------------------
# expand_single_source_spec
# Summary: Expands a single source specification (regular file, directory, or
#          glob pattern including "**") into normalized workspace-relative
#          Markdown file paths, rejecting symlinks, disabled member repos,
#          and the wiki directory itself.
# @param $1: source_spec         - File path, directory path, or glob pattern.
# @param $2: out_candidates_file - Output file to append discovered paths.
# @returns: 0 on valid expansion; 1 if explicit path does not exist.
# @throws: Writes error to stderr on path traversal or symlinks (OWASP A03).
# @sideEffects: Appends workspace-relative paths to $2.
# -----------------------------------------------------------------------------
expand_single_source_spec() {
    _spec="$(printf '%s' "$1" | tr -d '\r')"
    _out_file="$2"
    [ -n "$_spec" ] || return 0

    case "$_spec" in
        *..*|/*)
            printf 'Error [security]: Unsafe source path "%s" rejected (OWASP A03).\n' "$_spec" >&2
            return 1
            ;;
    esac

    _abs_spec="${RNEX_WORKSPACE_ROOT}/${_spec#./}"

    # Case 1: Glob pattern (*, ?, [) including globstar (**)
    case "$_spec" in
        *\**|*\?*|*\[*)
            _prefix="${_spec%%[\*\?\[]*}"
            _prefix="${_prefix%/}"
            _search_root="${RNEX_WORKSPACE_ROOT}"
            [ -n "$_prefix" ] && _search_root="${RNEX_WORKSPACE_ROOT}/${_prefix#./}"
            [ -d "$_search_root" ] || return 0

            find "$_search_root" -type f \( -name '*.md' -o -name '*.mdx' \) \
                ! -path "${RNEX_WIKI_ROOT}/*" ! -path '*/.rnex/*' ! -path '*/.git/*' ! -path '*/node_modules/*' -print \
            | while IFS= read -r _found_abs; do
                [ -L "$_found_abs" ] && continue
                _rel="$(normalize_workspace_rel_path "$RNEX_WORKSPACE_ROOT" "$_found_abs")" || continue
                _is_workspace_source_enabled "$_rel" || continue
                if match_globstar_path "$_rel" "$_spec" "$RNEX_WORKSPACE_ROOT"; then
                    printf '%s\n' "$_rel" >> "$_out_file"
                fi
            done
            return 0
            ;;
    esac

    # Case 2: Reject symbolic links explicitly (OWASP ASVS A03)
    if [ -L "$_abs_spec" ]; then
        printf 'Error [ingest]: Symbolic link "%s" is not permitted.\n' "$_spec" >&2
        return 1
    fi

    # Case 3: Exact regular file
    if [ -f "$_abs_spec" ]; then
        _rel="$(normalize_workspace_rel_path "$RNEX_WORKSPACE_ROOT" "$_abs_spec")" || return 1
        _is_workspace_source_enabled "$_rel" || return 0
        printf '%s\n' "$_rel" >> "$_out_file"
        return 0
    fi

    # Case 4: Directory -> recursively find all regular .md/.mdx files
    if [ -d "$_abs_spec" ]; then
        find "$_abs_spec" -type f \( -name '*.md' -o -name '*.mdx' \) \
            ! -path "${RNEX_WIKI_ROOT}/*" ! -path '*/.rnex/*' ! -path '*/.git/*' ! -path '*/node_modules/*' -print \
        | while IFS= read -r _found_abs; do
            [ -L "$_found_abs" ] && continue
            _rel="$(normalize_workspace_rel_path "$RNEX_WORKSPACE_ROOT" "$_found_abs")" || continue
            _is_workspace_source_enabled "$_rel" || continue
            printf '%s\n' "$_rel" >> "$_out_file"
        done
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# resolve_candidate_sources
# Summary: Expands either an explicit positional source argument ($1 — file,
#          directory, or glob pattern) or the configured `plugins.llm-wiki.sources`
#          list into sorted, unique workspace-relative Markdown paths.
# @param $1: explicit_source_arg - Optional CLI positional path (empty for config).
# @param $2: out_candidates_file - File receiving sorted candidate workspace_rel_paths.
# @returns: 0 on success; 1 if an explicit CLI source argument is invalid/missing.
# @throws: Writes error to stderr on missing or invalid explicit argument.
# @sideEffects: Writes sorted workspace-relative file paths to $2.
# -----------------------------------------------------------------------------
resolve_candidate_sources() {
    _rcs_arg="$1"
    _rcs_out="$2"
    : > "$_rcs_out"

    if [ -n "$_rcs_arg" ]; then
        if ! expand_single_source_spec "$_rcs_arg" "$_rcs_out"; then
            rm -f "$_rcs_out"
            printf 'Error [ingest]: Source "%s" not found or invalid.\n' "$_rcs_arg" >&2
            return 1
        fi
    else
        _rcs_list="$(parse_configured_workspace_sources "$RNEX_WORKSPACE_ROOT")"
        _rcs_spec_tmp="${_rcs_out}.specs.$$"
        printf '%s\n' "$_rcs_list" > "$_rcs_spec_tmp"
        while IFS= read -r _rcs_entry <&3; do
            [ -n "$_rcs_entry" ] || continue
            expand_single_source_spec "$_rcs_entry" "$_rcs_out" < /dev/null || true
        done 3< "$_rcs_spec_tmp"
        rm -f "$_rcs_spec_tmp"
    fi

    atomic_sort_unique_file "$_rcs_out" || true
    return 0
}

# -----------------------------------------------------------------------------
# filter_missing_sources
# Summary: Computes the set difference (`comm -23`) between a sorted file of
#          candidate workspace-relative paths ($1) and all paths already
#          indexed in existing wiki shards, writing only missing paths to $2.
# @param $1: candidates_file  - Sorted file of candidate workspace_rel_paths.
# @param $2: out_missing_file - Destination file receiving missing paths.
# @returns: 0 on success.
# @sideEffects: Writes sorted missing workspace-relative paths to $2.
# -----------------------------------------------------------------------------
filter_missing_sources() {
    _fms_cand="$1"
    _fms_out="$2"
    _fms_idx="${_fms_out}.idx.$$"
    : > "$_fms_out"

    extract_already_indexed_paths "$_fms_idx"

    if [ -s "$_fms_cand" ]; then
        if [ -s "$_fms_idx" ]; then
            LC_ALL=C comm -23 "$_fms_cand" "$_fms_idx" > "$_fms_out"
        else
            cp "$_fms_cand" "$_fms_out"
        fi
    fi

    rm -f "$_fms_idx"
    return 0
}

# -----------------------------------------------------------------------------
# resolve_missing_sources_to_ingest
# Summary: Resolves candidate Markdown files from either the passed CLI source
#          argument ($1) or configured `plugins.llm-wiki.sources` in
#          .local.rnex.yaml / rnex.yaml, and filters out any source already
#          present in existing wiki shards.
# @param $1: explicit_source_arg - Optional CLI source argument (empty for config).
# @param $2: out_missing_file    - File receiving ONLY missing workspace_rel_paths.
# @returns: 0 on success; 1 if an explicit CLI source argument is invalid/missing.
# @throws: Writes error to stderr on missing explicit argument file.
# @sideEffects: Writes sorted missing workspace-relative file paths to $2.
# -----------------------------------------------------------------------------
resolve_missing_sources_to_ingest() {
    _explicit_arg="$1"
    _out_missing="$2"
    _candidates_tmp="${_out_missing}.cand.$$"
    : > "$_out_missing"

    if ! resolve_candidate_sources "$_explicit_arg" "$_candidates_tmp"; then
        rm -f "$_candidates_tmp"
        return 1
    fi

    filter_missing_sources "$_candidates_tmp" "$_out_missing"
    rm -f "$_candidates_tmp"
    return 0
}
