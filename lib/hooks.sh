#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/hooks.sh — Automated Git hooks management and event dispatch
# ============================================================================

RNEX_MANAGED_GIT_HOOKS="post-merge post-checkout post-commit pre-commit pre-push"

# ---- Shared Hook Resolution & Environment Helpers --------------------------

# Resolve active workspace root for hook execution without mutating global state
_resolve_hook_workspace() {
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
  [ -n "$_ws" ] || return 1
  _hook_root="$(cd "$_ws" 2>/dev/null && pwd -P)"
  _hook_config_merged="$_hook_root/rnex.yaml"
  if [ -n "$CUSTOM_CONFIG" ]; then
    _hook_config_merged="$(resolve_path "$CUSTOM_CONFIG" 2>/dev/null || true)"
  fi
  [ -f "$_hook_config_merged" ] || return 1
  return 0
}

# Locate a hook script for a plugin (checks scoped .rnex/plugins/<name>/hooks first,
# then toolkit source directory). Accepts multiple candidate filenames in priority order.
_resolve_plugin_hook_script() {
  _rphs_root="$1"; _rphs_plugin="$2"
  shift 2
  _rphs_scoped="$_rphs_root/.rnex/plugins/$_rphs_plugin/hooks"
  _rphs_src=""

  for _cand_name in "$@"; do
    if [ -f "$_rphs_scoped/$_cand_name" ]; then
      printf '%s' "$_rphs_scoped/$_cand_name"
      return 0
    fi
  done

  _rphs_src="$(find_plugin_dir "$_rphs_plugin" 2>/dev/null || true)"
  if [ -n "$_rphs_src" ]; then
    for _cand_name in "$@"; do
      if [ -f "$_rphs_src/hooks/$_cand_name" ]; then
        printf '%s' "$_rphs_src/hooks/$_cand_name"
        return 0
      fi
    done
  fi
  return 1
}

# ---- Action Command Hook Dispatcher -----------------------------------------

_run_hook_internal() {
  _hook_target_plugin="$1"
  _hook_phase_cmd="$2"
  shift 2 2>/dev/null || true

  _resolve_hook_workspace || return 0

  _hook_cmd="${_hook_phase_cmd#*_}"
  _hook_file="${_hook_phase_cmd}.sh"
  _hook_args="$*"
  _hook_quiet="${_sync_quiet:-0}"

  _old_nexus="$NEXUS_DIR"
  _old_yaml="$WORKSPACE_YAML"
  _old_local_yaml="$WORKSPACE_LOCAL_YAML"
  NEXUS_DIR="$_hook_root"
  WORKSPACE_YAML="$_hook_config_merged"
  WORKSPACE_LOCAL_YAML="$_hook_root/$RNEX_LOCAL_CONFIG_FILE"
  _skill_dirs="$(get_active_provider_skill_dirs 2>/dev/null || true)"

  if [ -n "$_hook_target_plugin" ]; then
    _plugins="$_hook_target_plugin"
  else
    _plugins="$(yaml_list_plugins 2>/dev/null || true)"
  fi

  for _pname in $_plugins; do
    [ -n "$_pname" ] || continue
    if [ -z "$_hook_target_plugin" ]; then
      yaml_plugin_enabled "$_pname" 2>/dev/null || continue
    fi

    RNEX_PLUGIN_DIR="$_hook_root/.rnex/plugins/$_pname"
    if [ "$_hook_phase_cmd" = "after_init" ]; then
      _hook_script="$(_resolve_plugin_hook_script "$_hook_root" "$_pname" "after_init.sh" "after_sync.sh" || true)"
    else
      _hook_script="$(_resolve_plugin_hook_script "$_hook_root" "$_pname" "$_hook_file" || true)"
    fi

    if [ -n "$_hook_script" ] && [ -f "$_hook_script" ]; then
      chmod +x "$_hook_script" 2>/dev/null || true
      (
        RNEX_ROOT="$_hook_root"
        RNEX_CONFIG_MERGED="$_hook_config_merged"
        RNEX_CMD="$_hook_cmd"
        RNEX_ARGS="$_hook_args"
        RNEX_QUIET="$_hook_quiet"
        RNEX_PROVIDER_SKILL_DIRS="$_skill_dirs"
        export RNEX_ROOT RNEX_CONFIG_MERGED RNEX_PLUGIN_DIR RNEX_CMD RNEX_ARGS RNEX_QUIET RNEX_PROVIDER_SKILL_DIRS RNEX_LIB_DIR
        set -- "$@"
        # shellcheck source=/dev/null
        . "$_hook_script"
      ) || true
    fi
  done
  WORKSPACE_LOCAL_YAML="$_old_local_yaml"
  WORKSPACE_YAML="$_old_yaml"
  NEXUS_DIR="$_old_nexus"
}

run_hook() {
  _hook_phase_cmd="$1"
  shift 2>/dev/null || true
  _run_hook_internal "" "$_hook_phase_cmd" "$@"
}

run_plugin_hook() {
  _hook_target_plugin="$1"
  _hook_phase_cmd="$2"
  shift 2 2>/dev/null || true
  _run_hook_internal "$_hook_target_plugin" "$_hook_phase_cmd" "$@"
}

run_plugin_git_hooks() {
  _hook_name="$1"
  shift 2>/dev/null || true

  _ws="${NEXUS_DIR:-}"
  [ -n "$_ws" ] && [ -f "$_ws/rnex.yaml" ] || return 0

  RNEX_ROOT="$(cd "$_ws" 2>/dev/null && pwd -P)"
  RNEX_CONFIG_MERGED="$RNEX_ROOT/rnex.yaml"
  RNEX_CMD="hooks"
  RNEX_ARGS="$*"
  RNEX_QUIET="${_sync_quiet:-0}"

  _stdin_data=""
  if [ ! -t 0 ]; then
    _stdin_data="$(cat)"
  fi

  _plugins="$(yaml_list_plugins 2>/dev/null || true)"
  for _pname in $_plugins; do
    [ -n "$_pname" ] || continue
    yaml_plugin_enabled "$_pname" 2>/dev/null || continue

    RNEX_PLUGIN_DIR="$RNEX_ROOT/.rnex/plugins/$_pname"
    _h_cand="$(_resolve_plugin_hook_script "$RNEX_ROOT" "$_pname" "git_${_hook_name}.sh" "${_hook_name}.sh" || true)"

    if [ -n "$_h_cand" ] && [ -f "$_h_cand" ]; then
      chmod +x "$_h_cand" 2>/dev/null || true
      if [ -n "$_stdin_data" ]; then
        printf '%s\n' "$_stdin_data"
      fi | env \
        NEXUS_DIR="$RNEX_ROOT" \
        WORKSPACE_YAML="$RNEX_ROOT/${RNEX_CONFIG_FILE:-rnex.yaml}" \
        WORKSPACE_LOCAL_YAML="$RNEX_ROOT/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}" \
        RNEX_ROOT="$RNEX_ROOT" \
        RNEX_CONFIG_MERGED="$RNEX_CONFIG_MERGED" \
        RNEX_PLUGIN_DIR="$RNEX_PLUGIN_DIR" \
        RNEX_CMD="$RNEX_CMD" \
        RNEX_ARGS="$RNEX_ARGS" \
        RNEX_QUIET="$RNEX_QUIET" \
        RNEX_LIB_DIR="${RNEX_LIB_DIR:-}" \
        RNEX_CONFIG_FILE="${RNEX_CONFIG_FILE:-rnex.yaml}" \
        RNEX_LOCAL_CONFIG_FILE="${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}" \
        "$_h_cand" "$@" || true
    fi
  done
}

# ---- Git Hooks Management --------------------------------------------------

_create_hook_script() {
  _dst="$1"
  _hook_type="$2"

  # Preserve custom / repository-owned wrappers that are not auto-managed by rnex
  if [ -f "$_dst" ] && ! grep -q "Managed automatically by rnex" "$_dst" 2>/dev/null; then
    return 0
  fi

  _sub_tmp="$(mktemp)"
  cat > "$_sub_tmp" <<HOOK_EOF
#!/bin/sh
# Repo Nexus Git Hook: $_hook_type
# Managed automatically by rnex. Do not edit manually.

_dir="\$(cd "\$(dirname "\$0")/../.." 2>/dev/null && pwd -P)"
if [ -x "\$_dir/rnex" ]; then
  "\$_dir/rnex" hooks run $_hook_type "\$@"
elif command -v rnex >/dev/null 2>&1; then
  rnex hooks run $_hook_type "\$@"
fi
HOOK_EOF

  chmod +x "$_sub_tmp"

  # Avoid rewriting / modifying file if already identical (prevents inode churn & self-rewrite)
  if [ -f "$_dst" ] && cmp -s "$_sub_tmp" "$_dst"; then
    rm -f "$_sub_tmp"
    return 0
  fi

  mkdir -p "$(dirname "$_dst")"
  mv "$_sub_tmp" "$_dst"
}

_install_managed_hook_scripts() {
  _imh_dir="$1"
  mkdir -p "$_imh_dir"
  for _h in $RNEX_MANAGED_GIT_HOOKS; do
    _create_hook_script "$_imh_dir/$_h" "$_h"
  done
}

cmd_hooks_install_dir() {
  _ws_dir="$1"
  if ! git -C "$_ws_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "Directory '$_ws_dir' is not a Git repository. Run 'git init' first."
  fi
  _install_managed_hook_scripts "$_ws_dir/.rnex/hooks"
  git -C "$_ws_dir" config core.hooksPath .rnex/hooks
  log_ok "Configured Git hooks in .rnex/hooks (core.hooksPath = .rnex/hooks)"
}

cmd_hooks_uninstall_dir() {
  _ws_dir="$1"
  if git -C "$_ws_dir" config --get core.hooksPath >/dev/null 2>&1; then
    git -C "$_ws_dir" config --unset core.hooksPath || true
  fi
  rm -rf "$_ws_dir/.rnex/hooks"
  log_ok "Uninstalled Repo Nexus Git hooks (core.hooksPath unset)"
}

# Re-sync workspace if sync_stamp is stale or config files changed in git diff
_sync_if_hook_config_changed() {
  _shc_hook="$1"
  shift || true
  _cfg_changed=0
  _stamp_file=""
  if [ -f "$NEXUS_DIR/.rnex/sync_stamp" ]; then
    _stamp_file="$NEXUS_DIR/.rnex/sync_stamp"
  elif [ -f "$NEXUS_DIR/.rnex/.sync_stamp" ]; then
    _stamp_file="$NEXUS_DIR/.rnex/.sync_stamp"
  fi

  if [ -z "$_stamp_file" ] || [ "$(get_config_sum "$NEXUS_DIR")" != "$(cat "$_stamp_file" 2>/dev/null)" ]; then
    _cfg_changed=1
  else
    case "$_shc_hook" in
      post-merge)
        git -C "$NEXUS_DIR" diff-tree -r --name-only ORIG_HEAD HEAD 2>/dev/null | grep -qE "(^rnex\.yaml$|^\.local\.rnex\.yaml$)" && _cfg_changed=1
        ;;
      post-checkout)
        [ -n "${1:-}" ] && [ -n "${2:-}" ] && git -C "$NEXUS_DIR" diff-tree -r --name-only "$1" "$2" 2>/dev/null | grep -qE "(^rnex\.yaml$|^\.local\.rnex\.yaml$)" && _cfg_changed=1
        ;;
      pre-commit)
        git -C "$NEXUS_DIR" diff --cached --name-only 2>/dev/null | grep -qE "(^rnex\.yaml$|^\.local\.rnex\.yaml$)" && _cfg_changed=1
        ;;
    esac
  fi

  if [ "$_cfg_changed" -eq 1 ]; then
    cmd_sync -y --quiet || true
  fi
}

# Delegate to repository-owned hook in scripts/githooks/<hook> or .githooks/<hook>
_delegate_repo_githook() {
  _drg_hook="$1"; _drg_non_blocking="$2"; _drg_stdin="$3"
  shift 3 || true

  _drg_script=""
  if [ -x "$NEXUS_DIR/scripts/githooks/$_drg_hook" ]; then
    _drg_script="$NEXUS_DIR/scripts/githooks/$_drg_hook"
  elif [ -x "$NEXUS_DIR/.githooks/$_drg_hook" ]; then
    _drg_script="$NEXUS_DIR/.githooks/$_drg_hook"
  fi
  [ -n "$_drg_script" ] || return 0

  if [ -n "$_drg_stdin" ]; then
    if [ "$_drg_non_blocking" -eq 1 ]; then
      printf '%s\n' "$_drg_stdin" | "$_drg_script" "$@" || true
    else
      printf '%s\n' "$_drg_stdin" | "$_drg_script" "$@" || return $?
    fi
  else
    if [ "$_drg_non_blocking" -eq 1 ]; then
      "$_drg_script" "$@" || true
    else
      "$_drg_script" "$@" || return $?
    fi
  fi
}

cmd_hooks() {
  case "${1:-status}" in
    install|uninstall)
      _h_action="$1"
      require_workspace
      _local=0
      shift || true
      while [ $# -gt 0 ]; do
        case "$1" in
          --local) _local=1 ;;
        esac
        shift
      done
      if [ "$_h_action" = "install" ]; then
        cmd_hooks_install_dir "$NEXUS_DIR"
        _gh_val="true"
      else
        cmd_hooks_uninstall_dir "$NEXUS_DIR"
        _gh_val="false"
      fi
      if [ "$_local" -eq 1 ]; then
        yaml_set_top_level_local "git_hooks" "$_gh_val"
        log_dim "Recorded git_hooks: $_gh_val in $RNEX_LOCAL_CONFIG_FILE"
      else
        yaml_set_top_level "git_hooks" "$_gh_val"
        log_dim "Recorded git_hooks: $_gh_val in $RNEX_CONFIG_FILE"
      fi
      _load_git_hooks
      ;;
    status)
      require_workspace
      printf '\n%bRepo Nexus Git Hooks Status%b\n' "$_B" "$_NC"
      printf '=%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28
      printf '\n\n'

      printf '  %b●%b Configuration:  ' "$_DIM" "$_NC"
      case "$GIT_HOOKS_CONFIG" in
        true|yes|1) printf '%bgit_hooks: true%b %b(enabled in config)%b\n' "$_G" "$_NC" "$_DIM" "$_NC" ;;
        false|no|0) printf '%bgit_hooks: false%b %b(disabled in config)%b\n' "$_Y" "$_NC" "$_DIM" "$_NC" ;;
        *)          printf '%bnot configured%b %b(defaults to active if git repo)%b\n' "$_DIM" "$_NC" "$_DIM" "$_NC" ;;
      esac

      _hp="$(git -C "$NEXUS_DIR" config --get core.hooksPath 2>/dev/null || true)"
      if [ "$_hp" = ".rnex/hooks" ] || [ "$_hp" = "$NEXUS_DIR/.rnex/hooks" ]; then
        printf '  %b●%b core.hooksPath: %s %b(active)%b\n' "$_G" "$_NC" "$_hp" "$_DIM" "$_NC"
      elif [ -n "$_hp" ]; then
        printf '  %b!%b core.hooksPath: %s %b(external/custom)%b\n' "$_Y" "$_NC" "$_hp" "$_DIM" "$_NC"
      else
        printf '  %b○%b core.hooksPath: %b(not configured — run "rnex hooks install")%b\n' "$_DIM" "$_NC" "$_DIM" "$_NC"
      fi

      printf '\n%bInstalled Hooks in .rnex/hooks/:%b\n' "$_BOLD" "$_NC"
      for _h in $RNEX_MANAGED_GIT_HOOKS; do
        if [ -f "$NEXUS_DIR/.rnex/hooks/$_h" ]; then
          printf '  %b✓%b %-15s %b(installed)%b\n' "$_G" "$_NC" "$_h" "$_DIM" "$_NC"
        else
          printf '  %b○%b %-15s %b(not installed)%b\n' "$_DIM" "$_NC" "$_h" "$_DIM" "$_NC"
        fi
      done

      _has_triggers=0
      _plugins="$(yaml_list_plugins 2>/dev/null || true)"
      for _pname in $_plugins; do
        [ -n "$_pname" ] || continue
        yaml_plugin_enabled "$_pname" 2>/dev/null || continue
        _active_trigger="$(yaml_plugin_get "$_pname" "lint_trigger" 2>/dev/null || true)"
        if [ -n "$_active_trigger" ] || [ -d "$NEXUS_DIR/.rnex/plugins/$_pname/hooks" ]; then
          if [ "$_has_triggers" -eq 0 ]; then
            printf '\n%bActive Plugin Triggers:%b\n' "$_BOLD" "$_NC"
            _has_triggers=1
          fi
          if [ -n "$_active_trigger" ]; then
            printf '  %b●%b %s: %s\n' "$_G" "$_NC" "$_pname" "$_active_trigger"
          else
            printf '  %b○%b %s: (manual only / no trigger set in rnex.yaml)\n' "$_DIM" "$_NC" "$_pname"
          fi
        fi
      done
      [ "$_has_triggers" -eq 1 ] && printf '\n'
      return 0
      ;;
    run)
      shift
      _hook_name="$1"
      shift || true
      export _RNEX_INSIDE_HOOK=1
      require_workspace
      case "$_hook_name" in
        post-merge|post-checkout)
          _sync_if_hook_config_changed "$_hook_name" "$@"
          run_plugin_git_hooks "$_hook_name" "$@"
          _delegate_repo_githook "$_hook_name" 1 "" "$@"
          ;;
        post-commit)
          run_plugin_git_hooks "post-commit" "$@"
          _delegate_repo_githook "post-commit" 1 "" "$@"
          ;;
        pre-commit)
          _sync_if_hook_config_changed "pre-commit" "$@"
          run_plugin_git_hooks "pre-commit" "$@"
          _delegate_repo_githook "pre-commit" 0 "" "$@" || return $?
          ;;
        pre-push)
          _stdin_data=""
          if [ ! -t 0 ]; then
            _stdin_data="$(cat)"
          fi
          if [ -n "$_stdin_data" ]; then
            printf '%s\n' "$_stdin_data" | run_plugin_git_hooks "pre-push" "$@"
          else
            run_plugin_git_hooks "pre-push" "$@"
          fi
          _delegate_repo_githook "pre-push" 0 "$_stdin_data" "$@" || return $?
          ;;
      esac
      return 0
      ;;
    *)
      die "Unknown hooks command: $1. Usage: rnex hooks <install|uninstall|status>"
      ;;
  esac
}
