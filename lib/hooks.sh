#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/hooks.sh — Automated Git hooks management and event dispatch
# ============================================================================

RNEX_MANAGED_GIT_HOOKS="post-merge post-checkout post-commit pre-commit pre-push"

# Validate that a hook name adheres strictly to POSIX Git hook naming conventions.
# Pattern: ^[a-z][a-z0-9-]*$ (prevents path traversal and shell injection attacks).
#
# @param $1 Hook name to validate.
# @returns 0 if valid, 1 otherwise.
# @pure
hooks_validate_name() {
  _hvn_name="${1:-}"
  case "$_hvn_name" in
    "") return 1 ;;
    [!a-z]*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
    *) return 0 ;;
  esac
}

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

  _rphs_src="$(plugin_resolve_dir "$_rphs_plugin" 2>/dev/null || true)"
  [ -n "$_rphs_src" ] || _rphs_src="$(find_plugin_dir "$_rphs_plugin" 2>/dev/null || true)"
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

# Resolve the canonical filesystem path to the Git hooks directory (.git/hooks).
# Handles standard repositories, git worktrees, and custom gitdirs.
#
# @param $1 Optional workspace root path (defaults to $NEXUS_DIR or current directory).
# @returns Outputs absolute or canonical path to the hooks directory.
# @pure Does not mutate filesystem state.
hooks_get_dir() {
  _hgd_ws="${1:-${NEXUS_DIR:-.}}"
  if ! git -C "$_hgd_ws" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi
  _hgd_path="$(git -C "$_hgd_ws" rev-parse --git-path hooks 2>/dev/null || true)"
  if [ -z "$_hgd_path" ]; then
    if [ -d "$_hgd_ws/.git" ]; then
      _hgd_path="$_hgd_ws/.git/hooks"
    else
      return 1
    fi
  fi
  case "$_hgd_path" in
    /*) ;;
    *)  _hgd_path="$_hgd_ws/$_hgd_path" ;;
  esac
  printf '%s' "$_hgd_path"
  return 0
}

# Verify whether an executable Repo Nexus hook wrapper is installed in .git/hooks.
# Checks that the file exists, is executable, and contains the official wrapper marker.
#
# @param $1 Hook name to inspect (e.g., pre-commit, post-merge).
# @param $2 Optional workspace root path.
# @returns 0 if installed and valid, 1 otherwise.
# @pure
hooks_is_wrapper_installed() {
  _hiw_name="$1"
  _hiw_ws="${2:-${NEXUS_DIR:-.}}"
  hooks_validate_name "$_hiw_name" || return 1
  _hiw_dir="$(hooks_get_dir "$_hiw_ws")" || return 1
  _hiw_file="$_hiw_dir/$_hiw_name"
  [ -f "$_hiw_file" ] || return 1
  [ -x "$_hiw_file" ] || return 1
  if grep -q "REPO-NEXUS-HOOK-WRAPPER" "$_hiw_file" 2>/dev/null || \
     grep -q "Managed automatically by rnex" "$_hiw_file" 2>/dev/null; then
    return 0
  fi
  # Also consider installed if preserved user wrapper or custom team hook is active
  if [ -f "$_hiw_dir/${_hiw_name}.user" ]; then
    return 0
  fi
  return 1
}

# Install or update an executable Repo Nexus hook wrapper in .git/hooks.
# Preserves existing non-managed user hooks:
# - If the hook has configured commands in rnex.yaml, moves existing hook to <hook>.user and chains it.
# - If the hook has no configured commands, preserves the custom wrapper in place untouched.
# Prevents self-rewrite / inode churn by checking cmp -s before writing.
#
# @param $1 Hook name to install.
# @param $2 Optional workspace root path.
# @returns 0 on success, 1 on failure.
# @sideEffects Creates/modifies files in .git/hooks/.
hooks_install_wrapper() {
  _hiw_hook="$1"
  _hiw_ws="${2:-${NEXUS_DIR:-.}}"
  hooks_validate_name "$_hiw_hook" || return 1
  _hiw_dir="$(hooks_get_dir "$_hiw_ws")" || return 1
  mkdir -p "$_hiw_dir"
  _hiw_dst="$_hiw_dir/$_hiw_hook"

  # If a custom non-sample hook exists without Repo Nexus marker:
  if [ -f "$_hiw_dst" ]; then
    if ! grep -q "REPO-NEXUS-HOOK-WRAPPER" "$_hiw_dst" 2>/dev/null && \
       ! grep -q "Managed automatically by rnex" "$_hiw_dst" 2>/dev/null; then
      _hook_cmds="$(yaml_get_git_hook_commands "$_hiw_hook" 2>/dev/null || true)"
      if [ -n "$_hook_cmds" ]; then
        # Hook has configured rnex commands: preserve user hook as .user and chain
        mv "$_hiw_dst" "${_hiw_dst}.user"
        chmod +x "${_hiw_dst}.user" 2>/dev/null || true
      else
        # Hook has no custom rnex commands: preserve custom wrapper untouched in place
        return 0
      fi
    fi
  fi

  _sub_tmp="$(mktemp "${_hiw_dst}.tmp.XXXXXX" 2>/dev/null || mktemp)"
  cat > "$_sub_tmp" <<HOOK_EOF
#!/bin/sh
# Repo Nexus Git Hook: $_hiw_hook
# REPO-NEXUS-HOOK-WRAPPER
# Managed automatically by rnex. Do not edit manually.

_dir="\$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "\$_dir" ] || _dir="\$(cd "\$(dirname "\$0")/../.." 2>/dev/null && pwd -P)"
if [ -x "\$_dir/rnex" ]; then
  "\$_dir/rnex" _hook $_hiw_hook "\$@"
elif command -v rnex >/dev/null 2>&1; then
  rnex _hook $_hiw_hook "\$@"
fi
_rnex_rc=\$?

# Chain preserved user hook if present
_hooks_dir="\$(dirname "\$0")"
if [ -x "\$_hooks_dir/${_hiw_hook}.user" ]; then
  "\$_hooks_dir/${_hiw_hook}.user" "\$@" || exit \$?
fi

exit \$_rnex_rc
HOOK_EOF

  chmod +x "$_sub_tmp"

  # Avoid rewriting / modifying file if already identical (prevents inode churn & self-rewrite)
  if [ -f "$_hiw_dst" ] && cmp -s "$_sub_tmp" "$_hiw_dst"; then
    rm -f "$_sub_tmp"
    return 0
  fi

  cp "$_sub_tmp" "$_hiw_dst" 2>/dev/null || mv "$_sub_tmp" "$_hiw_dst" 2>/dev/null || true
  rm -f "$_sub_tmp" 2>/dev/null || true
  chmod +x "$_hiw_dst" 2>/dev/null || true
  return 0
}

# Synchronize all configured Git hooks into .git/hooks wrappers.
# 1. Installs/updates wrappers for all configured hooks from yaml_get_git_hooks.
# 2. Removes stale Repo Nexus wrappers for hooks no longer configured, restoring <hook>.user if present.
# 3. Cleans up legacy .rnex/hooks if core.hooksPath was configured to it.
#
# @param $1 Optional workspace root path.
# @returns 0 on success.
# @sideEffects Modifies files in .git/hooks/.
hooks_sync_all() {
  _hsa_ws="${1:-${NEXUS_DIR:-.}}"
  _hsa_dir="$(hooks_get_dir "$_hsa_ws")" || return 0
  mkdir -p "$_hsa_dir"

  _configured_hooks="$(yaml_get_git_hooks 2>/dev/null || true)"

  # 1. Install or update wrappers for all configured hooks
  for _hsa_hook in $_configured_hooks; do
    [ -n "$_hsa_hook" ] || continue
    hooks_install_wrapper "$_hsa_hook" "$_hsa_ws"
  done

  # 2. Clean up stale Repo Nexus wrappers for hooks no longer configured
  if [ -d "$_hsa_dir" ]; then
    for _hsa_file in "$_hsa_dir"/*; do
      [ -f "$_hsa_file" ] || continue
      case "$_hsa_file" in
        *.sample|*.user|*.tmp.*) continue ;;
      esac
      _hsa_base="$(basename "$_hsa_file")"
      if grep -q "REPO-NEXUS-HOOK-WRAPPER" "$_hsa_file" 2>/dev/null || \
         grep -q "Managed automatically by rnex" "$_hsa_file" 2>/dev/null; then
        if [ -n "$_configured_hooks" ] && printf '%s\n' "$_configured_hooks" | grep -qx "$_hsa_base"; then
          : # Configured hook, keep active
        else
          rm -f "$_hsa_file"
          # Restore preserved user hook if present
          if [ -f "$_hsa_dir/${_hsa_base}.user" ]; then
            mv "$_hsa_dir/${_hsa_base}.user" "$_hsa_file"
            chmod +x "$_hsa_file" 2>/dev/null || true
          fi
        fi
      fi
    done
  fi

  # 3. Clean up legacy .rnex/hooks if core.hooksPath was previously set to it
  _hp="$(git -C "$_hsa_ws" config --get core.hooksPath 2>/dev/null || true)"
  if [ "$_hp" = ".rnex/hooks" ] || [ "$_hp" = "$_hsa_ws/.rnex/hooks" ]; then
    git -C "$_hsa_ws" config --unset core.hooksPath 2>/dev/null || true
  fi
  rm -rf "$_hsa_ws/.rnex/hooks" 2>/dev/null || true
  return 0
}

# Verify that all configured Git hooks have active wrappers installed in .git/hooks.
#
# @param $1 Optional workspace root path.
# @returns 0 if all configured hooks are installed and executable,
#          1 if any configured hook wrapper is missing/invalid,
#          2 if no Git hooks are configured in workspace.
# @pure
hooks_verify_all() {
  _hva_ws="${1:-${NEXUS_DIR:-.}}"
  _hva_hooks="$(yaml_get_git_hooks 2>/dev/null || true)"
  [ -n "$_hva_hooks" ] || return 2

  _hva_dir="$(hooks_get_dir "$_hva_ws")" || return 1
  [ -d "$_hva_dir" ] || return 1

  for _hva_h in $_hva_hooks; do
    [ -n "$_hva_h" ] || continue
    if ! hooks_is_wrapper_installed "$_hva_h" "$_hva_ws"; then
      return 1
    fi
  done
  return 0
}

# Backward compatibility wrapper for install_git_hooks
install_git_hooks() {
  _ws_dir="${1:-${NEXUS_DIR:-.}}"
  if ! git -C "$_ws_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  for _imh in $RNEX_MANAGED_GIT_HOOKS; do
    hooks_install_wrapper "$_imh" "$_ws_dir"
  done
  hooks_sync_all "$_ws_dir"
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
