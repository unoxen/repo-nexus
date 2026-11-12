#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2016
# =============================================================================
# File: plugins/llm-wiki/lib/source_helpers.sh
# Architectural Layer: Domain Helpers (helpers/)
# Single Responsibility: Discover candidate Markdown source files from an
# explicit CLI source argument or configured `sources` in rnex YAML configs,
# and filter them against existing .rnex/wiki/*.md shards so ONLY missing
# sources are ingested into the B-Tree knowledge store.
#
# Design Patterns & Principles:
#   - Information Expert (GRASP): Encapsulates knowledge of source file
#     discovery, glob matching, and shard ID derivation.
#   - Strategy Pattern (GoF): Supports multiple source discovery strategies
#     (explicit file, directory scan, globstar recursion, YAML configuration).
#   - Filter Pipeline: Candidate paths are discovered, deduplicated, and
#     filtered against already-indexed shard records via set difference (comm).
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
# Summary: Parses the `sources` list from .local.rnex.yaml (Priority 1) or
#          rnex.yaml (Priority 2), or plugin configuration. Supports both
#          YAML block sequences (`- item`) and inline arrays (`sources: [...]`).
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
            function emit_inline(raw, prefix,   n, i, parts, tok) {
                sub(/^[[:space:]]*\[/, "", raw)
                sub(/\][[:space:]]*$/, "", raw)
                n = split(raw, parts, ",")
                for (i = 1; i <= n; i++) {
                    tok = clean_token(parts[i])
                    if (tok != "") print (prefix != "" ? prefix "/" tok : tok)
                }
            }
            /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
            {
                match($0, /^[ ]*/)
                indent = RLENGTH
                line = substr($0, indent + 1)

                if (indent == 0) {
                    in_repos = (line ~ /^repos:[[:space:]]*$/)
                    in_plugins = (line ~ /^plugins:[[:space:]]*$/)
                    curr_repo = ""
                    in_repo_sources = 0
                    in_top_sources = 0
                    in_llm_wiki = 0
                    in_llm_wiki_sources = 0
                    if (line ~ /^sources:[[:space:]]*\[.*\][[:space:]]*$/) {
                        sub(/^sources:[[:space:]]*/, "", line)
                        emit_inline(line, "")
                        found_top_sources = 1
                    } else if (line ~ /^sources:[[:space:]]*$/) {
                        in_top_sources = 1
                        found_top_sources = 1
                    }
                    next
                }
                if (in_top_sources) {
                    if (line ~ /^-[[:space:]]+/) {
                        sub(/^-[[:space:]]+/, "", line)
                        tok = clean_token(line)
                        if (tok != "") print tok
                    } else if (indent == 0) {
                        in_top_sources = 0
                    }
                    next
                }
                if (in_plugins) {
                    if (line ~ /^llm-wiki:[[:space:]]*$/) {
                        in_llm_wiki = 1
                        in_llm_wiki_sources = 0
                        next
                    }
                    if (in_llm_wiki) {
                        if (line ~ /^sources:[[:space:]]*\[.*\][[:space:]]*$/) {
                            sub(/^sources:[[:space:]]*/, "", line)
                            emit_inline(line, "")
                            found_top_sources = 1
                        } else if (line ~ /^sources:[[:space:]]*$/) {
                            in_llm_wiki_sources = 1
                            found_top_sources = 1
                        } else if (in_llm_wiki_sources && line ~ /^-[[:space:]]+/) {
                            sub(/^-[[:space:]]+/, "", line)
                            tok = clean_token(line)
                            if (tok != "") print tok
                        } else if (line !~ /^-[[:space:]]+/) {
                            in_llm_wiki_sources = 0
                        }
                    }
                }
                if (in_repos) {
                    if (indent == 2 && line ~ /^[^[:space:]-][^:]*:[[:space:]]*$/) {
                        curr_repo = line
                        sub(/:.*$/, "", curr_repo)
                        curr_repo = clean_token(curr_repo)
                        repo_order[++num_repos] = curr_repo
                        repo_enabled[curr_repo] = 1
                        in_repo_sources = 0
                        next
                    }
                    if (curr_repo != "") {
                        if (line ~ /^enabled:[[:space:]]*false/) {
                            repo_enabled[curr_repo] = 0
                        }
                        if (line ~ /^sources:[[:space:]]*\[.*\][[:space:]]*$/) {
                            sub(/^sources:[[:space:]]*/, "", line)
                            emit_inline(line, "repos/" curr_repo)
                            repo_has_sources[curr_repo] = 1
                        } else if (line ~ /^sources:[[:space:]]*$/) {
                            in_repo_sources = 1
                        } else if (in_repo_sources && line ~ /^-[[:space:]]+/) {
                            sub(/^-[[:space:]]+/, "", line)
                            tok = clean_token(line)
                            if (tok != "") {
                                print "repos/" curr_repo "/" tok
                                repo_has_sources[curr_repo] = 1
                            }
                        } else if (line !~ /^-[[:space:]]+/) {
                            in_repo_sources = 0
                        }
                    }
                }
            }
            END {
                for (i = 1; i <= num_repos; i++) {
                    r = repo_order[i]
                    if (repo_enabled[r] && !repo_has_sources[r]) {
                        print "repos/" r "/README.md"
                    }
                }
            }
        ' "$_cfg_file")"
        if [ -n "$_extracted" ]; then
            _found_sources="$_extracted"
            break
        fi
    done

    # 3. If still empty, fall back to default candidate sources
    if [ -z "$_found_sources" ]; then
        _found_sources="README.md
docs
repos/**/README.md"
    fi

    printf '%s\n' "$_found_sources"
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
        # Matches both formats:
        # 1. - **[Title](../../path)** (`path`) — summary
        # 2. - **slug** (`path`) — summary
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
#          Markdown file paths, rejecting symlinks and the wiki directory itself.
# @param $1: source_spec - File path, directory path, or glob pattern.
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
                if match_globstar_path "$_rel" "$_spec"; then
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
            printf '%s\n' "$_rel" >> "$_out_file"
        done
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# resolve_missing_sources_to_ingest
# Summary: Resolves candidate Markdown files from either the passed CLI source
#          argument ($1) or configured `sources` in .local.rnex.yaml / rnex.yaml,
#          and filters out any source already present in .rnex/wiki/*.md shards.
# @param $1: explicit_source_arg - Optional CLI source argument (empty for config).
# @param $2: out_missing_file - File receiving ONLY missing workspace_rel_paths.
# @returns: 0 on success; 1 if an explicit CLI source argument is invalid/missing.
# @throws: Writes error to stderr on missing explicit argument file.
# @sideEffects: Writes sorted missing workspace-relative file paths to $2.
# -----------------------------------------------------------------------------
resolve_missing_sources_to_ingest() {
    _explicit_arg="$1"
    _out_missing="$2"
    _candidates_tmp="${_out_missing}.cand.$$"
    _indexed_tmp="${_out_missing}.idx.$$"
    : > "$_candidates_tmp"
    : > "$_out_missing"

    if [ -n "$_explicit_arg" ]; then
        if ! expand_single_source_spec "$_explicit_arg" "$_candidates_tmp"; then
            rm -f "$_candidates_tmp" "$_indexed_tmp"
            printf 'Error [ingest]: Source "%s" not found or invalid.\n' "$_explicit_arg" >&2
            return 1
        fi
    else
        _sources_list="$(parse_configured_workspace_sources "$RNEX_WORKSPACE_ROOT")"
        _spec_tmp="${_out_missing}.specs.$$"
        printf '%s\n' "$_sources_list" > "$_spec_tmp"
        while IFS= read -r _src_entry <&3; do
            [ -n "$_src_entry" ] || continue
            expand_single_source_spec "$_src_entry" "$_candidates_tmp" < /dev/null || true
        done 3< "$_spec_tmp"
        rm -f "$_spec_tmp"
    fi

    atomic_sort_unique_file "$_candidates_tmp" || true
    extract_already_indexed_paths "$_indexed_tmp"

    # Keep ONLY candidate paths NOT already present in $_indexed_tmp
    if [ -s "$_candidates_tmp" ]; then
        if [ -s "$_indexed_tmp" ]; then
            LC_ALL=C comm -23 "$_candidates_tmp" "$_indexed_tmp" > "$_out_missing"
        else
            cp "$_candidates_tmp" "$_out_missing"
        fi
    fi

    rm -f "$_candidates_tmp" "$_indexed_tmp"
    return 0
}

# -----------------------------------------------------------------------------
# Backwards-Compatible Helpers
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

match_globstar_path() {
    _candidate_path="$1"
    _target_pat="$2"

    _candidate_path="$(printf '%s' "$_candidate_path" | tr -d '"'\''' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    _target_pat="$(printf '%s' "$_target_pat" | tr -d '"'\''' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    while [ "${_candidate_path#./}" != "$_candidate_path" ]; do _candidate_path="${_candidate_path#./}"; done
    while [ "${_target_pat#./}" != "$_target_pat" ]; do _target_pat="${_target_pat#./}"; done

    if [ -n "${RNEX_WORKSPACE_ROOT:-}" ]; then
        _candidate_path="${_candidate_path#"${RNEX_WORKSPACE_ROOT}/"}"
    fi

    if [ "$_candidate_path" = "$_target_pat" ]; then
        return 0
    fi

    case "$_target_pat" in
        *\*\**)
            _prefix="${_target_pat%%\*\**}"
            _suffix="${_target_pat##*\*\*}"
            _suffix="${_suffix#/}"

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
            # shellcheck disable=SC2254
            case "$_candidate_path" in
                $_target_pat) return 0 ;;
                *) return 1 ;;
            esac
            ;;
    esac
}
