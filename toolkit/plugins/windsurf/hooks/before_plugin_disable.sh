#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v clean_rnex_instructions >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

clean_rnex_instructions "$_root/.windsurfrules"
clean_provider_user_skills "$_root/.windsurf/rules"
rm -rf "$_root/.windsurf/prompts" 2>/dev/null || true
rmdir "$_root/.windsurf/rules" 2>/dev/null || true
rmdir "$_root/.windsurf" 2>/dev/null || true
