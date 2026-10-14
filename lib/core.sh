#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/core.sh — Terminal colors, logging, path, and version utilities
# ============================================================================

# ---- Terminal Colours (auto-detected) -------------------------------------

if [ -t 1 ]; then
  _R='\033[0;31m' _G='\033[0;32m' _Y='\033[1;33m' _B='\033[0;34m' _C='\033[0;36m'
  _BOLD='\033[1m' _DIM='\033[2m' _NC='\033[0m'
else
  _R='' _G='' _Y='' _B='' _C='' _BOLD='' _DIM='' _NC=''
fi

# ---- Logging ---------------------------------------------------------------

log_ok()   { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '%b[✓]%b %b\n' "$_G" "$_NC" "$1"; }
log_warn() { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '%b[!]%b %b\n' "$_Y" "$_NC" "$1"; }
log_err()  { printf '%b[✗]%b %b\n' "$_R" "$_NC" "$1" >&2; }
log_info() { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '%b[i]%b %b\n' "$_C" "$_NC" "$1"; }
log_dim()  { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '%b    %b%b\n' "$_DIM" "$1" "$_NC"; }
die()      { log_err "$1"; exit 1; }

# ---- Path Utilities --------------------------------------------------------

resolve_path() {
  _input="$1"
  case "$_input" in
    \~/*) _input="$HOME/${_input#\~/}" ;;
    \~)   _input="$HOME" ;;
  esac
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

# Resolve location of this script (follows symlinks)
resolve_script_path() {
  _source="$1"
  while [ -L "$_source" ]; do
    _dir="$(cd "$(dirname "$_source")" 2>/dev/null && pwd -P)"
    _source="$(readlink "$_source")"
    case "$_source" in
      /*) ;;
      *)  _source="$_dir/$_source" ;;
    esac
  done
  cd "$(dirname "$_source")" 2>/dev/null && pwd -P
}

# ---- Version Resolution (package.json is single source of truth) ----------

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

# Compare version strings: returns 0 if $1 == $2, 1 if $1 > $2, 2 if $1 < $2
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
