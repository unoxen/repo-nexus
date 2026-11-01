#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/gemini/hooks/after_sync.sh — Gemini / Antigravity sync hook
# ============================================================================
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    # shellcheck source=/dev/null
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

ensure_provider_ignore "$_root/.geminiignore" \
  "Gemini CLI file discovery un-ignore for member repos" \
  "Created .geminiignore (enabling Gemini CLI file discovery for member repos)"

merge_rnex_instructions "$_root/GEMINI.md"

if ! provider_option_enabled "gemini" "skills" 2>/dev/null; then
  clean_provider_user_skills "$_root/.agents/skills"
fi

if provider_auto_sync_enabled "gemini"; then
  sync_agents_auto_sync_hook "$_root/.agents/hooks.json"
else
  clean_agents_auto_sync_hook "$_root/.agents/hooks.json"
fi

if [ -d "$_root/.gemini/skills" ]; then
  clean_provider_user_skills "$_root/.gemini/skills"
  rmdir "$_root/.gemini/skills" 2>/dev/null || true
  rmdir "$_root/.gemini" 2>/dev/null || true
fi
