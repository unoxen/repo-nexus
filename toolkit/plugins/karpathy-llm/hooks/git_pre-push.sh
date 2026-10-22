#!/bin/sh
set -e
for _kl_common in \
  "${RNEX_PLUGIN_DIR:-}/hooks/_common.sh" \
  "$(dirname "$0")/_common.sh" \
  "${RNEX_ROOT:-.}/.rnex/plugins/karpathy-llm/hooks/_common.sh" \
  "${RNEX_ROOT:-.}/toolkit/plugins/karpathy-llm/hooks/_common.sh"; do
  [ -f "$_kl_common" ] && { . "$_kl_common"; break; }
done

if [ "$_trigger" = "git-pre-push" ] || [ "$_trigger" = "pre-push" ]; then
  _has_wiki_changes=0
  _has_input=0
  _z40="0000000000000000000000000000000000000000"

  # 1. Inspect pushed revisions if provided on stdin (standard Git pre-push hook contract)
  if [ ! -t 0 ]; then
    while read -r _local_ref _local_sha _remote_ref _remote_sha; do
      [ -z "$_local_sha" ] && continue
      [ "$_local_sha" = "$_z40" ] && continue
      _has_input=1

      if [ -z "$_remote_sha" ] || [ "$_remote_sha" = "$_z40" ]; then
        if git -C "$_root" diff-tree -r --name-only --root "$_local_sha" 2>/dev/null | grep -qE "(^|/)($_raw|$_wiki)/"; then
          _has_wiki_changes=1
          break
        fi
      else
        if git -C "$_root" diff-tree -r --name-only "$_remote_sha" "$_local_sha" 2>/dev/null | grep -qE "(^|/)($_raw|$_wiki)/"; then
          _has_wiki_changes=1
          break
        fi
      fi
    done
  fi

  # 2. Fallback when invoked without piped stdin (e.g. CLI direct execution or test runners)
  if [ "$_has_input" -eq 0 ]; then
    if [ -n "${1:-}" ] && [ -n "${2:-}" ] && git -C "$_root" cat-file -e "${1:-}" 2>/dev/null && git -C "$_root" cat-file -e "${2:-}" 2>/dev/null; then
      if git -C "$_root" diff-tree -r --name-only "$1" "$2" 2>/dev/null | grep -qE "(^|/)($_raw|$_wiki)/"; then
        _has_wiki_changes=1
      fi
    elif git -C "$_root" rev-parse --verify HEAD >/dev/null 2>&1; then
      if git -C "$_root" diff-tree -r --name-only --root HEAD 2>/dev/null | grep -qE "(^|/)($_raw|$_wiki)/"; then
        _has_wiki_changes=1
      fi
    elif git -C "$_root" status --porcelain 2>/dev/null | grep -qE "(^[A-Z? ]+[ ]+|/)($_raw|$_wiki)/"; then
      _has_wiki_changes=1
    fi
  fi

  if [ "$_has_wiki_changes" -eq 1 ] && [ "$_notify" != "false" ]; then
    if [ ! -f "$_wiki_path/index.md" ] || [ ! -f "$_wiki_path/hot.md" ]; then
      printf '[WIKI] Warning: Required wiki files (index.md or hot.md) missing in %s/.\n' "$_wiki"
    fi
    printf '[WIKI] Reminder: Wiki files changed. Run the rnex-karpathy-llm-wiki-lint skill to verify.\n'
  fi
fi
