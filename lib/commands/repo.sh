#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/repo.sh — Member repository management commands
# ============================================================================

# Main dispatcher for 'rnex repo <subcommand>' operations.
cmd_repo() {
  [ $# -gt 0 ] || die "Usage: rnex repo <add|remove|set|clone|status|exec|list> [arguments...]"
  _subcmd="$1"
  shift
  case "$_subcmd" in
    add)            cmd_repo_add "$@" ;;
    remove|rm)      cmd_repo_remove "$@" ;;
    set)            cmd_repo_set "$@" ;;
    clone)          cmd_repo_clone "$@" ;;
    status)         cmd_repo_status "$@" ;;
    exec)           cmd_repo_exec "$@" ;;
    list|ls)        cmd_list "$@" ;;
    help|-h|--help) cmd_repo_help ;;
    *)              die "Unknown repo subcommand: $_subcmd (try 'rnex repo help')" ;;
  esac
}

cmd_repo_help() {
  cat <<EOF
Usage: rnex repo <subcommand> [arguments...]

Subcommands:
  add <url> [--name <name>] [--branch <branch>] [--local] [--disabled] [--readonly]
                      Add and optionally clone a member repository
  remove <name> [--purge] [-y|--yes]
                      Remove a repository from configuration (use --purge to delete directory)
  set <name> [--enable|--disable] [--readonly|--readwrite] [--global|--local]
                      Update repository configuration flags (default: --local)
  clone <name>        Clone a single member repository
  status <name>       Show detailed status and git status for a repository
  exec <name> <cmd...>
                      Execute a shell command inside repos/<name>
  list                List all member repositories with clone state and branch

EOF
}

# Register a new repository in workspace configuration and clone it into ./repos/<name>.
# Usage:
#   rnex repo add <url> [--name <name>] [--branch <branch>] [--local] [--disabled] [--readonly]
#   rnex repo add [<name>] <git-url> (backwards compatible positional syntax)
cmd_repo_add() {
  require_workspace
  _pos1=""
  _pos2=""
  _name_opt=""
  _branch=""
  _enabled="true"
  _readonly="false"
  _is_local=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --local) _is_local=1 ;;
      --disabled) _enabled="false" ;;
      --readonly) _readonly="true" ;;
      -n|--name)
        shift
        [ $# -gt 0 ] || die "Option --name requires an argument"
        _name_opt="$1"
        ;;
      --name=*)
        _name_opt="${1#*=}"
        ;;
      -b|--branch)
        shift
        [ $# -gt 0 ] || die "Option --branch requires an argument"
        _branch="$1"
        ;;
      --branch=*)
        _branch="${1#*=}"
        ;;
      --no-rnex-dir|--rnex-dir=false|--rnex-dir|--rnex-dir=true)
        # Obsolete flag ignored after transition to on-demand member .rnex
        ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        if [ -z "$_pos1" ]; then
          _pos1="$1"
        elif [ -z "$_pos2" ]; then
          _pos2="$1"
        else
          die "Unexpected argument: $1"
        fi
        ;;
    esac
    shift
  done

  # Derive repo name and URL:
  # 1. If --name was explicitly passed, _pos1 is the URL.
  # 2. If 2 positional arguments: <name> <git-url>
  # 3. If 1 positional argument: <git-url> (inferred from URL)
  if [ -n "$_name_opt" ]; then
    _name="$_name_opt"
    _url="$_pos1"
  elif [ -n "$_pos2" ]; then
    _name="$_pos1"
    _url="$_pos2"
  elif [ -n "$_pos1" ]; then
    _url="$_pos1"
    _name="$(repo_name_from_path "$_url")"
  else
    die "Usage: rnex repo add <url> [--name <name>] [--branch <branch>] [--local] [--disabled] [--readonly]"
  fi

  [ -n "$_name" ] || die "Could not determine repository name from '$_url'"
  [ -n "$_url" ] || die "Usage: rnex repo add <url> [--name <name>] [--branch <branch>] [--local] [--disabled] [--readonly]"

  ensure_repos_dir
  _target_dir="$(resolve_repo_path "$_name")"

  # Clone repo into destination if enabled and not already cloned
  if [ "$_enabled" = "true" ] && [ ! -d "$_target_dir" ]; then
    if [ -n "$_branch" ]; then
      log_info "Cloning $_name (branch: $_branch) from $_url into $_target_dir..."
      if ! git clone -b "$_branch" "$_url" "$_target_dir"; then
        die "Failed to clone repository from $_url (branch: $_branch)"
      fi
    else
      log_info "Cloning $_name from $_url into $_target_dir..."
      if ! git clone "$_url" "$_target_dir"; then
        die "Failed to clone repository from $_url"
      fi
    fi
  fi

  if [ "$_is_local" -eq 1 ]; then
    yaml_set_local "$_name" "url" "$_url"
    [ -n "$_branch" ] && yaml_set_local "$_name" "branch" "$_branch"
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
      [ -n "$_branch" ] && yaml_set "$_name" "branch" "$_branch"
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

  yaml_add_repo "$_name" "$_url" "$_enabled" "$_readonly" "$_branch"
  sync_repo_rnex "$_name"
  sync_code_workspace
  run_hook "after_sync" "$@"
  printf '\n'
  log_ok "Registered and added repo '${_name}'"
}

# Remove a member repository from configuration. Deletes local folder only when --purge is specified.
# Usage:
#   rnex repo remove <name> [--purge] [-y|--yes]
cmd_repo_remove() {
  require_workspace
  _name=""
  _purge=0
  _yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -p|--purge) _purge=1 ;;
      -y|--yes)   _yes=1 ;;
      -*)         die "Unknown option: $1" ;;
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

  [ -n "$_name" ] || die "Usage: rnex repo remove <name> [--purge] [-y|--yes]"
  yaml_has_repo "$_name" || die "Repo '$_name' is not registered"

  _target_dir="$(resolve_repo_path "$_name")"
  yaml_remove_repo "$_name"

  if [ "$_purge" -eq 1 ] && [ -d "$_target_dir" ]; then
    rm -rf "$_target_dir"
    log_ok "Removed and deleted repo '$_name' ($_target_dir)"
  else
    log_ok "Unregistered repo '$_name'"
  fi
  sync_code_workspace
  run_hook "after_sync" "$@"
}

# Modify repository configuration flags (--enable, --disable, --readonly, --readwrite).
# Defaults to modifying local machine configuration (.local.rnex.yaml) unless --global is set.
# Usage:
#   rnex repo set <name> [--enable|--disable] [--readonly|--readwrite] [--global|--local]
cmd_repo_set() {
  require_workspace
  _name=""
  _enable_val=""
  _ro_val=""
  _target="local"

  while [ $# -gt 0 ]; do
    case "$1" in
      --global)                     _target="global" ;;
      --local)                      _target="local" ;;
      --enable)                     _enable_val="true" ;;
      --disable)                    _enable_val="false" ;;
      --enable=true|--enable=1)     _enable_val="true" ;;
      --enable=false|--enable=0)    _enable_val="false" ;;
      --readonly)                   _ro_val="true" ;;
      --readwrite|--no-readonly)    _ro_val="false" ;;
      --readonly=true|--readonly=1) _ro_val="true" ;;
      --readonly=false|--readonly=0) _ro_val="false" ;;
      -*)                           die "Unknown option: $1" ;;
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

  [ -n "$_name" ] || die "Usage: rnex repo set <name> [--enable|--disable] [--readonly|--readwrite] [--global|--local]"
  yaml_has_repo "$_name" || die "Repo '$_name' is not registered"
  [ -n "$_enable_val" ] || [ -n "$_ro_val" ] || die "Specify at least one setting to change (--enable/--disable, --readonly/--readwrite)"

  if [ "$_target" = "local" ]; then
    if [ -n "$_enable_val" ]; then
      yaml_set_local "$_name" "enabled" "$_enable_val"
      if [ "$_enable_val" = "true" ]; then
        log_ok "Enabled repo '$_name' locally in $(basename "$WORKSPACE_LOCAL_YAML")"
      else
        log_ok "Disabled repo '$_name' locally in $(basename "$WORKSPACE_LOCAL_YAML")"
      fi
    fi
    if [ -n "$_ro_val" ]; then
      yaml_set_local "$_name" "readonly" "$_ro_val"
      if [ "$_ro_val" = "true" ]; then
        log_ok "Marked repo '$_name' as read-only locally in $(basename "$WORKSPACE_LOCAL_YAML")"
      else
        log_ok "Disabled read-only mode for '$_name' locally in $(basename "$WORKSPACE_LOCAL_YAML")"
      fi
    fi
  else
    if [ -n "$_enable_val" ]; then
      yaml_set "$_name" "enabled" "$_enable_val"
      if [ "$_enable_val" = "true" ]; then
        log_ok "Enabled repo '$_name' in $(basename "$WORKSPACE_YAML")"
      else
        log_ok "Disabled repo '$_name' in $(basename "$WORKSPACE_YAML")"
      fi
    fi
    if [ -n "$_ro_val" ]; then
      yaml_set "$_name" "readonly" "$_ro_val"
      if [ "$_ro_val" = "true" ]; then
        log_ok "Marked repo '$_name' as read-only in $(basename "$WORKSPACE_YAML")"
      else
        log_ok "Disabled read-only mode for '$_name' in $(basename "$WORKSPACE_YAML")"
      fi
    fi
  fi

  if [ "$_enable_val" = "true" ]; then
    sync_repo_rnex "$_name"
  fi
  sync_code_workspace
  run_hook "after_sync" "$@"
}

# Clone a single member repository declared in configuration.
# Usage:
#   rnex repo clone <name>
cmd_repo_clone() {
  require_workspace
  [ $# -gt 0 ] || die "Usage: rnex repo clone <name>"
  _name="$1"
  yaml_has_repo "$_name" || die "Repo '$_name' is not registered in configuration"

  _url="$(yaml_get "$_name" "url")"
  [ -n "$_url" ] || _url="$(yaml_get "$_name" "path")"
  [ -n "$_url" ] || die "Repo '$_name' has no Git URL declared in configuration"

  ensure_repos_dir
  _dest="$(resolve_repo_path "$_name")"
  if [ -d "$_dest/.git" ]; then
    log_ok "Repo '$_name' is already present at $_dest"
    return 0
  elif [ -e "$_dest" ]; then
    die "Destination $_dest already exists but is not a Git repo"
  fi

  _branch="$(yaml_get_repo_branch "$_name")"
  if [ -n "$_branch" ]; then
    log_info "Cloning $_name (branch: $_branch) from $_url into $_dest..."
    if git clone -b "$_branch" "$_url" "$_dest"; then
      log_ok "Successfully cloned '$_name'"
      sync_repo_rnex "$_name"
      sync_code_workspace
      run_hook "after_sync" "$@"
    else
      die "Failed to clone '$_name' from $_url"
    fi
  else
    log_info "Cloning $_name from $_url into $_dest..."
    if git clone "$_url" "$_dest"; then
      log_ok "Successfully cloned '$_name'"
      sync_repo_rnex "$_name"
      sync_code_workspace
      run_hook "after_sync" "$@"
    else
      die "Failed to clone '$_name' from $_url"
    fi
  fi
}

# Display configuration and git status for a single member repository.
# Usage:
#   rnex repo status <name>
cmd_repo_status() {
  require_workspace
  [ $# -gt 0 ] || die "Usage: rnex repo status <name>"
  _name="$1"
  yaml_has_repo "$_name" || die "Repo '$_name' is not registered"

  _url="$(yaml_get "$_name" "url")"
  [ -n "$_url" ] || _url="$(yaml_get "$_name" "path")"
  _dest="$(resolve_repo_path "$_name")"
  _en="enabled"
  yaml_repo_enabled "$_name" || _en="disabled"
  _ro="false"
  yaml_repo_readonly "$_name" && _ro="true"
  _branch="$(yaml_get_repo_branch "$_name")"

  printf '\n%bRepository: %s%b\n' "$_B" "$_name" "$_NC"
  printf '  URL:      %s\n' "${_url:-(none)}"
  printf '  Path:     %s\n' "$_dest"
  printf '  State:    %s\n' "$_en"
  printf '  Readonly: %s\n' "$_ro"
  [ -n "$_branch" ] && printf '  Target Branch: %s\n' "$_branch"

  if [ -d "$_dest/.git" ]; then
    _curr_b="$(git -C "$_dest" symbolic-ref --short HEAD 2>/dev/null || git -C "$_dest" rev-parse --short HEAD 2>/dev/null || true)"
    printf '  Active Branch: %s\n' "${_curr_b:-(detached)}"
    printf '\n%bGit Status:%b\n' "$_DIM" "$_NC"
    (cd "$_dest" && git status -s)
  else
    printf '  Cloned:   no (directory missing)\n'
  fi
  printf '\n'
}

# Execute a shell command inside a single member repository's directory.
# Propagates the exit code from the executed command.
# Usage:
#   rnex repo exec <name> <command...>
cmd_repo_exec() {
  require_workspace
  [ $# -ge 2 ] || die "Usage: rnex repo exec <name> <command...>"
  _name="$1"
  shift
  yaml_has_repo "$_name" || die "Repo '$_name' is not registered"

  _repo_dir="$(resolve_repo_path "$_name")"
  [ -d "$_repo_dir" ] || die "Repo '$_name' is not cloned yet at $_repo_dir"

  _cmd="$*"
  printf '%b[%s]%b %s\n' "$_B" "$_name" "$_NC" "$_cmd"
  printf '%s\n' "----------------------------------------"
  (cd "$_repo_dir" && eval "$_cmd")
}

# Clone all enabled repositories declared in configuration that are not yet cloned.
# Skips disabled repositories and already existing clones. Respects repo branch setting.
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
      _branch="$(yaml_get_repo_branch "$_name")"
      if [ -n "$_branch" ]; then
        log_info "Cloning $_name (branch: $_branch) from $_url..."
        if git clone -b "$_branch" "$_url" "$_dest"; then
          log_ok "Successfully cloned '$_name'"
          sync_repo_rnex "$_name"
        else
          log_err "Failed to clone '$_name' from $_url"
        fi
      else
        log_info "Cloning $_name from $_url..."
        if git clone "$_url" "$_dest"; then
          log_ok "Successfully cloned '$_name'"
          sync_repo_rnex "$_name"
        else
          log_err "Failed to clone '$_name' from $_url"
        fi
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
      log_warn "Repo '$_name' is not cloned yet — skipping (run 'rnex clone' or 'rnex repo clone $_name')"
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
