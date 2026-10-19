#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

_ci="$_root/.cursorignore"
if [ ! -f "$_ci" ]; then
  cat > "$_ci" <<CI_EOF
# Cursor codebase indexing un-ignore for member repos
!repos/*
CI_EOF
  [ "${RNEX_QUIET:-0}" -eq 0 ] && log_ok "Created .cursorignore (enabling Cursor indexing for member repos)"
elif ! grep -q '!repos/\*' "$_ci" 2>/dev/null; then
  printf '\n# Cursor codebase indexing un-ignore for member repos\n!repos/*\n' >> "$_ci"
  [ "${RNEX_QUIET:-0}" -eq 0 ] && log_dim "Added !repos/* to .cursorignore"
fi

# Instructions management (always maintained when cursor plugin is enabled)
merge_rnex_instructions "$_root/.cursorrules"
mkdir -p "$_root/.cursor/rules"
_c_body="$(mktemp)"
get_rnex_instructions > "$_c_body"
{
  printf -- '---\ndescription: Repo Nexus Virtual Meta-Repo routing protocol\nglobs: *\nalwaysApply: true\n---\n\n%s\n' "${AI_MARKER_START:-<!-- REPO-NEXUS:START -->}"
  cat "$_c_body"
  printf '\n%s\n' "${AI_MARKER_END:-<!-- REPO-NEXUS:END -->}"
} > "$_root/.cursor/rules/rnex-context.mdc"
rm -f "$_c_body"
rm -f "$_root/.cursor/rules/repo-nexus.mdc" 2>/dev/null || true

_sk="$(provider_option_enabled "cursor" "skills" 2>/dev/null && echo "true" || echo "false")"
if [ "$_sk" != "true" ]; then
  clean_provider_user_skills "$_root/.cursor/rules"
fi
