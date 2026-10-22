#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v clean_rnex_instructions >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

clean_provider_ignore "$_root/.cursorignore"
clean_rnex_instructions "$_root/.cursorrules"
rm -f "$_root/.cursor/rules/rnex-context.mdc" "$_root/.cursor/rules/repo-nexus.mdc" 2>/dev/null || true
clean_provider_user_skills "$_root/.cursor/rules"
rm -rf "$_root/.cursor/prompts" 2>/dev/null || true
rmdir "$_root/.cursor/rules" 2>/dev/null || true
rmdir "$_root/.cursor" 2>/dev/null || true
