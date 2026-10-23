#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/status.sh — Workspace health and status diagnostics
# ============================================================================

# Query active plugins for any non-manual lint triggers (e.g. git hook triggers).
_status_active_plugin_trigger() {
  for _p in $(yaml_list_plugins 2>/dev/null || true); do
    yaml_plugin_enabled "$_p" 2>/dev/null || continue
    _trig="$(yaml_plugin_get "$_p" "lint_trigger" 2>/dev/null || true)"
    [ -z "$_trig" ] && _trig="$(yaml_plugin_get "$_p" "trigger" 2>/dev/null || true)"
    if [ -n "$_trig" ] && [ "$_trig" != "manual" ]; then
      printf '%s' "$_trig"
      return 0
    fi
  done
  return 0
}

# Check if a directory contains any rnex-* user skills or skill symlinks.
_status_has_rnex_skills() {
  [ -d "$1" ] && { ls "$1"/rnex-*.md >/dev/null 2>&1 || ls -d "$1"/rnex-* >/dev/null 2>&1; }
}

# Print comprehensive read-only workspace diagnostic report:
# Shows config versions, gitignore rules, AI context routing, registered plugins,
# git hooks status, and member repository status.
cmd_status() {
  require_workspace
  ensure_repos_dir

  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--fix)
        die "'rnex status --fix' is removed. Use 'rnex sync' to reconcile the workspace."
        ;;
      -y|--yes|-q|--quiet) ;;
      *) ;;
    esac
    shift
  done

  # --------------------------------------------------------------------------
  # Read-Only Inspection mode (rnex status)
  # --------------------------------------------------------------------------
  printf '\n%b%s%b\n' "$_B" "Repo Nexus Workspace Status" "$_NC"
  printf '=%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28
  printf '\n\n'

  printf '%bConfiguration:%b\n' "$_BOLD" "$_NC"
  if [ -f "$WORKSPACE_YAML" ]; then
    _vc_res=0
    version_cmp "$WORKSPACE_CONFIG_VERSION" "$RNEX_VERSION" || _vc_res=$?
    if [ "$_vc_res" -eq 2 ]; then
      printf '  %b!%b Repo Config:   %s %b(v%s is older than CLI v%s; run "rnex sync")%b\n' "$_Y" "$_NC" "$WORKSPACE_YAML" "$_DIM" "${WORKSPACE_CONFIG_VERSION:-0.0.0}" "$RNEX_VERSION" "$_NC"
    elif [ -n "$WORKSPACE_CONFIG_VERSION" ]; then
      printf '  %b●%b Repo Config:   %s %b(loaded, v%s)%b\n' "$_G" "$_NC" "$WORKSPACE_YAML" "$_DIM" "$WORKSPACE_CONFIG_VERSION" "$_NC"
    else
      printf '  %b●%b Repo Config:   %s %b(loaded)%b\n' "$_G" "$_NC" "$WORKSPACE_YAML" "$_DIM" "$_NC"
    fi
  else
    printf '  %b✗%b Repo Config:   %s %b(missing)%b\n' "$_R" "$_NC" "$WORKSPACE_YAML" "$_R" "$_NC"
  fi
  if [ -f "$WORKSPACE_LOCAL_YAML" ]; then
    printf '  %b●%b Local Config:  %s %b(loaded, overrides repo config)%b\n' "$_G" "$_NC" "$WORKSPACE_LOCAL_YAML" "$_DIM" "$_NC"
  else
    printf '  %b○%b Local Config:  %s %b(not found — using repo defaults)%b\n' "$_DIM" "$_NC" "$WORKSPACE_LOCAL_YAML" "$_DIM" "$_NC"
  fi
  printf '  %b●%b Repos Dir:     %s\n' "$_DIM" "$_NC" "$REPOS_DIR"
  if [ -n "$CODE_WORKSPACE_FILE" ]; then
    printf '  %b●%b Workspace:   %s\n' "$_DIM" "$_NC" "$CODE_WORKSPACE_FILE"
  fi

  _stamp_file="$NEXUS_DIR/.rnex/sync_stamp"
  _cur_sum="$(get_config_sum "$NEXUS_DIR")"
  if [ ! -f "$_stamp_file" ] || [ "$_cur_sum" != "$(cat "$_stamp_file" 2>/dev/null)" ]; then
    printf '  %b!%b Sync Stamp:    workspace out of sync with configuration (run "rnex sync")\n' "$_Y" "$_NC"
  else
    printf '  %b✓%b Sync Stamp:    workspace synchronized with configuration\n' "$_G" "$_NC"
  fi

  _gi="$NEXUS_DIR/.gitignore"
  _gi_repos=0; _gi_local=0; _gi_has_counter=0; _gi_has_rnex=0
  if [ -f "$_gi" ]; then
    grep -q '^repos' "$_gi" 2>/dev/null && _gi_repos=1
    grep -qF "$RNEX_LOCAL_CONFIG_FILE" "$_gi" 2>/dev/null && _gi_local=1
    grep -q "lint_trigger_counter" "$_gi" 2>/dev/null && _gi_has_counter=1
    (grep -q '^\.rnex/' "$_gi" 2>/dev/null || grep -q '^\.rnex$' "$_gi" 2>/dev/null) && _gi_has_rnex=1
  fi

  if [ "$_gi_repos" -eq 1 ] && [ "$_gi_local" -eq 1 ] && [ "$_gi_has_counter" -eq 0 ] && [ "$_gi_has_rnex" -eq 0 ]; then
    printf '  %b✓%b Git Ignore:    repos/ and %s ignored in .gitignore\n' "$_G" "$_NC" "$RNEX_LOCAL_CONFIG_FILE"
  else
    printf '  %b!%b Git Ignore:    recommend running "rnex sync" to update .gitignore (repos/, local configs)\n' "$_Y" "$_NC"
  fi

  _hooks_path="$(git -C "$NEXUS_DIR" config --get core.hooksPath 2>/dev/null || true)"
  _gh_active=0
  if [ "$_hooks_path" = ".rnex/hooks" ] || [ "$_hooks_path" = "$NEXUS_DIR/.rnex/hooks" ]; then
    _gh_active=1
  fi

  case "$GIT_HOOKS_CONFIG" in
    false|no|0)
      if [ "$_gh_active" -eq 1 ]; then
        printf '  %b!%b Git Hooks:     active in Git, but disabled in config (git_hooks: false; run "rnex sync" to reconcile)\n' "$_Y" "$_NC"
      else
        printf '  %b○%b Git Hooks:     disabled in configuration (git_hooks: false)\n' "$_DIM" "$_NC"
      fi
      ;;
    true|yes|1)
      if [ "$_gh_active" -eq 1 ]; then
        _active_trigger="$(_status_active_plugin_trigger)"
        if [ -n "$_active_trigger" ]; then
          printf '  %b✓%b Git Hooks:     active (git_hooks: true, .rnex/hooks — %s)\n' "$_G" "$_NC" "$_active_trigger"
        else
          printf '  %b✓%b Git Hooks:     active (git_hooks: true, .rnex/hooks — post-merge auto-sync)\n' "$_G" "$_NC"
        fi
      else
        printf '  %b!%b Git Hooks:     enabled in config (git_hooks: true), but not active in Git (run "rnex sync")\n' "$_Y" "$_NC"
      fi
      ;;
    *)
      if [ "$_gh_active" -eq 1 ]; then
        _active_trigger="$(_status_active_plugin_trigger)"
        if [ -n "$_active_trigger" ]; then
          printf '  %b✓%b Git Hooks:     active (.rnex/hooks — post-merge auto-sync, %s)\n' "$_G" "$_NC" "$_active_trigger"
        else
          printf '  %b✓%b Git Hooks:     active (.rnex/hooks — post-merge auto-sync)\n' "$_G" "$_NC"
        fi
      else
        printf '  %b○%b Git Hooks:     not configured (run "rnex hooks install" to enable)\n' "$_DIM" "$_NC"
      fi
      ;;
  esac

  printf '\n'

  printf '%bWorkspace AI Context (Routing):%b\n' "$_BOLD" "$_NC"
  if [ -f "$NEXUS_DIR/.rnex/ai-instructions.md" ]; then
    printf '  %b✓%b %s %b(compiled AI instructions)%b\n' "$_G" "$_NC" ".rnex/ai-instructions.md" "$_DIM" "$_NC"
  else
    printf '  %b✗%b %s %b(compiled AI instructions — MISSING; run "rnex sync" to create)%b\n' "$_R" "$_NC" ".rnex/ai-instructions.md" "$_R" "$_NC"
  fi
  if [ -f "$NEXUS_DIR/AGENTS.md" ]; then
    printf '  %b✓%b %s %b(standard instructions directive)%b\n' "$_G" "$_NC" "AGENTS.md" "$_DIM" "$_NC"
  elif ! has_active_provider_instructions "$NEXUS_DIR"; then
    printf '  %b✗%b %s %b(standard instructions directive — MISSING; run "rnex sync" to create)%b\n' "$_R" "$_NC" "AGENTS.md" "$_R" "$_NC"
  fi
  for _pair in \
    "CLAUDE.md:Claude" \
    "GEMINI.md:Gemini" \
    "CODEX.md:Codex" \
    ".cursorrules:Cursor" \
    ".windsurfrules:Windsurf" \
    ".github/copilot-instructions.md:Copilot"; do
    _ifile="${_pair%%:*}"
    _ilbl="${_pair#*:}"
    if [ -f "$NEXUS_DIR/$_ifile" ]; then
      printf '  %b✓%b %s %b(%s instructions)%b\n' "$_G" "$_NC" "$_ifile" "$_DIM" "$_ilbl" "$_NC"
    fi
  done
  if [ -n "$CODE_WORKSPACE_FILE" ]; then
    if [ -f "$NEXUS_DIR/$CODE_WORKSPACE_FILE" ]; then
      printf '  %b✓%b %s %b(VS Code / Cursor workspace)%b\n' "$_G" "$_NC" "$CODE_WORKSPACE_FILE" "$_DIM" "$_NC"
    else
      printf '  %b✗%b %s %b(VS Code / Cursor workspace — MISSING; run "rnex sync" to create)%b\n' "$_R" "$_NC" "$CODE_WORKSPACE_FILE" "$_R" "$_NC"
    fi
  fi
  for _found_cw in "$NEXUS_DIR"/*.code-workspace; do
    if [ -f "$_found_cw" ] && [ "$(basename "$_found_cw")" != "$CODE_WORKSPACE_FILE" ]; then
      printf '  %b✓%b %s %b(VS Code / Cursor workspace)%b\n' "$_G" "$_NC" "$(basename "$_found_cw")" "$_DIM" "$_NC"
    fi
  done
  if [ -d "$NEXUS_DIR/.rnex" ]; then
    printf '  %b✓%b %s\n' "$_G" "$_NC" ".rnex/"
  fi
  if [ -d "$NEXUS_DIR/.rnex/skills" ]; then
    printf '  %b✓%b %s %b(workspace skills)%b\n' "$_G" "$_NC" ".rnex/skills/" "$_DIM" "$_NC"
  fi
  for _spair in \
    ".cursor/rules/:Cursor" \
    ".claude/skills/:Claude" \
    ".windsurf/rules/:Windsurf" \
    ".agents/skills/:Gemini" \
    ".gemini/skills/:Gemini" \
    ".codex/skills/:Codex" \
    ".github/skills/:Copilot"; do
    _sdir="${_spair%%:*}"
    _slbl="${_spair#*:}"
    [ "$_sdir" = ".gemini/skills/" ] && _status_has_rnex_skills "$NEXUS_DIR/.agents/skills" && continue
    if _status_has_rnex_skills "$NEXUS_DIR/${_sdir%/}"; then
      printf '  %b✓%b %s %b(%s user skills)%b\n' "$_G" "$_NC" "$_sdir" "$_DIM" "$_slbl" "$_NC"
    fi
  done
  printf '\n'

  printf '%bActive Plugins:%b\n' "$_BOLD" "$_NC"
  _active_plugins="$(yaml_list_plugins)"
  if [ -z "$_active_plugins" ]; then
    printf '  %b%s%b\n' "$_DIM" "(No plugins enabled. Use 'rnex plugin list')" "$_NC"
  else
    echo "$_active_plugins" | while read -r _pname; do
      [ -n "$_pname" ] || continue
      _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
      if [ -n "$_pdir" ]; then
        _ver="$(plugin_get_field "$_pdir" "version")"
        _desc="$(plugin_get_field "$_pdir" "description")"
        if ! yaml_plugin_enabled "$_pname"; then
          printf '  %b○%b %-18s %b[disabled locally]%b\n' "$_DIM" "$_NC" "$_pname" "$_DIM" "$_NC"
        else
          printf '  %b●%b %-18s %b(v%s)%b %s\n' "$_G" "$_NC" "$_pname" "$_DIM" "${_ver:-0.1.0}" "$_NC" "${_desc:+- $_desc}"
          printf '    %bScoped directory: .rnex/plugins/%s%b\n' "$_DIM" "$_pname" "$_NC"
          if [ -n "$_pdir" ] && [ -f "$_pdir/plugin.yaml" ]; then
            _opts=""
            if grep -q "skills:" "$_pdir/plugin.yaml" 2>/dev/null || [ -n "$(yaml_plugin_get "$_pname" "skills" 2>/dev/null)" ]; then
              _opts="${_opts:+$_opts, }skills=$(provider_option_enabled "$_pname" "skills" && echo "true" || echo "false")"
            fi
            if grep -q "auto_sync_on:" "$_pdir/plugin.yaml" 2>/dev/null || grep -q "autoSyncOn:" "$_pdir/plugin.yaml" 2>/dev/null || [ -n "$(yaml_plugin_get "$_pname" "auto_sync_on" 2>/dev/null)" ] || [ -n "$(yaml_plugin_get "$_pname" "autoSyncOn" 2>/dev/null)" ]; then
              _aso="$(yaml_plugin_get "$_pname" "auto_sync_on" 2>/dev/null || true)"
              [ -z "$_aso" ] && _aso="$(yaml_plugin_get "$_pname" "autoSyncOn" 2>/dev/null || true)"
              [ -z "$_aso" ] && _aso="SessionStart"
              _opts="${_opts:+$_opts, }auto_sync_on=$_aso"
            fi
            if [ -n "$_opts" ]; then
              printf '    %b↳ Options: %s%b\n' "$_DIM" "$_opts" "$_NC"
            fi
            if [ "$_pname" = "karpathy-llm" ] && [ -n "$(plugin_legacy_raw_dir "$_pname" 2>/dev/null)" ]; then
              printf '    %b↳ [!] Deprecated: raw_dir — run "rnex sync" to rewrite to sources%b\n' "$_Y" "$_NC"
            fi
          fi
        fi
      else
        printf '  %b✗%b %-18s %bMISSING%b\n' "$_R" "$_NC" "$_pname" "$_R" "$_NC"
        printf '    %b↳ [!] Issue: plugin declared in config but directory not found on disk%b\n' "$_R" "$_NC"
      fi
    done
  fi
  printf '\n'

  printf '%b%s%b\n' "$_BOLD" "Member Repositories:" "$_NC"
  _all_repos="$(yaml_list_repos)"
  if [ -z "$_all_repos" ]; then
    printf '  %b%s%b\n' "$_DIM" "(No repositories registered yet. Use 'rnex add [<name>] <git-url>')" "$_NC"
  else
    echo "$_all_repos" | while read -r _name; do
      [ -n "$_name" ] || continue
      _url="$(yaml_get "$_name" "url")"
      [ -n "$_url" ] || _url="$(yaml_get "$_name" "path")"

      _rdir="$(resolve_repo_path "$_name")"
      if ! yaml_repo_enabled "$_name"; then
        printf '  %b○%b %-18s %b[disabled]%b %s\n' "$_DIM" "$_NC" "$_name" "$_DIM" "$_NC" "${_url:+- $_url}"
      elif [ -d "$_rdir/.git" ]; then
        _b="$(git -C "$_rdir" symbolic-ref --short HEAD 2>/dev/null || git -C "$_rdir" rev-parse --short HEAD 2>/dev/null || echo "head")"
        _tags=""
        if yaml_repo_readonly "$_name"; then
          _tags=" ${_Y}[readonly]${_NC}"
        fi
        if [ -d "$_rdir/.rnex" ]; then
          _tags="${_tags} ${_DIM}[.rnex]${_NC}"
        fi
        printf '  %b●%b %-18s %b[%s]%b%b %s\n' "$_G" "$_NC" "$_name" "$_C" "$_b" "$_NC" "$_tags" "${_url:+- $_url}"
      else
        printf '  %b✗%b %-18s %b[missing — run "rnex clone"]%b %s\n' "$_R" "$_NC" "$_name" "$_R" "$_NC" "${_url:+- $_url}"
      fi
    done
  fi
  printf '\n'
}
