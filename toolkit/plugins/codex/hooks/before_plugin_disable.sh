#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/codex/hooks/before_plugin_disable.sh — OpenAI Codex cleanup hook
# ============================================================================
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v clean_provider_user_skills >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    # shellcheck source=/dev/null
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

clean_provider_user_skills "$_root/.codex/skills"
clean_provider_agents "$_root/.codex/agents" ".agent.md"
clean_rnex_instructions "$_root/CODEX.md"
rmdir "$_root/.codex" 2>/dev/null || true
