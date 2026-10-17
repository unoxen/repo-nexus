#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

if ! command -v clean_rnex_instructions >/dev/null 2>&1; then
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

clean_rnex_instructions "$_root/CLAUDE.md"
clean_provider_user_skills "$_root/.claude/skills"
rm -rf "$_root/.claude/commands" "$_root/.claude/prompts" 2>/dev/null || true
rmdir "$_root/.claude" 2>/dev/null || true
