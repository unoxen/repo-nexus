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

if [ "$_trigger" = "git-post-commit" ] || [ "$_trigger" = "post-commit" ]; then
  if git -C "$_root" diff-tree -r --name-only --root HEAD 2>/dev/null | grep -qE "(^|/)($_raw|$_wiki)/"; then
    if [ "$_notify" != "false" ]; then
      printf '[WIKI] Changes committed to %s/ or %s/. Run wiki-lint or wiki-ingest as needed.\n' "$_raw" "$_wiki"
    fi
  fi
fi
