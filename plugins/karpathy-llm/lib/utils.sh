#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/utils.sh
# Architectural Layer: Pure General Utilities (utils/ — Zero Domain Dependencies)
# Single Responsibility: Provide stateless, deterministic, dependency-free
# string, slug, path normalization, relative link prefix calculation,
# markdown sanitization, ISO-8601 UTC date retrieval, and atomic file sorting.
#
# Design Patterns & Principles:
#   - Single Responsibility Principle (SRP): Each utility function addresses
#     one specific data transformation or string manipulation task.
#   - Functional Purity: All utilities are strictly pure and side-effect free,
#     except for get_iso_utc_date (reads system clock) and atomic_sort_unique_file
#     (atomic filesystem sort operation).
#   - Zero Domain Dependencies: Contains zero knowledge of repository models,
#     plugin configurations, or domain entities.
#
# Standards: Pure POSIX Shell (/bin/sh), OWASP ASVS A03 Input Sanitization.
# =============================================================================

# Guard against redundant multiple inclusion in subshells or helper chains
if [ "${RNEX_KARPATHY_UTILS_SH_SOURCED:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
RNEX_KARPATHY_UTILS_SH_SOURCED=1

# -----------------------------------------------------------------------------
# get_iso_utc_date
# Summary: Returns the current UTC date formatted strictly in ISO-8601
#          representation (YYYY-MM-DD).
# @returns: 10-character ISO-8601 date string on stdout.
# @pure (Deterministic with respect to system clock at invocation time)
# -----------------------------------------------------------------------------
get_iso_utc_date() {
    date -u +"%Y-%m-%d"
}

# -----------------------------------------------------------------------------
# normalize_slug_id
# Summary: Converts an arbitrary string or file stem into a canonical lowercase
#          alphanumeric slug (a-z, 0-9, hyphen) suitable for deterministic
#          B-Tree shard file names or entry keys.
# @param $1: raw_identifier - Input title, filename, or token string.
# @returns: Canonical slug on stdout; returns 1 if resulting slug is empty.
# @pure
# -----------------------------------------------------------------------------
normalize_slug_id() {
    _slug="$(printf '%s' "$1" \
        | LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
    if [ -z "$_slug" ]; then
        return 1
    fi
    printf '%s\n' "$_slug"
    return 0
}

# -----------------------------------------------------------------------------
# normalize_workspace_rel_path
# Summary: Normalizes an absolute or relative path to a safe, canonical
#          workspace-relative file path by stripping leading "./", redundant
#          slashes, and Windows CR characters.
#          Rejects path traversal ("..") and absolute paths outside the root.
# @param $1: workspace_root - Absolute workspace root path.
# @param $2: target_path - Absolute or workspace-relative file path.
# @returns: Clean workspace-relative path on stdout, or 1 if outside root or invalid.
# @throws: Returns 1 on invalid path traversal or out-of-boundary access (OWASP A03).
# @pure
# -----------------------------------------------------------------------------
normalize_workspace_rel_path() {
    _ws_root="${1%/}"
    _raw_path="$(printf '%s' "$2" | tr -d '\r')"

    case "$_raw_path" in
        "${_ws_root}/"*)
            # Strip workspace root prefix if absolute
            _rel="${_raw_path#"${_ws_root}/"}"
            ;;
        /*)
            # Absolute path outside workspace root is rejected (OWASP A03)
            return 1
            ;;
        *)
            _rel="$_raw_path"
            ;;
    esac

    # Strip leading "./", collapse redundant slashes, and strip trailing slash
    _rel="$(printf '%s' "$_rel" | sed 's#^\./##; s#///*#/#g; s#/$##')"
    case "$_rel" in
        ''|*..*|/*)
            return 1
            ;;
    esac
    printf '%s\n' "$_rel"
    return 0
}

# -----------------------------------------------------------------------------
# compute_upward_rel_prefix
# Summary: Computes the upward relative traversal prefix ("../") needed to reach
#          the workspace root from a given workspace-relative directory
#          (e.g., ".rnex/wiki" -> "../../", "wiki" -> "../", "docs/wiki" -> "../../").
# @param $1: wiki_rel_dir - Clean workspace-relative directory path.
# @returns: Upward relative path prefix ending with "/" on stdout.
# @pure
# -----------------------------------------------------------------------------
compute_upward_rel_prefix() {
    _clean_dir="$(printf '%s' "$1" | sed 's#^\./##; s#/$##')"
    if [ -z "$_clean_dir" ] || [ "$_clean_dir" = "." ]; then
        return 0
    fi
    printf '%s' "$_clean_dir" | LC_ALL=C awk -F'/' '{
        prefix = ""
        for (i = 1; i <= NF; i++) {
            if ($i != "" && $i != ".") {
                prefix = prefix "../"
            }
        }
        print prefix
    }'
}

# -----------------------------------------------------------------------------
# sanitize_markdown_summary
# Summary: Sanitizes a single-line summary string by stripping control chars,
#          tabs, pipes, and newlines that could corrupt Markdown table or list
#          formatting. Collapses consecutive whitespace and truncates to 140 chars.
# @param $1: raw_text - Input summary string.
# @returns: Sanitized summary truncated to 140 characters on stdout.
# @pure
# -----------------------------------------------------------------------------
sanitize_markdown_summary() {
    printf '%s' "$1" \
        | tr '\t\r\n|' '    ' \
        | sed 's/  */ /g; s/^ //; s/ $//' \
        | cut -c1-140
}

# -----------------------------------------------------------------------------
# sanitize_single_line_text
# Summary: Strips tabs, carriage returns, and newlines from a string and collapses
#          consecutive whitespace into a single space, trimming leading/trailing edges.
# @param $1: raw_text - Unsanitized input text.
# @returns: Single-line, whitespace-collapsed string on stdout.
# @pure
# -----------------------------------------------------------------------------
sanitize_single_line_text() {
    printf '%s' "$1" | tr '\t\r\n' '   ' | sed 's/  */ /g; s/^ //; s/ $//'
}

# -----------------------------------------------------------------------------
# atomic_sort_unique_file
# Summary: Sorts a file in-place using strict byte-order collation (LC_ALL=C)
#          and eliminates duplicate lines atomically via a temporary file.
# @param $1: target_file - File path to sort in place.
# @returns: 0 on success; 1 on failure.
# @sideEffects: Replaces $1 atomically with sorted unique lines.
# -----------------------------------------------------------------------------
atomic_sort_unique_file() {
    _target="$1"
    [ -f "$_target" ] || return 1
    _tmp="${_target}.tmp.$$"
    if LC_ALL=C sort -u "$_target" > "$_tmp"; then
        mv "$_tmp" "$_target"
        return 0
    fi
    rm -f "$_tmp"
    return 1
}
