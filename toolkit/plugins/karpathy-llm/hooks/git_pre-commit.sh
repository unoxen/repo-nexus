#!/bin/sh
# shellcheck shell=sh disable=SC2154
set -e
for _kl_common in \
  "${RNEX_PLUGIN_DIR:-}/hooks/_common.sh" \
  "$(dirname "$0")/_common.sh" \
  "${RNEX_ROOT:-.}/.rnex/plugins/karpathy-llm/hooks/_common.sh" \
  "${RNEX_ROOT:-.}/toolkit/plugins/karpathy-llm/hooks/_common.sh"; do
  [ -f "$_kl_common" ] && { . "$_kl_common"; break; }
done

if [ "$_trigger" = "git-pre-commit" ] || [ "$_trigger" = "pre-commit" ]; then
  if git -C "$_root" diff --cached --name-only 2>/dev/null | grep -qE "(^|/)($_raw|$_wiki)/"; then
    if [ "$_notify" != "false" ]; then
      printf '[WIKI] Pre-commit verification: pending changes in %s/ or %s/.\n' "$_raw" "$_wiki"
    fi
  fi
fi
