#!/bin/sh
# shellcheck shell=sh
# ==============================================================================
# templates/rnex-env.sh — Standalone Repo Nexus Environment Bootstrap
# ==============================================================================
# Exports workspace root and dynamic member repository directories for hooks,
# subshells, and background AI tasks.
# ==============================================================================

RNEX_ROOT="${RNEX_ROOT:-${NEXUS_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P)}}"
export RNEX_ROOT

# Resolve library directory
if [ -z "${RNEX_LIB_DIR:-}" ]; then
  for _lib_cand in "$RNEX_ROOT/lib" "$(dirname "$0")/../lib"; do
    if [ -d "$_lib_cand" ] && [ -f "$_lib_cand/core.sh" ]; then
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
