#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# templates/rnex-env.sh — Repo Nexus Plugin & Skill Contract Environment Loader
# Single source of truth resides in lib/sdk.sh (copied to .rnex/bin/rnex-env.sh on sync)
# ============================================================================

export RNEX_ROOT="${RNEX_ROOT:-${NEXUS_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P)}}"

for _rnex_sdk_cand in \
  "${RNEX_LIB_DIR:-}/sdk.sh" \
  "$(dirname "$0")/../lib/sdk.sh" \
  "$RNEX_ROOT/lib/sdk.sh"; do
  if [ -n "$_rnex_sdk_cand" ] && [ -f "$_rnex_sdk_cand" ]; then
    # shellcheck source=/dev/null
    . "$_rnex_sdk_cand"
    break
  fi
done
