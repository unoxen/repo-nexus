#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/core.sh — Terminal colors, logging, path, and version utilities
# ============================================================================

# ---- Terminal Colours (auto-detected) -------------------------------------
# ANSI color codes enabled only when stdout is an interactive terminal (TTY)
if [ -t 1 ]; then
  _R='\033[0;31m' _G='\033[0;32m' _Y='\033[1;33m' _B='\033[0;34m' _C='\033[0;36m'
  _BOLD='\033[1m' _DIM='\033[2m' _NC='\033[0m'
else
  _R='' _G='' _Y='' _B='' _C='' _BOLD='' _DIM='' _NC=''
fi

# ---- Logging Utilities ----------------------------------------------------
# Standardized CLI messages with symbol prefixes, respecting quiet flags.

# Print green success checkmark [✓]
log_ok()   { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '%b[✓]%b %b\n' "$_G" "$_NC" "$1"; }

# Print yellow warning indicator [!]
log_warn() { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '%b[!]%b %b\n' "$_Y" "$_NC" "$1"; }

# Print red failure cross [✗] to stderr
log_err()  { printf '%b[✗]%b %b\n' "$_R" "$_NC" "$1" >&2; }

# Print cyan information notice [i]
log_info() { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '%b[i]%b %b\n' "$_C" "$_NC" "$1"; }

# Print dimmed indented detail text
log_dim()  { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '%b    %b%b\n' "$_DIM" "$1" "$_NC"; }

# Log fatal error message to stderr and terminate with non-zero exit code
die()      { log_err "$1"; exit 1; }

# ---- Path Utilities --------------------------------------------------------

# Canonicalize any relative, absolute, or tilde-prefixed path into an absolute physical path.
# Preserves non-existent destination targets while resolving parent directories.
resolve_path() {
  _input="$1"
  # Expand tilde (~ or ~/path) to user HOME directory
  case "$_input" in
    \~/*) _input="$HOME/${_input#\~/}" ;;
    \~)   _input="$HOME" ;;
  esac

  # Canonicalize absolute or relative paths
  case "$_input" in
    /*)
      if [ -d "$_input" ]; then
        (cd "$_input" 2>/dev/null && pwd -P)
      elif [ -d "$(dirname "$_input")" ]; then
        printf '%s/%s' "$(cd "$(dirname "$_input")" 2>/dev/null && pwd -P)" "$(basename "$_input")"
      else
        printf '%s' "$_input"
      fi
      ;;
    *)
      if [ -d "$_input" ]; then
        (cd "$_input" 2>/dev/null && pwd -P)
      elif [ -d "$(dirname "$_input")" ]; then
        printf '%s/%s' "$(cd "$(dirname "$_input")" 2>/dev/null && pwd -P)" "$(basename "$_input")"
      else
        printf '%s/%s' "$PWD" "$_input"
      fi
      ;;
  esac
}

# Determine if a configuration value is enabled.
# Returns 0 (true) by default unless explicitly set to a falsy value (false, no, 0, disabled, off, none).
is_enabled_val() {
  _iev="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$_iev" in
    false|no|0|disabled|off|none) return 1 ;;
    *) return 0 ;;
  esac
}

# Strict check for truthy values.
# Returns 0 (true) only if explicitly true, yes, 1, on, or enabled; otherwise returns 1.
is_truthy() {
  _it="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$_it" in
    true|yes|1|on|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

# Normalize a relative path string by stripping surrounding whitespace, quotes,
# leading ./ or /, and trailing slashes.
normalize_rel_path() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##'
}


# ---- Version Resolution (package.json is single source of truth) ----------

# Dynamically locate the nearest package.json and extract its "version" field.
# Falls back to 0.5.1 if package.json cannot be read.
resolve_version() {
  _sdir="$(dirname "$SCRIPT_LOCATION")"
  for _cand in "$SCRIPT_LOCATION/package.json" "$_sdir/package.json" "$_sdir/../package.json"; do
    if [ -f "$_cand" ]; then
      _v="$(awk '/"version"[ ]*:/ { sub(/.*"version"[ ]*:[ ]*"/, ""); sub(/".*/, ""); print; exit }' "$_cand")"
      if [ -n "$_v" ]; then
        printf '%s' "$_v"
        return 0
      fi
    fi
  done
  printf '0.5.1'
}

RNEX_VERSION="$(resolve_version)"

# Compare two dot-separated version strings (e.g., "0.7.38" vs "0.7.39").
# Returns:
#   0 if $1 == $2
#   1 if $1 > $2
#   2 if $1 < $2
version_cmp() {
  [ "$1" = "$2" ] && return 0
  _v1="$1"
  _v2="$2"
  while [ -n "$_v1" ] || [ -n "$_v2" ]; do
    case "$_v1" in
      *.*) _p1="${_v1%%.*}"; _v1="${_v1#*.}" ;;
      *)   _p1="$_v1"; _v1="" ;;
    esac
    case "$_v2" in
      *.*) _p2="${_v2%%.*}"; _v2="${_v2#*.}" ;;
      *)   _p2="$_v2"; _v2="" ;;
    esac
    _p1="${_p1:-0}"
    _p2="${_p2:-0}"
    if [ "$_p1" -gt "$_p2" ] 2>/dev/null; then
      return 1
    elif [ "$_p1" -lt "$_p2" ] 2>/dev/null; then
      return 2
    fi
  done
  return 0
}
