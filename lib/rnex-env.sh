#!/bin/sh
# shellcheck shell=sh
# ==============================================================================
# lib/rnex-env.sh — Standalone Repo Nexus Environment Bootstrap
# ==============================================================================
# Architectural Layer: Runtime Environment Contract / Subshell SDK Bootstrap
# Design Pattern: Strategy / Service Locator / Bootstrap Contract
# Single Responsibility:
#   Exports workspace root and dynamic member repository directories for hooks,
#   subshells, and background AI tasks, and locates and sources core SDK helpers.
# ==============================================================================

RNEX_ROOT="${RNEX_ROOT:-${NEXUS_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P)}}"
export RNEX_ROOT

# Resolve library directory
if [ -z "${RNEX_LIB_DIR:-}" ]; then
  _rnex_bin_cand=""
  if command -v rnex >/dev/null 2>&1; then
    _rnex_bin_cand="$(dirname "$(command -v rnex)")"
  fi
  for _lib_cand in \
    "$RNEX_ROOT/lib" \
    "$(dirname "$0")/../lib" \
    "$(dirname "$0")/../../lib" \
    "$(dirname "$0")/../../../lib" \
    "$(dirname "$0")/../../../../lib" \
    "${RNEX_INSTALL_DIR:-}/lib" \
    "${_rnex_bin_cand:+$_rnex_bin_cand/lib}" \
    "${_rnex_bin_cand:+$_rnex_bin_cand/../lib}" \
    "${_rnex_bin_cand:+$_rnex_bin_cand/../share/repo-nexus/lib}" \
    "$HOME/.local/share/repo-nexus/lib"; do
    if [ -n "$_lib_cand" ] && [ -d "$_lib_cand" ] && [ -f "$_lib_cand/core.sh" ]; then
      RNEX_LIB_DIR="$(cd "$_lib_cand" 2>/dev/null && pwd -P)"
      break
    fi
  done
fi

if [ -n "${RNEX_LIB_DIR:-}" ] && [ -f "$RNEX_LIB_DIR/core.sh" ]; then
  # shellcheck source=/dev/null
  . "$RNEX_LIB_DIR/core.sh" 2>/dev/null || true
  # shellcheck source=/dev/null
  [ -f "$RNEX_LIB_DIR/yaml.sh" ] && . "$RNEX_LIB_DIR/yaml.sh" 2>/dev/null || true
fi

# Dynamically export RNEX_REPOS_DIR and REPOS_DIR
if command -v yaml_get_repos_dir >/dev/null 2>&1; then
  RNEX_REPOS_DIR="$(yaml_get_repos_dir 2>/dev/null || printf 'repos')"
else
  RNEX_REPOS_DIR="${REPOS_DIR_REL:-repos}"
fi
[ -n "$RNEX_REPOS_DIR" ] || RNEX_REPOS_DIR="repos"
export RNEX_REPOS_DIR

REPOS_DIR="${REPOS_DIR:-$RNEX_ROOT/$RNEX_REPOS_DIR}"
export REPOS_DIR

# Source SDK helpers if present
if [ -n "${RNEX_LIB_DIR:-}" ] && [ -f "$RNEX_LIB_DIR/sdk.sh" ]; then
  # shellcheck source=/dev/null
  . "$RNEX_LIB_DIR/sdk.sh" 2>/dev/null || true
fi
