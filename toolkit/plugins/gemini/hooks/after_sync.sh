#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

_gi="$_root/.geminiignore"
if [ ! -f "$_gi" ]; then
  cat > "$_gi" <<GI_EOF
# Gemini CLI file discovery un-ignore for member repos
!repos/*
GI_EOF
  [ "${RNEX_QUIET:-0}" -eq 0 ] && log_ok "Created .geminiignore (enabling Gemini CLI file discovery for member repos)"
elif ! grep -q '!repos/\*' "$_gi" 2>/dev/null; then
  printf '\n# Gemini CLI file discovery un-ignore for member repos\n!repos/*\n' >> "$_gi"
  [ "${RNEX_QUIET:-0}" -eq 0 ] && log_dim "Added !repos/* to .geminiignore"
fi

_inst="$(provider_option_enabled "gemini" "instructions" 2>/dev/null && echo "true" || echo "false")"
if [ "$_inst" = "true" ]; then
  merge_rnex_instructions "$_root/GEMINI.md"
else
  clean_rnex_instructions "$_root/GEMINI.md"
fi

_sk="$(provider_option_enabled "gemini" "skills" 2>/dev/null && echo "true" || echo "false")"
if [ "$_sk" != "true" ]; then
  clean_provider_user_skills "$_root/.agents/skills"
fi

# Clean legacy .gemini/skills if it exists
if [ -d "$_root/.gemini/skills" ]; then
  clean_provider_user_skills "$_root/.gemini/skills"
  rmdir "$_root/.gemini/skills" 2>/dev/null || true
  rmdir "$_root/.gemini" 2>/dev/null || true
fi
