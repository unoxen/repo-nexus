#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/sync.sh — Workspace reconciliation and compilation
# ============================================================================

_write_auto_sync_script() {
  _dir="${1:-$NEXUS_DIR}"
  _bin_dir="$_dir/.rnex/bin"
  mkdir -p "$_bin_dir"
  _script="$_bin_dir/auto-sync.sh"
  cat > "$_script" <<'EOF'
#!/bin/sh
set -e
_ws="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P)"
[ -f "$_ws/rnex.yaml" ] || exit 0

_stamp="$_ws/.rnex/sync_stamp"
[ -f "$_stamp" ] || _stamp="$_ws/.rnex/.sync_stamp"
_cur_sum="$(cd "$_ws" 2>/dev/null && cksum rnex.yaml .local.rnex.yaml 2>/dev/null | cksum | awk '{print $1, $2}')"
_saved_sum=""
[ -f "$_stamp" ] && _saved_sum="$(cat "$_stamp" 2>/dev/null)"

if [ ! -f "$_stamp" ] || [ "$_cur_sum" != "$_saved_sum" ]; then
  if [ -x "$_ws/rnex" ]; then
    "$_ws/rnex" sync -y --quiet
  elif command -v rnex >/dev/null 2>&1; then
    (cd "$_ws" && rnex sync -y --quiet)
  fi
fi
EOF
  chmod +x "$_script"
}

_sync_ai_session_start_hooks() {
  # Claude and other providers manage their own session start hooks in hooks/after_sync.sh
  :
}

cmd_sync() {
  require_workspace
  ensure_repos_dir

  _old_sync_quiet="${_sync_quiet:-0}"
  _sync_auto_yes=0
  _sync_quiet=0
  _sync_upgrade=0

  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) _sync_auto_yes=1 ;;
      -q|--quiet) _sync_quiet=1 ;;
      --upgrade) _sync_upgrade=1 ;;
      -f|--fix) ;; # Accepted silently for backward compatibility
      *) ;;
    esac
    shift
  done

  [ "$_sync_quiet" -eq 0 ] && log_info "Reconciling Repo Nexus workspace at $NEXUS_DIR..."

  # Version detection & non-destructive upgrade
  _vc_res=0
  version_cmp "$WORKSPACE_CONFIG_VERSION" "$RNEX_VERSION" || _vc_res=$?
  if [ "$_vc_res" -eq 2 ] || [ "$_sync_upgrade" -eq 1 ]; then
    upgrade_workspace_config "$WORKSPACE_YAML" "$RNEX_VERSION"
    _load_workspace_version
    _load_repos_dir
    _load_code_workspace
    _load_git_hooks
    [ "$_sync_quiet" -eq 0 ] && log_ok "Upgraded workspace configuration and routing instructions to v$RNEX_VERSION"
  fi

  # Reconcile legacy plugin settings (e.g. karpathy-llm raw_dir -> sources, strip ingest_member_readmes)
  migrate_karpathy_llm_config "$WORKSPACE_YAML"
  [ -f "$WORKSPACE_LOCAL_YAML" ] && migrate_karpathy_llm_config "$WORKSPACE_LOCAL_YAML"

  # --------------------------------------------------------------------------
  # Step 1: Sync hardcoded files & invoke commands that do not depend on config
  # --------------------------------------------------------------------------
  # 1.1. Ensure .gitignore ignores repos/, local configs; ensure .ignore has !repos/*
  reconcile_gitignore "$NEXUS_DIR"

  # 1.2. Reconcile universal workspace instructions in AGENTS.md
  if has_active_provider_instructions; then
    clean_rnex_instructions "$NEXUS_DIR/AGENTS.md"
  else
    merge_rnex_instructions "$NEXUS_DIR/AGENTS.md"
  fi

  # 1.3. Generate auto-sync script and AI session-start hooks (hardcoded harness)
  _write_auto_sync_script "$NEXUS_DIR"
  _sync_ai_session_start_hooks "$NEXUS_DIR"

  # 1.4. Sync core agentic skills into .rnex/skills/ and write rnex-env.sh
  sync_skills

  # --------------------------------------------------------------------------
  # Step 2: Generate .rnex/ai-instructions.md and .rnex/sync_stamp
  # --------------------------------------------------------------------------
  # 2.1. Compile .rnex/ai-instructions.md
  build_ai_instructions "$NEXUS_DIR"

  # 2.2. Update sync stamp (.rnex/sync_stamp)
  update_sync_stamp "$NEXUS_DIR"

  # --------------------------------------------------------------------------
  # Step 3: The rest of synchronization
  # --------------------------------------------------------------------------
  # 3.1. Reconcile plugins (scopes, deterministic sync, lifecycle hooks copy, templates, leaked dir cleanup)
  sync_plugins

  # 3.2. Reconcile Git hooks according to configuration
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
          _install_managed_hook_scripts "$NEXUS_DIR/.rnex/hooks"
        fi
      fi
      ;;
    *)
      _cur_hp="$(git -C "$NEXUS_DIR" config --get core.hooksPath 2>/dev/null || true)"
      if [ "$_cur_hp" = ".rnex/hooks" ] || [ "$_cur_hp" = "$NEXUS_DIR/.rnex/hooks" ]; then
        if [ "${_RNEX_INSIDE_HOOK:-0}" -ne 1 ]; then
          _install_managed_hook_scripts "$NEXUS_DIR/.rnex/hooks"
        fi
      fi
      ;;
  esac

  # 3.3. Reconcile member repos (.rnex/ harness sync)
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

  # 3.4. Reconcile VS Code / Cursor multi-root workspace if configured
  sync_code_workspace

  if [ "$_sync_quiet" -eq 0 ]; then
    log_ok "Sync complete — workspace, plugins, skills, and member .rnex directories reconciled"
  fi
  _sync_quiet="$_old_sync_quiet"
  return 0
}
