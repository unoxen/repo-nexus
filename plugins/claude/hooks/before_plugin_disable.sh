#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/claude/hooks/before_plugin_disable.sh — Claude Code cleanup hook
# ============================================================================
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v clean_provider_user_skills >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    # shellcheck source=/dev/null
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

clean_provider_user_skills "$_root/.claude/skills"
clean_claude_auto_sync_hook "$_root/.claude/settings.json"
clean_rnex_instructions "$_root/CLAUDE.md"
rm -rf "$_root/.claude/commands" "$_root/.claude/prompts" 2>/dev/null || true
rmdir "$_root/.claude" 2>/dev/null || true
