#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/karpathy-llm/hooks/before_plugin_disable.sh — Wiki skill cleanup
# ============================================================================
set -e
[ -z "$RNEX_ROOT" ] && { echo "Error: RNEX_ROOT not set"; exit 1; }

if ! command -v rnex_unregister_user_skill >/dev/null 2>&1; then
  for _env_cand in "$RNEX_ROOT/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$RNEX_ROOT/lib/sdk.sh"; do
    # shellcheck source=/dev/null
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

if command -v rnex_unregister_user_skill >/dev/null 2>&1; then
  rnex_unregister_user_skill "wiki-ingest" "karpathy-llm"
  rnex_unregister_user_skill "wiki-lint" "karpathy-llm"
  rnex_unregister_user_skill "wiki-ingest"
  rnex_unregister_user_skill "wiki-lint"
fi
