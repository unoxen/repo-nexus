#!/bin/sh
set -e
for _kl_common in \
  "${RNEX_PLUGIN_DIR:-}/hooks/_common.sh" \
  "$(dirname "$0")/_common.sh" \
  "${RNEX_ROOT:-.}/.rnex/plugins/karpathy-llm/hooks/_common.sh" \
  "${RNEX_ROOT:-.}/toolkit/plugins/karpathy-llm/hooks/_common.sh"; do
  [ -f "$_kl_common" ] && { . "$_kl_common"; break; }
done

if [ "$_trigger" = "git-post-merge" ] || [ "$_trigger" = "post-merge" ]; then
  if git -C "$_root" diff-tree -r --name-only ORIG_HEAD HEAD 2>/dev/null | grep -qE "(^|/)($_raw|$_wiki)/"; then
    if [ "$_notify" != "false" ]; then
      printf '[WIKI] Incoming merge modified %s/ or %s/. Run wiki-lint or wiki-ingest as needed.\n' "$_raw" "$_wiki"
    fi
  fi
fi
