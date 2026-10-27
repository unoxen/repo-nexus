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

  # 2. Execute configured commands from rnex_hooks.<event_name>
  if [ -z "$_hook_target_plugin" ]; then
    _hook_norm="$(printf '%s' "$_hook_phase_cmd" | tr '-' '_')"
    case ":${RNEX_HOOK_ACTIVE:-}:" in
      *":${_hook_norm}:"*)
        # Re-entrant loop guard: skip re-entrant execution of this hook event
        ;;
      *)
        _rnex_cmds="$(yaml_get_rnex_hook_commands "$_hook_norm" 2>/dev/null || true)"
        if [ -n "$_rnex_cmds" ]; then
          _prev_active="${RNEX_HOOK_ACTIVE:-}"
          export RNEX_HOOK_ACTIVE="${RNEX_HOOK_ACTIVE:+${RNEX_HOOK_ACTIVE}:}${_hook_norm}"
          _is_blocking=0
          case "$_hook_norm" in
            before_*) _is_blocking=1 ;;
          esac
          _old_ifs="$IFS"
          IFS='
'
          for _rcmd in $_rnex_cmds; do
            IFS="$_old_ifs"
            [ -n "$_rcmd" ] || continue
            if [ "$_is_blocking" -eq 1 ]; then
              (
                RNEX_ROOT="$_hook_root"
                RNEX_CONFIG_MERGED="$_hook_config_merged"
                RNEX_CMD="$_hook_cmd"
                RNEX_ARGS="$_hook_args"
                RNEX_HOOK_EVENT="$_hook_phase_cmd"
                RNEX_HOOK_ARGS="$_hook_args"
                RNEX_QUIET="$_hook_quiet"
                RNEX_PROVIDER_SKILL_DIRS="$_skill_dirs"
                export RNEX_ROOT RNEX_CONFIG_MERGED RNEX_CMD RNEX_ARGS RNEX_HOOK_EVENT RNEX_HOOK_ARGS RNEX_QUIET RNEX_PROVIDER_SKILL_DIRS RNEX_LIB_DIR NEXUS_DIR WORKSPACE_YAML WORKSPACE_LOCAL_YAML
                cd "$_hook_root" && eval "$_rcmd"
              ) || {
                _cmd_rc=$?
                export RNEX_HOOK_ACTIVE="$_prev_active"
                WORKSPACE_LOCAL_YAML="$_old_local_yaml"
                WORKSPACE_YAML="$_old_yaml"
                NEXUS_DIR="$_old_nexus"
                return "$_cmd_rc"
              }
            else
              (
                RNEX_ROOT="$_hook_root"
                RNEX_CONFIG_MERGED="$_hook_config_merged"
                RNEX_CMD="$_hook_cmd"
                RNEX_ARGS="$_hook_args"
                RNEX_HOOK_EVENT="$_hook_phase_cmd"
                RNEX_HOOK_ARGS="$_hook_args"
                RNEX_QUIET="$_hook_quiet"
                RNEX_PROVIDER_SKILL_DIRS="$_skill_dirs"
                export RNEX_ROOT RNEX_CONFIG_MERGED RNEX_CMD RNEX_ARGS RNEX_HOOK_EVENT RNEX_HOOK_ARGS RNEX_QUIET RNEX_PROVIDER_SKILL_DIRS RNEX_LIB_DIR NEXUS_DIR WORKSPACE_YAML WORKSPACE_LOCAL_YAML
                cd "$_hook_root" && eval "$_rcmd"
              ) || true
            fi
          done
          IFS="$_old_ifs"
          export RNEX_HOOK_ACTIVE="$_prev_active"
        fi
        ;;
    esac
  fi
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

  mkdir -p "$(dirname "$_dst")"
  _sub_tmp="$(mktemp "${_dst}.tmp.XXXXXX" 2>/dev/null || mktemp)"
  cat > "$_sub_tmp" <<HOOK_EOF
#!/bin/sh
# Repo Nexus Git Hook: $_hook_type
# Managed automatically by rnex. Do not edit manually.

_dir="\$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "\$_dir" ] || _dir="\$(cd "\$(dirname "\$0")/../.." 2>/dev/null && pwd -P)"
if [ -x "\$_dir/rnex" ]; then
  "\$_dir/rnex" _hook $_hook_type "\$@"
elif command -v rnex >/dev/null 2>&1; then
  rnex _hook $_hook_type "\$@"
fi
HOOK_EOF

  chmod +x "$_sub_tmp"

  # Avoid rewriting / modifying file if already identical (prevents inode churn & self-rewrite)
  if [ -f "$_dst" ] && cmp -s "$_sub_tmp" "$_dst"; then
    rm -f "$_sub_tmp"
    return 0
  fi

  cp "$_sub_tmp" "$_dst" 2>/dev/null || mv "$_sub_tmp" "$_dst" 2>/dev/null || true
  rm -f "$_sub_tmp" 2>/dev/null || true
}

_install_managed_hook_scripts() {
  _imh_dir="$1"
  mkdir -p "$_imh_dir"
  for _h in $RNEX_MANAGED_GIT_HOOKS; do
    _create_hook_script "$_imh_dir/$_h" "$_h"
  done
}

install_git_hooks() {
  _ws_dir="${1:-$NEXUS_DIR}"
  if ! git -C "$_ws_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  _git_dir="$(cd "$_ws_dir" 2>/dev/null && git rev-parse --git-dir 2>/dev/null)"
  case "$_git_dir" in
    /*) ;;
    *)  _git_dir="$_ws_dir/$_git_dir" ;;
  esac
  [ -d "$_git_dir" ] || return 0
  _hooks_dir="$_git_dir/hooks"
  _install_managed_hook_scripts "$_hooks_dir"
  # Clean up legacy .rnex/hooks if core.hooksPath was previously set to it
  _hp="$(git -C "$_ws_dir" config --get core.hooksPath 2>/dev/null || true)"
  if [ "$_hp" = ".rnex/hooks" ] || [ "$_hp" = "$_ws_dir/.rnex/hooks" ]; then
    git -C "$_ws_dir" config --unset core.hooksPath || true
  fi
  rm -rf "$_ws_dir/.rnex/hooks" 2>/dev/null || true
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

# Execute a Git hook by name, reading configured commands from git.hooks.<hook_name>,
# running active plugin git hooks, and delegating to repo-owned hooks.
run_git_hook() {
  _hook_name="$1"
  shift 2>/dev/null || true
  export _RNEX_INSIDE_HOOK=1
  require_workspace

  _is_blocking=0
  case "$_hook_name" in
    pre-commit|pre-push) _is_blocking=1 ;;
    post-merge|post-checkout)
      build_ai_instructions "$NEXUS_DIR" 2>/dev/null || true
      ;;
  esac

  _stdin_data=""
  if [ ! -t 0 ]; then
    _stdin_data="$(cat)"
  fi

  # 1. Execute configured commands from git.hooks.<hook_name>
  _cmds="$(yaml_get_git_hook_commands "$_hook_name" 2>/dev/null || true)"
  if [ -n "$_cmds" ]; then
    _old_ifs="$IFS"
    IFS='
'
    for _c in $_cmds; do
      IFS="$_old_ifs"
      [ -n "$_c" ] || continue
      if [ "$_is_blocking" -eq 1 ]; then
        (cd "$NEXUS_DIR" && eval "$_c") || return $?
      else
        (cd "$NEXUS_DIR" && eval "$_c") || true
      fi
    done
    IFS="$_old_ifs"
  fi

  # 2. Plugin git hooks
  if [ -n "$_stdin_data" ]; then
    printf '%s\n' "$_stdin_data" | run_plugin_git_hooks "$_hook_name" "$@"
  else
    run_plugin_git_hooks "$_hook_name" "$@"
  fi

  # 3. Delegate to repository-owned githook in scripts/githooks or .githooks
  _drg_blocking=1
  [ "$_is_blocking" -eq 1 ] && _drg_blocking=0
  _drg_rc=0
  _delegate_repo_githook "$_hook_name" "$_drg_blocking" "$_stdin_data" "$@" || _drg_rc=$?
  if [ "$_is_blocking" -eq 1 ] && [ "$_drg_rc" -ne 0 ]; then
    return "$_drg_rc"
  fi

  return 0
}
