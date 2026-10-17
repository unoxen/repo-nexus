#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

_inst="$(provider_option_enabled "copilot" "instructions" 2>/dev/null && echo "true" || echo "false")"
if [ "$_inst" = "true" ]; then
  mkdir -p "$_root/.github"
  merge_rnex_instructions "$_root/.github/copilot-instructions.md"
else
  clean_rnex_instructions "$_root/.github/copilot-instructions.md"
fi

_sk="$(provider_option_enabled "copilot" "skills" 2>/dev/null && echo "true" || echo "false")"
if [ "$_sk" != "true" ]; then
  clean_provider_user_skills "$_root/.github/skills"
fi
