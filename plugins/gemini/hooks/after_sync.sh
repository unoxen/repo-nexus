#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# File: plugins/gemini/hooks/after_sync.sh
# Architectural Layer: Plugin Lifecycle Hook (after_sync)
# Single Responsibility: Reconcile Google Gemini / Antigravity instruction file,
# ignore file, skills, and hooks.
# ============================================================================
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v rnex_sdk_sync_provider >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "$_root/.rnex/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    # shellcheck source=/dev/null
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

rnex_sdk_sync_provider "$_root" "gemini"
