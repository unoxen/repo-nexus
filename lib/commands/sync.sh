#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/sync.sh — Workspace synchronization, audit, and repair
# ============================================================================

cmd_sync() {
  require_workspace
  ensure_repos_dir

  _sync_fix=0
  _sync_auto_yes=0
  _sync_quiet=0
  _sync_upgrade_explicit=0

  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--fix) _sync_fix=1 ;;
      -y|--yes) _sync_auto_yes=1 ;;
      -q|--quiet) _sync_quiet=1 ;;
      --upgrade) _sync_upgrade_explicit=1; _sync_auto_yes=1; _sync_fix=1 ;;
      *) ;;
    esac
    shift
  done

  # --------------------------------------------------------------------------
  # Reconciliation / fix mode (--fix)
  # --------------------------------------------------------------------------
  if [ "$_sync_fix" -eq 1 ]; then
    [ "$_sync_quiet" -eq 0 ] && log_info "Reconciling Repo Nexus workspace at $NEXUS_DIR..."

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
      [ "$_sync_quiet" -eq 0 ] && log_ok "Upgraded workspace configuration and routing instructions to v$RNEX_VERSION"
    fi

    # 1. Ensure .gitignore ignores repos/, .rnex/, and local configs, and strips legacy counters; ensure .ignore has !repos/*
    reconcile_gitignore "$NEXUS_DIR"

    # 2. Reconcile plugins (scopes, asset pruning for disabled plugins)
    sync_plugins

    # 3. Reconcile universal workspace instructions in AGENTS.md
    merge_rnex_instructions "$NEXUS_DIR/AGENTS.md"

    # 4. Sync standard skills, workflows, and provider prompts
    sync_prompts

    # 5. Reconcile Git hooks according to configuration
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

    if [ "$_sync_quiet" -eq 0 ]; then
      log_ok "Sync complete — workspace, plugins, prompts, and member .rnex directories reconciled"
    fi
    return 0
  fi

  # --------------------------------------------------------------------------
  # Dry-run audit mode (without --fix) — log issues or inconsistencies only
  # --------------------------------------------------------------------------
  [ "$_sync_quiet" -eq 0 ] && log_info "Checking workspace synchronization at $NEXUS_DIR..."

  _issues=0

  # 1. Configuration version check
  _vc_res=0
  version_cmp "$WORKSPACE_CONFIG_VERSION" "$RNEX_VERSION" || _vc_res=$?
  if [ "$_vc_res" -eq 2 ]; then
    log_warn "Workspace configuration version (v$WORKSPACE_CONFIG_VERSION) is older than CLI (v$RNEX_VERSION)"
    _issues=$((_issues + 1))
  fi

  # 2. Git ignore and search ignore checks
  _gi="$NEXUS_DIR/.gitignore"
  if [ ! -f "$_gi" ]; then
    log_warn "Missing .gitignore in workspace root"
    _issues=$((_issues + 1))
  else
    if ! grep -q '^\s*repos/\*' "$_gi" 2>/dev/null && ! grep -q '^repos' "$_gi" 2>/dev/null; then
      log_warn ".gitignore missing 'repos/*'"
      _issues=$((_issues + 1))
    fi
    if ! grep -qF "$RNEX_LOCAL_CONFIG_FILE" "$_gi" 2>/dev/null; then
      log_warn ".gitignore missing '$RNEX_LOCAL_CONFIG_FILE'"
      _issues=$((_issues + 1))
    fi
    if grep -q '^\.rnex/' "$_gi" 2>/dev/null || grep -q '^\.rnex$' "$_gi" 2>/dev/null; then
      log_warn ".gitignore contains '.rnex/' (workspace assets should be tracked in Git)"
      _issues=$((_issues + 1))
    fi
    if grep -q "lint_trigger_counter" "$_gi" 2>/dev/null; then
      log_warn ".gitignore contains legacy 'lint_trigger_counter'"
      _issues=$((_issues + 1))
    fi
  fi

  _ign="$NEXUS_DIR/.ignore"
  if [ ! -f "$_ign" ] || ! grep -q '!repos/\*' "$_ign" 2>/dev/null; then
    log_warn ".ignore missing or missing '!repos/*' pattern (needed for code search & indexing)"
    _issues=$((_issues + 1))
  fi

  # 3. Universal routing instructions check
  if [ ! -f "$NEXUS_DIR/AGENTS.md" ]; then
    log_warn "Missing AGENTS.md routing instructions"
    _issues=$((_issues + 1))
  else
    if ! grep -q "<!-- REPO-NEXUS:START -->" "$NEXUS_DIR/AGENTS.md" 2>/dev/null || \
       ! grep -q "<!-- REPO-NEXUS:END -->" "$NEXUS_DIR/AGENTS.md" 2>/dev/null; then
      log_warn "AGENTS.md missing Repo Nexus delimited routing block"
      _issues=$((_issues + 1))
    fi
  fi

  # 4. Plugins check
  for _p in $(yaml_list_plugins 2>/dev/null || true); do
    [ -n "$_p" ] || continue
    if yaml_plugin_enabled "$_p"; then
      if [ ! -d "$NEXUS_DIR/.rnex/plugins/$_p" ]; then
        log_warn "Active plugin '$_p' missing scoped directory at .rnex/plugins/$_p"
        _issues=$((_issues + 1))
      fi
    else
      if [ -d "$NEXUS_DIR/.rnex/plugins/$_p" ]; then
        log_warn "Disabled plugin '$_p' still present at .rnex/plugins/$_p"
        _issues=$((_issues + 1))
      fi
    fi
  done

  # Provider specific checks
  if gemini_plugin_enabled; then
    if [ ! -f "$NEXUS_DIR/GEMINI.md" ] || ! grep -q "<!-- REPO-NEXUS:START -->" "$NEXUS_DIR/GEMINI.md" 2>/dev/null; then
      log_warn "GEMINI.md missing or not reconciled"
      _issues=$((_issues + 1))
    fi
    if [ ! -f "$NEXUS_DIR/.geminiignore" ] || ! grep -q '!repos/\*' "$NEXUS_DIR/.geminiignore" 2>/dev/null; then
      log_warn ".geminiignore missing or missing '!repos/*'"
      _issues=$((_issues + 1))
    fi
  else
    if [ -f "$NEXUS_DIR/.geminiignore" ] && grep -q '!repos/\*' "$NEXUS_DIR/.geminiignore" 2>/dev/null; then
      log_warn ".geminiignore contains '!repos/*' but gemini plugin is disabled"
      _issues=$((_issues + 1))
    fi
  fi

  if cursor_plugin_enabled; then
    if [ ! -f "$NEXUS_DIR/.cursorrules" ] || ! grep -q "<!-- REPO-NEXUS:START -->" "$NEXUS_DIR/.cursorrules" 2>/dev/null; then
      log_warn ".cursorrules missing or not reconciled"
      _issues=$((_issues + 1))
    fi
    if [ ! -f "$NEXUS_DIR/.cursorignore" ] || ! grep -q '!repos/\*' "$NEXUS_DIR/.cursorignore" 2>/dev/null; then
      log_warn ".cursorignore missing or missing '!repos/*'"
      _issues=$((_issues + 1))
    fi
    if [ ! -f "$NEXUS_DIR/.cursor/rules/rnex-context.mdc" ]; then
      log_warn ".cursor/rules/rnex-context.mdc missing"
      _issues=$((_issues + 1))
    fi
  else
    if [ -f "$NEXUS_DIR/.cursorignore" ] && grep -q '!repos/\*' "$NEXUS_DIR/.cursorignore" 2>/dev/null; then
      log_warn ".cursorignore contains '!repos/*' but cursor plugin is disabled"
      _issues=$((_issues + 1))
    fi
  fi

  if claude_plugin_enabled; then
    if [ ! -f "$NEXUS_DIR/CLAUDE.md" ] || ! grep -q "<!-- REPO-NEXUS:START -->" "$NEXUS_DIR/CLAUDE.md" 2>/dev/null; then
      log_warn "CLAUDE.md missing or not reconciled"
      _issues=$((_issues + 1))
    fi
  fi

  if windsurf_plugin_enabled; then
    if [ ! -f "$NEXUS_DIR/.windsurfrules" ] || ! grep -q "<!-- REPO-NEXUS:START -->" "$NEXUS_DIR/.windsurfrules" 2>/dev/null; then
      log_warn ".windsurfrules missing or not reconciled"
      _issues=$((_issues + 1))
    fi
  fi

  # Provider skills check (should NOT exist in provider dirs)
  for _psk in "$NEXUS_DIR/.github/skills" "$NEXUS_DIR/.claude/skills" "$NEXUS_DIR/.gemini/skills" "$NEXUS_DIR/.cursor/skills" "$NEXUS_DIR/.windsurf/skills"; do
    if [ -d "$_psk" ]; then
      for _sub in "$_psk"/*; do
        if [ -d "$_sub" ]; then
          _aname="$(basename "$_sub")"
          if [ "$_aname" = "rnex-cross-repo-feature" ] || [ "$_aname" = "rnex-workspace-audit" ] || [ "$_aname" = "rnex-wiki-lint" ] || [ "$_aname" = "rnex-wiki-ingest" ] || [ "$_aname" = "wiki-curator" ]; then
            log_warn "Found obsolete provider skill directory: $_sub (skills should reside in .rnex/skills)"
            _issues=$((_issues + 1))
          fi
        fi
      done
    fi
  done

  # 5. Skills and workflows in .rnex
  if [ ! -d "$NEXUS_DIR/.rnex/skills" ]; then
    log_warn "Standard workspace skills directory missing (.rnex/skills)"
    _issues=$((_issues + 1))
  fi
  if [ ! -d "$NEXUS_DIR/.rnex/workflows" ]; then
    log_warn "Standard workspace workflows directory missing (.rnex/workflows)"
    _issues=$((_issues + 1))
  fi

  # 6. Git hooks
  _cur_hp="$(git -C "$NEXUS_DIR" config --get core.hooksPath 2>/dev/null || true)"
  case "$GIT_HOOKS_CONFIG" in
    false|no|0)
      if [ "$_cur_hp" = ".rnex/hooks" ] || [ "$_cur_hp" = "$NEXUS_DIR/.rnex/hooks" ]; then
        log_warn "Git hooks active in Git, but disabled in configuration (git_hooks: false)"
        _issues=$((_issues + 1))
      fi
      ;;
    true|yes|1)
      if git -C "$NEXUS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if [ "$_cur_hp" != ".rnex/hooks" ] && [ "$_cur_hp" != "$NEXUS_DIR/.rnex/hooks" ]; then
          log_warn "Git hooks enabled in configuration (git_hooks: true), but not active in Git"
          _issues=$((_issues + 1))
        fi
      fi
      ;;
  esac

  # 7. Member repositories
  for _name in $(yaml_list_repos 2>/dev/null || true); do
    [ -n "$_name" ] || continue
    if yaml_repo_enabled "$_name"; then
      _rdir="$(resolve_repo_path "$_name")"
      if [ ! -d "$_rdir" ]; then
        log_warn "Member repo '$_name' is missing on disk (run: rnex clone)"
        _issues=$((_issues + 1))
      elif [ ! -d "$_rdir/.rnex" ]; then
        log_warn "Member repo '$_name' missing .rnex directory"
        _issues=$((_issues + 1))
      fi
    fi
  done

  # 8. Multi-root workspace file
  if [ -n "$CODE_WORKSPACE_FILE" ]; then
    if [ ! -f "$NEXUS_DIR/$CODE_WORKSPACE_FILE" ]; then
      log_warn "Multi-root workspace file missing ($CODE_WORKSPACE_FILE)"
      _issues=$((_issues + 1))
    fi
  fi

  if [ "$_issues" -eq 0 ]; then
    [ "$_sync_quiet" -eq 0 ] && log_ok "Workspace is synchronized — no issues or inconsistencies found."
    return 0
  else
    [ "$_sync_quiet" -eq 0 ] && log_warn "Found $_issues inconsistency(ies). Run 'rnex sync --fix' to reconcile."
    return 1
  fi
}

cmd_fix() {
  _fix_is_quiet=0
  for _arg in "$@"; do
    case "$_arg" in
      -q|--quiet) _fix_is_quiet=1 ;;
    esac
  done
  [ "$_fix_is_quiet" -eq 0 ] && log_warn "Command 'rnex fix' is deprecated and will be removed in a future release. Use 'rnex sync --fix' instead."
  cmd_sync --fix "$@"
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
  cmd_sync --fix "$@"
}

cmd_upgrade() {
  cmd_update "$@"
}
