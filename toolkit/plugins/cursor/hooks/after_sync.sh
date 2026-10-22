#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

ensure_provider_ignore "$_root/.cursorignore" \
  "Cursor codebase indexing un-ignore for member repos" \
  "Created .cursorignore (enabling Cursor indexing for member repos)"

merge_rnex_instructions "$_root/.cursorrules"
mkdir -p "$_root/.cursor/rules"
{
  printf -- '---\ndescription: Repo Nexus Virtual Meta-Repo routing protocol\nglobs: *\nalwaysApply: true\n---\n\n%s\n' "${AI_MARKER_START:-<!-- REPO-NEXUS:START -->}"
  get_rnex_instructions
  printf '\n%s\n' "${AI_MARKER_END:-<!-- REPO-NEXUS:END -->}"
} > "$_root/.cursor/rules/rnex-context.mdc"
rm -f "$_root/.cursor/rules/repo-nexus.mdc" 2>/dev/null || true

if ! provider_option_enabled "cursor" "skills" 2>/dev/null; then
  clean_provider_user_skills "$_root/.cursor/rules"
fi
