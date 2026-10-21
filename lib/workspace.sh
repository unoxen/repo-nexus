#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/workspace.sh — Workspace detection, context loading, and configuration upgrade
# ============================================================================

RNEX_CONFIG_FILE="rnex.yaml"
RNEX_LOCAL_CONFIG_FILE=".local.rnex.yaml"

# ---- Workspace Detection (Context-Aware) ----------------------------------

find_workspace_dir() {
  _curr="$(pwd -P 2>/dev/null || pwd)"
  while [ -n "$_curr" ] && [ "$_curr" != "/" ]; do
    if [ -f "$_curr/$RNEX_CONFIG_FILE" ] || [ -f "$_curr/.rnex.yaml" ]; then
      printf '%s' "$_curr"
      return 0
    fi
    _curr="$(dirname "$_curr")"
  done
  if [ -f "/$RNEX_CONFIG_FILE" ] || [ -f "/.rnex.yaml" ]; then
    printf '/'
    return 0
  fi
  return 1
}

# ---- Config Checksum & Sync Stamp -----------------------------------------

get_config_sum() {
  _dir="${1:-${NEXUS_DIR:-.}}"
  _yaml="rnex.yaml"
  if [ -n "$CUSTOM_CONFIG" ]; then
    _yaml="$(basename "$CUSTOM_CONFIG")"
  elif [ -n "$WORKSPACE_YAML" ]; then
    _yaml="$(basename "$WORKSPACE_YAML")"
  fi
  ( cd "$_dir" 2>/dev/null && cksum "$_yaml" .local.rnex.yaml 2>/dev/null | cksum | awk '{print $1, $2}' )
}

update_sync_stamp() {
  _dir="${1:-${NEXUS_DIR:-.}}"
  mkdir -p "$_dir/.rnex"
  if [ ! -f "$_dir/.rnex/.gitignore" ]; then
    printf ".sync_stamp\nsync_stamp\n" > "$_dir/.rnex/.gitignore"
  else
    if ! grep -q "^\.sync_stamp" "$_dir/.rnex/.gitignore" 2>/dev/null; then
      printf ".sync_stamp\n" >> "$_dir/.rnex/.gitignore"
    fi
    if ! grep -q "^sync_stamp" "$_dir/.rnex/.gitignore" 2>/dev/null; then
      printf "sync_stamp\n" >> "$_dir/.rnex/.gitignore"
    fi
  fi
  _csum="$(get_config_sum "$_dir")"
  printf '%s\n' "$_csum" > "$_dir/.rnex/sync_stamp"
  rm -f "$_dir/.rnex/.sync_stamp"
}

check_auto_sync() {
  _ws="${NEXUS_DIR:-}"
  if [ -z "$_ws" ]; then
    if [ -n "$CUSTOM_CONFIG" ]; then
      _cfg_path="$(resolve_path "$CUSTOM_CONFIG" 2>/dev/null || true)"
      if [ -f "$_cfg_path" ]; then
        _ws="$(cd -P "$(dirname "$_cfg_path")" 2>/dev/null && pwd -P)"
      fi
    elif [ -f rnex.yaml ]; then
      _ws="."
    else
      _ws="$(find_workspace_dir 2>/dev/null || true)"
    fi
  fi
  [ -z "$_ws" ] && return 0
  _cfg_file="$_ws/rnex.yaml"
  if [ -n "$CUSTOM_CONFIG" ]; then
    _cfg_file="$(resolve_path "$CUSTOM_CONFIG" 2>/dev/null || true)"
  fi
  [ -f "$_cfg_file" ] || return 0
  _stamp="$_ws/.rnex/sync_stamp"
  [ -f "$_stamp" ] || _stamp="$_ws/.rnex/.sync_stamp"
  if [ ! -f "$_stamp" ] || [ "$(get_config_sum "$_ws")" != "$(cat "$_stamp" 2>/dev/null)" ]; then
    cmd_sync -y --quiet
  fi
}

auto_sync_if_needed() {
  check_auto_sync "$@"
}

require_workspace() {
  if [ -n "$CUSTOM_CONFIG" ]; then
    _cfg_path="$(resolve_path "$CUSTOM_CONFIG")"
    if [ ! -f "$_cfg_path" ]; then
      die "Specified config file does not exist: $_cfg_path"
    fi
    NEXUS_DIR="$(cd -P "$(dirname "$_cfg_path")" 2>/dev/null && pwd -P)"
    WORKSPACE_YAML="$_cfg_path"
    _init_local_yaml
    _load_workspace_version
    _load_repos_dir
    _load_code_workspace
    _load_git_hooks
    log_info "Using workspace at ${_BOLD}$NEXUS_DIR${_NC} ${_DIM}(via config: $WORKSPACE_YAML)${_NC}"
    return 0
  fi

  _found_dir="$(find_workspace_dir || true)"
  if [ -z "$_found_dir" ]; then
    log_err "No '$RNEX_CONFIG_FILE' found in current directory ($PWD) or parent directories."
    log_dim "To initialize a new Repo Nexus workspace here, run:"
    log_dim "  rnex init"
    log_dim "Or specify a workspace config file directly:"
    log_dim "  rnex --config /path/to/$RNEX_CONFIG_FILE <command>"
    log_dim "Or change directory to an existing workspace:"
    log_dim "  cd /path/to/workspace"
    exit 1
  fi

  NEXUS_DIR="$_found_dir"
  if [ -f "$NEXUS_DIR/$RNEX_CONFIG_FILE" ]; then
    WORKSPACE_YAML="$NEXUS_DIR/$RNEX_CONFIG_FILE"
  elif [ -f "$NEXUS_DIR/.rnex.yaml" ]; then
    WORKSPACE_YAML="$NEXUS_DIR/.rnex.yaml"
  else
    WORKSPACE_YAML="$NEXUS_DIR/$RNEX_CONFIG_FILE"
  fi
  _init_local_yaml
  _load_workspace_version
  _load_repos_dir
  _load_code_workspace
  _load_git_hooks

  log_info "Using workspace at ${_BOLD}$NEXUS_DIR${_NC} ${_DIM}($(basename "$WORKSPACE_YAML") found)${_NC}"
}

_init_local_yaml() {
  if [ -f "$NEXUS_DIR/$RNEX_LOCAL_CONFIG_FILE" ]; then
    WORKSPACE_LOCAL_YAML="$NEXUS_DIR/$RNEX_LOCAL_CONFIG_FILE"
  elif [ -f "$NEXUS_DIR/.rnex.local.yaml" ]; then
    WORKSPACE_LOCAL_YAML="$NEXUS_DIR/.rnex.local.yaml"
  else
    WORKSPACE_LOCAL_YAML="$NEXUS_DIR/$RNEX_LOCAL_CONFIG_FILE"
  fi
}

_load_workspace_version() {
  _wv=""
  if [ -f "$WORKSPACE_LOCAL_YAML" ]; then
    _wv="$(awk '/^version:/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$WORKSPACE_LOCAL_YAML")"
  fi
  if [ -z "$_wv" ] && [ -f "$WORKSPACE_YAML" ]; then
    _wv="$(awk '/^version:/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$WORKSPACE_YAML")"
  fi
  _wv="$(echo "$_wv" | tr -d " \t\r\n'\"")"
  WORKSPACE_CONFIG_VERSION="$_wv"
}

_load_repos_dir() {
  _rd=""
  if [ -f "$WORKSPACE_LOCAL_YAML" ]; then
    _rd="$(awk '/^repos_dir:/ { sub(/^repos_dir:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$WORKSPACE_LOCAL_YAML")"
  fi
  if [ -z "$_rd" ] && [ -f "$WORKSPACE_YAML" ]; then
    _rd="$(awk '/^repos_dir:/ { sub(/^repos_dir:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$WORKSPACE_YAML")"
  fi
  _rd="${_rd:-./repos}"
  case "$_rd" in
    /*) REPOS_DIR="$_rd" ;;
    *)  REPOS_DIR="$NEXUS_DIR/$_rd" ;;
  esac
}

_load_code_workspace() {
  _cw=""
  if [ -f "$WORKSPACE_LOCAL_YAML" ]; then
    _cw="$(awk '/^(code_workspace|vscode_workspace):/ { sub(/^[a-zA-Z0-9_]+:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$WORKSPACE_LOCAL_YAML")"
  fi
  if [ -z "$_cw" ] && [ -f "$WORKSPACE_YAML" ]; then
    _cw="$(awk '/^(code_workspace|vscode_workspace):/ { sub(/^[a-zA-Z0-9_]+:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$WORKSPACE_YAML")"
  fi
  _cw="$(echo "$_cw" | tr -d " \t\r\n'\"")"
  case "$_cw" in
    true|yes|1)
      _ws_basename="$(basename "$NEXUS_DIR")"
      CODE_WORKSPACE_FILE="$_ws_basename.code-workspace"
      ;;
    false|no|0|none|"")
      CODE_WORKSPACE_FILE=""
      ;;
    *)
      case "$_cw" in
        *.code-workspace) CODE_WORKSPACE_FILE="$_cw" ;;
        *) CODE_WORKSPACE_FILE="$_cw.code-workspace" ;;
      esac
      ;;
  esac
}

_load_git_hooks() {
  _gh=""
  if [ -f "$WORKSPACE_LOCAL_YAML" ]; then
    _gh="$(awk '/^(git_hooks|hooks):/ { sub(/^[a-zA-Z0-9_]+:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$WORKSPACE_LOCAL_YAML")"
  fi
  if [ -z "$_gh" ] && [ -f "$WORKSPACE_YAML" ]; then
    _gh="$(awk '/^(git_hooks|hooks):/ { sub(/^[a-zA-Z0-9_]+:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$WORKSPACE_YAML")"
  fi
  _gh="$(echo "$_gh" | tr -d " \t\r\n'\"")"
  GIT_HOOKS_CONFIG="$_gh"
}

migrate_karpathy_llm_config() {
  _mkc_f="$1"
  [ -f "$_mkc_f" ] || return 0

  _mkc_has_sources=0
  if command -v _yaml_plugin_list_from_file >/dev/null 2>&1; then
    [ -n "$(_yaml_plugin_list_from_file "$_mkc_f" "karpathy-llm" "sources")" ] && _mkc_has_sources=1
  elif grep -q '^[ \t]*sources:[ \t]*' "$_mkc_f" 2>/dev/null; then
    _mkc_has_sources=1
  fi

  _mkc_tmp="$(mktemp)"
  awk -v has_sources="$_mkc_has_sources" '
    /^[ \t]*plugins:[ \t]*(#.*)?$/ { in_plugins=1; in_target=0; plugin_indent=-1; print; next }
    in_plugins && /^[^ \t#]/ { in_plugins=0; in_target=0 }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^ingest_member_readmes:[ \t]*/ {
      next
    }
    !in_plugins || trimmed ~ /^([#]|$)/ {
      print
      next
    }

    in_target && (indent <= plugin_indent) {
      in_target=0
    }

    !in_target {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == "karpathy-llm" && trimmed ~ /:[ \t]*(#.*)?$/) {
        in_target=1
        plugin_indent=indent
      }
      print
      next
    }

    in_target && (indent > plugin_indent) {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == "raw_dir" && trimmed ~ /:[ \t]*/) {
        if (has_sources == 1) {
          next
        }
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
        while (sub(/^\.\//, "", val)) {}
        if (val != "." && val != "/") {
          sub(/\/+$/, "", val)
        }
        if (length(val) == 0) val = "docs"
        ind = substr($0, 1, indent)
        if (val ~ /[*?\[]|[ \t]/) {
          printf "%ssources:\n%s  - \"%s\"\n", ind, ind, val
        } else {
          printf "%ssources:\n%s  - %s\n", ind, ind, val
        }
        has_sources=1
        next
      }
    }
    { print }
  ' "$_mkc_f" > "$_mkc_tmp"

  if ! cmp -s "$_mkc_f" "$_mkc_tmp"; then
    mv "$_mkc_tmp" "$_mkc_f"
  else
    rm -f "$_mkc_tmp"
  fi
}

upgrade_workspace_config() {
  _f="$1"
  _ver="$2"
  [ -f "$_f" ] || return 0

  _tmp="$(mktemp)"

  # 1. Update or insert version
  if grep -q '^[ ]*version:' "$_f" 2>/dev/null; then
    awk -v ver="$_ver" '
      /^[ ]*version:[ ]*/ { print "version: " ver; next }
      { print }
    ' "$_f" > "$_tmp" && mv "$_tmp" "$_f"
  else
    awk -v ver="$_ver" '
      BEGIN { inserted=0 }
      /^[^#]/ && !inserted {
        print "# Workspace version"
        print "version: " ver
        print ""
        inserted=1
      }
      { print }
      END {
        if (!inserted) {
          print ""
          print "# Workspace version"
          print "version: " ver
        }
      }
    ' "$_f" > "$_tmp" && mv "$_tmp" "$_f"
  fi

  # 2. Check for legacy ai_instructions: if set, migrate to provider plugin and remove
  if grep -q '^[ ]*\(ai_instructions\|ai_instructions_file\):' "$_f" 2>/dev/null; then
    _old_aif="$(awk '/^[ ]*(ai_instructions|ai_instructions_file):/ { sub(/^[a-zA-Z0-9_]+:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$_f" | tr -d " \t\r\n'\"")"
    case "$_old_aif" in
      CLAUDE.md|claude)
        yaml_enable_plugin "claude" "$_f"
        ;;
      GEMINI.md|gemini)
        yaml_enable_plugin "gemini" "$_f"
        ;;
      .cursorrules|cursor)
        yaml_enable_plugin "cursor" "$_f"
        ;;
    esac
    awk '!/^[ ]*(ai_instructions|ai_instructions_file):/' "$_f" > "$_tmp" && mv "$_tmp" "$_f"
  fi

  # 3. Add code_workspace if missing
  if ! grep -q '^[ ]*\(code_workspace\|vscode_workspace\):' "$_f" 2>/dev/null; then
    awk '
      BEGIN { inserted=0 }
      /^[ ]*(plugins|repos):/ && !inserted {
        print "# VS Code / Cursor multi-root workspace file (default: false; e.g. true or workspace.code-workspace)"
        print "code_workspace: false"
        print ""
        inserted=1
      }
      { print }
      END {
        if (!inserted) {
          print ""
          print "code_workspace: false"
        }
      }
    ' "$_f" > "$_tmp" && mv "$_tmp" "$_f"
  fi

  # 4. Add git_hooks if missing
  if ! grep -q '^[ ]*\(git_hooks\|hooks\):' "$_f" 2>/dev/null; then
    _def_gh="false"
    _cur_hp="$(git -C "$NEXUS_DIR" config --get core.hooksPath 2>/dev/null || true)"
    if [ "$_cur_hp" = ".rnex/hooks" ] || [ "$_cur_hp" = "$NEXUS_DIR/.rnex/hooks" ]; then
      _def_gh="true"
    fi
    awk -v def_gh="$_def_gh" '
      BEGIN { inserted=0 }
      /^[ ]*(plugins|repos):/ && !inserted {
        print "# Automated workspace Git hooks (default: true; e.g. post-merge auto-sync, plugin triggers)"
        print "git_hooks: " def_gh
        print ""
        inserted=1
      }
      { print }
      END {
        if (!inserted) {
          print ""
          print "git_hooks: " def_gh
        }
      }
    ' "$_f" > "$_tmp" && mv "$_tmp" "$_f"
  fi

  # 5. Migrate legacy karpathy-llm raw_dir to sources and strip obsolete ingest_member_readmes
  migrate_karpathy_llm_config "$_f"

  rm -f "$_tmp"
}
