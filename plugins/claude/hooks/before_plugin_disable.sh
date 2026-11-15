#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# File: plugins/claude/hooks/before_plugin_disable.sh
# Architectural Layer: Plugin Lifecycle Hook (before_plugin_disable)
# Single Responsibility: Clean up managed Claude Code artifacts on disable.
# ============================================================================
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v rnex_sdk_disable_provider >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "$_root/.rnex/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    # shellcheck source=/dev/null
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

rnex_sdk_disable_provider "$_root" "claude"
