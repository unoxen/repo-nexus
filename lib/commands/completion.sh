#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands/completion.sh — Shell completion generators (bash, zsh, fish)
# ============================================================================

# Generate tab-completion script for the requested shell (bash, zsh, or fish).
# Usage:
#   source <(rnex completion bash)
#   source <(rnex completion zsh)
cmd_completion() {
  _shell="${1:-bash}"
  case "$_shell" in
    bash)
      cat <<'EOF'
_rnex_completions() {
  local cur prev commands repo_subcommands
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  commands="init install repo clone exec list sync status plugin completion version help"
  repo_subcommands="add remove set clone status exec list"

  case "$prev" in
    rnex)
      COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
      return 0
      ;;
    repo)
      COMPREPLY=( $(compgen -W "$repo_subcommands" -- "$cur") )
      return 0
      ;;
    init)
      COMPREPLY=( $(compgen -W "-y --yes --repos-dir --code-workspace --hooks --no-hooks --copilot --claude --gemini --codex --cursor --windsurf --karpathy" -- "$cur") )
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
      local plugins
      plugins=$(rnex plugin list 2>/dev/null | awk 'NR>3 && $2 ~ /^\[/ {print $3}')
      COMPREPLY=( $(compgen -W "list info enable install update disable help $plugins" -- "$cur") )
      return 0
      ;;
    remove|clone|status|exec|set)
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
  _stamp=".rnex/sync_stamp"
  if [ ! -f "$_stamp" ] || [ rnex.yaml -nt "$_stamp" ] || \
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
    'repo:Single-repository management (add, remove, set, clone, status, exec, list)'
    'clone:Clone missing member repositories'
    'exec:Execute a command across all member repositories'
    'list:List member repositories'
    'sync:Reconcile workspace, plugins, skills, and member .rnex directories'
    'status:Inspect workspace health and status (read-only)'
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
        repo)
          if [ "$CURRENT" -eq 2 ]; then
            local -a repo_cmds
            repo_cmds=('add:Add and optionally clone a member repository' 'remove:Remove a repository from configuration' 'set:Update repository configuration flags' 'clone:Clone a single repository' 'status:Show status of a repository' 'exec:Execute command in repository directory' 'list:List member repositories')
            _describe -t repo_cmds 'repo subcommand' repo_cmds
          elif [ "$words[2]" = "set" ]; then
            local -a set_opts
            set_opts=('--enable[Enable repository]' '--disable[Disable repository]' '--readonly[Mark repository read-only]' '--readwrite[Allow writing to repository]' '--global[Update team rnex.yaml]' '--local[Update workstation .local.rnex.yaml]')
            _describe -t set_opts 'repo set option' set_opts
          else
            local -a repos
            repos=($(rnex list 2>/dev/null | awk 'NR>2 {print $1}'))
            _describe -t repos 'repository' repos
          fi
          ;;
        init)
          local -a init_opts
          init_opts=('(-y --yes)'{-y,--yes}'[Automatically answer yes to prompts]' '--repos-dir[Directory for member repository clones]:dir:_files -/' '--code-workspace[Configure multi-root workspace file]' '--hooks[Configure automated git hooks]' '--no-hooks[Disable automated git hooks]' '--copilot[Enable Copilot plugin]' '--claude[Enable Claude plugin]' '--gemini[Enable Gemini plugin]' '--codex[Enable Codex plugin]' '--cursor[Enable Cursor plugin]' '--windsurf[Enable Windsurf plugin]' '--karpathy[Enable Karpathy LLM Wiki plugin]')
          _describe -t init_opts 'init option' init_opts
          ;;
        sync)
          local -a sync_opts
          sync_opts=('(-y --yes)'{-y,--yes}'[Automatically answer yes to prompts]' '(-q --quiet)'{-q,--quiet}'[Suppress non-error output]' '--upgrade[Upgrade workspace configuration schema]')
          _describe -t sync_opts 'sync option' sync_opts
          ;;
        status)
          ;;
        plugin)
          local -a plugin_cmds
          plugin_cmds=('list:List plugins' 'info:Show plugin details' 'enable:Enable plugin' 'install:Install/enable plugin' 'update:Update enabled plugin(s)' 'disable:Disable plugin' 'help:Display plugin help')
          _describe -t plugin_cmds 'plugin command' plugin_cmds
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
  _stamp=".rnex/sync_stamp"
  if [ ! -f "$_stamp" ] || [ rnex.yaml -nt "$_stamp" ] || \
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
complete -c rnex -n "__fish_seen_subcommand_from init" -l repos-dir -d "Directory for member repository clones"
complete -c rnex -n "__fish_seen_subcommand_from init" -l code-workspace -d "Configure multi-root workspace file"
complete -c rnex -n "__fish_seen_subcommand_from init" -l hooks -d "Configure automated git hooks"
complete -c rnex -n "__fish_seen_subcommand_from init" -l no-hooks -d "Disable automated git hooks"
complete -c rnex -n "__fish_use_subcommand" -a install -d "Install rnex globally"
complete -c rnex -n "__fish_use_subcommand" -a repo -d "Member repository management"
complete -c rnex -n "__fish_seen_subcommand_from repo" -a "add remove set clone status exec list"
complete -c rnex -n "__fish_seen_subcommand_from set" -l readonly -d "Mark repository read-only"
complete -c rnex -n "__fish_seen_subcommand_from set" -l readwrite -d "Allow writing to repository"
complete -c rnex -n "__fish_seen_subcommand_from set" -l enable -d "Enable repository"
complete -c rnex -n "__fish_seen_subcommand_from set" -l disable -d "Disable repository"
complete -c rnex -n "__fish_seen_subcommand_from set" -l global -d "Apply in team configuration"
complete -c rnex -n "__fish_seen_subcommand_from set" -l local -d "Apply in local configuration"
complete -c rnex -n "__fish_use_subcommand" -a clone -d "Clone missing repositories"
complete -c rnex -n "__fish_use_subcommand" -a exec -d "Execute command across member repos"
complete -c rnex -n "__fish_use_subcommand" -a list -d "List repositories"
complete -c rnex -n "__fish_use_subcommand" -a sync -d "Reconcile workspace, plugins, skills, and repos"
complete -c rnex -n "__fish_seen_subcommand_from sync" -l yes -s y -d "Automatically answer yes to prompts"
complete -c rnex -n "__fish_seen_subcommand_from sync" -l quiet -s q -d "Suppress non-error output"
complete -c rnex -n "__fish_seen_subcommand_from sync" -l upgrade -d "Upgrade workspace configuration schema"
complete -c rnex -n "__fish_use_subcommand" -a status -d "Inspect workspace status (read-only)"
complete -c rnex -n "__fish_use_subcommand" -a plugin -d "Manage plugins"
complete -c rnex -n "__fish_use_subcommand" -a completion -d "Generate completions"
complete -c rnex -n "__fish_use_subcommand" -a version -d "Show version"

function _rnex_auto_sync --on-event fish_prompt
  test -f rnex.yaml; or return 0
  set -l _stamp .rnex/sync_stamp
  if not test -f "$_stamp"; or test rnex.yaml -nt "$_stamp"; or test -f .local.rnex.yaml -a .local.rnex.yaml -nt "$_stamp"
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
