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

NEXUS_DIR="$_root"
RNEX_ROOT="$_root"
export NEXUS_DIR RNEX_ROOT

if ! command -v plugin_primary_source_dir >/dev/null 2>&1; then
  if [ -n "${RNEX_LIB_DIR:-}" ] && [ -f "$RNEX_LIB_DIR/plugins.sh" ]; then
    . "$RNEX_LIB_DIR/core.sh" 2>/dev/null || true
    . "$RNEX_LIB_DIR/yaml.sh" 2>/dev/null || true
    . "$RNEX_LIB_DIR/plugins.sh" 2>/dev/null || true
  elif [ -f "$_root/lib/plugins.sh" ]; then
    . "$_root/lib/core.sh" 2>/dev/null || true
    . "$_root/lib/yaml.sh" 2>/dev/null || true
    . "$_root/lib/plugins.sh" 2>/dev/null || true
  fi
fi
if command -v plugin_primary_source_dir >/dev/null 2>&1; then
  _psd="$(plugin_primary_source_dir "karpathy-llm" 2>/dev/null || true)"
  [ -n "$_psd" ] && _raw="$_psd"
fi

_trigger="$(get_cfg "lint_trigger" "manual")"
if [ "$_trigger" = "git-pre-commit" ] || [ "$_trigger" = "pre-commit" ]; then
  if git -C "$_root" diff --cached --name-only 2>/dev/null | grep -qE "(^|/)($_raw|$_wiki)/"; then
    _notify="$(get_cfg "notify_on_changes" "true")"
    if [ "$_notify" != "false" ]; then
      printf '[WIKI] Pre-commit verification: pending changes in %s/ or %s/.\n' "$_raw" "$_wiki"
    fi
  fi
fi
