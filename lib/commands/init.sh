#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/init.sh — Workspace initialization command
# ============================================================================

# Initialize a new Repo Nexus workspace in the specified directory (or current directory):
# Sets up rnex.yaml, .rnex/ harness, gitignore rules, routing instructions in AGENTS.md,
# enabled plugins (e.g. --claude, --gemini, --karpathy), and optional VS Code / Cursor workspace.
# Usage:
#   rnex init [-y|--yes] [--hooks|--no-hooks] [--<plugin>] [<directory>]
cmd_init() {
  _non_interactive=0
  _init_dir=""
  _cli_code_workspace=""
  _cli_hooks=""
  _cli_no_hooks=0
  _cli_plugins=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) _non_interactive=1 ;;
      --hooks) _cli_hooks="true" ;;
      --no-hooks) _cli_no_hooks=1; _cli_hooks="false" ;;
      --karpathy) _cli_plugins="${_cli_plugins:+$_cli_plugins }karpathy-llm" ;;
      --no-karpathy) _cli_plugins="$(printf '%s' " $_cli_plugins " | sed -e 's/ karpathy-llm / /g' -e 's/^ *//;s/ *$//')" ;;
      --plugin|--enable-plugin)
        shift
        [ -n "$1" ] && _cli_plugins="${_cli_plugins:+$_cli_plugins }$1"
        ;;
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
      --no-*)
        _pflag="${1#--no-}"
        if find_plugin_dir "$_pflag" >/dev/null 2>&1; then
          _cli_plugins="$(printf '%s' " $_cli_plugins " | sed -e "s/ $_pflag / /g" -e 's/^ *//;s/ *$//')"
        fi
        ;;
      --*)
        _pflag="${1#--}"
        if find_plugin_dir "$_pflag" >/dev/null 2>&1; then
          _cli_plugins="${_cli_plugins:+$_cli_plugins }$_pflag"
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
      printf '%bConfigure automated Git hooks (post-merge auto-sync & plugin triggers)? [Y/n]: %b' "$_BOLD" "$_NC"
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
    for _p in $_cli_plugins; do
      _pdir="$(find_plugin_dir "$_p" 2>/dev/null || true)"
      _cfg_lines=""
      if [ -n "$_pdir" ] && [ -f "$_pdir/plugin.yaml" ]; then
        _cfg_lines="$(plugin_config_default_lines "$_pdir/plugin.yaml")"
      fi
      if [ -n "$_cfg_lines" ]; then
        _init_plugins="${_init_plugins}  ${_p}:\n${_cfg_lines}\n"
      else
        _init_plugins="${_init_plugins}  ${_p}: {}\n"
      fi
    done

    _existing_repos=""
    if [ -d "$_init_dir/repos" ]; then
      for _d in "$_init_dir/repos"/*; do
        [ -d "$_d" ] || continue
        _r="$(basename "$_d")"
        case "$_r" in
          .*) continue ;;
          *) _existing_repos="${_existing_repos}  ${_r}:\n" ;;
        esac
      done
    fi

    if [ "$_init_git_hooks" = "false" ]; then
      _hooks_block='    post-merge: []
    post-checkout: []
    pre-commit: []
    pre-push: []'
    else
      _hooks_block='    post-merge:
      - "rnex sync --quiet"
    post-checkout:
      - "rnex sync --quiet"
    pre-commit: []
    pre-push: []'
    fi

    cat > "$_target_yaml" <<YAML_EOF
# Repo Nexus workspace configuration
# See templates/rnex.example.yaml for a comprehensive example with all options.

version: $RNEX_VERSION

# Directory for member repository clones
repos_dir: ./repos

# VS Code / Cursor multi-root workspace file (default: false; e.g. true or workspace.code-workspace)
code_workspace: ${_cli_code_workspace:-false}

# Git Integration (Ignore rules & Git hooks)
git:
  ignore:
    - "repos/"
    - "**/.rnex*/"
    - "**/rnex*/"
  hooks:
$_hooks_block

# RNEX Lifecycle Hooks
rnex_hooks:
  before_sync: []
  after_sync: []
  before_clone: []
  after_clone: []

# Workspace plugins
plugins:
$(printf '%b' "$_init_plugins")
# Member repositories managed by Repo Nexus
repos:
$(printf '%b' "$_existing_repos")
YAML_EOF
    _config_created=1
    log_ok "Created $RNEX_CONFIG_FILE"
  fi

  # Set active workspace context for initialization
  NEXUS_DIR="$_init_dir"
  WORKSPACE_YAML="$_target_yaml"
  WORKSPACE_LOCAL_YAML="$_init_dir/$RNEX_LOCAL_CONFIG_FILE"

  # ---- 2. Merge routing instructions into AI instructions files ------------
  merge_rnex_instructions "$_init_dir/AGENTS.md"
  for _if in CLAUDE.md GEMINI.md CODEX.md .cursorrules .windsurfrules .github/copilot-instructions.md; do
    [ -f "$_init_dir/$_if" ] && merge_rnex_instructions "$_init_dir/$_if"
  done

  # ---- 3. Create repos directory with .gitkeep -----------------------------
  _repos_dir="$_init_dir/repos"
  mkdir -p "$_repos_dir"
  [ -f "$_repos_dir/.gitkeep" ] || touch "$_repos_dir/.gitkeep"

  # ---- 4. Create internal .rnex directory and sync base assets -------------
  mkdir -p "$_init_dir/.rnex"
  mkdir -p "$_init_dir/.rnex/plugins"
  sync_plugins
  build_ai_instructions "$_init_dir"
  sync_skills

  # ---- 5. Ensure repos/ and local configs are gitignored ---------
  reconcile_gitignore "$_init_dir"

  # ---- 6. Generate VS Code / Cursor workspace if configured ----------------
  _orig_repos="$REPOS_DIR"
  _orig_cw="$CODE_WORKSPACE_FILE"
  _load_code_workspace "$_cli_code_workspace"
  _cw_name="$CODE_WORKSPACE_FILE"
  if [ -n "$_cw_name" ]; then
    REPOS_DIR="$_init_dir/repos"
    sync_code_workspace
  fi
  REPOS_DIR="$_orig_repos"
  CODE_WORKSPACE_FILE="$_orig_cw"

  # ---- 7. Setup automated Git hooks if inside a Git repository ------------
  if [ "$_is_git_ws" -eq 1 ]; then
    install_git_hooks "$_init_dir"
  fi

  _write_auto_sync_script "$_init_dir"
  update_sync_stamp "$_init_dir"

  if [ "$_config_created" -eq 1 ]; then
    printf '\n'
    log_ok "Initialized Repo Nexus workspace at ${_BOLD}$_init_dir${_NC}"
    _created_items="$RNEX_CONFIG_FILE, .rnex/, and repos/"
    [ -n "$_cw_name" ] && _created_items="$_created_items (and $_cw_name)"
    log_dim "Created $_created_items"
    printf '\n'
    log_info "Next steps:"
    log_dim "1. Add repositories with: rnex repo add <git-url> [--name <name>]"
    log_dim "2. Clone team repositories: rnex clone"
    log_dim "3. Run commands across all repos: rnex exec <command>"
  fi
}
