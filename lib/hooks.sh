#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/hooks.sh — Automated Git hooks management and event dispatch
# ============================================================================

# ---- Action Command Hook Dispatcher -----------------------------------------

run_hook() {
  _hook_phase_cmd="$1"
  shift 2>/dev/null || true

  _ws="${NEXUS_DIR:-}"
  if [ -z "$_ws" ]; then
    if [ -f rnex.yaml ]; then
      _ws="."
    else
      _ws="$(find_workspace_dir 2>/dev/null || true)"
    fi
  fi
  [ -z "$_ws" ] && return 0
  [ ! -f "$_ws/rnex.yaml" ] && return 0

  _hook_root="$(cd "$_ws" 2>/dev/null && pwd -P)"
  _hook_config_merged="$_hook_root/rnex.yaml"
  _hook_cmd="${_hook_phase_cmd#*_}"
  _hook_file="${_hook_phase_cmd}.sh"
  _hook_args="$*"
  _hook_quiet="${_sync_quiet:-0}"

  _old_nexus="$NEXUS_DIR"
  NEXUS_DIR="$_hook_root"
  _plugins="$(yaml_list_plugins 2>/dev/null || true)"
  _skill_dirs="$(get_active_provider_skill_dirs 2>/dev/null || true)"
  NEXUS_DIR="$_old_nexus"

  for _pname in $_plugins; do
    [ -n "$_pname" ] || continue
    yaml_plugin_enabled "$_pname" 2>/dev/null || continue

    RNEX_PLUGIN_DIR="$_hook_root/.rnex/plugins/$_pname"
    _hook_script="$RNEX_PLUGIN_DIR/hooks/$_hook_file"

    if [ ! -f "$_hook_script" ]; then
      _src_pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
      if [ -n "$_src_pdir" ] && [ -f "$_src_pdir/hooks/$_hook_file" ]; then
        _hook_script="$_src_pdir/hooks/$_hook_file"
      fi
    fi

    if [ -f "$_hook_script" ]; then
      chmod +x "$_hook_script" 2>/dev/null || true
      (
        RNEX_ROOT="$_hook_root"
        RNEX_CONFIG_MERGED="$_hook_config_merged"
        RNEX_CMD="$_hook_cmd"
        RNEX_ARGS="$_hook_args"
        RNEX_QUIET="$_hook_quiet"
        RNEX_PROVIDER_SKILL_DIRS="$_skill_dirs"
        export RNEX_ROOT RNEX_CONFIG_MERGED RNEX_PLUGIN_DIR RNEX_CMD RNEX_ARGS RNEX_QUIET RNEX_PROVIDER_SKILL_DIRS
        # shellcheck disable=SC2329
        rnex_register_user_skill() {
          skill_name="$1"
          target_path="$2"
          for provider_dir in $RNEX_PROVIDER_SKILL_DIRS; do
            mkdir -p "$RNEX_ROOT/$provider_dir"
            cat << EOF > "$RNEX_ROOT/$provider_dir/rnex-${skill_name}.md"
# User Skill: rnex-${skill_name}

CRITICAL: Do not execute inline heuristics. Read and strictly follow the agentic skill protocol at:
\`${target_path}\`
EOF
          done
        }

        # shellcheck disable=SC2329
        rnex_unregister_user_skill() {
          skill_name="$1"
          for provider_dir in $RNEX_PROVIDER_SKILL_DIRS; do
            rm -f "$RNEX_ROOT/$provider_dir/rnex-${skill_name}.md"
          done
        }
        set -- "$@"
        # shellcheck source=/dev/null
        . "$_hook_script"
      ) || true
    fi
  done
  NEXUS_DIR="$_old_nexus"
}

run_plugin_hook() {
  _target_plugin="$1"
  _hook_phase_cmd="$2"
  shift 2 2>/dev/null || true

  _ws="${NEXUS_DIR:-}"
  if [ -z "$_ws" ]; then
    if [ -f rnex.yaml ]; then
      _ws="."
    else
      _ws="$(find_workspace_dir 2>/dev/null || true)"
    fi
  fi
  [ -z "$_ws" ] && return 0
  [ ! -f "$_ws/rnex.yaml" ] && return 0

  _hook_root="$(cd "$_ws" 2>/dev/null && pwd -P)"
  _hook_config_merged="$_hook_root/rnex.yaml"
  _hook_file="${_hook_phase_cmd}.sh"
  _hook_cmd="${_hook_phase_cmd#*_}"
  _hook_args="$*"
  _hook_quiet="${_sync_quiet:-0}"

  _old_nexus="$NEXUS_DIR"
  NEXUS_DIR="$_hook_root"
  _skill_dirs="$(get_active_provider_skill_dirs 2>/dev/null || true)"
  NEXUS_DIR="$_old_nexus"

  RNEX_PLUGIN_DIR="$_hook_root/.rnex/plugins/$_target_plugin"
  _hook_script="$RNEX_PLUGIN_DIR/hooks/$_hook_file"

  if [ ! -f "$_hook_script" ]; then
    _src_pdir="$(find_plugin_dir "$_target_plugin" 2>/dev/null || true)"
    if [ -n "$_src_pdir" ] && [ -f "$_src_pdir/hooks/$_hook_file" ]; then
      _hook_script="$_src_pdir/hooks/$_hook_file"
    fi
  fi

  if [ -f "$_hook_script" ]; then
    chmod +x "$_hook_script" 2>/dev/null || true
    (
      RNEX_ROOT="$_hook_root"
      RNEX_CONFIG_MERGED="$_hook_config_merged"
      RNEX_CMD="$_hook_cmd"
      RNEX_ARGS="$_hook_args"
      RNEX_QUIET="$_hook_quiet"
      RNEX_PROVIDER_SKILL_DIRS="$_skill_dirs"
      export RNEX_ROOT RNEX_CONFIG_MERGED RNEX_PLUGIN_DIR RNEX_CMD RNEX_ARGS RNEX_QUIET RNEX_PROVIDER_SKILL_DIRS
      # shellcheck disable=SC2329
      rnex_register_user_skill() {
        skill_name="$1"
        target_path="$2"
        for provider_dir in $RNEX_PROVIDER_SKILL_DIRS; do
          mkdir -p "$RNEX_ROOT/$provider_dir"
          cat << EOF > "$RNEX_ROOT/$provider_dir/rnex-${skill_name}.md"
# User Skill: rnex-${skill_name}

CRITICAL: Do not execute inline heuristics. Read and strictly follow the agentic skill protocol at:
\`${target_path}\`
EOF
        done
      }

      # shellcheck disable=SC2329
      rnex_unregister_user_skill() {
        skill_name="$1"
        for provider_dir in $RNEX_PROVIDER_SKILL_DIRS; do
          rm -f "$RNEX_ROOT/$provider_dir/rnex-${skill_name}.md"
        done
      }
      set -- "$@"
      # shellcheck source=/dev/null
      . "$_hook_script"
    ) || true
  fi
}

run_plugin_git_hooks() {
  _hook_name="$1"
  shift 2>/dev/null || true

  _ws="${NEXUS_DIR:-}"
  [ -z "$_ws" ] && return 0
  [ ! -f "$_ws/rnex.yaml" ] && return 0

  RNEX_ROOT="$(cd "$_ws" 2>/dev/null && pwd -P)"
  RNEX_CONFIG_MERGED="$RNEX_ROOT/rnex.yaml"
  RNEX_CMD="hooks"
  RNEX_ARGS="$*"
  RNEX_QUIET="${_sync_quiet:-0}"

  _plugins="$(yaml_list_plugins 2>/dev/null || true)"
  for _pname in $_plugins; do
    [ -n "$_pname" ] || continue
    yaml_plugin_enabled "$_pname" 2>/dev/null || continue

    RNEX_PLUGIN_DIR="$RNEX_ROOT/.rnex/plugins/$_pname"
    _h_cand=""
    if [ -f "$RNEX_PLUGIN_DIR/hooks/git_${_hook_name}.sh" ]; then
      _h_cand="$RNEX_PLUGIN_DIR/hooks/git_${_hook_name}.sh"
    elif [ -f "$RNEX_PLUGIN_DIR/hooks/${_hook_name}.sh" ]; then
      _h_cand="$RNEX_PLUGIN_DIR/hooks/${_hook_name}.sh"
    fi

    if [ -z "$_h_cand" ]; then
      _src_pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
      if [ -n "$_src_pdir" ]; then
        if [ -f "$_src_pdir/hooks/git_${_hook_name}.sh" ]; then
          _h_cand="$_src_pdir/hooks/git_${_hook_name}.sh"
        elif [ -f "$_src_pdir/hooks/${_hook_name}.sh" ]; then
          _h_cand="$_src_pdir/hooks/${_hook_name}.sh"
        fi
      fi
    fi

    if [ -n "$_h_cand" ] && [ -f "$_h_cand" ]; then
      chmod +x "$_h_cand" 2>/dev/null || true
      (
        export RNEX_ROOT RNEX_CONFIG_MERGED RNEX_PLUGIN_DIR RNEX_CMD RNEX_ARGS RNEX_QUIET
        "$_h_cand" "$@"
      ) || true
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

cmd_hooks_install_dir() {
  _ws_dir="$1"
  if ! git -C "$_ws_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "Directory '$_ws_dir' is not a Git repository. Run 'git init' first."
  fi
  _h_dir="$_ws_dir/.rnex/hooks"
  mkdir -p "$_h_dir"
  _create_hook_script "$_h_dir/post-merge" "post-merge"
  _create_hook_script "$_h_dir/post-checkout" "post-checkout"
  _create_hook_script "$_h_dir/post-commit" "post-commit"
  _create_hook_script "$_h_dir/pre-commit" "pre-commit"
  _create_hook_script "$_h_dir/pre-push" "pre-push"

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

cmd_hooks() {
  case "${1:-status}" in
    install)
      require_workspace
      _local=0
      shift || true
      while [ $# -gt 0 ]; do
        case "$1" in
          --local) _local=1 ;;
        esac
        shift
      done
      cmd_hooks_install_dir "$NEXUS_DIR"
      if [ "$_local" -eq 1 ]; then
        yaml_set_top_level_local "git_hooks" "true"
        log_dim "Recorded git_hooks: true in $RNEX_LOCAL_CONFIG_FILE"
      else
        yaml_set_top_level "git_hooks" "true"
        log_dim "Recorded git_hooks: true in $RNEX_CONFIG_FILE"
      fi
      _load_git_hooks
      ;;
    uninstall)
      require_workspace
      _local=0
      shift || true
      while [ $# -gt 0 ]; do
        case "$1" in
          --local) _local=1 ;;
        esac
        shift
      done
      cmd_hooks_uninstall_dir "$NEXUS_DIR"
      if [ "$_local" -eq 1 ]; then
        yaml_set_top_level_local "git_hooks" "false"
        log_dim "Recorded git_hooks: false in $RNEX_LOCAL_CONFIG_FILE"
      else
        yaml_set_top_level "git_hooks" "false"
        log_dim "Recorded git_hooks: false in $RNEX_CONFIG_FILE"
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
      for _h in "post-merge" "post-checkout" "post-commit" "pre-commit" "pre-push"; do
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
        post-merge)
          _cfg_changed=0
          if [ ! -f "$NEXUS_DIR/.rnex/.sync_stamp" ] || [ "$(get_config_sum "$NEXUS_DIR")" != "$(cat "$NEXUS_DIR/.rnex/.sync_stamp" 2>/dev/null)" ]; then
            _cfg_changed=1
          elif git -C "$NEXUS_DIR" diff-tree -r --name-only ORIG_HEAD HEAD 2>/dev/null | grep -qE "(^rnex\.yaml$|^\.local\.rnex\.yaml$)"; then
            _cfg_changed=1
          fi
          if [ "$_cfg_changed" -eq 1 ]; then
            cmd_sync -y --quiet || true
          fi
          run_plugin_git_hooks "post-merge" "$@"
          if [ -x "$NEXUS_DIR/scripts/githooks/post-merge" ]; then
            "$NEXUS_DIR/scripts/githooks/post-merge" "$@" || true
          elif [ -x "$NEXUS_DIR/.githooks/post-merge" ]; then
            "$NEXUS_DIR/.githooks/post-merge" "$@" || true
          fi
          return 0
          ;;
        post-checkout)
          _cfg_changed=0
          if [ ! -f "$NEXUS_DIR/.rnex/.sync_stamp" ] || [ "$(get_config_sum "$NEXUS_DIR")" != "$(cat "$NEXUS_DIR/.rnex/.sync_stamp" 2>/dev/null)" ]; then
            _cfg_changed=1
          elif [ -n "$1" ] && [ -n "$2" ] && git -C "$NEXUS_DIR" diff-tree -r --name-only "$1" "$2" 2>/dev/null | grep -qE "(^rnex\.yaml$|^\.local\.rnex\.yaml$)"; then
            _cfg_changed=1
          fi
          if [ "$_cfg_changed" -eq 1 ]; then
            cmd_sync -y --quiet || true
          fi
          run_plugin_git_hooks "post-checkout" "$@"
          if [ -x "$NEXUS_DIR/scripts/githooks/post-checkout" ]; then
            "$NEXUS_DIR/scripts/githooks/post-checkout" "$@" || true
          elif [ -x "$NEXUS_DIR/.githooks/post-checkout" ]; then
            "$NEXUS_DIR/.githooks/post-checkout" "$@" || true
          fi
          return 0
          ;;
        post-commit)
          run_plugin_git_hooks "post-commit" "$@"
          if [ -x "$NEXUS_DIR/scripts/githooks/post-commit" ]; then
            "$NEXUS_DIR/scripts/githooks/post-commit" "$@" || true
          elif [ -x "$NEXUS_DIR/.githooks/post-commit" ]; then
            "$NEXUS_DIR/.githooks/post-commit" "$@" || true
          fi
          return 0
          ;;
        pre-commit)
          _cfg_changed=0
          if [ ! -f "$NEXUS_DIR/.rnex/.sync_stamp" ] || [ "$(get_config_sum "$NEXUS_DIR")" != "$(cat "$NEXUS_DIR/.rnex/.sync_stamp" 2>/dev/null)" ]; then
            _cfg_changed=1
          elif git -C "$NEXUS_DIR" diff --cached --name-only 2>/dev/null | grep -qE "(^rnex\.yaml$|^\.local\.rnex\.yaml$)"; then
            _cfg_changed=1
          fi
          if [ "$_cfg_changed" -eq 1 ]; then
            cmd_sync -y --quiet || true
          fi
          run_plugin_git_hooks "pre-commit" "$@"
          if [ -x "$NEXUS_DIR/scripts/githooks/pre-commit" ]; then
            "$NEXUS_DIR/scripts/githooks/pre-commit" "$@" || return $?
          elif [ -x "$NEXUS_DIR/.githooks/pre-commit" ]; then
            "$NEXUS_DIR/.githooks/pre-commit" "$@" || return $?
          fi
          return 0
          ;;
        pre-push)
          run_plugin_git_hooks "pre-push" "$@"
          if [ -x "$NEXUS_DIR/scripts/githooks/pre-push" ]; then
            "$NEXUS_DIR/scripts/githooks/pre-push" "$@" || return $?
          elif [ -x "$NEXUS_DIR/.githooks/pre-push" ]; then
            "$NEXUS_DIR/.githooks/pre-push" "$@" || return $?
          fi
          return 0
          ;;
      esac
      return 0
      ;;
    *)
      die "Unknown hooks command: $1. Usage: rnex hooks <install|uninstall|status>"
      ;;
  esac
}
