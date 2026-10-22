#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

mkdir -p "$_root/.github"
merge_rnex_instructions "$_root/.github/copilot-instructions.md"

if ! provider_option_enabled "copilot" "skills" 2>/dev/null; then
  clean_provider_user_skills "$_root/.github/skills"
fi
