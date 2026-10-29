#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/plugin.sh — Plugin management commands
# ============================================================================

# List all available, enabled, and disabled plugins found in the workspace toolkit.
cmd_plugin_list() {
  require_workspace
  printf '\n%b%s%b\n' "$_B" "Repo Nexus Plugins" "$_NC"
  printf '=%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18
  printf '\n\n'

  list_all_available_plugin_dirs | while read -r _pdir; do
    [ -n "$_pdir" ] || continue
    _name="$(plugin_get_field "$_pdir" "name")"
    [ -n "$_name" ] || _name="$(basename "$_pdir")"
    _version="$(plugin_get_version "$_name" "$_pdir")"
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

    _pcmds="$(plugin_list_commands "$_name" 2>/dev/null || true)"
    if [ -n "$_pcmds" ]; then
      echo "$_pcmds" | while read -r _c; do
        [ -n "$_c" ] || continue
        _cdesc="$(plugin_get_command_desc "$_name" "$_c" 2>/dev/null || true)"
        if [ -n "$_cdesc" ]; then
          printf '                 %b↳ rnex plugin %s %-10s%b %s\n' "$_DIM" "$_name" "$_c" "$_NC" "$_cdesc"
        else
          printf '                 %b↳ rnex plugin %s %s%b\n' "$_DIM" "$_name" "$_c" "$_NC"
        fi
      done
    fi
  done
  printf '\n'
  log_dim "To enable a plugin:  rnex plugin enable <name>"
  log_dim "To view details:    rnex plugin info <name>"
  log_dim "To disable:         rnex plugin disable <name>"
  log_dim "To run commands:    rnex plugin <name> <command> [options...]"
  printf '\n'
}

# Display detailed metadata, configurable options, and template paths for a specific plugin.
cmd_plugin_info() {
  require_workspace
  _pname="$1"
  [ -n "$_pname" ] || die "Usage: rnex plugin info <name>"

  _pdir="$(plugin_resolve_dir "$_pname" 2>/dev/null || true)"
  [ -n "$_pdir" ] || _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
  [ -n "$_pdir" ] || die "Plugin '$_pname' not found."

  _name="$(plugin_get_field "$_pdir" "name")"
  [ -n "$_name" ] || _name="$_pname"
  _ver="$(plugin_get_version "$_name" "$_pdir")"
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

  _skill_target="$(plugin_get_skill_dir "$_name" "$_pdir")"
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
          # List-valued options (e.g. sources): show the effective list, comma-separated
          _cur="$(get_plugin_config_list "$_name" "$_opt" 2>/dev/null | awk '{ out = (NR == 1) ? $0 : out ", " $0 } END { if (NR) print out }')"
        fi
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
          *_dir)
            _cur="$(printf '%s' "$_cur" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
            ;;
        esac
        printf '  - %s: %s  (current: %s)\n' "$_opt" "$_desc" "${_cur:-default}"
      done
    fi
  fi

  printf '\n%bScoped Directory:%b .rnex/plugins/%s\n' "$_BOLD" "$_NC" "$_name"

  _cmds="$(plugin_list_commands "$_name" 2>/dev/null || true)"
  if [ -n "$_cmds" ]; then
    printf '\n%bCommands:%b\n' "$_BOLD" "$_NC"
    echo "$_cmds" | while read -r _c; do
      [ -n "$_c" ] || continue
      _cdesc="$(plugin_get_command_desc "$_name" "$_c")"
      if [ -n "$_cdesc" ]; then
        printf '  - rnex plugin %s %-12s - %s\n' "$_name" "$_c" "$_cdesc"
      else
        printf '  - rnex plugin %s %s\n' "$_name" "$_c"
      fi
    done
  fi

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

# Enable a plugin in workspace configuration (team or local) and sync assets.
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

  _pdir="$(plugin_resolve_dir "$_pname" 2>/dev/null || true)"
  [ -n "$_pdir" ] || _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
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

# Disable a plugin, dispatch before_plugin_disable hook, and prune its assets.
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

  _pdir="$(plugin_resolve_dir "$_pname" 2>/dev/null || true)"
  [ -n "$_pdir" ] || _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
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

cmd_plugin_update() {
  require_workspace
  _update_pname="$1"
  if [ -n "$_update_pname" ]; then
    yaml_has_plugin "$_update_pname" || die "Plugin '$_update_pname' is not enabled in workspace"
    _pdir="$(plugin_resolve_dir "$_update_pname" 2>/dev/null || true)"
    [ -n "$_pdir" ] || _pdir="$(find_plugin_dir "$_update_pname" 2>/dev/null || true)"
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

cmd_plugin_help() {
  printf '\n%bUsage:%b rnex plugin <action|plugin> [command] [options...]\n\n' "$_BOLD" "$_NC"
  printf '%bPlugin Lifecycle Actions:%b\n' "$_BOLD" "$_NC"
  printf '  rnex plugin list                         List available, enabled, and disabled plugins\n'
  printf '  rnex plugin info <name>                  Display metadata, commands, and options for a plugin\n'
  printf '  rnex plugin enable [--local] <name>      Enable a plugin in workspace\n'
  printf '  rnex plugin disable [--local] <name>     Disable a plugin\n'
  printf '  rnex plugin update [<name>]              Update enabled plugin(s)\n\n'
  printf '%bPlugin Commands:%b\n' "$_BOLD" "$_NC"
  printf '  rnex plugin <name> <command> [opts...]   Execute a command provided by a plugin\n'
  printf '  rnex plugin <command> [opts...]          Execute command (shorthand across enabled plugins)\n\n'
}

cmd_plugin() {
  require_workspace
  _action="${1:-list}"

  case "$_action" in
    list)
      shift
      cmd_plugin_list "$@"
      return $?
      ;;
    info)
      shift
      cmd_plugin_info "$@"
      return $?
      ;;
    enable|install)
      shift
      _h_pname=""
      for _arg in "$@"; do
        case "$_arg" in --*) ;; *) _h_pname="$_arg" ;; esac
      done
      RNEX_PLUGIN_NAME="$_h_pname"
      export RNEX_PLUGIN_NAME
      run_hook "before_plugin_enable" "$@"
      cmd_plugin_enable "$@"
      _rc=$?
      [ "$_rc" -eq 0 ] && run_hook "after_plugin_enable" "$@"
      return "$_rc"
      ;;
    disable|uninstall|remove)
      shift
      _h_pname=""
      for _arg in "$@"; do
        case "$_arg" in --*) ;; *) _h_pname="$_arg" ;; esac
      done
      RNEX_PLUGIN_NAME="$_h_pname"
      export RNEX_PLUGIN_NAME
      run_hook "before_plugin_disable" "$@"
      cmd_plugin_disable "$@"
      _rc=$?
      [ "$_rc" -eq 0 ] && run_hook "after_plugin_disable" "$@"
      return "$_rc"
      ;;
    update|upgrade)
      shift
      cmd_plugin_update "$@"
      return $?
      ;;
    help|-h|--help)
      shift
      cmd_plugin_help "$@"
      return $?
      ;;
  esac

  # 1. Explicit plugin command invocation: rnex plugin <name> <command> [options...]
  if plugin_exists "$_action"; then
    _target_plugin="$1"
    shift
    if [ $# -eq 0 ]; then
      cmd_plugin_info "$_target_plugin"
      return $?
    fi
    _target_cmd="$1"
    shift
    if ! yaml_plugin_enabled "$_target_plugin"; then
      die "Plugin '$_target_plugin' is not enabled in workspace (run 'rnex plugin enable $_target_plugin')"
    fi
    if ! plugin_has_command "$_target_plugin" "$_target_cmd"; then
      die "Unknown command '$_target_cmd' for plugin '$_target_plugin' (run 'rnex plugin info $_target_plugin' to see available commands)"
    fi
    run_plugin_command "$_target_plugin" "$_target_cmd" "$@"
    return $?
  fi

  # 2. Shorthand fallback: search enabled plugins for matching command
  _found_plugin=""
  for _p in $(yaml_list_plugins 2>/dev/null || true); do
    [ -n "$_p" ] || continue
    if yaml_plugin_enabled "$_p" 2>/dev/null; then
      if plugin_has_command "$_p" "$_action"; then
        _found_plugin="$_p"
        break
      fi
    fi
  done

  if [ -n "$_found_plugin" ]; then
    _shorthand_cmd="$1"
    shift
    run_plugin_command "$_found_plugin" "$_shorthand_cmd" "$@"
    return $?
  fi

  # 3. Check if command belongs to an available but disabled plugin
  for _pdir in $(list_all_available_plugin_dirs 2>/dev/null || true); do
    _p="$(basename "$_pdir")"
    if plugin_has_command "$_p" "$_action"; then
      die "Command '$_action' belongs to plugin '$_p', which is currently disabled. Run: rnex plugin enable $_p"
    fi
  done

  die "Unknown plugin subcommand or plugin: $_action (try 'rnex plugin list')"
}
