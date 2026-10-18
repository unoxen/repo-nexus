#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

if ! command -v clean_rnex_instructions >/dev/null 2>&1; then
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

clean_provider_ignore "$_root/.geminiignore"
clean_rnex_instructions "$_root/GEMINI.md"
clean_provider_user_skills "$_root/.agents/skills"
clean_provider_user_skills "$_root/.gemini/skills"
rm -rf "$_root/.gemini/prompts" 2>/dev/null || true
rmdir "$_root/.gemini" 2>/dev/null || true
rmdir "$_root/.agents" 2>/dev/null || true
