#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/sync.sh — Workspace reconciliation and compilation
# ============================================================================

# Write the standalone .rnex/bin/rnex-auto-sync.sh helper used by hooks and subshells
# to rapidly verify workspace stamp checksum and trigger rnex sync on config changes.
_write_auto_sync_script() {
  _dir="${1:-$NEXUS_DIR}"
  _bin_dir="$_dir/.rnex/bin"
  mkdir -p "$_bin_dir"
  _script="$_bin_dir/rnex-auto-sync.sh"
  cat > "$_script" <<'EOF'
#!/bin/sh
set -e
_ws="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P)"
[ -f "$_ws/rnex.yaml" ] || exit 0

_stamp="$_ws/.rnex/sync_stamp"
_cur_sum="$(cd "$_ws" 2>/dev/null && cksum rnex.yaml .local.rnex.yaml 2>/dev/null | cksum | awk '{print $1, $2}')"
_saved_sum=""
[ -f "$_stamp" ] && _saved_sum="$(cat "$_stamp" 2>/dev/null)"

if [ ! -f "$_stamp" ] || [ "$_cur_sum" != "$_saved_sum" ]; then
  if [ -x "$_ws/rnex" ]; then
    "$_ws/rnex" --ignore-hooks sync -y --quiet
  elif command -v rnex >/dev/null 2>&1; then
    (cd "$_ws" && rnex --ignore-hooks sync -y --quiet)
  fi
fi
EOF
  chmod +x "$_script"
}

# Primary workspace reconciliation command:
# Reconciles .gitignore / .ignore routing, AGENTS.md / provider instruction files,
# core skills, AI instruction compilation, active plugins, Git hooks, member
# repositories, and VS Code / Cursor workspace files.
# Usage:
#   rnex sync [-y|--yes] [-q|--quiet]
cmd_sync() {
  require_workspace
  ensure_repos_dir

  _old_sync_quiet="${_sync_quiet:-0}"
  _sync_auto_yes=0
  _sync_quiet=0

  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) _sync_auto_yes=1 ;;
      -q|--quiet) _sync_quiet=1 ;;
      *) ;;
    esac
    shift
  done

  [ "$_sync_quiet" -eq 0 ] && log_info "Reconciling Repo Nexus workspace at $NEXUS_DIR..."

  # --------------------------------------------------------------------------
  # Step 1: Sync hardcoded files & invoke commands that do not depend on config
  # --------------------------------------------------------------------------
  # 1.1. Ensure .gitignore ignores repos/, local configs; ensure .ignore has !repos/*
  reconcile_gitignore "$NEXUS_DIR"

  # 1.2. Reconcile universal workspace instructions in AGENTS.md (permanent main context file)
  # and all existing permanent provider instructions files
  reconcile_ai_instructions_files "$NEXUS_DIR"

  # 1.3. Generate auto-sync script (hardcoded harness)
  _write_auto_sync_script "$NEXUS_DIR"

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
  # 3.1. Reconcile plugins (scopes, deterministic sync, lifecycle hooks copy, templates)
  sync_plugins

  # 3.2. Reconcile Git hooks
  if [ -e "$NEXUS_DIR/.git" ]; then
    hooks_sync_all "$NEXUS_DIR"
    if [ "$_sync_quiet" -eq 0 ]; then
      _synced_hooks="$(yaml_get_git_hooks 2>/dev/null || true)"
      if [ -n "$_synced_hooks" ]; then
        log_ok "Synchronized Git hook wrappers in $(hooks_get_dir "$NEXUS_DIR" 2>/dev/null || echo ".git/hooks")"
      fi
    fi
  fi

  # 3.3. Reconcile member repos (<repos_dir> unlisted pruning & missing clone checks)
  prune_unlisted_repos "$REPOS_DIR"
  yaml_list_repos | while read -r _name; do
    [ -n "$_name" ] || continue
    if yaml_repo_enabled "$_name"; then
      _rdir="$(resolve_repo_path "$_name")"
      if [ ! -d "$_rdir" ]; then
        log_warn "Member repo '$_name' is missing on disk. Run: rnex clone"
      fi
    fi
  done

  # 3.4. Reconcile VS Code / Cursor multi-root workspace if configured
  sync_code_workspace

  # 3.5. Validate configuration schema, deprecated keys, and declared plugins (Fail-Fast)
  _sync_validation_failed=0
  if command -v validate_workspace_config >/dev/null 2>&1; then
    validate_workspace_config || _sync_validation_failed=1
  fi
  if command -v validate_configured_plugins >/dev/null 2>&1; then
    validate_configured_plugins || _sync_validation_failed=1
  fi

  _sync_quiet="$_old_sync_quiet"
  if [ "$_sync_validation_failed" -ne 0 ]; then
    return 1
  fi
  if [ "$_sync_quiet" -eq 0 ]; then
    log_ok "Sync complete — workspace, plugins, skills, and member repositories reconciled"
  fi
  return 0
}
