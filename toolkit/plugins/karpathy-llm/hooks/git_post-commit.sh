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
        if (trimmed ~ ("^[\"\x27]?" plugin "[\"\x27]?:")) {
          in_target=1
          plugin_indent=indent
          next
        }
      }

      in_target && (indent > plugin_indent) {
        if (trimmed ~ ("^[\"\x27]?" key "[\"\x27]?:[ \t]*")) {
          sub("^[\"\x27]?" key "[\"\x27]?:[ \t]*", "", trimmed)
          if (trimmed ~ /^"[^"]*"/) {
            match(trimmed, /^"[^"]*"/)
            val = substr(trimmed, 2, RLENGTH - 2)
          } else if (trimmed ~ /^\x27[^\x27]*\x27/) {
            match(trimmed, /^\x27[^\x27]*\x27/)
            val = substr(trimmed, 2, RLENGTH - 2)
          } else {
            sub(/[ \t]*#.*$/, "", trimmed)
            sub(/[ \t]+$/, "", trimmed)
            val = trimmed
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
if [ "$_trigger" = "git-post-commit" ] || [ "$_trigger" = "post-commit" ]; then
  if git -C "$_root" diff-tree -r --name-only --root HEAD 2>/dev/null | grep -qE "(^|/)($_raw|$_wiki)/"; then
    _notify="$(get_cfg "notify_on_changes" "true")"
    if [ "$_notify" != "false" ]; then
      printf '[WIKI] Changes committed to %s/ or %s/. Run wiki-lint or wiki-ingest as needed.\n' "$_raw" "$_wiki"
    fi
  fi
fi
