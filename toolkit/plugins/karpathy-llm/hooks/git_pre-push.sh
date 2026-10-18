#!/bin/sh
set -e
_root="${RNEX_ROOT:-$PWD}"
get_cfg() {
  _key="$1"; _def="$2"
  _val=""
  for _cfg in "$_root/.local.rnex.yaml" "$_root/rnex.yaml"; do
    [ -f "$_cfg" ] || continue
    _val="$(awk -v plugin="karpathy-llm" -v key="$_key" '
      /^[ \t]*plugins:[ \t]*(#.*)?$/ { in_plugins=1; in_target=0; plugin_indent=-1; next }
      in_plugins && /^[^ \t#]/ { in_plugins=0; in_target=0 }
      !in_plugins { next }
      {
        match($0, /^[ \t]*/)
        indent = RLENGTH
        trimmed = substr($0, indent + 1)
      }
      trimmed ~ /^([#]|$)/ { next }

      in_target && (indent <= plugin_indent) {
        in_target=0
      }

      !in_target {
        k = trimmed
        sub(/:.*/, "", k)
        gsub(/^["\047]|["\047]$/, "", k)
        gsub(/[[:space:]]/, "", k)
        if (k == plugin && trimmed ~ /:[ \t]*(#.*)?$/) {
          in_target=1
          plugin_indent=indent
          next
        }
      }

      in_target && (indent > plugin_indent) {
        k = trimmed
        sub(/:.*/, "", k)
        gsub(/^["\047]|["\047]$/, "", k)
        gsub(/[[:space:]]/, "", k)
        if (k == key && trimmed ~ /:[ \t]*/) {
          val = trimmed
          sub(/^[^:]*:[ \t]*/, "", val)
          if (val ~ /^"[^"]*"/) {
            match(val, /^"[^"]*"/)
            val = substr(val, 2, RLENGTH - 2)
          } else if (val ~ /^\047[^\047]*\047/) {
            match(val, /^\047[^\047]*\047/)
            val = substr(val, 2, RLENGTH - 2)
          } else {
            sub(/[ \t]*#.*$/, "", val)
            sub(/[ \t]+$/, "", val)
          }
          print val
          exit
        }
      }
    ' "$_cfg")"
    [ -n "$_val" ] && break
  done
  [ -n "$_val" ] && printf '%s' "$_val" || printf '%s' "$_def"
}

_wiki="$(get_cfg "wiki_dir" ".rnex/wiki")"
_raw="$(get_cfg "raw_dir" "./docs")"
_wiki="$(printf '%s' "$_wiki" | sed -e 's#^/##' -e 's#/$##')"
_raw="$(printf '%s' "$_raw" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"

_trigger="$(get_cfg "lint_trigger" "manual")"
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

  if [ "$_has_wiki_changes" -eq 1 ]; then
    _notify="$(get_cfg "notify_on_changes" "true")"
    if [ "$_notify" != "false" ]; then
      _wiki_path="$_root/$_wiki"
      if [ ! -f "$_wiki_path/index.md" ] || [ ! -f "$_wiki_path/hot.md" ]; then
        printf '[WIKI] Warning: Required wiki files (index.md or hot.md) missing in %s/.\n' "$_wiki"
      fi
      printf '[WIKI] Reminder: Wiki files changed. Run the rnex-karpathy-llm-wiki-lint skill to verify.\n'
    fi
  fi
fi
