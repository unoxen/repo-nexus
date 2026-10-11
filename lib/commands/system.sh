#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/system.sh — System commands: install, version, help
# ============================================================================

cmd_install() {
  _target_bin="${1:-$HOME/.local/bin}"
  _target_bin="$(resolve_path "$_target_bin")"
  mkdir -p "$_target_bin"

  _source_cli="$SCRIPT_LOCATION/rnex"
  [ -f "$_source_cli" ] || _source_cli="$SCRIPT_LOCATION"
  [ -f "$_source_cli" ] || die "Could not locate source CLI executable to install"

  chmod +x "$_source_cli"
  ln -sf "$_source_cli" "$_target_bin/rnex"
  ln -sf "$_source_cli" "$_target_bin/repo-nexus"

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

cmd_version() {
  printf 'rnex %s\n' "$RNEX_VERSION"
}

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
    init [-y] [--code-workspace [file]] [--hooks|--no-hooks] [--copilot] [--claude] [--gemini] [--cursor] [--windsurf] [dir]
                            Initialize a new Repo Nexus workspace (default: AGENTS.md)
    install [dir]           Install rnex & repo-nexus globally into ~/.local/bin (or custom dir)
    fix [-y] [--quiet]      Reconcile workspace, upgrade configuration & routing, sync plugins & repos (aliases: sync, update, upgrade)
    update [-y]             Part of fix: check version, upgrade schema, and reconcile workspace (alias: upgrade)
    upgrade [-y]            Alias for update
    hooks <install|uninstall|status> [--local]
                            Manage automated Git hooks (--local writes to .local.rnex.yaml)
    completion <shell>      Generate shell completion script (bash, zsh, fish)

  REPO MANAGEMENT
    add [--local] [--disabled] [--no-rnex-dir] <name> <git-url>
                            Register and clone repo (--local writes to .local.rnex.yaml)
    clone                   Clone all missing enabled repositories declared in rnex.yaml
    exec <command...>       Execute a shell command across all active member repositories
    remove <name>           Unregister and delete member repository
    enable [--local] <name> Enable a member repository in active workspace
    disable [--local] <name> Disable a member repository in workspace
    list                    List all member repositories with clone state & active branch
    status                  Inspect workspace health, active repos, and plugins
    rnex-dir <enable|disable> <name>  Toggle .rnex directory integration for a member repo

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
    rnex fix                                    # Reconcile all repos, plugins, and .rnex directories
    rnex update                                 # Upgrade workspace configuration to newest version (part of fix)
    rnex hooks install                          # Enable automated workspace Git hooks
    rnex completion zsh                         # Generate Zsh completion script

EOF
}
