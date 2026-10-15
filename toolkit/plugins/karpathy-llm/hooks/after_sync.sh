#!/bin/sh
set -e

# Exit early if rnex utilities aren't available 
[ -z "$RNEX_ROOT" ] && { echo "Error: RNEX_ROOT not set"; exit 1; }

# Resolve root workspace
_root="$RNEX_ROOT"

# Target directory inside .rnex/ (the internal wiki's Raw intake state)
WIKI_RAW_DIR="$RNEX_ROOT/.rnex/wiki/raw"
mkdir -p "$WIKI_RAW_DIR"

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

# 1. Parse 'raw_dir' configuration from rnex.yaml/.local.rnex.yaml (Defaults to './docs')
# We check if parsed in RNEX_CONFIG_MERGED (YAML) using a standard grep/sed lookup
RAW_DIR_VAL=$(grep -h -E '^\s*raw_dir:' "$RNEX_ROOT/rnex.yaml" "$RNEX_ROOT/.local.rnex.yaml" 2>/dev/null | tail -n1 | awk -F: '{print $NF}' | awk '{print $1}' | tr -d '"'\''')
[ -z "$RAW_DIR_VAL" ] && RAW_DIR_VAL="$(get_cfg "raw_dir" "./docs")"
RAW_DIR="${RAW_DIR_VAL:-./docs}"

# Clear and sync the custom local raw folder files to raw intake (if any exist)
if [ -d "$RNEX_ROOT/$RAW_DIR" ]; then
  _raw_abs="$(cd "$RNEX_ROOT/$RAW_DIR" 2>/dev/null && pwd -P || true)"
  _wiki_raw_abs="$(cd "$WIKI_RAW_DIR" 2>/dev/null && pwd -P || true)"
  if [ -n "$_raw_abs" ] && [ "$_raw_abs" != "$_wiki_raw_abs" ]; then
    find "$RNEX_ROOT/$RAW_DIR" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.json" \) 2>/dev/null | while read -r filepath; do
      filename=$(basename "$filepath")
      # Prevent overwriting standard operational files
      if [ "$filename" != "index.md" ] && [ "$filename" != "hot.md" ] && [ "$filename" != "_log.md" ]; then
        cp "$filepath" "$WIKI_RAW_DIR/$filename"
      fi
    done
  fi
fi

# 2. Automatically sync README.md from all enabled/cloned member repositories
# Get list of enabled repositories using a secure cross-repo read or `rnex list`
REPOS_DIR_VAL=$(grep -h -E '^\s*repos_dir:' "$RNEX_ROOT/rnex.yaml" "$RNEX_ROOT/.local.rnex.yaml" 2>/dev/null | tail -n1 | awk -F: '{print $NF}' | awk '{print $1}' | tr -d '"'\''')
REPOS_DIR="${REPOS_DIR_VAL:-./repos}"

if [ -d "$RNEX_ROOT/$REPOS_DIR" ]; then
  for repo_path in "$RNEX_ROOT/$REPOS_DIR"/*; do
    [ ! -d "$repo_path" ] && continue
    repo_name=$(basename "$repo_path")
    
    # Ignore repos that are disabled locally (checking status state)
    # Checks if enabled: false exists for this repo in configuration
    if grep -A5 "  $repo_name:" "$RNEX_ROOT/rnex.yaml" "$RNEX_ROOT/.local.rnex.yaml" 2>/dev/null | grep -q "enabled: false"; then
      continue
    fi

    # Read and sync any README file with case-insensitive check
    for readme_name in README.md readme.md README.markdown README; do
      if [ -f "$repo_path/$readme_name" ]; then
        # Namespace the copied file with its repo name to prevent conflicts
        cp "$repo_path/$readme_name" "$WIKI_RAW_DIR/README_${repo_name}.md"
        break
      fi
    done
  done
fi
