#!/bin/sh
set -e
_root="${RNEX_ROOT:-$PWD}"
get_cfg() {
  _key="$1"; _def="$2"
  _val=""
  if [ -f "$_root/.local.rnex.yaml" ]; then
    _val="$(awk -v k="$_key" '
      /^plugins:/ { in_p=1; in_k=0; next }
      in_p && /^[^ #]/ { in_p=0; in_k=0 }
      in_p && match($0, "^[ ]*karpathy-llm:[ ]*(#.*)?$") { in_k=1; next }
      in_k && (/^[ ]{1,2}[^ #]/ || /^[^ #]/) { in_k=0 }
      in_k && $0 ~ ("^[ ]*" k ":") {
        sub("^[ ]*" k ":[ ]*", "")
        sub(/[ ]*#.*/, "")
        gsub(/["\047]/, "")
        print
        exit
      }
    ' "$_root/.local.rnex.yaml")"
  fi
  if [ -z "$_val" ] && [ -f "$_root/rnex.yaml" ]; then
    _val="$(awk -v k="$_key" '
      /^plugins:/ { in_p=1; in_k=0; next }
      in_p && /^[^ #]/ { in_p=0; in_k=0 }
      in_p && match($0, "^[ ]*karpathy-llm:[ ]*(#.*)?$") { in_k=1; next }
      in_k && (/^[ ]{1,2}[^ #]/ || /^[^ #]/) { in_k=0 }
      in_k && $0 ~ ("^[ ]*" k ":") {
        sub("^[ ]*" k ":[ ]*", "")
        sub(/[ ]*#.*/, "")
        gsub(/["\047]/, "")
        print
        exit
      }
    ' "$_root/rnex.yaml")"
  fi
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
