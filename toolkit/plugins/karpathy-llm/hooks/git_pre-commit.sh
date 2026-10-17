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
if [ "$_trigger" = "git-pre-commit" ] || [ "$_trigger" = "pre-commit" ]; then
  if git -C "$_root" diff --cached --name-only 2>/dev/null | grep -qE "(^|/)($_raw|$_wiki)/"; then
    _notify="$(get_cfg "notify_on_changes" "true")"
    if [ "$_notify" != "false" ]; then
      printf '[WIKI] Pre-commit verification: pending changes in %s/ or %s/.\n' "$_raw" "$_wiki"
    fi
  fi
fi
