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
# @param $1 Raw path string.
# @returns Canonical absolute path on stdout.
# @pure
resolve_path() {
  _input="$1"
  # Expand tilde (~ or ~/path) to user HOME directory
  case "$_input" in
    \~/*) _input="$HOME/${_input#\~/}" ;;
    \~)   _input="$HOME" ;;
  esac

  if [ -d "$_input" ]; then
    (cd "$_input" 2>/dev/null && pwd -P)
  elif [ -d "$(dirname "$_input")" ]; then
    printf '%s/%s' "$(cd "$(dirname "$_input")" 2>/dev/null && pwd -P)" "$(basename "$_input")"
  else
    case "$_input" in
      /*) printf '%s' "$_input" ;;
      *)  printf '%s/%s' "$PWD" "$_input" ;;
    esac
  fi
}

# Strip trailing slashes from a path while preserving root '/'.
# @param $1 Path string.
# @returns Path without trailing slashes on stdout.
# @pure
strip_trailing_slashes() {
  _sts="$1"
  while [ "$_sts" != "${_sts%/}" ] && [ -n "${_sts%/}" ]; do
    _sts="${_sts%/}"
  done
  printf '%s' "$_sts"
}

# Strip leading './' prefixes and trailing slashes from a relative subpath.
# @param $1 Relative path string.
# @returns Cleaned relative path on stdout.
# @pure
clean_rel_subpath() {
  _crs="$1"
  while [ "${_crs#./}" != "$_crs" ]; do
    _crs="${_crs#./}"
  done
  strip_trailing_slashes "$_crs"
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

# Dynamically locate the nearest package.json and extract its top-level semver "version" field.
# Anchored to semver digits so script keys (e.g. "version": "./scripts/...") are never matched.
# Falls back to 0.10.4 if package.json cannot be read.
resolve_version() {
  _sdir="$(dirname "$SCRIPT_LOCATION")"
  for _cand in "$SCRIPT_LOCATION/package.json" "$_sdir/package.json" "$_sdir/../package.json"; do
    if [ -f "$_cand" ]; then
      _v="$(awk '/^[ \t]*"version"[ \t]*:[ \t]*"[0-9]/ { sub(/.*"version"[ \t]*:[ \t]*"/, ""); sub(/".*/, ""); print; exit }' "$_cand")"
      if [ -n "$_v" ]; then
        printf '%s' "$_v"
        return 0
      fi
    fi
  done
  printf '0.10.4'
}

RNEX_VERSION="$(resolve_version)"

# Shared directory locator for built-in Repo Nexus asset directories (plugins, skills).
# @param $1 Subdirectory name ("plugins" or "skills").
# @param $2 Primary explicit override path (e.g. $RNEX_PLUGINS_DIR).
# @param $3 Secondary explicit override path (e.g. $PLUGINS_DIR).
# @returns Resolved directory path on stdout; returns 0 if found, 1 otherwise.
# @pure
_find_asset_dir() {
  _fad_sub="$1"
  _fad_ovr1="${2:-}"
  _fad_ovr2="${3:-}"
  if [ -n "$_fad_ovr1" ] && [ -d "$_fad_ovr1" ]; then
    printf '%s' "$_fad_ovr1"
    return 0
  fi
  if [ -n "$_fad_ovr2" ] && [ -d "$_fad_ovr2" ]; then
    printf '%s' "$_fad_ovr2"
    return 0
  fi
  _sdir="$(dirname "$SCRIPT_LOCATION")"
  for _cand in \
    "${RNEX_ROOT:+$RNEX_ROOT/$_fad_sub}" \
    "$SCRIPT_LOCATION/$_fad_sub" \
    "$_sdir/$_fad_sub" \
    "$_sdir/../$_fad_sub" \
    "${NEXUS_DIR:+$NEXUS_DIR/$_fad_sub}"; do
    if [ -n "$_cand" ] && [ -d "$_cand" ]; then
      printf '%s' "$_cand"
      return 0
    fi
  done
  return 1
}

# Locate the built-in plugins directory containing embedded plugins.
find_plugins_root() {
  _find_asset_dir "plugins" "${RNEX_PLUGINS_DIR:-}" "${PLUGINS_DIR:-}"
}

# Locate the built-in skills directory containing core agentic skills.
find_skills_dir() {
  _find_asset_dir "skills" "${RNEX_SKILLS_DIR:-}" "${SKILLS_DIR:-}"
}

RNEX_PLUGINS_DIR="${RNEX_PLUGINS_DIR:-$(find_plugins_root 2>/dev/null || true)}"
PLUGINS_DIR="${PLUGINS_DIR:-$RNEX_PLUGINS_DIR}"
RNEX_SKILLS_DIR="${RNEX_SKILLS_DIR:-$(find_skills_dir 2>/dev/null || true)}"
SKILLS_DIR="${SKILLS_DIR:-$RNEX_SKILLS_DIR}"

# ==============================================================================
# AI Context Compilation File Contracts
# Architectural Layer: Core Configuration Constants
# Responsibility: Single source of truth for compiled AI instruction filenames.
# ==============================================================================
RNEX_AI_INSTRUCTIONS_RELPATH=".rnex/ai-instructions.md"
RNEX_REPOS_INSTRUCTIONS_RELPATH=".rnex/repos-instructions.md"
RNEX_PLUGIN_AI_FILENAME="ai-instructions.md"

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
