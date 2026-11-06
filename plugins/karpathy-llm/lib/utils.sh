#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/utils.sh
# Architectural Layer: Pure General Utilities (utils/ — Zero Domain Dependencies)
# Single Responsibility: Provide deterministic string sanitization, slug
# normalization, ISO-8601 date formatting, atomic C-locale sorting, and O(log N)
# prefix search over sorted plaintext files.
# Extension Points: Strategy selection in binary_search_sorted_prefix (native
# POSIX/BSD `look` binary search vs. deterministic `LC_ALL=C awk` early-exit).
# Patterns Applied: Strategy Pattern (look binary search with awk early-exit
# fallback), Pure Fabrication (GRASP).
# Security (OWASP A03): Sanitizes tabs, newlines, carriage returns, and shell
# metacharacters from untrusted text prior to TSV or Markdown serialization.
# =============================================================================

# -----------------------------------------------------------------------------
# get_iso_utc_date
# Summary: Formats current system UTC clock as an ISO-8601 date (YYYY-MM-DD).
# @param: None.
# @returns: 10-character YYYY-MM-DD string on stdout.
# @throws: None (falls back to standard POSIX date invocation).
# @sideEffects: Reads UTC system clock via POSIX `date -u`.
# -----------------------------------------------------------------------------
get_iso_utc_date() {
    date -u +"%Y-%m-%d"
}

# -----------------------------------------------------------------------------
# get_iso_utc_timestamp
# Summary: Formats current system UTC clock as an ISO-8601 timestamp
#          (YYYY-MM-DDTHH:MM:SSZ) for append-only audit log entries.
# @param: None.
# @returns: 20-character ISO-8601 UTC timestamp on stdout.
# @throws: None.
# @sideEffects: Reads UTC system clock via POSIX `date -u`.
# -----------------------------------------------------------------------------
get_iso_utc_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# -----------------------------------------------------------------------------
# sanitize_tsv_field
# Summary: Strips tabs, carriage returns, and newlines from an arbitrary string
#          so it cannot corrupt TSV column boundaries or inject forged records.
# @param $1: raw_input - Untrusted string value.
# @returns: Sanitized single-line, tab-free string on stdout.
# @throws: None.
# @pure
# -----------------------------------------------------------------------------
sanitize_tsv_field() {
    # Replace horizontal tabs, carriage returns, and newlines with spaces,
    # collapse consecutive spaces, and trim leading/trailing whitespace.
    printf '%s' "$1" | tr '\t\r\n' '   ' | sed 's/  */ /g; s/^ //; s/ $//'
}

# -----------------------------------------------------------------------------
# normalize_slug_id
# Summary: Normalizes a raw page title or wikilink target into a canonical,
#          lowercase ASCII identifier ([a-z0-9_-]).
# @param $1: raw_identifier - String to normalize.
# @returns: Canonical lowercase slug on stdout; returns 0 on valid slug.
# @throws: Returns 1 if the resulting normalized slug is empty.
# @pure
# -----------------------------------------------------------------------------
normalize_slug_id() {
    # Convert uppercase ASCII to lowercase in C locale, replace any non-slug
    # characters with hyphens, collapse multiple hyphens, and strip edge hyphens.
    _slug="$(printf '%s' "$1" \
        | LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C sed 's/[^a-z0-9_-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
    if [ -z "$_slug" ]; then
        return 1
    fi
    printf '%s\n' "$_slug"
    return 0
}

# -----------------------------------------------------------------------------
# atomic_sort_unique_file
# Summary: Sorts a file lexicographically using strict byte-order (LC_ALL=C),
#          deduplicates identical lines, and replaces the target atomically.
# @param $1: target_file - Path to the file to sort in-place.
# @returns: 0 on success; 1 on missing file or write error.
# @throws: Cleans up temporary file and returns 1 if sort fails.
# @sideEffects: Atomically overwrites target_file via a temporary sibling file.
# -----------------------------------------------------------------------------
atomic_sort_unique_file() {
    _target="$1"
    if [ -z "$_target" ] || [ ! -f "$_target" ]; then
        return 1
    fi
    _tmp_file="${_target}.tmp.$$"
    if LC_ALL=C sort -u "$_target" > "$_tmp_file"; then
        mv "$_tmp_file" "$_target"
        return 0
    fi
    rm -f "$_tmp_file"
    return 1
}

# -----------------------------------------------------------------------------
# binary_search_sorted_prefix
# Summary: Performs an O(log N) binary search for lines starting with a given
#          prefix in an LC_ALL=C sorted file using POSIX `look`, falling back
#          to an early-exit sorted `awk` scan if `look` is absent or disabled.
# @pattern Strategy (Runtime selection between BSD/POSIX `look` and early-exit `awk`)
# @param $1: search_prefix - Exact string prefix to match at line start.
# @param $2: sorted_file   - Path to an LC_ALL=C sorted file.
# @returns: Matching lines on stdout; 0 even if zero matches found, 1 on error.
# @throws: Returns 1 if search_prefix is empty or sorted_file does not exist.
# @pure (Read-only operation on deterministic sorted input)
# -----------------------------------------------------------------------------
binary_search_sorted_prefix() {
    _prefix="$1"
    _file="$2"

    if [ -z "$_prefix" ] || [ -z "$_file" ] || [ ! -f "$_file" ]; then
        return 1
    fi

    # Strategy 1: Use native `look` binary search O(log N) when available
    # and not explicitly bypassed via RNEX_FORCE_AWK_BINARY_SEARCH=1 (for testing).
    if [ "${RNEX_FORCE_AWK_BINARY_SEARCH:-0}" != "1" ] && command -v look >/dev/null 2>&1; then
        # `look` returns exit code 1 when no lines match; normalize to 0.
        LC_ALL=C look -- "$_prefix" "$_file" 2>/dev/null || true
        return 0
    fi

    # Strategy 2: Deterministic early-exit scan in C locale.
    # Because _file is strictly sorted in LC_ALL=C order, as soon as a line's
    # prefix is lexicographically greater than _prefix, no subsequent line can match.
    LC_ALL=C awk -v pfx="$_prefix" '
        BEGIN { plen = length(pfx) }
        {
            sub_str = substr($0, 1, plen)
            if (sub_str == pfx) {
                print $0
            } else if (sub_str > pfx) {
                exit 0
            }
        }
    ' "$_file"
    return 0
}
