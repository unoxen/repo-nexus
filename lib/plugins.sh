#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/plugins.sh — Plugin Engine (discovery, metadata, and scoped synchronization)
# ============================================================================

find_plugin_dir() {
  _query="$1"
  _sdir="$(dirname "$SCRIPT_LOCATION")"
  for _cand in \
    "$NEXUS_DIR/toolkit/plugins/$_query" \
    "$SCRIPT_LOCATION/toolkit/plugins/$_query" \
    "$_sdir/toolkit/plugins/$_query" \
    "$NEXUS_DIR/plugins/$_query" \
    "$NEXUS_DIR/.rnex/plugins/$_query" \
    "$NEXUS_DIR/.nexus/plugins/$_query"; do
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
    "$NEXUS_DIR/toolkit/plugins" \
    "$SCRIPT_LOCATION/toolkit/plugins" \
    "$_sdir/toolkit/plugins" \
    "$NEXUS_DIR/plugins" \
    "$NEXUS_DIR/.rnex/plugins" \
    "$NEXUS_DIR/.nexus/plugins"; do
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

plugin_list_rules() {
  _pdir="$1"
  [ -f "$_pdir/plugin.yaml" ] || return 0
  awk '
    /^(rules|instructions|ai_files):[ ]*(#.*)?$/ { in_sec = 1; next }
    in_sec && /^[^ #]/ { in_sec = 0 }
    in_sec && /^[ ]*-[ ]*/ {
      line = $0
      sub(/^[ ]*-[ ]*/, "", line)
      sub(/[ ]*#.*/, "", line)
      if (length(line) > 0) print line
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
      if (length($0) > 0) print $0
    }
  ' "$_pdir/plugin.yaml"
}

karpathy_wiki_dir() {
  _d="$(yaml_plugin_get "karpathy-llm" "wiki_dir" 2>/dev/null || true)"
  _d="$(printf '%s' "$_d" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#^/##' -e 's#/$##')"
  if [ -n "$_d" ]; then
    printf '%s' "$_d"
  else
    printf '.rnex/wiki'
  fi
}

karpathy_raw_dir() {
  _d="$(yaml_plugin_get "karpathy-llm" "raw_dir" 2>/dev/null || true)"
  _d="$(printf '%s' "$_d" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
  if [ -n "$_d" ]; then
    printf '%s' "$_d"
  else
    printf 'docs'
  fi
}

# Sync plugins into scoped directories: .rnex/plugins/<plugin-name>/
sync_plugins() {
  _wiki_dir="$(karpathy_wiki_dir)"
  _raw_dir="$(karpathy_raw_dir)"

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
      _s="$(printf '%s' "$_s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      _d="$(printf '%s' "$_d" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

      # Resolve dynamic destination placeholders for wiki and raw directories
      _d="$(printf '%s' "$_d" | sed \
        -e "s|{wiki_dir}|$_wiki_dir|g" \
        -e "s|{raw_dir}|$_raw_dir|g" \
        -e "s|^wiki/|${_wiki_dir}/|" \
        -e "s|^raw/|${_raw_dir}/|")"

      _src_path="$_pdir/$_s"
      _dest_path="$NEXUS_DIR/$_d"

      if [ -f "$_src_path" ] && [ ! -f "$_dest_path" ]; then
        mkdir -p "$(dirname "$_dest_path")"
        sed -e "s|{wiki_dir}|$_wiki_dir|g" \
            -e "s|{raw_dir}|$_raw_dir|g" \
            -e "s|/raw/|/$_raw_dir/|g" \
            -e "s|raw/|$_raw_dir/|g" \
            -e "s|/wiki/|/$_wiki_dir/|g" \
            -e "s|wiki/|$_wiki_dir/|g" \
            "$_src_path" > "$_dest_path"
        [ -x "$_src_path" ] && chmod +x "$_dest_path" 2>/dev/null || true
        log_ok "Initialized template: $_d"
      fi
    done
  done
}
