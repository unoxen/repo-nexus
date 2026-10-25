#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/plugins.sh — Plugin Engine (discovery, metadata, and scoped synchronization)
# ============================================================================

# Search all candidate toolkit directories and locate a plugin by name containing plugin.yaml.
find_plugin_dir() {
  _query="$1"
  _sdir="$(dirname "$SCRIPT_LOCATION")"
  for _cand in \
    "${RNEX_ROOT:-}/toolkit/plugins/$_query" \
    "${RNEX_TOOLKIT_DIR:-}/plugins/$_query" \
    "${RNEX_PLUGINS_DIR:-}/$_query" \
    "$NEXUS_DIR/toolkit/plugins/$_query" \
    "$SCRIPT_LOCATION/toolkit/plugins/$_query" \
    "$_sdir/toolkit/plugins/$_query" \
    "$NEXUS_DIR/plugins/$_query" \
    "$NEXUS_DIR/.rnex/plugins/$_query" \
    "$NEXUS_DIR/.nexus/plugins/$_query"; do
    [ -n "$_cand" ] || continue
    if [ -f "$_cand/plugin.yaml" ]; then
      printf '%s' "$_cand"
      return 0
    fi
  done
  return 1
}

# Scan and list all unique plugin directories across workspace and toolkit locations.
list_all_available_plugin_dirs() {
  _sdir="$(dirname "$SCRIPT_LOCATION")"
  _dirs=""
  for _parent in \
    "${RNEX_ROOT:-}/toolkit/plugins" \
    "${RNEX_TOOLKIT_DIR:-}/plugins" \
    "${RNEX_PLUGINS_DIR:-}" \
    "$NEXUS_DIR/toolkit/plugins" \
    "$SCRIPT_LOCATION/toolkit/plugins" \
    "$_sdir/toolkit/plugins" \
    "$NEXUS_DIR/plugins" \
    "$NEXUS_DIR/.rnex/plugins" \
    "$NEXUS_DIR/.nexus/plugins"; do
    [ -n "$_parent" ] || continue
    if [ -d "$_parent" ]; then
      for _sub in "$_parent"/*; do
        if [ -d "$_sub" ] && [ -f "$_sub/plugin.yaml" ]; then
          _b="$(basename "$_sub")"
          case " $_dirs " in
            *" $_b "*) ;;
            *)
              _dirs="$_dirs $_b"
              printf '%s\n' "$_sub"
              ;;
          esac
        fi
      done
    fi
  done
}

# Extract a top-level scalar field (e.g. name, version, description) from plugin.yaml.
plugin_get_field() {
  _pdir="$1"; _fld="$2"
  [ -f "$_pdir/plugin.yaml" ] || return 1
  awk -v fld="$_fld" '
    $0 ~ ("^" fld ":") {
      sub("^" fld ":[ ]*", "");
      sub(/[ ]*#.*/, "");
      print
    }
  ' "$_pdir/plugin.yaml"
}

# Parse declared template source-to-destination mappings from plugin.yaml.
plugin_list_templates() {
  _pdir="$1"
  [ -f "$_pdir/plugin.yaml" ] || return 0
  awk '
    /^templates:/ { t=1; next }
    t && /^[^ #]/ { exit }
    t && /^[ ]*-[ ]*/ {
      sub(/^[ ]*-[ ]*/, "");
      sub(/[ ]*#.*/, "");
      gsub(/["\047]/, "");
      if (length($0) > 0) print $0
    }
  ' "$_pdir/plugin.yaml"
}

# Parse declared instruction files from plugin.yaml.
plugin_list_instructions() {
  _pdir="$1"
  [ -f "$_pdir/plugin.yaml" ] || return 0
  awk '
    /^instructions:/ { t=1; next }
    t && /^[^ #]/ { exit }
    t && /^[ ]*-[ ]*/ {
      sub(/^[ ]*-[ ]*/, "");
      sub(/[ ]*#.*/, "");
      if (length($0) > 0) print $0
    }
  ' "$_pdir/plugin.yaml"
}

# Substitute configurable placeholders (e.g. {wiki_dir}, {raw_dir}) in template destination paths.
plugin_resolve_placeholders() {
  _p="$1"; _pd="$2"; _str="$3"
  _res="$(printf '%s' "$_str" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"")"

  if [ -f "$_pd/plugin.yaml" ]; then
    _keys="$(awk '
      /^config_defaults:[ ]*$/ || /^config_defaults:[ ]*#/ { in_c=1; next }
      in_c && /^[^ #]/ { exit }
      in_c && /^[ ]*[a-zA-Z0-9_.-]+:[ ]*/ {
        k = $0
        sub(/^[ ]*/, "", k)
        sub(/:.*/, "", k)
        print k
      }
    ' "$_pd/plugin.yaml")"

    for _k in $_keys; do
      _v="$(yaml_plugin_get "$_p" "$_k" 2>/dev/null || true)"
      if [ -z "$_v" ]; then
        _v="$(awk -v k="$_k" '
          /^config_defaults:[ ]*$/ || /^config_defaults:[ ]*#/ { in_c=1; next }
          in_c && /^[^ #]/ { exit }
          in_c && $0 ~ ("^[ ]*" k ":") {
            sub("^[ ]*" k ":[ ]*", "")
            sub(/[ ]*#.*/, "")
            gsub(/["\047]/, "")
            print
            exit
          }
        ' "$_pd/plugin.yaml")"
      fi
      case "$_k" in
        *_dir|dir)
          _v="$(normalize_rel_path "$_v")"
          ;;
      esac
      _res="$(printf '%s' "$_res" | sed -e "s|{$_k}|$_v|g")"
    done
  fi

  # Fallback resolution for core wiki/raw placeholders and legacy prefixes
  _w_val="$(yaml_plugin_get "$_p" "wiki_dir" 2>/dev/null || true)"
  [ -n "$_w_val" ] || _w_val="wiki"
  _w_val="$(normalize_rel_path "$_w_val")"

  # {raw_dir} (legacy alias) resolves to the first explicit directory source; when no
  # directory source exists it stays unresolved so callers can skip the destination.
  _r_val="$(plugin_primary_source_dir "$_p" 2>/dev/null || true)"

  _res="$(printf '%s' "$_res" | sed -e "s|{wiki_dir}|${_w_val}|g" -e "s|^\.\{0,1\}\/\{0,1\}wiki/|${_w_val}/|")"
  if [ -n "$_r_val" ]; then
    _res="$(printf '%s' "$_res" | sed -e "s|{raw_dir}|${_r_val}|g" -e "s|^\.\{0,1\}\/\{0,1\}raw/|${_r_val}/|")"
  fi

  _res="$(printf '%s' "$_res" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##')"

  printf '%s' "$_res"
}

plugin_instantiate_template() {
  _p="$1"; _pd="$2"; _src="$3"; _dest="$4"

  _w_val="$(yaml_plugin_get "$_p" "wiki_dir" 2>/dev/null || true)"
  [ -z "$_w_val" ] && _w_val="wiki"
  _w_val="$(printf '%s' "$_w_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^/##' -e 's#/$##')"

  _r_val="$(plugin_primary_source_dir "$_p" 2>/dev/null || true)"
  [ -z "$_r_val" ] && _r_val="docs"

  # {sources}: human-readable list of configured intake sources (sed-escaped)
  _s_val="$(plugin_sources_display "$_p" 2>/dev/null || true)"
  [ -z "$_s_val" ] && _s_val="$(printf '\140%s/\140' "$_r_val")"
  _s_val="$(printf '%s' "$_s_val" | sed -e 's/[\\&|]/\\&/g')"

  sed -e "s|{wiki_dir}|$_w_val|g" \
      -e "s|{raw_dir}|$_r_val|g" \
      -e "s|{sources}|$_s_val|g" \
      "$_src" > "$_dest"
}

# Deterministically sync plugin asset directories and manifest files into destination
sync_plugin_bundle() {
  _spb_src="$1"; _spb_dest="$2"
  [ -n "$_spb_src" ] && [ -n "$_spb_dest" ] || return 0
  [ "$_spb_src" != "$_spb_dest" ] || return 0

  mkdir -p "$_spb_dest"
  rm -rf "${_spb_dest:?}/prompts" 2>/dev/null || true
  for _sub in rules workflows instructions skills agents templates hooks commands; do
    if [ -d "$_spb_src/$_sub" ]; then
      rm -rf "${_spb_dest:?}/$_sub"
      mkdir -p "$_spb_dest/$_sub"
      cp -R "$_spb_src/$_sub"/. "$_spb_dest/$_sub"/ 2>/dev/null || true
      if [ "$_sub" = "hooks" ] || [ "$_sub" = "commands" ]; then
        chmod +x "$_spb_dest/$_sub"/* 2>/dev/null || true
      fi
    else
      rm -rf "${_spb_dest:?}/$_sub"
    fi
  done
  for _meta in plugin.yaml instructions.md README.md; do
    if [ -f "$_spb_src/$_meta" ]; then
      cp "$_spb_src/$_meta" "$_spb_dest/$_meta"
    fi
  done
}

# Clean up obsolete leaked root ./raw and ./wiki directories if non-default paths are configured
_clean_leaked_plugin_dirs() {
  _cld_root="${1:-$NEXUS_DIR}"
  _cld_raw="$2"
  _cld_wiki="$3"

  if [ "$_cld_raw" != "raw" ] && [ -d "$_cld_root/raw" ] && \
     ! plugin_source_dirs "karpathy-llm" 2>/dev/null | grep -qx 'raw'; then
    if ! rmdir "$_cld_root/raw" 2>/dev/null; then
      _can_clean=1
      for _f in "$_cld_root/raw"/* "$_cld_root/raw"/.[!.]* "$_cld_root/raw"/..?*; do
        [ -e "$_f" ] || continue
        _b="$(basename "$_f")"
        [ "$_b" = ".gitkeep" ] && continue
        [ -f "$_cld_root/$_cld_raw/$_b" ] && cmp -s "$_f" "$_cld_root/$_cld_raw/$_b" && continue
        _can_clean=0
        break
      done
      if [ "$_can_clean" -eq 1 ]; then
        rm -rf "$_cld_root/raw" 2>/dev/null || true
        log_dim "Cleaned up obsolete root raw/ directory"
      fi
    else
      log_dim "Removed empty obsolete root raw/ directory"
    fi
  fi

  if [ "$_cld_wiki" != "wiki" ] && [ -d "$_cld_root/wiki" ]; then
    if ! rmdir "$_cld_root/wiki" 2>/dev/null; then
      _can_clean=1
      for _f in "$_cld_root/wiki"/* "$_cld_root/wiki"/.[!.]* "$_cld_root/wiki"/..?*; do
        [ -e "$_f" ] || continue
        _b="$(basename "$_f")"
        case "$_b" in
          index.md|_log.md|hot.md|.gitkeep) continue ;;
          *)
            [ -f "$_cld_root/$_cld_wiki/$_b" ] && cmp -s "$_f" "$_cld_root/$_cld_wiki/$_b" && continue
            _can_clean=0
            break
            ;;
        esac
      done
      if [ "$_can_clean" -eq 1 ]; then
        rm -rf "$_cld_root/wiki" 2>/dev/null || true
        log_dim "Cleaned up obsolete root wiki/ directory"
      fi
    else
      log_dim "Removed empty obsolete root wiki/ directory"
    fi
  fi
}

# Sync plugins into scoped directories: .rnex/plugins/<plugin-name>/
sync_plugins() {
  # Clean up any bogus placeholder directories accidentally created in workspace root
  for _bogus in \
    "$NEXUS_DIR/\"{wiki_dir}" \
    "$NEXUS_DIR/\"{raw_dir}" \
    "$NEXUS_DIR/{wiki_dir}" \
    "$NEXUS_DIR/{raw_dir}"; do
    if [ -d "$_bogus" ]; then
      rm -rf "$_bogus"
      log_dim "Cleaned up leaked placeholder directory: $(basename "$_bogus")"
    fi
  done

  # Clean up obsolete leaked root ./raw and ./wiki directories if non-default paths are configured
  _raw_cfg="$(plugin_primary_source_dir "karpathy-llm" 2>/dev/null || true)"
  [ -n "$_raw_cfg" ] || _raw_cfg="docs"
  _wiki_cfg="$(yaml_plugin_get "karpathy-llm" "wiki_dir" 2>/dev/null || true)"
  [ -n "$_wiki_cfg" ] || _wiki_cfg="wiki"
  _wiki_cfg="$(normalize_rel_path "$_wiki_cfg")"
  _clean_leaked_plugin_dirs "$NEXUS_DIR" "$_raw_cfg" "$_wiki_cfg"

  # 1. Prune plugins that are disabled or no longer enabled in config
  if [ -d "$NEXUS_DIR/.rnex/plugins" ]; then
    for _existing in "$NEXUS_DIR/.rnex/plugins"/*; do
      [ -d "$_existing" ] || continue
      _pname="$(basename "$_existing")"
      if ! yaml_plugin_enabled "$_pname"; then
        run_plugin_hook "$_pname" "before_plugin_disable"
        clean_plugin_user_skills "$_existing"
        rm -rf "$_existing"
        log_ok "Removed disabled plugin scope: .rnex/plugins/$_pname"
      fi
    done
    rmdir "$NEXUS_DIR/.rnex/plugins" 2>/dev/null || true
  fi

  # Also run cleanup hook for any available plugin that is disabled
  for _pdir in $(list_all_available_plugin_dirs 2>/dev/null || true); do
    _pname="$(basename "$_pdir")"
    if ! yaml_plugin_enabled "$_pname" 2>/dev/null; then
      run_plugin_hook "$_pname" "before_plugin_disable"
    fi
  done

  # 2. Sync enabled plugins
  yaml_list_plugins | while read -r _pname; do
    [ -n "$_pname" ] || continue
    yaml_plugin_enabled "$_pname" || continue
    _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
    if [ -z "$_pdir" ]; then
      log_warn "Plugin '$_pname' declared in config but not found on disk"
      continue
    fi

    sync_plugin_bundle "$_pdir" "$NEXUS_DIR/.rnex/plugins/$_pname"

    # Provision explicit directory sources declared under plugins.<name>.sources (e.g. ./docs)
    for _sdir in $(plugin_source_dirs "$_pname" 2>/dev/null); do
      [ -n "$_sdir" ] || continue
      _full_sdir="$NEXUS_DIR/$_sdir"
      if [ ! -d "$_full_sdir" ]; then
        mkdir -p "$_full_sdir"
        [ -f "$_full_sdir/.gitkeep" ] || touch "$_full_sdir/.gitkeep"
        log_ok "Created intake source directory: $_sdir"
      fi
    done

    # Initialize templates declared in plugin (functional external dirs like raw/, wiki/)
    plugin_list_templates "$_pdir" | while read -r _item; do
      [ -n "$_item" ] || continue
      _s="${_item%%:*}"
      _d="${_item#*:}"
      _s="$(printf '%s' "$_s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"")"
      _d="$(printf '%s' "$_d" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"")"

      _d="$(plugin_resolve_placeholders "$_pname" "$_pdir" "$_d")"

      # No explicit directory source configured (e.g. glob-only sources): nothing to provision
      case "$_d" in
        *"{raw_dir}"*) continue ;;
      esac

      # Defensive guard: never create directories or files if placeholder expansion failed or quotes leaked
      case "$_d" in
        *"{"*"}"*|*\"*|*\'*)
          log_warn "Skipping invalid template destination with unresolved placeholders: $_d"
          continue
          ;;
      esac

      _src_path="$_pdir/$_s"
      _dest_path="$NEXUS_DIR/$_d"

      if [ -f "$_src_path" ] && [ ! -f "$_dest_path" ]; then
        mkdir -p "$(dirname "$_dest_path")"
        plugin_instantiate_template "$_pname" "$_pdir" "$_src_path" "$_dest_path"
        if [ -x "$_src_path" ]; then
          chmod +x "$_dest_path" 2>/dev/null || true
        fi
        log_ok "Initialized template: $_d"
      fi
    done
  done
}

# ----------------------------------------------------------------------------
# Plugin source resolution (directories + POSIX glob patterns)
# ----------------------------------------------------------------------------

# True if the argument contains a glob metacharacter (*, ?, [)
_src_has_glob() {
  case "$1" in
    *'*'*|*'?'*|*'['*) return 0 ;;
  esac
  return 1
}

# Workspace-relative member repositories directory (default: repos)
_plugin_repos_rel_dir() {
  _prd="${REPOS_DIR:-}"
  if [ -n "$_prd" ]; then
    _prd="${_prd#"${NEXUS_DIR:-.}"/}"
  else
    _prd="repos"
  fi
  while [ "${_prd#./}" != "$_prd" ]; do _prd="${_prd#./}"; done
  printf '%s' "${_prd%/}"
}

# Normalize a source entry: trim whitespace/CR, strip leading ./ and trailing /
_src_normalize_entry() {
  _sne="$(printf '%s' "$1" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  while [ "${_sne#./}" != "$_sne" ]; do _sne="${_sne#./}"; done
  [ "$_sne" = "." ] || _sne="${_sne%/}"
  printf '%s' "$_sne"
}

# True if a normalized entry names a file rather than a directory
# (glob pattern, .md/.txt suffix, or an existing regular file)
_src_is_file_like() {
  _src_has_glob "$1" && return 0
  case "$1" in
    *.md|*.txt) return 0 ;;
  esac
  [ -f "${NEXUS_DIR:-.}/$1" ] && return 0
  return 1
}

# List explicit directory sources of a plugin that rnex may provision (mkdir).
# Skips glob patterns, file entries, absolute paths, '..' traversal, the workspace
# root, and paths inside the member repositories directory.
plugin_source_dirs() {
  _psd_rdir="$(_plugin_repos_rel_dir)"
  get_plugin_config_list "$1" "sources" 2>/dev/null | while IFS= read -r _psd_e || [ -n "$_psd_e" ]; do
    _psd_e="$(_src_normalize_entry "$_psd_e")"
    case "$_psd_e" in
      ''|.|/*|..|../*|*/..|*/../*) continue ;;
    esac
    _src_is_file_like "$_psd_e" && continue
    case "$_psd_e" in
      "$_psd_rdir"|"$_psd_rdir"/*) continue ;;
    esac
    printf '%s\n' "$_psd_e"
  done
}

# First provisionable directory source (legacy {raw_dir} placeholder); may be empty
plugin_primary_source_dir() {
  plugin_source_dirs "$1" | sed -n '1p'
}

# Human-readable source list for templates, e.g.: `docs/`, `repos/**/README.md`
plugin_sources_display() {
  get_plugin_config_list "$1" "sources" 2>/dev/null | while IFS= read -r _psy_e || [ -n "$_psy_e" ]; do
    _psy_e="$(_src_normalize_entry "$_psy_e")"
    [ -n "$_psy_e" ] || continue
    if _src_is_file_like "$_psy_e"; then
      printf '\140%s\140\n' "$_psy_e"
    else
      printf '\140%s/\140\n' "$_psy_e"
    fi
  done | awk '{ out = (NR == 1) ? $0 : out ", " $0 } END { if (NR) print out }'
}

# Split a pattern into its leading wildcard-free directory prefix and the rest.
# The last component always stays in the rest. Sets _sp_base (default ".") and _sp_rest.
_src_static_prefix() {
  _sp_base=""
  _sp_rest="$1"
  while :; do
    _sp_comp="${_sp_rest%%/*}"
    [ "$_sp_comp" = "$_sp_rest" ] && break
    _src_has_glob "$_sp_comp" && break
    _sp_base="${_sp_base:+$_sp_base/}$_sp_comp"
    _sp_rest="${_sp_rest#*/}"
  done
  [ -z "$_sp_base" ] && _sp_base="."
  return 0
}

# List all files under a directory, pruning hidden directories/files and node_modules
_src_find_dir() {
  find "$1" ! -path "$1" -type d \( -name '.*' -o -name node_modules \) -prune -o -type f ! -name '.*' -print 2>/dev/null
}

# Resolve a recursive glob: <base>/**/<rest>  (base "." for a leading **/)
_src_find_recursive() {
  _fr_base="$1"; _fr_rest="$2"
  if [ "${_fr_rest#*/}" = "$_fr_rest" ] && ! _src_has_glob "$_fr_base"; then
    # Single trailing component: exact semantics via -name at any depth
    [ -d "$_fr_base" ] || return 0
    find "$_fr_base" ! -path "$_fr_base" -type d \( -name .git -o -name .rnex -o -name node_modules \) -prune \
      -o -type f -name "$_fr_rest" -print 2>/dev/null
    return 0
  fi
  _fr_start="$_fr_base"
  if _src_has_glob "$_fr_base"; then
    _src_static_prefix "$_fr_base/x"
    _fr_start="$_sp_base"
  fi
  [ -d "$_fr_start" ] || return 0
  find "$_fr_start" ! -path "$_fr_start" -type d \( -name .git -o -name .rnex -o -name node_modules \) -prune \
    -o -type f \( -path "$_fr_base/$_fr_rest" -o -path "$_fr_base/*/$_fr_rest" \) -print 2>/dev/null
}

# Resolve a single-level glob (e.g. repos/*/README.md, docs/*.md) with bounded depth
_src_find_glob() {
  _src_static_prefix "$1"
  [ -d "$_sp_base" ] || return 0
  # Prune directories at (or below) the pattern depth so find never descends further
  _fg_depth="$_sp_base"
  _fg_r="$_sp_rest"
  while :; do
    _fg_depth="$_fg_depth/*"
    case "$_fg_r" in
      */*) _fg_r="${_fg_r#*/}" ;;
      *) break ;;
    esac
  done
  find "$_sp_base" ! -path "$_sp_base" -type d \( -name .git -o -name .rnex -o -name node_modules -o -path "$_fg_depth" \) -prune \
    -o -type f -path "$_sp_base/$_sp_rest" -print 2>/dev/null
}

# Resolve one normalized source entry (run from the workspace root)
_src_resolve_entry() {
  _re="$1"
  case "$_re" in
    '**')
      _src_find_dir "."
      ;;
    */'**')
      _re="${_re%/\*\*}"
      [ -d "$_re" ] && _src_find_dir "$_re"
      ;;
    '**/'*)
      _src_find_recursive "." "${_re#\*\*/}"
      ;;
    *'/**/'*)
      _src_find_recursive "${_re%%/\*\*/*}" "${_re#*/\*\*/}"
      ;;
    *)
      if [ -d "$_re" ]; then
        _src_find_dir "$_re"
      elif [ -f "$_re" ]; then
        printf '%s\n' "$_re"
      elif _src_has_glob "$_re"; then
        _src_find_glob "$_re"
      fi
      ;;
  esac
  return 0
}

# Resolve plugin source entries (directories, files, glob patterns) into a
# deduplicated, sorted list of workspace-relative file paths.
# Input: newline-separated entries as $1 (or stdin), e.g. from get_plugin_config_list.
# Files inside member repositories disabled via `enabled: false` are excluded.
resolve_plugin_sources() {
  _rs_root="${NEXUS_DIR:-${RNEX_ROOT:-.}}"

  _saved_wy="${WORKSPACE_YAML:-}"
  _saved_wly="${WORKSPACE_LOCAL_YAML:-}"
  [ -z "$WORKSPACE_YAML" ] && WORKSPACE_YAML="$_rs_root/${RNEX_CONFIG_FILE:-rnex.yaml}"
  [ -z "$WORKSPACE_LOCAL_YAML" ] && WORKSPACE_LOCAL_YAML="$_rs_root/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"

  # Workspace-relative member repositories directory (default: repos)
  _rs_rdir="$(_plugin_repos_rel_dir)"

  # Space-separated list of disabled repositories (local config overrides repo config)
  _rs_disabled="$(yaml_list_repos 2>/dev/null | while IFS= read -r _rs_r; do
    [ -n "$_rs_r" ] || continue
    yaml_repo_enabled "$_rs_r" || printf '%s ' "$_rs_r"
  done)"

  _rs_out="$(
    if [ "$#" -gt 0 ]; then
      printf '%s\n' "$1"
    else
      cat
    fi | (
      cd "$_rs_root" || exit 0
      while IFS= read -r _rs_e || [ -n "$_rs_e" ]; do
        _rs_e="$(printf '%s' "$_rs_e" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        while [ "${_rs_e#./}" != "$_rs_e" ]; do _rs_e="${_rs_e#./}"; done
        [ "$_rs_e" = "." ] || _rs_e="${_rs_e%/}"
        [ -n "$_rs_e" ] || continue
        _src_resolve_entry "$_rs_e"
      done
    ) | sed -e 's#^\(\./\)*##' | awk -v prefix="$_rs_rdir/" -v disabled="$_rs_disabled" '
      BEGIN {
        n = split(disabled, d, " ")
        for (i = 1; i <= n; i++) off[d[i]] = 1
      }
      length($0) == 0 { next }
      index($0, prefix) == 1 {
        name = substr($0, length(prefix) + 1)
        sub(/\/.*/, "", name)
        if (name in off) next
      }
      { print }
    ' | sort -u
  )"

  WORKSPACE_YAML="$_saved_wy"
  WORKSPACE_LOCAL_YAML="$_saved_wly"

  printf '%s\n' "$_rs_out" | awk 'NF'
}

# ---- Plugin Command Engine (discovery, execution, and listings) -------------

# Check if a plugin exists either in workspace, toolkit, or config.
plugin_exists() {
  _pe_name="$1"
  [ -n "$_pe_name" ] || return 1
  [ -d "$NEXUS_DIR/.rnex/plugins/$_pe_name" ] && return 0
  find_plugin_dir "$_pe_name" >/dev/null 2>&1 && return 0
  yaml_has_plugin "$_pe_name" 2>/dev/null && return 0
  return 1
}

# Locate a custom command executable for a plugin.
# Checks .rnex/plugins/<name>/commands/<command>.sh or <command>,
# falling back to candidate toolkit directories (e.g. toolkit/plugins/<name>/commands/).
plugin_find_command() {
  _pfc_pname="$1"
  _pfc_cmd="$2"
  [ -n "$_pfc_pname" ] && [ -n "$_pfc_cmd" ] || return 1

  # 1. Scoped directory in workspace
  for _cand in \
    "$NEXUS_DIR/.rnex/plugins/$_pfc_pname/commands/${_pfc_cmd}.sh" \
    "$NEXUS_DIR/.rnex/plugins/$_pfc_pname/commands/${_pfc_cmd}"; do
    if [ -f "$_cand" ]; then
      printf '%s' "$_cand"
      return 0
    fi
  done

  # 2. Candidate source plugin directory
  _pdir="$(find_plugin_dir "$_pfc_pname" 2>/dev/null || true)"
  if [ -n "$_pdir" ]; then
    for _cand in \
      "$_pdir/commands/${_pfc_cmd}.sh" \
      "$_pdir/commands/${_pfc_cmd}"; do
      if [ -f "$_cand" ]; then
        printf '%s' "$_cand"
        return 0
      fi
    done
  fi

  return 1
}

# Test if a plugin declares or provides an executable command.
plugin_has_command() {
  _phc_path="$(plugin_find_command "$1" "$2")"
  [ -n "$_phc_path" ] && [ -f "$_phc_path" ]
}

# List all custom command names declared for a plugin.
# Scans commands/ directory in plugin directory and workspace scoped directory,
# and parses any `commands:` section in plugin.yaml.
plugin_list_commands() {
  _plc_pname="$1"
  [ -n "$_plc_pname" ] || return 0

  _plc_cmds=""
  # 1. From workspace scoped commands/
  if [ -d "$NEXUS_DIR/.rnex/plugins/$_plc_pname/commands" ]; then
    for _f in "$NEXUS_DIR/.rnex/plugins/$_plc_pname/commands"/*; do
      [ -f "$_f" ] || continue
      _cname="$(basename "$_f")"
      _cname="${_cname%.sh}"
      case " $_plc_cmds " in
        *" $_cname "*) ;;
        *) _plc_cmds="$_plc_cmds $_cname"; printf '%s\n' "$_cname" ;;
      esac
    done
  fi

  # 2. From plugin definition source directory commands/
  _pdir="$(find_plugin_dir "$_plc_pname" 2>/dev/null || true)"
  if [ -n "$_pdir" ] && [ -d "$_pdir/commands" ]; then
    for _f in "$_pdir/commands"/*; do
      [ -f "$_f" ] || continue
      _cname="$(basename "$_f")"
      _cname="${_cname%.sh}"
      case " $_plc_cmds " in
        *" $_cname "*) ;;
        *) _plc_cmds="$_plc_cmds $_cname"; printf '%s\n' "$_cname" ;;
      esac
    done
  fi

  # 3. From plugin.yaml commands section (if declared)
  if [ -n "$_pdir" ] && [ -f "$_pdir/plugin.yaml" ]; then
    _yaml_cmds="$(awk '
      /^commands:[ ]*$/ || /^commands:[ ]*#/ { in_cmd=1; next }
      in_cmd && /^[^ #]/ { exit }
      in_cmd && /^[ ]*-[ ]*[a-zA-Z0-9_.-]+:/ {
        line = $0
        sub(/^[ ]*-[ ]*/, "", line)
        sub(/:.*/, "", line)
        print line
      }
      in_cmd && /^[ ]*-[ ]*[a-zA-Z0-9_.-]+[ ]*$/ {
        line = $0
        sub(/^[ ]*-[ ]*/, "", line)
        gsub(/[ "]/, "", line)
        print line
      }
      in_cmd && /^[ ]*[a-zA-Z0-9_.-]+:[ ]*/ {
        line = $0
        sub(/^[ ]*/, "", line)
        sub(/:.*/, "", line)
        print line
      }
    ' "$_pdir/plugin.yaml")"
    for _cname in $_yaml_cmds; do
      [ -n "$_cname" ] || continue
      case " $_plc_cmds " in
        *" $_cname "*) ;;
        *) _plc_cmds="$_plc_cmds $_cname"; printf '%s\n' "$_cname" ;;
      esac
    done
  fi
}

# Retrieve the description of a plugin command declared in plugin.yaml.
plugin_get_command_desc() {
  _pgc_pname="$1"
  _pgc_cmd="$2"
  _pdir="$(find_plugin_dir "$_pgc_pname" 2>/dev/null || true)"
  [ -n "$_pdir" ] && [ -f "$_pdir/plugin.yaml" ] || return 0

  awk -v cmd="$_pgc_cmd" '
    /^commands:[ ]*$/ || /^commands:[ ]*#/ { in_cmd=1; next }
    in_cmd && /^[^ #]/ { exit }
    in_cmd && ($0 ~ ("^[ ]*-[ ]*" cmd ":") || $0 ~ ("^[ ]*" cmd ":")) {
      sub(/^[^:]*:[ ]*/, "")
      sub(/[ ]*#.*/, "")
      gsub(/^["\047]|["\047]$/, "")
      print
      exit
    }
  ' "$_pdir/plugin.yaml"
}

# Execute a plugin command, forwarding all arguments and exporting workspace environment variables.
run_plugin_command() {
  _rpc_plugin="$1"
  _rpc_cmd="$2"
  shift 2 2>/dev/null || true

  _rpc_script="$(plugin_find_command "$_rpc_plugin" "$_rpc_cmd")"
  if [ -z "$_rpc_script" ] || [ ! -f "$_rpc_script" ]; then
    die "Command '$_rpc_cmd' not found for plugin '$_rpc_plugin'"
  fi

  chmod +x "$_rpc_script" 2>/dev/null || true

  _rpc_root="${NEXUS_DIR:-${RNEX_ROOT:-$PWD}}"
  _rpc_yaml="${WORKSPACE_YAML:-$_rpc_root/${RNEX_CONFIG_FILE:-rnex.yaml}}"
  _rpc_local_yaml="${WORKSPACE_LOCAL_YAML:-${LOCAL_WORKSPACE_YAML:-$_rpc_root/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}}}"
  _rpc_lib_dir="${RNEX_LIB_DIR:-$_rpc_root/lib}"
  _rpc_args="$*"

  RNEX_PLUGIN_NAME="$_rpc_plugin"
  RNEX_PLUGIN_COMMAND="$_rpc_cmd"
  RNEX_PLUGIN_ARGS="$_rpc_args"
  export RNEX_PLUGIN_NAME RNEX_PLUGIN_COMMAND RNEX_PLUGIN_ARGS

  if command -v run_hook >/dev/null 2>&1; then
    run_hook "before_plugin_command" "$_rpc_plugin" "$_rpc_cmd" "$@"
  fi
  (
    RNEX_ROOT="$_rpc_root"
    NEXUS_DIR="$_rpc_root"
    WORKSPACE_YAML="$_rpc_yaml"
    WORKSPACE_LOCAL_YAML="$_rpc_local_yaml"
    LOCAL_WORKSPACE_YAML="$_rpc_local_yaml"
    RNEX_LIB_DIR="$_rpc_lib_dir"
    RNEX_PLUGIN_NAME="$_rpc_plugin"
    RNEX_PLUGIN_COMMAND="$_rpc_cmd"
    RNEX_PLUGIN_ARGS="$_rpc_args"
    RNEX_PLUGIN_DIR="$_rpc_root/.rnex/plugins/$_rpc_plugin"
    export RNEX_ROOT NEXUS_DIR WORKSPACE_YAML WORKSPACE_LOCAL_YAML LOCAL_WORKSPACE_YAML RNEX_LIB_DIR RNEX_PLUGIN_NAME RNEX_PLUGIN_COMMAND RNEX_PLUGIN_ARGS RNEX_PLUGIN_DIR
    if [ -x "$_rpc_script" ]; then
      "$_rpc_script" "$@"
    else
      sh "$_rpc_script" "$@"
    fi
  )
  _rc=$?
  if [ "$_rc" -eq 0 ] && command -v run_hook >/dev/null 2>&1; then
    run_hook "after_plugin_command" "$_rpc_plugin" "$_rpc_cmd" "$@"
  fi
  return "$_rc"
}
