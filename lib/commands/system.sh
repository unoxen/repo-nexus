#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/system.sh — System commands: install, version, help
# ============================================================================

# Install rnex and repo-nexus executables and asset libraries into user bin and share directories.
cmd_install() {
  _target_bin="${1:-${RNEX_BIN_DIR:-$HOME/.local/bin}}"
  _target_bin="$(resolve_path "$_target_bin")"
  mkdir -p "$_target_bin"

  _src_root="$SCRIPT_LOCATION"
  [ -f "$_src_root/rnex" ] || _src_root="$(dirname "$SCRIPT_LOCATION")"
  _source_cli="$_src_root/rnex"
  [ -f "$_source_cli" ] || die "Could not locate source CLI executable to install"

  if [ -n "${RNEX_INSTALL_DIR:-}" ]; then
    _install_dir="$(resolve_path "$RNEX_INSTALL_DIR")"
  elif [ -n "${1:-}" ]; then
    case "$(basename "$_target_bin")" in
      bin) _install_dir="$(dirname "$_target_bin")/share/repo-nexus" ;;
      *)   _install_dir="$_target_bin" ;;
    esac
  else
    _install_dir="$HOME/.local/share/repo-nexus"
  fi

  mkdir -p "$_install_dir"
  if [ "$_src_root" != "$_install_dir" ]; then
    rm -rf "$_install_dir/docs"
    cp "$_source_cli" "$_install_dir/rnex"
    [ -f "$_src_root/package.json" ] && cp "$_src_root/package.json" "$_install_dir/package.json"
    for _asset in lib templates toolkit; do
      if [ -d "$_src_root/$_asset" ]; then
        rm -rf "${_install_dir:?}/$_asset"
        cp -R "$_src_root/$_asset" "$_install_dir/$_asset"
      fi
    done
  fi

  _installed_cli="$_install_dir/rnex"
  chmod +x "$_installed_cli"
  if [ "$_target_bin" != "$_install_dir" ]; then
    ln -sf "$_installed_cli" "$_target_bin/rnex"
  fi
  ln -sf "$_installed_cli" "$_target_bin/repo-nexus"

  log_ok "Installed 'rnex' and 'repo-nexus' into $_target_bin"
  case ":$PATH:" in
    *":$_target_bin:"*) ;;
    *)
      log_warn "$_target_bin is not in your PATH."
      log_dim "Add it to your shell configuration:"
      log_dim "  export PATH=\"$_target_bin:\$PATH\""
      ;;
  esac
}

# Output current Repo Nexus version from package.json.
cmd_version() {
  printf 'rnex %s\n' "$RNEX_VERSION"
}

# Check workspace configuration version against current CLI and run sync to upgrade if needed.
cmd_update() {
  require_workspace
  _cmp=0
  version_cmp "$WORKSPACE_CONFIG_VERSION" "$RNEX_VERSION" || _cmp=$?
  if [ "$_cmp" -eq 0 ]; then
    log_ok "Workspace configuration and routing instructions are already up to date (v$RNEX_VERSION)"
  elif [ "$_cmp" -eq 1 ]; then
    log_info "Workspace configuration version (v$WORKSPACE_CONFIG_VERSION) is newer than current CLI (v$RNEX_VERSION)"
  fi
  cmd_sync "$@"
}

cmd_upgrade() {
  cmd_update "$@"
}

# Display complete CLI usage, command catalog, options, and practical examples.
cmd_help() {
  cat <<EOF

  rnex — Repo Nexus CLI  (v$RNEX_VERSION)
  Virtual Meta-Repo companion for multi-repo AI workspaces (no git submodules).

  USAGE
  rnex [options] <command> [arguments]

  OPTIONS
    -c, --config <file>     Path to $RNEX_CONFIG_FILE (executes in the directory where config lives)
    -h, --help              Show help information
    -v, --version           Show version

  WORKSPACE & SYSTEM SETUP
    init [-y] [--code-workspace [file]] [--hooks|--no-hooks] [--copilot] [--claude] [--gemini] [--codex] [--cursor] [--windsurf] [--karpathy] [dir]
                            Initialize a new Repo Nexus workspace (default: AGENTS.md)
    install [dir]           Install rnex & repo-nexus globally into ~/.local/bin (or custom dir)
    sync [-y] [--quiet]     Reconcile workspace, plugins, skills, member .rnex directories, and compile AI instructions
    status                  Inspect workspace health, active repos, loaded config, git hooks, and plugins (read-only)
    update [-y]             Check version, upgrade schema, and reconcile workspace (alias: upgrade)
    upgrade [-y]            Alias for update
    hooks <install|uninstall|status> [--local]
                            Manage automated Git hooks (--local writes to .local.rnex.yaml)
    completion <shell>      Generate shell completion script (bash, zsh, fish)

  REPO MANAGEMENT
    add [--local] [--disabled] [--readonly] [<name>] <git-url>
                            Register and clone repo (--local writes to .local.rnex.yaml)
    clone                   Clone all missing enabled repositories declared in rnex.yaml
    exec <command...>       Execute a shell command across all active member repositories
    remove <name>           Unregister and delete member repository
    enable [--local] <name> Enable a member repository in active workspace
    disable [--local] <name> Disable a member repository in workspace
    readonly [--local] <enable|disable> <name>
                            Toggle read-only (information-only) status for a member repo
    list                    List all member repositories with clone state & active branch

  PLUGIN MANAGEMENT
    plugin [list]           List available and enabled plugins
    plugin info <name>      Show details of a plugin
    plugin enable [--local] <name>   Enable/install plugin in workspace (scoped to .rnex/plugins/<name>/)
    plugin install [--local] <name>  Alias for plugin enable
    plugin update [name]    Update enabled plugin(s) from source
    plugin disable [--local] <name>  Disable plugin from workspace

  EXAMPLES
    rnex init                                   # Initialize workspace in current folder
    rnex add backend git@github.com:org/api.git # Register and clone backend repo
    rnex clone                                  # Clone all team repositories defined in rnex.yaml
    rnex exec git status -s                     # Check Git status across all repos
    rnex exec npm test                          # Run tests in all repos
    rnex disable analytics --local              # Disable analytics repo on local machine only
    rnex enable analytics                       # Re-enable analytics repo
    rnex list                                   # List all member repos and active branches
    rnex status                                 # Inspect workspace configuration and health
    rnex sync                                   # Reconcile all repos, plugins, skills, and .rnex directories
    rnex update                                 # Upgrade workspace configuration to newest version
    rnex hooks install                          # Enable automated workspace Git hooks
    rnex completion zsh                         # Generate Zsh completion script

EOF
}
