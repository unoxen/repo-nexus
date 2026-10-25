#!/bin/sh
# shellcheck shell=sh disable=SC2154
set -e

# Exit early if rnex utilities aren't available 
[ -z "$RNEX_ROOT" ] && { echo "Error: RNEX_ROOT not set"; exit 1; }

for _kl_common in \
  "${RNEX_PLUGIN_DIR:-}/hooks/_common.sh" \
  "$(dirname "$0")/_common.sh" \
  "${RNEX_ROOT:-.}/.rnex/plugins/karpathy-llm/hooks/_common.sh" \
  "${RNEX_ROOT:-.}/toolkit/plugins/karpathy-llm/hooks/_common.sh"; do
  # shellcheck source=/dev/null
  [ -f "$_kl_common" ] && { . "$_kl_common"; break; }
done

mkdir -p "$_wiki_path"

_has_src_dirs=0
if command -v plugin_source_dirs >/dev/null 2>&1; then
  for _sdir in $(plugin_source_dirs "karpathy-llm"); do
    [ -n "$_sdir" ] || continue
    case "$_sdir" in
      *'*'*|*'?'*|*'['*|*.md|*.txt) continue ;;
    esac
    _has_src_dirs=1
    mkdir -p "$_root/$_sdir"
    [ -f "$_root/$_sdir/.gitkeep" ] || touch "$_root/$_sdir/.gitkeep"
  done
fi

if [ "$_has_src_dirs" -eq 0 ]; then
  _raw_legacy="$(get_cfg "raw_dir" "./docs")"
  _raw_legacy="$(printf '%s' "$_raw_legacy" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
  case "$_raw_legacy" in
    *'*'*|*'?'*|*'['*|*.md|*.txt) ;;
    *)
      _has_sources=""
      for _cf in "$_root/.local.rnex.yaml" "$_root/rnex.yaml"; do
        [ -f "$_cf" ] && grep -q "^[ ]*sources:[ ]*" "$_cf" 2>/dev/null && { _has_sources="1"; break; }
      done
      if [ "$_has_sources" != "1" ]; then
        mkdir -p "$_root/$_raw_legacy"
        [ -f "$_root/$_raw_legacy/.gitkeep" ] || touch "$_root/$_raw_legacy/.gitkeep"
      fi
      ;;
  esac
fi

# Clean up obsolete leaked root ./raw and ./wiki directories if non-default paths are configured
command -v _clean_leaked_plugin_dirs >/dev/null 2>&1 && _clean_leaked_plugin_dirs "$_root" "$_raw" "$_wiki"

# Ensure configured wiki_dir and default control files (index.md, hot.md, _log.md) exist
kl_ensure_wiki_files

# Clean up legacy staging directory only if empty or positively verified as managed duplicate copies
if [ -d "$_wiki_path/raw" ]; then
  if ! rmdir "$_wiki_path/raw" 2>/dev/null; then
    _has_user_content=0
    for _rf in "$_wiki_path/raw"/* "$_wiki_path/raw"/.[!.]* "$_wiki_path/raw"/..?*; do
      [ -e "$_rf" ] || continue
      _rname="$(basename "$_rf")"
      case "$_rname" in
        README_*.md)
          _rrepo="${_rname#README_}"
          _rrepo="${_rrepo%.md}"
          if [ -f "$_root/repos/$_rrepo/README.md" ] && cmp -s "$_rf" "$_root/repos/$_rrepo/README.md"; then
            continue
          fi
          _has_user_content=1
          break
          ;;
        *)
          if [ -f "$_raw_path/$_rname" ] && cmp -s "$_rf" "$_raw_path/$_rname"; then
            continue
          fi
          _has_user_content=1
          break
          ;;
      esac
    done

    if [ "$_has_user_content" -eq 0 ]; then
      rm -rf "${_wiki_path:?}/raw" 2>/dev/null || true
    else
      printf '[WIKI] Warning: %s/raw contains custom or uncommitted files. Preserving directory without deletion.\n' "$_wiki"
    fi
  fi
fi

# 1. Register plugin User Skills via contract helper (with plugin name prefix)
if ! command -v rnex_register_user_skill >/dev/null 2>&1 && ! command -v rnex_generate_user_skill >/dev/null 2>&1; then
  if [ -f "$RNEX_ROOT/.rnex/bin/rnex-env.sh" ]; then
    # shellcheck source=/dev/null
    . "$RNEX_ROOT/.rnex/bin/rnex-env.sh"
  fi
fi

# Clean up stale unprefixed skills
if command -v rnex_unregister_user_skill >/dev/null 2>&1; then
  rnex_unregister_user_skill "wiki-ingest"
  rnex_unregister_user_skill "wiki-lint"
fi

_reg_fn=""
if command -v rnex_generate_user_skill >/dev/null 2>&1; then
  _reg_fn="rnex_generate_user_skill"
elif command -v rnex_register_user_skill >/dev/null 2>&1; then
  _reg_fn="rnex_register_user_skill"
fi

if [ -n "$_reg_fn" ]; then
  for skill_file in "$RNEX_ROOT/.rnex/plugins/karpathy-llm/skills"/*.md; do
    [ -f "$skill_file" ] || continue
    skill_name=$(basename "$skill_file" .md)
    "$_reg_fn" "$skill_name" ".rnex/plugins/karpathy-llm/skills/${skill_name}.md" "karpathy-llm"
  done
fi

# 2. Automatically ingest README.md from registered/enabled member repositories when included in sources
_skip_all_readmes=0
if command -v get_plugin_config_list >/dev/null 2>&1; then
  _src_list="$(get_plugin_config_list "karpathy-llm" "sources" 2>/dev/null || true)"
  if [ -n "$_src_list" ]; then
    _skip_all_readmes=1
    while IFS= read -r _s_item || [ -n "$_s_item" ]; do
      case "$_s_item" in
        *README*|*readme*|repos/*|"./repos/"*|"$_clean_repos"/*|*"**"*)
          _skip_all_readmes=0
          break
          ;;
      esac
    done <<EOF_SRC
$_src_list
EOF_SRC
  fi
fi

_ALL_INGESTED_REPOS=""
_ALL_INGESTED_COUNT=0

if [ "$_skip_all_readmes" -ne 1 ]; then
  for repo_name in $(yaml_list_repos); do
    [ -n "$repo_name" ] || continue
    yaml_repo_enabled "$repo_name" || continue
    kl_resolve_repo_paths "$repo_name"

    [ -d "$_kl_repo_path" ] || continue

    # Read and ingest any README file directly in-place (no staging copy)
    for readme_name in README.md readme.md README.markdown README; do
      if [ -f "$_kl_repo_path/$readme_name" ]; then
        kl_ingest_member_readme "$repo_name" "$_kl_repo_path" "$readme_name" "$_kl_repo_rel" 0
        _ALL_INGESTED_REPOS="${_ALL_INGESTED_REPOS:+$_ALL_INGESTED_REPOS, }$repo_name"
        _ALL_INGESTED_COUNT=$((_ALL_INGESTED_COUNT + 1))
        break
      fi
    done
  done
fi

# 3. Enforce strict ~500-word ceiling on hot.md (condense Section 1 if needed)
kl_condense_hot_cache "$_ALL_INGESTED_COUNT" "$_ALL_INGESTED_REPOS"

# 4. Ensure sync stamp is updated
if command -v update_sync_stamp >/dev/null 2>&1; then
  update_sync_stamp "$_root"
elif [ -f "$_root/lib/workspace.sh" ]; then
  # shellcheck source=/dev/null
  . "$_root/lib/workspace.sh" 2>/dev/null || true
  update_sync_stamp "$_root" 2>/dev/null || true
fi

