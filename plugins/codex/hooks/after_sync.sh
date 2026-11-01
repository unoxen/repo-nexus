#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/codex/hooks/after_sync.sh — OpenAI Codex synchronization hook
# ============================================================================
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    # shellcheck source=/dev/null
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

merge_rnex_instructions "$_root/CODEX.md"

if ! provider_option_enabled "codex" "skills" 2>/dev/null; then
  clean_provider_user_skills "$_root/.codex/skills"
fi
