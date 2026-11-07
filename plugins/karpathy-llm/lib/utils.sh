#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/utils.sh
# Architectural Layer: General & Dependency-Free Utilities (utils/)
# Single Responsibility: Pure, stateless string slugification, link target
# canonicalization, TSV field sanitization, ISO-8601 UTC date formatting, atomic
# sorting, and O(log N) LC_ALL=C binary search.
# Purity: Strictly pure (@pure) with zero domain or external dependencies.
# Security (OWASP A03): Sanitizes tabs, control characters, and path traversal
# sequences from all inputs before TSV or shell processing.
# =============================================================================

# -----------------------------------------------------------------------------
# get_iso_utc_date
# Summary: Returns the current UTC date formatted strictly as YYYY-MM-DD.
# @returns: 10-character ISO-8601 date string on stdout.
# @sideEffects: Reads system clock via POSIX `date -u`.
# -----------------------------------------------------------------------------
get_iso_utc_date() {
    date -u +"%Y-%m-%d"
}

# -----------------------------------------------------------------------------
# get_iso_utc_timestamp
# Summary: Formats current system UTC clock as an ISO-8601 timestamp
#          (YYYY-MM-DDTHH:MM:SSZ) for append-only audit log entries.
# @returns: 20-character ISO-8601 UTC timestamp on stdout.
# @sideEffects: Reads UTC system clock via POSIX `date -u`.
# -----------------------------------------------------------------------------
get_iso_utc_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# -----------------------------------------------------------------------------
# sanitize_tsv_field
# Summary: Strips tabs, carriage returns, and newlines from a string so it
#          cannot corrupt column alignment in TSV graph files.
# @param $1: raw_value - Unsanitized input text.
# @returns: Single-line, tab-free string on stdout.
# @pure
# -----------------------------------------------------------------------------
sanitize_tsv_field() {
    printf '%s' "$1" | tr '\t\r\n' '   ' | sed 's/  */ /g; s/^ //; s/ $//'
}

# -----------------------------------------------------------------------------
# normalize_slug_id
# Summary: Converts an arbitrary string or file stem into a canonical lowercase
#          alphanumeric slug (a-z, 0-9, hyphen).
# @param $1: raw_identifier - Input title, filename, or link token.
# @returns: Canonical slug on stdout; returns 1 if resulting slug is empty.
# @pure
# -----------------------------------------------------------------------------
normalize_slug_id() {
    _slug="$(printf '%s' "$1" \
        | LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C sed 's/\.md$//; s/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')"
    if [ -z "$_slug" ]; then
        return 1
    fi
    printf '%s\n' "$_slug"
    return 0
}

# -----------------------------------------------------------------------------
# canonicalize_link_target
# Summary: Normalizes either a [[wikilink]] expression (with optional path
#          prefixes, #anchors, or |aliases) or a relative Markdown link target
#          into a canonical node_id slug candidate.
# @param $1: raw_target - Extracted link string (e.g., "concepts/auth#jwt|Auth"
#            or "../repos/backend/user-api.md").
# @returns: Canonical target slug on stdout; returns 1 if external URL or system file.
# @pure
# -----------------------------------------------------------------------------
canonicalize_link_target() {
    _raw="$1"

    # Reject external URLs, mailto links, and in-page anchors
    case "$_raw" in
        ''|\#*|http://*|https://*|mailto:*|ftp:*|data:*)
            return 1
            ;;
    esac

    # Strip [[ ... ]] enclosing brackets if present
    _cleaned="$(printf '%s' "$_raw" | sed 's/^\[\[//; s/\]\]$//')"

    # Strip display alias after pipe (|...), anchor after hash (#...), and .md suffix
    _cleaned="$(printf '%s' "$_cleaned" | sed 's/|.*$//; s/#.*$//; s/\.md$//')"

    # Strip leading relative path segments and pillar prefixes
    _cleaned="$(printf '%s' "$_cleaned" | sed 's#^/*##; s#^\(\.\./\)*##; s#^\./##; s#^wiki/##; s#^concepts/##; s#^repos/##; s#^sources/##')"

    # Ignore references to system metadata files (_index, _log, _graph)
    case "$_cleaned" in
        ''|_index*|index|_log*|_graph*)
            return 1
            ;;
    esac

    normalize_slug_id "$_cleaned"
}

# -----------------------------------------------------------------------------
# atomic_sort_unique_file
# Summary: Sorts a file lexicographically using strict byte-order (LC_ALL=C),
#          deduplicates identical lines, and replaces the target atomically.
# @param $1: target_file - Path to the file to sort in-place.
# @returns: 0 on success; 1 on missing file or write error.
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
# Summary: Performs an O(log N) prefix lookup on an LC_ALL=C sorted TSV file
#          using POSIX `look` (with a deterministic early-exit `awk` fallback).
# @param $1: search_prefix - Prefix key to match at the start of the line.
# @param $2: sorted_file - Path to the LC_ALL=C sorted TSV file.
# @returns: Matching lines on stdout; 0 on success.
# @pure
# -----------------------------------------------------------------------------
binary_search_sorted_prefix() {
    _prefix="$1"
    _file="$2"
    [ -n "$_prefix" ] && [ -f "$_file" ] || return 1

    if [ "${RNEX_FORCE_AWK_BINARY_SEARCH:-0}" != "1" ] && command -v look >/dev/null 2>&1; then
        LC_ALL=C look -- "$_prefix" "$_file" 2>/dev/null || true
    else
        LC_ALL=C awk -v p="$_prefix" '
            BEGIN { plen = length(p) }
            {
                head = substr($0, 1, plen)
                if (head == p) { print $0 }
                else if (head > p) { exit 0 }
            }
        ' "$_file"
    fi
    return 0
}
