#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# File: plugins/cursor/hooks/after_sync.sh
# Architectural Layer: Plugin Lifecycle Hook (after_sync)
# Single Responsibility: Reconcile Cursor IDE rules, ignore file, skills, and hooks.
# ============================================================================
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
if ! command -v rnex_sdk_sync_provider >/dev/null 2>&1; then
  for _env_cand in "$_root/.rnex/bin/rnex-env.sh" "$_root/.rnex/rnex-env.sh" "${RNEX_LIB_DIR:-}/sdk.sh" "$_root/lib/sdk.sh"; do
    # shellcheck source=/dev/null
    [ -n "$_env_cand" ] && [ -f "$_env_cand" ] && { . "$_env_cand"; break; }
  done
fi

mkdir -p "$_root/.cursor/rules"
{
  printf -- '---\ndescription: Repo Nexus Virtual Meta-Repo routing protocol\nglobs: *\nalwaysApply: true\n---\n\n%s\n' "${AI_MARKER_START:-<!-- REPO-NEXUS:START -->}"
  get_rnex_instructions
  printf '%s\n' "${AI_MARKER_END:-<!-- REPO-NEXUS:END -->}"
} > "$_root/.cursor/rules/rnex-context.mdc"

rnex_sdk_sync_provider "$_root" "cursor"
