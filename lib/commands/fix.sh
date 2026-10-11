#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/fix.sh — Workspace reconciliation, upgrade, and repair
# ============================================================================

cmd_fix() {
  require_workspace
  ensure_repos_dir

  _fix_auto_yes=0
  _fix_quiet=0
  _fix_upgrade_explicit=0

  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) _fix_auto_yes=1 ;;
      -q|--quiet) _fix_quiet=1 ;;
      --upgrade) _fix_upgrade_explicit=1; _fix_auto_yes=1 ;;
      *) ;;
    esac
    shift
  done

  [ "$_fix_quiet" -eq 0 ] && log_info "Reconciling Repo Nexus workspace at $NEXUS_DIR..."

  # Version detection & non-destructive upgrade (integrated as single process)
  _vc_res=0
  version_cmp "$WORKSPACE_CONFIG_VERSION" "$RNEX_VERSION" || _vc_res=$?
  if [ "$_vc_res" -eq 2 ]; then
    upgrade_workspace_config "$WORKSPACE_YAML" "$RNEX_VERSION"
    _load_workspace_version
    _load_repos_dir
    _load_code_workspace
    _load_git_hooks
    _load_copilot
    [ "$_fix_quiet" -eq 0 ] && log_ok "Upgraded workspace configuration and routing instructions to v$RNEX_VERSION"
  fi

  # 1. Ensure .gitignore ignores repos/, .rnex/, and local configs, and strips legacy counters
  reconcile_gitignore "$NEXUS_DIR"

  # 2. Reconcile universal workspace instructions in AGENTS.md
  merge_rnex_instructions "$NEXUS_DIR/AGENTS.md"

  # 3. Sync standard skills, workflows, and provider prompts
  sync_prompts

  # 4. Reconcile Git hooks according to configuration
  case "$GIT_HOOKS_CONFIG" in
    false|no|0)
      _cur_hp="$(git -C "$NEXUS_DIR" config --get core.hooksPath 2>/dev/null || true)"
      if [ "$_cur_hp" = ".rnex/hooks" ] || [ "$_cur_hp" = "$NEXUS_DIR/.rnex/hooks" ]; then
        cmd_hooks_uninstall_dir "$NEXUS_DIR"
      fi
      ;;
    true|yes|1)
      if git -C "$NEXUS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _cur_hp="$(git -C "$NEXUS_DIR" config --get core.hooksPath 2>/dev/null || true)"
        if [ "$_cur_hp" != ".rnex/hooks" ] && [ "$_cur_hp" != "$NEXUS_DIR/.rnex/hooks" ]; then
          cmd_hooks_install_dir "$NEXUS_DIR"
        elif [ "${_RNEX_INSIDE_HOOK:-0}" -ne 1 ]; then
          _hooks_dir="$NEXUS_DIR/.rnex/hooks"
          _create_hook_script "$_hooks_dir/post-merge" "post-merge"
          _create_hook_script "$_hooks_dir/post-commit" "post-commit"
          _create_hook_script "$_hooks_dir/pre-commit" "pre-commit"
          _create_hook_script "$_hooks_dir/pre-push" "pre-push"
        fi
      fi
      ;;
    *)
      _cur_hp="$(git -C "$NEXUS_DIR" config --get core.hooksPath 2>/dev/null || true)"
      if [ "$_cur_hp" = ".rnex/hooks" ] || [ "$_cur_hp" = "$NEXUS_DIR/.rnex/hooks" ]; then
        if [ "${_RNEX_INSIDE_HOOK:-0}" -ne 1 ]; then
          _hooks_dir="$NEXUS_DIR/.rnex/hooks"
          _create_hook_script "$_hooks_dir/post-merge" "post-merge"
          _create_hook_script "$_hooks_dir/post-commit" "post-commit"
          _create_hook_script "$_hooks_dir/pre-commit" "pre-commit"
          _create_hook_script "$_hooks_dir/pre-push" "pre-push"
        fi
      fi
      ;;
  esac

  # 5. Reconcile plugins
  sync_plugins

  # 6. Reconcile member repos
  yaml_list_repos | while read -r _name; do
    [ -n "$_name" ] || continue
    if yaml_repo_enabled "$_name"; then
      _rdir="$(resolve_repo_path "$_name")"
      if [ -d "$_rdir" ]; then
        sync_repo_rnex "$_name"
      else
        log_warn "Member repo '$_name' is missing on disk. Run: rnex clone"
      fi
    fi
  done

  # 7. Reconcile VS Code / Cursor multi-root workspace if configured
  sync_code_workspace

  if [ "$_fix_quiet" -eq 0 ]; then
    log_ok "Fix complete — workspace, plugins, prompts, and member .rnex directories reconciled"
  fi
  return 0
}

cmd_sync() {
  cmd_fix "$@"
}

cmd_update() {
  require_workspace
  _cmp=0
  version_cmp "$WORKSPACE_CONFIG_VERSION" "$RNEX_VERSION" || _cmp=$?
  if [ "$_cmp" -eq 0 ]; then
    log_ok "Workspace configuration and routing instructions are already up to date (v$RNEX_VERSION)"
  elif [ "$_cmp" -eq 1 ]; then
    log_info "Workspace configuration version (v$WORKSPACE_CONFIG_VERSION) is newer than current CLI (v$RNEX_VERSION)"
  fi
  cmd_fix "$@"
}

cmd_upgrade() {
  cmd_update "$@"
}
