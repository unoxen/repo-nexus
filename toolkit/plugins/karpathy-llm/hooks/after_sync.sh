#!/bin/sh
set -e

# Resolve root workspace
_root="${RNEX_ROOT:-$PWD}"

# Helper to read plugin config
get_cfg() {
  _key="$1"; _def="$2"
  _val=""
  if [ -f "$_root/.local.rnex.yaml" ]; then
    _val="$(awk -v k="$_key" '
      /^plugins:/ { in_p=1; next }
      in_p && /^[ ]*karpathy-llm:/ { in_k=1; next }
      in_k && /^[^ ]/ { exit }
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
      /^plugins:/ { in_p=1; next }
      in_p && /^[ ]*karpathy-llm:/ { in_k=1; next }
      in_k && /^[^ ]/ { exit }
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

# Clean relative paths
_wiki="$(printf '%s' "$_wiki" | sed -e 's#^/##' -e 's#/$##')"
_raw="$(printf '%s' "$_raw" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"

_wiki_path="$_root/$_wiki"
_raw_path="$_root/$_raw"

mkdir -p "$_wiki_path" "$_raw_path"
[ -f "$_raw_path/.gitkeep" ] || touch "$_raw_path/.gitkeep"

_pdir="${RNEX_PLUGIN_DIR:-$_root/.rnex/plugins/karpathy-llm}"
if [ ! -d "$_pdir/templates" ] && [ -d "$_root/toolkit/plugins/karpathy-llm/templates" ]; then
  _tmpl_dir="$_root/toolkit/plugins/karpathy-llm/templates"
else
  _tmpl_dir="$_pdir/templates"
fi

if [ -f "$_tmpl_dir/index.md" ] && [ ! -f "$_wiki_path/index.md" ]; then
  sed -e "s|{wiki_dir}|$_wiki|g" -e "s|{raw_dir}|$_raw|g" "$_tmpl_dir/index.md" > "$_wiki_path/index.md"
fi
if [ -f "$_tmpl_dir/hot.md" ] && [ ! -f "$_wiki_path/hot.md" ]; then
  sed -e "s|{wiki_dir}|$_wiki|g" -e "s|{raw_dir}|$_raw|g" "$_tmpl_dir/hot.md" > "$_wiki_path/hot.md"
fi
if [ -f "$_tmpl_dir/_log.md" ] && [ ! -f "$_wiki_path/_log.md" ]; then
  sed -e "s|{wiki_dir}|$_wiki|g" -e "s|{raw_dir}|$_raw|g" "$_tmpl_dir/_log.md" > "$_wiki_path/_log.md"
fi

# Ensure template in .rnex/plugins/karpathy-llm/templates
mkdir -p "$_pdir/templates"
if [ -f "$_tmpl_dir/rnex-wiki-page.sample.md" ] && [ ! -f "$_pdir/templates/rnex-wiki-page.template.md" ]; then
  cp "$_tmpl_dir/rnex-wiki-page.sample.md" "$_pdir/templates/rnex-wiki-page.template.md"
fi
