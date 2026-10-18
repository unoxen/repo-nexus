#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/plugin.sh — Plugin management commands
# ============================================================================

cmd_plugin_list() {
  require_workspace
  printf '\n%b%s%b\n' "$_B" "Repo Nexus Plugins" "$_NC"
  printf '=%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18
  printf '\n\n'

  list_all_available_plugin_dirs | while read -r _pdir; do
    [ -n "$_pdir" ] || continue
    _name="$(plugin_get_field "$_pdir" "name")"
    [ -n "$_name" ] || _name="$(basename "$_pdir")"
    _version="$(plugin_get_field "$_pdir" "version")"
    _desc="$(plugin_get_field "$_pdir" "description")"

    if yaml_plugin_enabled "$_name"; then
      printf '  %b[enabled]%b   %b%-15s%b %b(v%s)%b - %s\n' \
        "$_G" "$_NC" "$_BOLD" "$_name" "$_NC" "$_DIM" "${_version:-0.1.0}" "$_NC" "$_desc"
    elif yaml_has_plugin "$_name"; then
      printf '  %b[disabled]%b  %b%-15s%b %b(v%s)%b - %s\n' \
        "$_Y" "$_NC" "$_BOLD" "$_name" "$_NC" "$_DIM" "${_version:-0.1.0}" "$_NC" "$_desc"
    else
      printf '  %b[available]%b %b%-15s%b %b(v%s)%b - %s\n' \
        "$_DIM" "$_NC" "$_BOLD" "$_name" "$_NC" "$_DIM" "${_version:-0.1.0}" "$_NC" "$_desc"
    fi
  done
  printf '\n'
  log_dim "To enable a plugin:  rnex plugin enable <name>"
  log_dim "To view details:    rnex plugin info <name>"
  log_dim "To disable:         rnex plugin disable <name>"
  printf '\n'
}

cmd_plugin_info() {
  require_workspace
  _pname="$1"
  [ -n "$_pname" ] || die "Usage: rnex plugin info <name>"

  _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
  [ -n "$_pdir" ] || die "Plugin '$_pname' not found."

  _name="$(plugin_get_field "$_pdir" "name")"
  [ -n "$_name" ] || _name="$_pname"
  _ver="$(plugin_get_field "$_pdir" "version")"
  _desc="$(plugin_get_field "$_pdir" "description")"
  _author="$(plugin_get_field "$_pdir" "author")"
  _home="$(plugin_get_field "$_pdir" "homepage")"

  if yaml_plugin_enabled "$_name"; then
    _status="${_G}enabled${_NC}"
  elif yaml_has_plugin "$_name"; then
    _status="${_DIM}disabled in configuration${_NC}"
  else
    _status="${_DIM}available (not enabled)${_NC}"
  fi

  printf '\n'
  printf '%bPlugin:%b       %b%s%b %b(v%s)%b\n' "$_BOLD" "$_NC" "$_BOLD" "$_name" "$_NC" "$_DIM" "${_ver:-0.1.0}" "$_NC"
  printf '%bStatus:%b       %b\n' "$_BOLD" "$_NC" "$_status"
  [ -n "$_desc" ] && printf '%bDescription:%b  %s\n' "$_BOLD" "$_NC" "$_desc"
  [ -n "$_author" ] && printf '%bAuthor:%b       %s\n' "$_BOLD" "$_NC" "$_author"
  [ -n "$_home" ] && printf '%bHomepage:%b     %s\n' "$_BOLD" "$_NC" "$_home"
  printf '%bLocation:%b     %s\n' "$_BOLD" "$_NC" "$_pdir"

  _skill_target="$(plugin_get_field "$_pdir" "skill_dir" 2>/dev/null || true)"
  [ -z "$_skill_target" ] && case "$_name" in
    copilot)  _skill_target=".github/skills/" ;;
    claude)   _skill_target=".claude/skills/" ;;
    gemini)   _skill_target=".gemini/skills/" ;;
    cursor)   _skill_target=".cursor/rules/" ;;
    windsurf) _skill_target=".windsurf/rules/" ;;
  esac
  case "$_skill_target" in
    */|"") ;;
    *) _skill_target="${_skill_target}/" ;;
  esac

  if [ -f "$_pdir/plugin.yaml" ]; then
    _cfg_lines="$(awk '
      /^config_descriptions:[ ]*$/ || /^config_descriptions:[ ]*#/ { in_d=1; next }
      in_d && /^[^ #]/ { exit }
      in_d && /^[ ]*[a-zA-Z0-9_.-]+:[ ]*/ {
        print $0
      }
    ' "$_pdir/plugin.yaml")"

    if [ -n "$_cfg_lines" ]; then
      printf '\n%bConfigurable Options (in rnex.yaml or .local.rnex.yaml):%b\n' "$_BOLD" "$_NC"
      echo "$_cfg_lines" | while read -r _cline; do
        [ -n "$_cline" ] || continue
        _opt="${_cline%%:*}"
        _opt="$(printf '%s' "$_opt" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        _desc="${_cline#*:}"
        _desc="$(printf '%s' "$_desc" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
        [ -n "$_skill_target" ] && _desc="$(printf '%s' "$_desc" | sed -e "s|{skill_dir}|$_skill_target|g")"

        _cur="$(yaml_plugin_get "$_name" "$_opt" 2>/dev/null || true)"
        if [ -z "$_cur" ]; then
          _cur="$(awk -v k="$_opt" '
            /^config_defaults:[ ]*$/ || /^config_defaults:[ ]*#/ { in_c=1; next }
            in_c && /^[^ #]/ { exit }
            in_c && $0 ~ ("^[ ]*" k ":") {
              sub("^[ ]*" k ":[ ]*", "")
              sub(/[ ]*#.*/, "")
              gsub(/^["\047]|["\047]$/, "")
              print
              exit
            }
          ' "$_pdir/plugin.yaml")"
        fi
        case "$_opt" in
          *_dir|dir)
            _cur="$(printf '%s' "$_cur" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
            ;;
        esac
        printf '  - %s: %s  (current: %s)\n' "$_opt" "$_desc" "${_cur:-default}"
      done
    fi
  fi

  printf '\n%bScoped Directory:%b .rnex/plugins/%s\n' "$_BOLD" "$_NC" "$_name"

  _tmpl="$(plugin_list_templates "$_pdir")"
  if [ -n "$_tmpl" ]; then
    printf '\n%bExternal Directories & Templates:%b\n' "$_BOLD" "$_NC"
    echo "$_tmpl" | while read -r _item; do
      [ -n "$_item" ] || continue
      _s="${_item%%:*}"
      _d="${_item#*:}"
      _s="$(printf '%s' "$_s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"")"
      _d="$(printf '%s' "$_d" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"")"
      _d="$(plugin_resolve_placeholders "$_name" "$_pdir" "$_d")"
      printf '  - %s → %s\n' "$_s" "$_d"
    done
  fi
  printf '\n'
}

cmd_plugin_enable() {
  require_workspace
  _is_local=0
  _pname=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --local) _is_local=1 ;;
      *) _pname="$1" ;;
    esac
    shift
  done
  [ -n "$_pname" ] || die "Usage: rnex plugin enable [--local] <name>"

  _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
  [ -n "$_pdir" ] || die "Plugin '$_pname' not found."

  _name="$(plugin_get_field "$_pdir" "name")"
  [ -n "$_name" ] || _name="$_pname"

  if [ "$_is_local" -eq 1 ]; then
    yaml_enable_plugin "$_name" "$WORKSPACE_LOCAL_YAML"
    log_ok "Plugin '$_name' enabled locally in $(basename "$WORKSPACE_LOCAL_YAML")"
  else
    yaml_enable_plugin "$_name" "$WORKSPACE_YAML"
    log_ok "Plugin '$_name' enabled in $(basename "$WORKSPACE_YAML")"
  fi

  cmd_sync
  run_plugin_hook "$_name" "after_sync"
  log_ok "Plugin '$_name' active in workspace (.rnex/plugins/$_name)"
}

cmd_plugin_disable() {
  require_workspace
  _is_local=0
  _pname=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --local) _is_local=1 ;;
      *) _pname="$1" ;;
    esac
    shift
  done
  [ -n "$_pname" ] || die "Usage: rnex plugin disable [--local] <name>"

  _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
  _name="$_pname"
  if [ -n "$_pdir" ]; then
    _n="$(plugin_get_field "$_pdir" "name")"
    [ -n "$_n" ] && _name="$_n"
  fi

  # Dispatch before_plugin_disable plugin lifecycle hook
  run_plugin_hook "$_name" "before_plugin_disable"

  if [ "$_is_local" -eq 1 ]; then
    if _yaml_list_plugins_from_file "$WORKSPACE_YAML" | grep -qx "$_name" 2>/dev/null; then
      yaml_plugin_set_local "$_name" "enabled" "false"
      log_ok "Plugin '$_name' disabled locally in $(basename "$WORKSPACE_LOCAL_YAML")"
    else
      _yaml_disable_plugin_in_file "$WORKSPACE_LOCAL_YAML" "$_name"
      log_ok "Plugin '$_name' removed from $(basename "$WORKSPACE_LOCAL_YAML")"
    fi
  else
    yaml_disable_plugin "$_name"
    log_ok "Plugin '$_name' disabled from workspace"
  fi

  cmd_sync -q
}

cmd_rnex_dir() {
  require_workspace
  _action=""
  _name=""
  _is_local=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --local) _is_local=1 ;;
      enable|disable)
        if [ -z "$_action" ]; then
          _action="$1"
        elif [ -z "$_name" ]; then
          _name="$1"
        fi
        ;;
      *)
        if [ -z "$_action" ]; then
          _action="$1"
        elif [ -z "$_name" ]; then
          _name="$1"
        else
          die "Unexpected argument: $1"
        fi
        ;;
    esac
    shift
  done

  case "$_action" in
    enable)
      [ -n "$_name" ] || die "Usage: rnex rnex-dir <enable|disable> <name> [--local]"
      yaml_has_repo "$_name" || die "Repo '$_name' is not registered"
      if [ "$_is_local" -eq 1 ]; then
        yaml_set_local "$_name" "rnex_dir" "true"
        log_ok "Enabled member .rnex directory for '$_name' locally in $(basename "$WORKSPACE_LOCAL_YAML")"
      else
        yaml_set "$_name" "rnex_dir" "true"
        log_ok "Enabled member .rnex directory for '$_name' in $(basename "$WORKSPACE_YAML")"
      fi
      sync_repo_rnex "$_name"
      ;;
    disable)
      [ -n "$_name" ] || die "Usage: rnex rnex-dir <enable|disable> <name> [--local]"
      yaml_has_repo "$_name" || die "Repo '$_name' is not registered"
      if [ "$_is_local" -eq 1 ]; then
        yaml_set_local "$_name" "rnex_dir" "false"
        log_ok "Disabled member .rnex directory for '$_name' locally in $(basename "$WORKSPACE_LOCAL_YAML")"
      else
        yaml_set "$_name" "rnex_dir" "false"
        log_ok "Disabled member .rnex directory for '$_name' in $(basename "$WORKSPACE_YAML")"
      fi
      clean_repo_rnex "$_name"
      ;;
    *)
      die "Usage: rnex rnex-dir <enable|disable> <name> [--local]"
      ;;
  esac
}

cmd_plugin_update() {
  require_workspace
  _update_pname="$1"
  if [ -n "$_update_pname" ]; then
    yaml_has_plugin "$_update_pname" || die "Plugin '$_update_pname' is not enabled in workspace"
    _pdir="$(find_plugin_dir "$_update_pname" 2>/dev/null || true)"
    [ -n "$_pdir" ] || die "Plugin '$_update_pname' not found."
    log_info "Updating plugin '$_update_pname'..."
    cmd_sync
    run_plugin_hook "$_update_pname" "after_sync"
    log_ok "Plugin '$_update_pname' updated"
  else
    log_info "Updating all enabled plugins..."
    cmd_sync
    run_hook "after_sync"
    log_ok "All plugins updated"
  fi
}

cmd_plugin() {
  _subcmd="${1:-list}"
  shift 2>/dev/null || true
  case "$_subcmd" in
    list)                      cmd_plugin_list "$@" ;;
    info)                      cmd_plugin_info "$@" ;;
    enable|install)            cmd_plugin_enable "$@" ;;
    disable|uninstall|remove)  cmd_plugin_disable "$@" ;;
    update|upgrade)            cmd_plugin_update "$@" ;;
    *)                         die "Unknown plugin subcommand: $_subcmd (try 'rnex plugin list')" ;;
  esac
}
