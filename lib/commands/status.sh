#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/status.sh — Workspace health and status diagnostics
# ============================================================================

# Check if a directory contains any rnex-* user skill pointers or skill bundles.
_status_has_rnex_skills() {
  [ -d "$1" ] && { ls "$1"/rnex-*.md >/dev/null 2>&1 || ls -d "$1"/rnex-* >/dev/null 2>&1; }
}

# Print comprehensive read-only workspace diagnostic report:
# Shows config versions, gitignore rules, AI context routing, registered plugins,
# git hooks status, and member repository status.
cmd_status() {
  require_workspace

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
  _repos_dir_name="$(yaml_get_repos_dir 2>/dev/null || printf 'repos')"
  [ -n "$_repos_dir_name" ] || _repos_dir_name="repos"
  _gi_repos=0; _gi_local=0; _gi_has_counter=0; _gi_has_rnex=0; _gi_has_markers=0; _gi_custom_ok=1
  if [ -f "$_gi" ]; then
    (grep -q "^${_repos_dir_name}/" "$_gi" 2>/dev/null || grep -q "^${_repos_dir_name}\*" "$_gi" 2>/dev/null || grep -q '^repos' "$_gi" 2>/dev/null) && _gi_repos=1
    grep -qF "$RNEX_LOCAL_CONFIG_FILE" "$_gi" 2>/dev/null && _gi_local=1
    grep -q "lint_trigger_counter" "$_gi" 2>/dev/null && _gi_has_counter=1
    grep -q '\*\*/\.rnex\*/' "$_gi" 2>/dev/null && _gi_has_rnex=1
    if grep -qFx -- "${GITIGNORE_MARKER_START:-# REPO-NEXUS:START}" "$_gi" 2>/dev/null && \
       grep -qFx -- "${GITIGNORE_MARKER_END:-# REPO-NEXUS:END}" "$_gi" 2>/dev/null; then
      _gi_has_markers=1
      _gi_exp_tmp="$(mktemp)"
      _gi_act_tmp="$(mktemp)"
      _build_rnex_gitignore_section > "$_gi_exp_tmp"
      awk -v s="${GITIGNORE_MARKER_START:-# REPO-NEXUS:START}" -v e="${GITIGNORE_MARKER_END:-# REPO-NEXUS:END}" '
        $0 == s { in_b = 1 }
        in_b { print }
        $0 == e { in_b = 0; exit }
      ' "$_gi" > "$_gi_act_tmp"
      if ! cmp -s "$_gi_exp_tmp" "$_gi_act_tmp"; then
        _gi_custom_ok=0
      fi
      rm -f "$_gi_exp_tmp" "$_gi_act_tmp"
    fi
  fi

  if [ "$_gi_repos" -eq 1 ] && [ "$_gi_local" -eq 1 ] && [ "$_gi_has_counter" -eq 0 ] && [ "$_gi_has_rnex" -eq 1 ] && [ "$_gi_has_markers" -eq 1 ] && [ "$_gi_custom_ok" -eq 1 ]; then
    printf '  %b✓%b Git Ignore:    %s/, %s, and **/.rnex*/ ignored in .gitignore\n' "$_G" "$_NC" "$_repos_dir_name" "$RNEX_LOCAL_CONFIG_FILE"
  else
    printf '  %b!%b Git Ignore:    recommend running "rnex sync" to update .gitignore (%s/, local configs)\n' "$_Y" "$_NC" "$_repos_dir_name"
  fi

  _git_dir=""
  if git -C "$NEXUS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _git_dir="$(git -C "$NEXUS_DIR" rev-parse --git-dir 2>/dev/null || echo "$NEXUS_DIR/.git")"
  fi
  _configured_hooks="$(yaml_list_git_hooks 2>/dev/null || true)"
  _hooks_active=0
  if [ -n "$_git_dir" ] && [ -x "$_git_dir/hooks/post-merge" ]; then
    _hooks_active=1
  fi

  if [ -n "$_configured_hooks" ]; then
    if [ "$_hooks_active" -eq 1 ]; then
      printf '  %b✓%b Git Hooks:     active (wrappers in %s/hooks)\n' "$_G" "$_NC" "$(basename "$_git_dir")"
    else
      printf '  %b!%b Git Hooks:     configured in git.hooks, but wrappers missing in %s/hooks (run "rnex sync")\n' "$_Y" "$_NC" "$(basename "$_git_dir")"
    fi
  else
    if [ "$_hooks_active" -eq 1 ]; then
      printf '  %b●%b Git Hooks:     wrappers active in %s/hooks\n' "$_DIM" "$_NC" "$(basename "$_git_dir")"
    else
      printf '  %b○%b Git Hooks:     none configured in git.hooks (run "rnex sync" to install wrappers)\n' "$_DIM" "$_NC"
    fi
  fi

  printf '\n'

  printf '%bWorkspace AI Context (Routing):%b\n' "$_BOLD" "$_NC"
  if [ -f "$NEXUS_DIR/.rnex/ai-instructions.md" ]; then
    printf '  %b✓%b %s %b(compiled AI instructions)%b\n' "$_G" "$_NC" ".rnex/ai-instructions.md" "$_DIM" "$_NC"
  else
    printf '  %b✗%b %s %b(compiled AI instructions — MISSING; run "rnex sync" to create)%b\n' "$_R" "$_NC" ".rnex/ai-instructions.md" "$_R" "$_NC"
  fi

  _has_any_instructions=0
  if [ -f "$NEXUS_DIR/AGENTS.md" ]; then
    printf '  %b✓%b %s %b(standard instructions directive)%b\n' "$_G" "$_NC" "AGENTS.md" "$_DIM" "$_NC"
    _has_any_instructions=1
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
      _has_any_instructions=1
    fi
  done
  if [ "$_has_any_instructions" -eq 0 ]; then
    _active_ifiles=""
    command -v get_active_provider_instruction_files >/dev/null 2>&1 && _active_ifiles="$(get_active_provider_instruction_files "$NEXUS_DIR" 2>/dev/null || true)"
    _target_ifile="${_active_ifiles:-AGENTS.md}"
    printf '  %b✗%b %s %b(instructions directive — MISSING; run "rnex sync" to create)%b\n' "$_R" "$_NC" "$_target_ifile" "$_R" "$_NC"
  fi
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
      _pdir="$(plugin_resolve_dir "$_pname" 2>/dev/null || true)"
      [ -n "$_pdir" ] || _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
      if [ -n "$_pdir" ]; then
        _ver="$(plugin_get_version "$_pname" "$_pdir")"
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
    printf '  %b%s%b\n' "$_DIM" "(No repositories registered yet. Use 'rnex repo add <git-url> [--name <name>]')" "$_NC"
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
