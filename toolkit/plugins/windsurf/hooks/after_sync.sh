#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

# Instructions management (always maintained when windsurf plugin is enabled)
merge_rnex_instructions "$_root/.windsurfrules"

_sk="$(provider_option_enabled "windsurf" "skills" 2>/dev/null && echo "true" || echo "false")"
if [ "$_sk" != "true" ]; then
  clean_provider_user_skills "$_root/.windsurf/rules"
fi
