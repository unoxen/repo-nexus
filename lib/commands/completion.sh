#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/completion.sh — Shell completion generators (bash, zsh, fish)
# ============================================================================

cmd_completion() {
  _shell="${1:-bash}"
  case "$_shell" in
    bash)
      cat <<'EOF'
_rnex_completions() {
  local cur prev commands
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  commands="init install add clone exec remove enable disable list sync status rnex-dir update upgrade hooks plugin completion version help"

  case "$prev" in
    rnex)
      COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
      return 0
      ;;
    sync)
      COMPREPLY=( $(compgen -W "-y --yes -q --quiet --upgrade" -- "$cur") )
      return 0
      ;;
    status)
      COMPREPLY=()
      return 0
      ;;
    plugin)
      COMPREPLY=( $(compgen -W "list info enable install update disable" -- "$cur") )
      return 0
      ;;
    hooks)
      COMPREPLY=( $(compgen -W "install uninstall status" -- "$cur") )
      return 0
      ;;
    enable|disable|remove|show|hide|rnex-dir)
      local repos
      repos=$(rnex list 2>/dev/null | awk 'NR>2 {print $1}')
      COMPREPLY=( $(compgen -W "$repos" -- "$cur") )
      return 0
      ;;
    completion)
      COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
      return 0
      ;;
  esac
}
complete -F _rnex_completions rnex
complete -F _rnex_completions repo-nexus

# Prompt hook for zero-fork auto-synchronization
_rnex_auto_sync() {
  [ -f rnex.yaml ] || return 0
  _stamp=""
  [ -f .rnex/sync_stamp ] && _stamp=".rnex/sync_stamp"
  [ -z "$_stamp" ] && [ -f .rnex/.sync_stamp ] && _stamp=".rnex/.sync_stamp"
  if [ -z "$_stamp" ] || [ rnex.yaml -nt "$_stamp" ] || \
     { [ -f .local.rnex.yaml ] && [ .local.rnex.yaml -nt "$_stamp" ]; }; then
    rnex sync -y --quiet
  fi
}
if [[ ! "$PROMPT_COMMAND" =~ "_rnex_auto_sync" ]]; then
  PROMPT_COMMAND="_rnex_auto_sync${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
EOF
      ;;
    zsh)
      cat <<'EOF'
#compdef rnex repo-nexus

_rnex() {
  local -a commands
  commands=(
    'init:Initialize a new Repo Nexus workspace'
    'install:Install rnex globally into ~/.local/bin'
    'add:Register and clone a member repository'
    'clone:Clone missing member repositories'
    'exec:Execute a command across all member repositories'
    'remove:Unregister and delete a repository'
    'enable:Enable a repository in active workspace'
    'disable:Disable a repository in workspace'
    'list:List member repositories'
    'sync:Reconcile workspace, plugins, skills, and member .rnex directories'
    'status:Inspect workspace health and status (read-only)'
    'rnex-dir:Toggle .rnex directory integration for a repo'
    'update:Upgrade workspace configuration and routing instructions'
    'upgrade:Alias for update'
    'hooks:Manage automated Git hooks'
    'plugin:Manage plugins'
    'completion:Generate shell completions'
    'version:Display version'
    'help:Display help'
  )

  _arguments -C \
    '(-c --config)'{-c,--config}'[Specify config file]:file:_files' \
    '(-v --version)'{-v,--version}'[Display version]' \
    '(-h --help)'{-h,--help}'[Display help]' \
    '1:command:->command' \
    '*::arguments:->args'

  case "$state" in
    command)
      _describe -t commands 'rnex command' commands
      ;;
    args)
      case "$words[1]" in
        sync)
          local -a sync_opts
          sync_opts=('(-y --yes)'{-y,--yes}'[Automatically answer yes to prompts]' '(-q --quiet)'{-q,--quiet}'[Suppress non-error output]' '--upgrade[Upgrade workspace configuration schema]')
          _describe -t sync_opts 'sync option' sync_opts
          ;;
        status)
          ;;
        plugin)
          local -a plugin_cmds
          plugin_cmds=('list:List plugins' 'info:Show plugin details' 'enable:Enable plugin' 'install:Install/enable plugin' 'update:Update enabled plugin(s)' 'disable:Disable plugin')
          _describe -t plugin_cmds 'plugin command' plugin_cmds
          ;;
        hooks)
          local -a hook_cmds
          hook_cmds=('install:Install Git hooks' 'uninstall:Uninstall Git hooks' 'status:Show Git hooks status')
          _describe -t hook_cmds 'hooks command' hook_cmds
          ;;
        enable|disable|remove|show|hide|rnex-dir)
          local -a repos
          repos=($(rnex list 2>/dev/null | awk 'NR>2 {print $1}'))
          _describe -t repos 'repository' repos
          ;;
        completion)
          local -a shells
          shells=('bash:Bash completion' 'zsh:Zsh completion' 'fish:Fish completion')
          _describe -t shells 'shell' shells
          ;;
      esac
      ;;
  esac
}

_rnex "$@"

# Prompt hook for zero-fork auto-synchronization
_rnex_auto_sync() {
  [ -f rnex.yaml ] || return 0
  _stamp=""
  [ -f .rnex/sync_stamp ] && _stamp=".rnex/sync_stamp"
  [ -z "$_stamp" ] && [ -f .rnex/.sync_stamp ] && _stamp=".rnex/.sync_stamp"
  if [ -z "$_stamp" ] || [ rnex.yaml -nt "$_stamp" ] || \
     { [ -f .local.rnex.yaml ] && [ .local.rnex.yaml -nt "$_stamp" ]; }; then
    rnex sync -y --quiet
  fi
}
autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd _rnex_auto_sync || precmd_functions+=(_rnex_auto_sync)
EOF
      ;;
    fish)
      cat <<'EOF'
complete -c rnex -n "__fish_use_subcommand" -a init -d "Initialize a new workspace"
complete -c rnex -n "__fish_use_subcommand" -a install -d "Install rnex globally"
complete -c rnex -n "__fish_use_subcommand" -a add -d "Register and clone a repository"
complete -c rnex -n "__fish_use_subcommand" -a clone -d "Clone missing repositories"
complete -c rnex -n "__fish_use_subcommand" -a exec -d "Execute command across member repos"
complete -c rnex -n "__fish_use_subcommand" -a remove -d "Remove a repository"
complete -c rnex -n "__fish_use_subcommand" -a enable -d "Enable a repository"
complete -c rnex -n "__fish_use_subcommand" -a disable -d "Disable a repository"
complete -c rnex -n "__fish_use_subcommand" -a list -d "List repositories"
complete -c rnex -n "__fish_use_subcommand" -a rnex-dir -d "Toggle .rnex directory integration for a repo"
complete -c rnex -n "__fish_seen_subcommand_from rnex-dir" -a "enable disable"
complete -c rnex -n "__fish_seen_subcommand_from rnex-dir" -l local -d "Apply locally"
complete -c rnex -n "__fish_use_subcommand" -a sync -d "Reconcile workspace, plugins, skills, and repos"
complete -c rnex -n "__fish_seen_subcommand_from sync" -l yes -s y -d "Automatically answer yes to prompts"
complete -c rnex -n "__fish_seen_subcommand_from sync" -l quiet -s q -d "Suppress non-error output"
complete -c rnex -n "__fish_seen_subcommand_from sync" -l upgrade -d "Upgrade workspace configuration schema"
complete -c rnex -n "__fish_use_subcommand" -a status -d "Inspect workspace status (read-only)"
complete -c rnex -n "__fish_use_subcommand" -a update -d "Upgrade workspace configuration"
complete -c rnex -n "__fish_use_subcommand" -a upgrade -d "Upgrade workspace configuration"
complete -c rnex -n "__fish_use_subcommand" -a hooks -d "Manage Git hooks"
complete -c rnex -n "__fish_use_subcommand" -a plugin -d "Manage plugins"
complete -c rnex -n "__fish_use_subcommand" -a completion -d "Generate completions"
complete -c rnex -n "__fish_use_subcommand" -a version -d "Show version"

function _rnex_auto_sync --on-event fish_prompt
  test -f rnex.yaml; or return 0
  set -l _stamp ""
  if test -f .rnex/sync_stamp
    set _stamp .rnex/sync_stamp
  else if test -f .rnex/.sync_stamp
    set _stamp .rnex/.sync_stamp
  end
  if test -z "$_stamp"; or test rnex.yaml -nt "$_stamp"; or test -f .local.rnex.yaml -a .local.rnex.yaml -nt "$_stamp"
    rnex sync -y --quiet
  end
end
EOF
      ;;
    *)
      die "Unsupported shell: $_shell (supported: bash, zsh, fish)"
      ;;
  esac
}
