#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/init.sh — Workspace initialization command
# ============================================================================

cmd_init() {
  _non_interactive=0
  _init_dir=""
  _cli_code_workspace=""
  _cli_hooks=""
  _cli_no_hooks=0
  _cli_copilot=""
  _cli_claude=""
  _cli_gemini=""
  _cli_cursor=""
  _cli_windsurf=""
  _cli_karpathy=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) _non_interactive=1 ;;
      --hooks) _cli_hooks="true" ;;
      --no-hooks) _cli_no_hooks=1; _cli_hooks="false" ;;
      --copilot) _cli_copilot="true" ;;
      --no-copilot) _cli_copilot="false" ;;
      --claude) _cli_claude="true" ;;
      --no-claude) _cli_claude="false" ;;
      --gemini) _cli_gemini="true" ;;
      --no-gemini) _cli_gemini="false" ;;
      --cursor) _cli_cursor="true" ;;
      --no-cursor) _cli_cursor="false" ;;
      --windsurf) _cli_windsurf="true" ;;
      --no-windsurf) _cli_windsurf="false" ;;
      --karpathy|--karpathy-llm) _cli_karpathy="true" ;;
      --no-karpathy|--no-karpathy-llm) _cli_karpathy="false" ;;
      --ai|--instructions|--ai-instructions)
        shift
        # Legacy flag ignored in favor of plugins
        ;;
      --code-workspace|--vscode)
        _cli_code_workspace="true"
        if [ $# -ge 2 ]; then
          case "$2" in
            -*) ;;
            *)
              case "$2" in
                true|false|*.code-workspace)
                  shift
                  _cli_code_workspace="$1"
                  ;;
              esac
              ;;
          esac
        fi
        ;;
      *)
        if [ -z "$_init_dir" ]; then
          _init_dir="$1"
        fi
        ;;
    esac
    shift
  done

  if [ -n "$CUSTOM_CONFIG" ]; then
    _target_yaml="$(resolve_path "$CUSTOM_CONFIG")"
    _init_dir="$(dirname "$_target_yaml")"
  else
    _init_dir="${_init_dir:-$PWD}"
    _init_dir="$(resolve_path "$_init_dir")"
    _target_yaml="$_init_dir/$RNEX_CONFIG_FILE"
  fi
  mkdir -p "$_init_dir"

  _is_git_ws=0
  if git -C "$_init_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _is_git_ws=1
  fi

  _init_git_hooks="false"
  if [ "$_is_git_ws" -eq 1 ]; then
    if [ "$_cli_no_hooks" -eq 1 ] || [ "$_cli_hooks" = "false" ]; then
      _init_git_hooks="false"
    elif [ "$_cli_hooks" = "true" ] || [ "$_non_interactive" -eq 1 ]; then
      _init_git_hooks="true"
    elif [ -t 0 ]; then
      printf '%bConfigure automated Git hooks (post-merge auto-sync & wiki triggers)? [Y/n]: %b' "$_BOLD" "$_NC"
      read -r _h_ans
      case "$_h_ans" in
        n*|N*) _init_git_hooks="false" ;;
        *) _init_git_hooks="true" ;;
      esac
    else
      _init_git_hooks="true"
    fi
  fi

  # ---- 1. Create config file if none exists ---------------------------------
  _config_created=0
  if [ -f "$_target_yaml" ]; then
    log_warn "Workspace configuration already exists at $_init_dir ($RNEX_CONFIG_FILE exists)"
    log_dim "To reconcile repos and plugins, run:"
    log_dim "  rnex sync"
  else
    _init_plugins=""
    if [ "$_cli_copilot" = "true" ]; then
      _init_plugins="${_init_plugins}  copilot:\n    instructions: true\n    skills: true\n"
    fi
    if [ "$_cli_claude" = "true" ]; then
      _init_plugins="${_init_plugins}  claude:\n    instructions: true\n    skills: true\n"
    fi
    if [ "$_cli_gemini" = "true" ]; then
      _init_plugins="${_init_plugins}  gemini:\n    instructions: true\n    skills: true\n"
    fi
    if [ "$_cli_cursor" = "true" ]; then
      _init_plugins="${_init_plugins}  cursor:\n    instructions: true\n    skills: true\n"
    fi
    if [ "$_cli_windsurf" = "true" ]; then
      _init_plugins="${_init_plugins}  windsurf:\n    instructions: true\n    skills: true\n"
    fi
    if [ "$_cli_karpathy" = "true" ]; then
      _init_plugins="${_init_plugins}  karpathy-llm:\n    raw_dir: \"./docs\"\n    wiki_dir: \".rnex/wiki\"\n    lint_trigger: \"manual\"\n    ingest_member_readmes: true\n"
    fi

    cat > "$_target_yaml" <<YAML_EOF
# Repo Nexus workspace configuration
# See templates/rnex.example.yaml for a comprehensive example with all options.

version: $RNEX_VERSION

# Directory for member repository clones
repos_dir: ./repos

# VS Code / Cursor multi-root workspace file (default: false; e.g. true or workspace.code-workspace)
code_workspace: ${_cli_code_workspace:-false}

# Automated workspace Git hooks (default: true; e.g. post-merge auto-sync, plugin triggers)
git_hooks: $_init_git_hooks

# Workspace plugins
plugins:
$(printf '%b' "$_init_plugins")
# Member repositories managed by Repo Nexus
repos:
YAML_EOF
    _config_created=1
    log_ok "Created $RNEX_CONFIG_FILE"
  fi

  # ---- 2. Merge routing instructions into AI instructions files ------------
  merge_rnex_instructions "$_init_dir/AGENTS.md"
  [ -f "$_init_dir/CLAUDE.md" ] && merge_rnex_instructions "$_init_dir/CLAUDE.md"
  [ -f "$_init_dir/GEMINI.md" ] && merge_rnex_instructions "$_init_dir/GEMINI.md"
  [ -f "$_init_dir/.cursorrules" ] && merge_rnex_instructions "$_init_dir/.cursorrules"
  [ -f "$_init_dir/.windsurfrules" ] && merge_rnex_instructions "$_init_dir/.windsurfrules"
  [ -f "$_init_dir/.github/copilot-instructions.md" ] && merge_rnex_instructions "$_init_dir/.github/copilot-instructions.md"

  # ---- 3. Create repos directory with .gitkeep -----------------------------
  _repos_dir="$_init_dir/repos"
  mkdir -p "$_repos_dir"
  [ -f "$_repos_dir/.gitkeep" ] || touch "$_repos_dir/.gitkeep"

  # ---- 4. Create internal .rnex directory and sync base assets -------------
  mkdir -p "$_init_dir/.rnex"
  mkdir -p "$_init_dir/.rnex/plugins"
  _orig_nexus="$NEXUS_DIR"
  _orig_yaml="$WORKSPACE_YAML"
  _orig_local_yaml="$WORKSPACE_LOCAL_YAML"
  NEXUS_DIR="$_init_dir"
  WORKSPACE_YAML="$_target_yaml"
  WORKSPACE_LOCAL_YAML="$_init_dir/$RNEX_LOCAL_CONFIG_FILE"
  sync_rnex_base_assets
  sync_plugins
  build_ai_instructions "$_init_dir"
  sync_skills
  WORKSPACE_LOCAL_YAML="$_orig_local_yaml"
  WORKSPACE_YAML="$_orig_yaml"
  NEXUS_DIR="$_orig_nexus"

  # ---- 5. Ensure repos/ and local configs are gitignored ---------
  reconcile_gitignore "$_init_dir"

  # ---- 6. Generate VS Code / Cursor workspace if configured ----------------
  _target_cw="$_cli_code_workspace"
  if [ -z "$_target_cw" ] && [ -f "$_init_dir/$RNEX_LOCAL_CONFIG_FILE" ]; then
    _target_cw="$(awk '/^(code_workspace|vscode_workspace):/ { sub(/^[a-zA-Z0-9_]+:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$_init_dir/$RNEX_LOCAL_CONFIG_FILE")"
  fi
  if [ -z "$_target_cw" ] && [ -f "$_target_yaml" ]; then
    _target_cw="$(awk '/^(code_workspace|vscode_workspace):/ { sub(/^[a-zA-Z0-9_]+:[ ]*/, ""); sub(/[ ]*#.*/, ""); val=$0 } END { if (val) print val }' "$_target_yaml")"
  fi
  _target_cw="$(echo "$_target_cw" | tr -d " \t\r\n'\"")"
  case "$_target_cw" in
    true|yes|1)
      _cw_name="$(basename "$_init_dir").code-workspace"
      ;;
    false|no|0|none|"")
      _cw_name=""
      ;;
    *)
      case "$_target_cw" in
        *.code-workspace) _cw_name="$_target_cw" ;;
        *) _cw_name="$_target_cw.code-workspace" ;;
      esac
      ;;
  esac

  if [ -n "$_cw_name" ]; then
    _orig_nexus="$NEXUS_DIR"
    _orig_repos="$REPOS_DIR"
    _orig_cw="$CODE_WORKSPACE_FILE"
    CODE_WORKSPACE_FILE="$_cw_name"
    NEXUS_DIR="$_init_dir"
    _repos_rel="repos"
    REPOS_DIR="$_init_dir/$_repos_rel"
    sync_code_workspace
    NEXUS_DIR="$_orig_nexus"
    REPOS_DIR="$_orig_repos"
    CODE_WORKSPACE_FILE="$_orig_cw"
  fi

  # ---- 7. Setup automated Git hooks if inside a Git repository ------------
  if [ "$_is_git_ws" -eq 1 ]; then
    if [ "$_init_git_hooks" = "true" ]; then
      cmd_hooks_install_dir "$_init_dir"
    else
      log_dim "Skipping Git hooks setup (run 'rnex hooks install' later to enable)"
    fi
  fi

  _write_auto_sync_script "$_init_dir"
  _sync_ai_session_start_hooks "$_init_dir"
  update_sync_stamp "$_init_dir"

  NEXUS_DIR="$_init_dir"
  WORKSPACE_YAML="$_target_yaml"
  WORKSPACE_LOCAL_YAML="$_init_dir/$RNEX_LOCAL_CONFIG_FILE"

  if [ "$_config_created" -eq 1 ]; then
    printf '\n'
    log_ok "Initialized Repo Nexus workspace at ${_BOLD}$_init_dir${_NC}"
    _created_items="$RNEX_CONFIG_FILE, .rnex/, and repos/"
    [ -n "$_cw_name" ] && _created_items="$_created_items (and $_cw_name)"
    log_dim "Created $_created_items"
    printf '\n'
    log_info "Next steps:"
    log_dim "1. Add repositories with: rnex add <name> <git-url>"
    log_dim "2. Clone team repositories: rnex clone"
    log_dim "3. Run commands across all repos: rnex exec <command>"
  fi
}
