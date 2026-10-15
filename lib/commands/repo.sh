#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/repo.sh — Member repository management commands
# ============================================================================

cmd_add() {
  require_workspace
  _assume=""
  _name=""
  _url=""
  _rnex_dir="true"
  _enabled="true"
  _is_local=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --local) _is_local=1 ;;
      --disabled) _enabled="false" ;;
      --no-rnex-dir|--rnex-dir=false) _rnex_dir="false" ;;
      --rnex-dir|--rnex-dir=true)    _rnex_dir="true" ;;
      -y|--yes) _assume="y" ;;
      -n|--no)  _assume="n" ;;
      *)
        if [ -z "$_name" ]; then
          _name="$1"
        elif [ -z "$_url" ]; then
          _url="$1"
        else
          die "Unexpected argument: $1"
        fi
        ;;
    esac
    shift
  done

  [ -n "$_name" ] || die "Usage: rnex add [--local] [--disabled] [--no-rnex-dir] <name> <git-url>"
  [ -n "$_url" ] || die "Usage: rnex add [--local] [--disabled] [--no-rnex-dir] <name> <git-url>"

  ensure_repos_dir
  _target_dir="$REPOS_DIR/$_name"

  # Clone repo into destination if enabled and not already cloned
  if [ "$_enabled" = "true" ] && [ ! -d "$_target_dir" ]; then
    log_info "Cloning $_name from $_url into $_target_dir..."
    if ! git clone "$_url" "$_target_dir"; then
      die "Failed to clone repository from $_url"
    fi
  fi

  if [ "$_is_local" -eq 1 ]; then
    yaml_set_local "$_name" "url" "$_url"
    [ "$_rnex_dir" = "false" ] && yaml_set_local "$_name" "rnex_dir" "false"
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
      [ "$_rnex_dir" = "false" ] && yaml_set "$_name" "rnex_dir" "false"
      [ "$_enabled" = "false" ] && yaml_set "$_name" "enabled" "false"
      sync_repo_rnex "$_name"
      sync_code_workspace
      run_hook "after_sync" "$@"
      printf '\n'
      log_ok "Updated repo '${_name}' in $(basename "$WORKSPACE_YAML")"
      return 0
    fi
  fi

  yaml_add_repo "$_name" "$_url" "$_rnex_dir" "$_enabled"
  sync_repo_rnex "$_name"
  sync_code_workspace
  run_hook "after_sync" "$@"
  printf '\n'
  log_ok "Registered and added repo '${_name}'"
}

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

    _dest="$REPOS_DIR/$_name"
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

cmd_exec() {
  require_workspace
  [ $# -gt 0 ] || die "Usage: rnex exec <command...>"

  _cmd="$*"
  _all_repos="$(yaml_list_repos)"
  [ -n "$_all_repos" ] || { log_warn "No repositories declared in configuration"; return 0; }

  echo "$_all_repos" | while read -r _name; do
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
      printf '%b[✗] %s failed (exit %s)%b\n' "$_R" "$_name" "$_rc" "$_NC"
    fi
  done
  printf '\n'
}

cmd_enable() {
  require_workspace
  _is_local=0
  _name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --local) _is_local=1 ;;
      *) _name="$1" ;;
    esac
    shift
  done
  [ -n "$_name" ] || die "Usage: rnex enable [--local] <name>"
  yaml_has_repo "$_name" || die "Repo '$_name' is not registered"

  if [ "$_is_local" -eq 1 ]; then
    yaml_set_local "$_name" "enabled" "true"
    log_ok "Enabled repo '$_name' locally in $(basename "$WORKSPACE_LOCAL_YAML")"
  else
    yaml_set "$_name" "enabled" "true"
    log_ok "Enabled repo '$_name' in $(basename "$WORKSPACE_YAML")"
  fi
  sync_repo_rnex "$_name"
  sync_code_workspace
  run_hook "after_sync" "$@"
}

cmd_disable() {
  require_workspace
  _is_local=0
  _name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --local) _is_local=1 ;;
      *) _name="$1" ;;
    esac
    shift
  done
  [ -n "$_name" ] || die "Usage: rnex disable [--local] <name>"
  yaml_has_repo "$_name" || die "Repo '$_name' is not registered"

  if [ "$_is_local" -eq 1 ]; then
    yaml_set_local "$_name" "enabled" "false"
    log_ok "Disabled repo '$_name' locally in $(basename "$WORKSPACE_LOCAL_YAML")"
  else
    yaml_set "$_name" "enabled" "false"
    log_ok "Disabled repo '$_name' in $(basename "$WORKSPACE_YAML")"
  fi
  sync_code_workspace
}

cmd_show() {
  cmd_enable "$@"
}

cmd_hide() {
  cmd_disable "$@"
}

cmd_remove() {
  require_workspace
  _name="$1"
  [ -n "$_name" ] || die "Usage: rnex remove <name>"
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

cmd_list() {
  require_workspace
  printf '\n%b%-18s %-10s %-8s %-14s %-10s %s%b\n' "$_B" "NAME" "STATE" "CLONED" "BRANCH" "RNEX_DIR" "URL" "$_NC"
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

    _rd="true"
    if ! repo_rnex_dir_enabled "$_name"; then
      _rd="false"
    fi

    printf '%-18s %-19b %-17b %-14s %-10s %s\n' \
      "$_name" "$_state" "$_cloned" "$_branch" "$_rd" "${_url:-(none)}"
  done
  printf '\n'
}
