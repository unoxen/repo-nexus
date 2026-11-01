#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/gemini/hooks/before_plugin_disable.sh — Gemini cleanup hook
# ============================================================================
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v clean_provider_user_skills >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    # shellcheck source=/dev/null
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

clean_provider_ignore "$_root/.geminiignore"
clean_rnex_instructions "$_root/GEMINI.md"
clean_provider_user_skills "$_root/.agents/skills"
clean_provider_user_skills "$_root/.gemini/skills"
clean_agents_auto_sync_hook "$_root/.agents/hooks.json"
rm -rf "$_root/.gemini/prompts" 2>/dev/null || true
rmdir "$_root/.gemini" 2>/dev/null || true
rmdir "$_root/.agents" 2>/dev/null || true
