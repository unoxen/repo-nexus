#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/utils.sh
# Architectural Layer: Pure General Utilities (utils/ — Zero Domain Dependencies)
# Single Responsibility: Pure string slugification, Markdown line sanitization,
# and ISO-8601 UTC date formatting.
# Purity: Strictly pure (@pure) with zero domain or external dependencies.
# Standards: POSIX Shell (/bin/sh), OWASP A03 Input Sanitization.
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
# sanitize_single_line_text
# Summary: Strips tabs, carriage returns, and newlines from a string and collapses
#          consecutive whitespace into a single space, trimming edges.
# @param $1: raw_text - Unsanitized input text.
# @returns: Single-line, whitespace-collapsed string on stdout.
# @pure
# -----------------------------------------------------------------------------
sanitize_single_line_text() {
    printf '%s' "$1" | tr '\t\r\n' '   ' | sed 's/  */ /g; s/^ //; s/ $//'
}

# -----------------------------------------------------------------------------
# normalize_slug_id
# Summary: Converts an arbitrary string or file stem into a canonical lowercase
#          alphanumeric slug (a-z, 0-9, hyphen) stripping extensions.
# @param $1: raw_identifier - Input title, filename, or link token.
# @returns: Canonical slug on stdout; returns 1 if resulting slug is empty.
# @pure
# -----------------------------------------------------------------------------
normalize_slug_id() {
    _slug="$(printf '%s' "$1" \
        | LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C sed 's/\.[^.]*$//; s/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')"
    if [ -z "$_slug" ]; then
        return 1
    fi
    printf '%s\n' "$_slug"
    return 0
}
