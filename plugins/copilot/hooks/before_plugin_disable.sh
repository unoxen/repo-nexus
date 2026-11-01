#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/copilot/hooks/before_plugin_disable.sh — Copilot cleanup hook
# ============================================================================
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v clean_provider_user_skills >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    # shellcheck source=/dev/null
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

clean_provider_user_skills "$_root/.github/skills"
clean_provider_agents "$_root/.github/agents" ".agent.md"
clean_rnex_instructions "$_root/.github/copilot-instructions.md"

if [ -d "$_root/.github/prompts" ]; then
  rm -f "$_root/.github/prompts"/rnex-*.prompt.md "$_root/.github/prompts"/rnex-*.md 2>/dev/null || true
  for _p in "$_root/.github/prompts"/rnex-*; do
    [ -e "$_p" ] || continue
    rm -rf "$_p" 2>/dev/null || true
  done
  rmdir "$_root/.github/prompts" 2>/dev/null || true
fi
rmdir "$_root/.github" 2>/dev/null || true
