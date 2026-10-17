#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

if ! command -v clean_rnex_instructions >/dev/null 2>&1; then
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

clean_rnex_instructions "$_root/.github/copilot-instructions.md"
clean_provider_user_skills "$_root/.github/skills"
clean_provider_agents "$_root/.github/agents" ".agent.md"
rm -rf "$_root/.github/prompts" 2>/dev/null || true
rmdir "$_root/.github" 2>/dev/null || true
