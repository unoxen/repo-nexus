#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/repo.sh — Member repository management commands
# ============================================================================

# Register a new repository in workspace configuration and clone it into ./repos/<name>.
# Usage:
#   rnex add [--local] [--disabled] [--readonly] [<name>] <git-url>
# If <name> is omitted, it is inferred from the last component of <git-url>.
cmd_add() {
  require_workspace
  _arg1=""
  _arg2=""
  _enabled="true"
  _readonly="false"
  _is_local=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --local) _is_local=1 ;;
      --disabled) _enabled="false" ;;
      --readonly) _readonly="true" ;;
      --no-rnex-dir|--rnex-dir=false|--rnex-dir|--rnex-dir=true)
        # Obsolete flag ignored after transition to on-demand member .rnex
        ;;
      *)
        if [ -z "$_arg1" ]; then
          _arg1="$1"
        elif [ -z "$_arg2" ]; then
          _arg2="$1"
        else
          die "Unexpected argument: $1"
        fi
        ;;
    esac
    shift
  done

  # Derive repo name and URL:
  # - If 2 positional args: <name> <git-url>
  # - If 1 positional arg:  <git-url> (name inferred from the last component of the path/URL)
  if [ -n "$_arg2" ]; then
    _name="$_arg1"
    _url="$_arg2"
  elif [ -n "$_arg1" ]; then
    _url="$_arg1"
    _name="$(repo_name_from_path "$_url")"
  else
    die "Usage: rnex add [--local] [--disabled] [--readonly] [<name>] <git-url>"
  fi

  [ -n "$_name" ] || die "Could not determine repository name from '$_url'"
  [ -n "$_url" ] || die "Usage: rnex add [--local] [--disabled] [--readonly] [<name>] <git-url>"

  ensure_repos_dir
  _target_dir="$(resolve_repo_path "$_name")"

  # Clone repo into destination if enabled and not already cloned
  if [ "$_enabled" = "true" ] && [ ! -d "$_target_dir" ]; then
    log_info "Cloning $_name from $_url into $_target_dir..."
    if ! git clone "$_url" "$_target_dir"; then
      die "Failed to clone repository from $_url"
    fi
  fi

  if [ "$_is_local" -eq 1 ]; then
    yaml_set_local "$_name" "url" "$_url"
    [ "$_readonly" = "true" ] && yaml_set_local "$_name" "readonly" "true"
    [ "$_enabled" = "false" ] && yaml_set_local "$_name" "enabled" "false"
    sync_repo_rnex "$_name"
    sync_code_workspace
    run_hook "after_sync" "$@"
    printf '\n'
    log_ok "Registered repo '${_name}' in $(basename "$WORKSPACE_LOCAL_YAML")"
    return 0
  fi

  if grep -q "^  $_name:" "$WORKSPACE_YAML" 2>/dev/null; then
    _existing_url="$(_yaml_get_from_file "$WORKSPACE_YAML" "$_name" "url")"
    [ -n "$_existing_url" ] || _existing_url="$(_yaml_get_from_file "$WORKSPACE_YAML" "$_name" "path")"
    if [ -n "$_existing_url" ]; then
      die "Repo '$_name' is already registered in $(basename "$WORKSPACE_YAML")"
    else
      yaml_set "$_name" "url" "$_url"
      [ "$_readonly" = "true" ] && yaml_set "$_name" "readonly" "true"
      [ "$_enabled" = "false" ] && yaml_set "$_name" "enabled" "false"
      sync_repo_rnex "$_name"
      sync_code_workspace
      run_hook "after_sync" "$@"
      printf '\n'
      log_ok "Updated repo '${_name}' in $(basename "$WORKSPACE_YAML")"
      return 0
    fi
  fi

  yaml_add_repo "$_name" "$_url" "$_enabled" "$_readonly"
  sync_repo_rnex "$_name"
  sync_code_workspace
  run_hook "after_sync" "$@"
  printf '\n'
  log_ok "Registered and added repo '${_name}'"
}

# Clone all enabled repositories declared in configuration that are not yet cloned.
# Skips disabled repositories and already existing clones.
cmd_clone() {
  require_workspace
  ensure_repos_dir

  _all_repos="$(yaml_list_repos)"
  [ -n "$_all_repos" ] || { log_warn "No repositories declared in configuration"; return 0; }

  printf '\n%bCloning workspace repositories into %s%b\n\n' "$_B" "$REPOS_DIR" "$_NC"

  echo "$_all_repos" | while read -r _name; do
    [ -n "$_name" ] || continue
    if ! yaml_repo_enabled "$_name"; then
      log_dim "[○] Skipping disabled repo: $_name"
      continue
    fi

    _url="$(yaml_get "$_name" "url")"
    [ -n "$_url" ] || _url="$(yaml_get "$_name" "path")"

    if [ -z "$_url" ]; then
      log_warn "Repo '$_name' has no Git URL declared in configuration"
      continue
    fi

    _dest="$(resolve_repo_path "$_name")"
    if [ -d "$_dest/.git" ]; then
      log_ok "Repo '$_name' is already present at $_dest"
    elif [ -e "$_dest" ]; then
      log_warn "Destination $_dest already exists but is not a Git repo"
    else
      log_info "Cloning $_name from $_url..."
      if git clone "$_url" "$_dest"; then
        log_ok "Successfully cloned '$_name'"
        sync_repo_rnex "$_name"
      else
        log_err "Failed to clone '$_name' from $_url"
      fi
    fi
  done
  sync_code_workspace
  run_hook "after_sync" "$@"
  printf '\n'
}

# Execute a shell command across all enabled member repositories in ./repos/<name>.
# Propagates non-zero exit codes if any repository command fails.
cmd_exec() {
  require_workspace
  [ $# -gt 0 ] || die "Usage: rnex exec <command...>"

  _cmd="$*"
  _all_repos="$(yaml_list_repos)"
  [ -n "$_all_repos" ] || { log_warn "No repositories declared in configuration"; return 0; }

  _has_failure=0
  _last_rc=0
  for _name in $_all_repos; do
    [ -n "$_name" ] || continue
    if ! yaml_repo_enabled "$_name"; then
      continue
    fi

    _repo_dir="$(resolve_repo_path "$_name")"
    if [ ! -d "$_repo_dir" ]; then
      log_warn "Repo '$_name' is not cloned yet — skipping (run 'rnex clone')"
      continue
    fi

    printf '\n%b[%s]%b %s\n' "$_B" "$_name" "$_NC" "$_cmd"
    printf '%s\n' "----------------------------------------"
    if (cd "$_repo_dir" && eval "$_cmd"); then
      printf '%b[✓] %s succeeded%b\n' "$_G" "$_name" "$_NC"
    else
      _rc=$?
      [ "$_rc" -ne 0 ] || _rc=1
      _has_failure=1
      _last_rc=$_rc
      printf '%b[✗] %s failed (exit %s)%b\n' "$_R" "$_name" "$_rc" "$_NC"
    fi
  done
  printf '\n'
  if [ "$_has_failure" -ne 0 ]; then
    return "$_last_rc"
  fi
  return 0
}

_repo_set_config_and_log() {
  _rname="$1"; _key="$2"; _val="$3"; _local_flag="$4"; _verb="$5"
  if [ "$_local_flag" -eq 1 ]; then
    yaml_set_local "$_rname" "$_key" "$_val"
    log_ok "$_verb '$_rname' locally in $(basename "$WORKSPACE_LOCAL_YAML")"
  else
    yaml_set "$_rname" "$_key" "$_val"
    log_ok "$_verb '$_rname' in $(basename "$WORKSPACE_YAML")"
  fi
}

_repo_toggle_state() {
  require_workspace
  _target_val="$1"; _verb="$2"
  shift 2
  _is_local=0; _name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --local) _is_local=1 ;;
      *) _name="$1" ;;
    esac
    shift
  done
  _cmd_lbl="enable"
  [ "$_target_val" = "false" ] && _cmd_lbl="disable"
  [ -n "$_name" ] || die "Usage: rnex $_cmd_lbl [--local] <name>"
  yaml_has_repo "$_name" || die "Repo '$_name' is not registered"
  _repo_set_config_and_log "$_name" "enabled" "$_target_val" "$_is_local" "$_verb"
}

# Enable a member repository in configuration and reconcile its workspace state.
cmd_enable() {
  _repo_toggle_state "true" "Enabled repo" "$@"
  sync_repo_rnex "$_name"
  sync_code_workspace
  run_hook "after_sync" "$@"
}

# Disable a member repository in configuration (skips execution and hides from IDE).
cmd_disable() {
  _repo_toggle_state "false" "Disabled repo" "$@"
  sync_code_workspace
}

cmd_show() {
  cmd_enable "$@"
}

cmd_hide() {
  cmd_disable "$@"
}

# Toggle the member repository read-only setting (enable or disable) for a specific repo.
# When a repository is read-only, it is strictly used for information / reference.
# Usage:
#   rnex readonly <enable|disable> <name> [--local]
cmd_readonly() {
  require_workspace
  _action=""
  _name=""
  _is_local=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --local) _is_local=1 ;;
      enable|true|yes|1)
        if [ -z "$_action" ]; then _action="true"; else _name="$1"; fi
        ;;
      disable|false|no|0)
        if [ -z "$_action" ]; then _action="false"; else _name="$1"; fi
        ;;
      *)
        if [ -z "$_action" ] && [ "$1" = "enable" ] || [ "$1" = "disable" ]; then
          _action="$1"
        elif [ -z "$_name" ]; then
          _name="$1"
        elif [ -z "$_action" ]; then
          _action="$1"
        fi
        ;;
    esac
    shift
  done

  case "$_action" in
    enable|true|yes|1) _action="true" ;;
    disable|false|no|0) _action="false" ;;
    "") _action="true" ;;
  esac

  [ -n "$_name" ] || die "Usage: rnex readonly <enable|disable> <name> [--local]"
  yaml_has_repo "$_name" || die "Repo '$_name' is not registered"

  if [ "$_action" = "true" ]; then
    _repo_set_config_and_log "$_name" "readonly" "true" "$_is_local" "Marked repo as read-only"
  else
    _repo_set_config_and_log "$_name" "readonly" "false" "$_is_local" "Disabled read-only mode for"
  fi
  sync_code_workspace
  run_hook "after_sync" "$@"
}

# Remove a member repository from configuration and delete its local directory in ./repos/<name>.
cmd_remove() {
  require_workspace
  _name=""
  _yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) _yes=1 ;;
      *)
        if [ -z "$_name" ]; then
          _name="$1"
        else
          die "Unexpected argument: $1"
        fi
        ;;
    esac
    shift
  done

  [ -n "$_name" ] || die "Usage: rnex remove <name> [-y]"
  yaml_has_repo "$_name" || die "Repo '$_name' is not registered"

  _target_dir="$(resolve_repo_path "$_name")"
  yaml_remove_repo "$_name"
  if [ -d "$_target_dir" ]; then
    rm -rf "$_target_dir"
    log_ok "Removed and deleted repo '$_name' ($_target_dir)"
  else
    log_ok "Unregistered repo '$_name'"
  fi
  sync_code_workspace
  run_hook "after_sync" "$@"
}

# Print a tabular status list of all registered member repositories, showing
# state (enabled/disabled), clone status, active git branch, readonly status, and URL.
cmd_list() {
  require_workspace
  printf '\n%b%-18s %-10s %-8s %-14s %-10s %s%b\n' "$_B" "NAME" "STATE" "CLONED" "BRANCH" "READONLY" "URL" "$_NC"
  printf '%-18s %-10s %-8s %-14s %-10s %s\n' "----" "-----" "------" "------" "--------" "---"
  yaml_list_repos | while read -r _name; do
    [ -n "$_name" ] || continue
    _url="$(yaml_get "$_name" "url")"
    [ -n "$_url" ] || _url="$(yaml_get "$_name" "path")"

    if yaml_repo_enabled "$_name"; then
      _state="${_G}enabled${_NC}"
    else
      _state="${_DIM}disabled${_NC}"
    fi

    _rdir="$(resolve_repo_path "$_name")"
    _cloned="${_R}missing${_NC}"
    _branch="-"
    if [ -d "$_rdir/.git" ]; then
      _cloned="${_G}cloned${_NC}"
      _b="$(git -C "$_rdir" symbolic-ref --short HEAD 2>/dev/null || git -C "$_rdir" rev-parse --short HEAD 2>/dev/null || true)"
      [ -n "$_b" ] && _branch="$_b"
    fi

    _ro="false"
    if yaml_repo_readonly "$_name"; then
      _ro="${_Y}true${_NC}"
    fi

    printf '%-18s %-19b %-17b %-14s %-19b %s\n' \
      "$_name" "$_state" "$_cloned" "$_branch" "$_ro" "${_url:-(none)}"
  done
  printf '\n'
}
