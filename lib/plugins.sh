#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/plugins.sh — Plugin Engine (discovery, metadata, and scoped synchronization)
# ============================================================================

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
          _v="$(printf '%s' "$_v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
          ;;
      esac
      _res="$(printf '%s' "$_res" | sed -e "s|{$_k}|$_v|g")"
    done
  fi

  # Fallback resolution for core wiki/raw placeholders and legacy prefixes
  _w_val="$(yaml_plugin_get "$_p" "wiki_dir" 2>/dev/null || true)"
  [ -z "$_w_val" ] && _w_val=".rnex/wiki"
  _w_val="$(printf '%s' "$_w_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"

  _r_val="$(yaml_plugin_get "$_p" "raw_dir" 2>/dev/null || true)"
  [ -z "$_r_val" ] && _r_val="docs"
  _r_val="$(printf '%s' "$_r_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"

  _res="$(printf '%s' "$_res" | sed \
    -e "s|{wiki_dir}|${_w_val}|g" \
    -e "s|{raw_dir}|${_r_val}|g" \
    -e "s|^\.\{0,1\}\/\{0,1\}wiki/|${_w_val}/|" \
    -e "s|^\.\{0,1\}\/\{0,1\}raw/|${_r_val}/|")"

  _res="$(printf '%s' "$_res" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##')"

  printf '%s' "$_res"
}

plugin_instantiate_template() {
  _p="$1"; _pd="$2"; _src="$3"; _dest="$4"

  _w_val="$(yaml_plugin_get "$_p" "wiki_dir" 2>/dev/null || true)"
  [ -z "$_w_val" ] && _w_val=".rnex/wiki"
  _w_val="$(printf '%s' "$_w_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^/##' -e 's#/$##')"

  _r_val="$(yaml_plugin_get "$_p" "raw_dir" 2>/dev/null || true)"
  [ -z "$_r_val" ] && _r_val="docs"
  _r_val="$(printf '%s' "$_r_val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"

  sed -e "s|{wiki_dir}|$_w_val|g" \
      -e "s|{raw_dir}|$_r_val|g" \
      "$_src" > "$_dest"
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
  _raw_cfg="$(yaml_plugin_get "karpathy-llm" "raw_dir" 2>/dev/null || true)"
  [ -z "$_raw_cfg" ] && _raw_cfg="docs"
  _raw_cfg="$(printf '%s' "$_raw_cfg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"

  _wiki_cfg="$(yaml_plugin_get "karpathy-llm" "wiki_dir" 2>/dev/null || true)"
  [ -z "$_wiki_cfg" ] && _wiki_cfg=".rnex/wiki"
  _wiki_cfg="$(printf '%s' "$_wiki_cfg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"

  if [ "$_raw_cfg" != "raw" ] && [ -d "$NEXUS_DIR/raw" ]; then
    if ! rmdir "$NEXUS_DIR/raw" 2>/dev/null; then
      _can_clean=1
      for _f in "$NEXUS_DIR/raw"/* "$NEXUS_DIR/raw"/.[!.]* "$NEXUS_DIR/raw"/..?*; do
        [ -e "$_f" ] || continue
        _b="$(basename "$_f")"
        if [ "$_b" = ".gitkeep" ]; then
          continue
        fi
        if [ -f "$NEXUS_DIR/$_raw_cfg/$_b" ] && cmp -s "$_f" "$NEXUS_DIR/$_raw_cfg/$_b"; then
          continue
        fi
        _can_clean=0
        break
      done
      if [ "$_can_clean" -eq 1 ]; then
        rm -rf "$NEXUS_DIR/raw"
        log_dim "Cleaned up obsolete root raw/ directory"
      fi
    else
      log_dim "Removed empty obsolete root raw/ directory"
    fi
  fi

  if [ "$_wiki_cfg" != "wiki" ] && [ -d "$NEXUS_DIR/wiki" ]; then
    if ! rmdir "$NEXUS_DIR/wiki" 2>/dev/null; then
      _can_clean=1
      for _f in "$NEXUS_DIR/wiki"/* "$NEXUS_DIR/wiki"/.[!.]* "$NEXUS_DIR/wiki"/..?*; do
        [ -e "$_f" ] || continue
        _b="$(basename "$_f")"
        case "$_b" in
          index.md|_log.md|hot.md|.gitkeep)
            continue
            ;;
          *)
            if [ -f "$NEXUS_DIR/$_wiki_cfg/$_b" ] && cmp -s "$_f" "$NEXUS_DIR/$_wiki_cfg/$_b"; then
              continue
            fi
            _can_clean=0
            break
            ;;
        esac
      done
      if [ "$_can_clean" -eq 1 ]; then
        rm -rf "$NEXUS_DIR/wiki"
        log_dim "Cleaned up obsolete root wiki/ directory"
      fi
    else
      log_dim "Removed empty obsolete root wiki/ directory"
    fi
  fi

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

    _scoped_dest="$NEXUS_DIR/.rnex/plugins/$_pname"
    if [ "$_pdir" != "$_scoped_dest" ]; then
      mkdir -p "$_scoped_dest"

      # Deterministically sync plugin asset directories (clean stale files; no prompts in plugins)
      rm -rf "${_scoped_dest:?}/prompts" 2>/dev/null || true
      for _sub in rules workflows instructions skills agents templates hooks; do
        if [ -d "$_pdir/$_sub" ]; then
          rm -rf "${_scoped_dest:?}/$_sub"
          mkdir -p "$_scoped_dest/$_sub"
          cp -R "$_pdir/$_sub"/. "$_scoped_dest/$_sub"/ 2>/dev/null || true
          [ "$_sub" = "hooks" ] && chmod +x "$_scoped_dest/hooks"/* 2>/dev/null || true
        else
          rm -rf "${_scoped_dest:?}/$_sub"
        fi
      done

      # Copy plugin manifest, instructions, and documentation
      if [ -f "$_pdir/plugin.yaml" ]; then
        cp "$_pdir/plugin.yaml" "$_scoped_dest/plugin.yaml"
      fi
      if [ -f "$_pdir/instructions.md" ]; then
        cp "$_pdir/instructions.md" "$_scoped_dest/instructions.md"
      fi
      if [ -f "$_pdir/README.md" ]; then
        cp "$_pdir/README.md" "$_scoped_dest/README.md"
      fi
    fi

    # Initialize templates declared in plugin (functional external dirs like raw/, wiki/)
    plugin_list_templates "$_pdir" | while read -r _item; do
      [ -n "$_item" ] || continue
      _s="${_item%%:*}"
      _d="${_item#*:}"
      _s="$(printf '%s' "$_s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"")"
      _d="$(printf '%s' "$_d" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"")"

      _d="$(plugin_resolve_placeholders "$_pname" "$_pdir" "$_d")"

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
        [ -x "$_src_path" ] && chmod +x "$_dest_path" 2>/dev/null || true
        log_ok "Initialized template: $_d"
      fi
    done
  done
}
