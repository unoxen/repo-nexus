#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/hooks.sh — Automated Git hooks management and event dispatch
# ============================================================================

_create_hook_script() {
  _dst="$1"
  _hook_type="$2"

  # Preserve custom / repository-owned wrappers that are not auto-managed by rnex
  if [ -f "$_dst" ] && ! grep -q "Managed automatically by rnex" "$_dst" 2>/dev/null; then
    return 0
  fi

  _sub_tmp="$(mktemp)"
  cat > "$_sub_tmp" <<HOOK_EOF
#!/bin/sh
# Repo Nexus Git Hook: $_hook_type
# Managed automatically by rnex. Do not edit manually.

_dir="\$(cd "\$(dirname "\$0")/../.." 2>/dev/null && pwd -P)"
if [ -x "\$_dir/rnex" ]; then
  "\$_dir/rnex" hooks run $_hook_type "\$@"
elif command -v rnex >/dev/null 2>&1; then
  rnex hooks run $_hook_type "\$@"
fi
HOOK_EOF

  chmod +x "$_sub_tmp"

  # Avoid rewriting / modifying file if already identical (prevents inode churn & self-rewrite)
  if [ -f "$_dst" ] && cmp -s "$_sub_tmp" "$_dst"; then
    rm -f "$_sub_tmp"
    return 0
  fi

  mkdir -p "$(dirname "$_dst")"
  mv "$_sub_tmp" "$_dst"
}

cmd_hooks_install_dir() {
  _ws_dir="$1"
  if ! git -C "$_ws_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "Directory '$_ws_dir' is not a Git repository. Run 'git init' first."
  fi
  _h_dir="$_ws_dir/.rnex/hooks"
  mkdir -p "$_h_dir"
  _create_hook_script "$_h_dir/post-merge" "post-merge"
  _create_hook_script "$_h_dir/post-commit" "post-commit"
  _create_hook_script "$_h_dir/pre-commit" "pre-commit"
  _create_hook_script "$_h_dir/pre-push" "pre-push"

  git -C "$_ws_dir" config core.hooksPath .rnex/hooks
  log_ok "Configured Git hooks in .rnex/hooks (core.hooksPath = .rnex/hooks)"
}

cmd_hooks_uninstall_dir() {
  _ws_dir="$1"
  if git -C "$_ws_dir" config --get core.hooksPath >/dev/null 2>&1; then
    git -C "$_ws_dir" config --unset core.hooksPath || true
  fi
  rm -rf "$_ws_dir/.rnex/hooks"
  log_ok "Uninstalled Repo Nexus Git hooks (core.hooksPath unset)"
}

cmd_hooks() {
  case "${1:-status}" in
    install)
      require_workspace
      _local=0
      shift || true
      while [ $# -gt 0 ]; do
        case "$1" in
          --local) _local=1 ;;
        esac
        shift
      done
      cmd_hooks_install_dir "$NEXUS_DIR"
      if [ "$_local" -eq 1 ]; then
        yaml_set_top_level_local "git_hooks" "true"
        log_dim "Recorded git_hooks: true in $RNEX_LOCAL_CONFIG_FILE"
      else
        yaml_set_top_level "git_hooks" "true"
        log_dim "Recorded git_hooks: true in $RNEX_CONFIG_FILE"
      fi
      _load_git_hooks
      ;;
    uninstall)
      require_workspace
      _local=0
      shift || true
      while [ $# -gt 0 ]; do
        case "$1" in
          --local) _local=1 ;;
        esac
        shift
      done
      cmd_hooks_uninstall_dir "$NEXUS_DIR"
      if [ "$_local" -eq 1 ]; then
        yaml_set_top_level_local "git_hooks" "false"
        log_dim "Recorded git_hooks: false in $RNEX_LOCAL_CONFIG_FILE"
      else
        yaml_set_top_level "git_hooks" "false"
        log_dim "Recorded git_hooks: false in $RNEX_CONFIG_FILE"
      fi
      _load_git_hooks
      ;;
    status)
      require_workspace
      printf '\n%bRepo Nexus Git Hooks Status%b\n' "$_B" "$_NC"
      printf '=%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28
      printf '\n\n'

      printf '  %b●%b Configuration:  ' "$_DIM" "$_NC"
      case "$GIT_HOOKS_CONFIG" in
        true|yes|1) printf '%bgit_hooks: true%b %b(enabled in config)%b\n' "$_G" "$_NC" "$_DIM" "$_NC" ;;
        false|no|0) printf '%bgit_hooks: false%b %b(disabled in config)%b\n' "$_Y" "$_NC" "$_DIM" "$_NC" ;;
        *)          printf '%bnot configured%b %b(defaults to active if git repo)%b\n' "$_DIM" "$_NC" "$_DIM" "$_NC" ;;
      esac

      _hp="$(git -C "$NEXUS_DIR" config --get core.hooksPath 2>/dev/null || true)"
      if [ "$_hp" = ".rnex/hooks" ] || [ "$_hp" = "$NEXUS_DIR/.rnex/hooks" ]; then
        printf '  %b●%b core.hooksPath: %s %b(active)%b\n' "$_G" "$_NC" "$_hp" "$_DIM" "$_NC"
      elif [ -n "$_hp" ]; then
        printf '  %b!%b core.hooksPath: %s %b(external/custom)%b\n' "$_Y" "$_NC" "$_hp" "$_DIM" "$_NC"
      else
        printf '  %b○%b core.hooksPath: %b(not configured — run "rnex hooks install")%b\n' "$_DIM" "$_NC" "$_DIM" "$_NC"
      fi

      printf '\n%bInstalled Hooks in .rnex/hooks/:%b\n' "$_BOLD" "$_NC"
      for _h in "post-merge" "post-commit" "pre-commit" "pre-push"; do
        if [ -f "$NEXUS_DIR/.rnex/hooks/$_h" ]; then
          printf '  %b✓%b %-15s %b(installed)%b\n' "$_G" "$_NC" "$_h" "$_DIM" "$_NC"
        else
          printf '  %b○%b %-15s %b(not installed)%b\n' "$_DIM" "$_NC" "$_h" "$_DIM" "$_NC"
        fi
      done

      _active_trigger=""
      if yaml_plugin_enabled "karpathy-llm"; then
        _active_trigger="$(yaml_plugin_get "karpathy-llm" "lint_trigger")"
        printf '\n%bActive Plugin Triggers:%b\n' "$_BOLD" "$_NC"
        if [ -n "$_active_trigger" ]; then
          printf '  %b●%b karpathy-llm: %s\n' "$_G" "$_NC" "$_active_trigger"
        else
          printf '  %b○%b karpathy-llm: (manual only / no trigger set in rnex.yaml)\n' "$_DIM" "$_NC"
        fi
        printf '\n'
      fi
      ;;
    run)
      shift
      _hook_name="$1"
      shift || true
      export _RNEX_INSIDE_HOOK=1
      require_workspace
      case "$_hook_name" in
        post-merge)
          cmd_sync --fix -y --quiet || true
          if yaml_plugin_enabled "karpathy-llm"; then
            _trigger="$(yaml_plugin_get "karpathy-llm" "lint_trigger")"
            if [ "$_trigger" = "git-post-merge" ] || [ "$_trigger" = "post-merge" ]; then
              _wiki_dir="$(karpathy_wiki_dir)"
              _raw_dir="$(karpathy_raw_dir)"
              _changed="$(git -C "$NEXUS_DIR" diff-tree -r --name-only ORIG_HEAD HEAD 2>/dev/null || true)"
              if echo "$_changed" | grep -qE "^(${_raw_dir}/|${_wiki_dir}/)"; then
                printf '%b[WIKI]%b Upstream changes detected in %s/ or %s/ after merge.\n' "$_Y" "$_NC" "$_raw_dir" "$_wiki_dir"
              fi
            fi
          fi
          if [ -x "$NEXUS_DIR/.githooks/post-merge" ]; then
            "$NEXUS_DIR/.githooks/post-merge" "$@" || true
          fi
          return 0
          ;;
        post-commit)
          if yaml_plugin_enabled "karpathy-llm"; then
            _trigger="$(yaml_plugin_get "karpathy-llm" "lint_trigger")"
            if [ "$_trigger" = "git-post-commit" ] || [ "$_trigger" = "post-commit" ]; then
              _wiki_dir="$(karpathy_wiki_dir)"
              _raw_dir="$(karpathy_raw_dir)"
              _changed="$(git -C "$NEXUS_DIR" diff-tree -r --name-only --no-commit-id HEAD 2>/dev/null || true)"
              if echo "$_changed" | grep -qE "^(${_raw_dir}/|${_wiki_dir}/)"; then
                _notify="$(yaml_plugin_get "karpathy-llm" "notify_on_changes")"
                [ "$_notify" != "false" ] && printf '%b[WIKI]%b Changes committed to %s/ or %s/. Run wiki-lint or wiki-ingest as needed.\n' "$_Y" "$_NC" "$_raw_dir" "$_wiki_dir"
              fi
            fi
          fi
          if [ -x "$NEXUS_DIR/.githooks/post-commit" ]; then
            "$NEXUS_DIR/.githooks/post-commit" "$@" || true
          fi
          return 0
          ;;
        pre-commit)
          if yaml_plugin_enabled "karpathy-llm"; then
            _trigger="$(yaml_plugin_get "karpathy-llm" "lint_trigger")"
            if [ "$_trigger" = "git-pre-commit" ] || [ "$_trigger" = "pre-commit" ]; then
              _wiki_dir="$(karpathy_wiki_dir)"
              _raw_dir="$(karpathy_raw_dir)"
              _staged="$(git -C "$NEXUS_DIR" diff --cached --name-only 2>/dev/null || true)"
              if echo "$_staged" | grep -qE "^(${_raw_dir}/|${_wiki_dir}/)"; then
                _notify="$(yaml_plugin_get "karpathy-llm" "notify_on_changes")"
                [ "$_notify" != "false" ] && printf '%b[WIKI]%b Pre-commit trigger: %s/ or %s/ staged for commit.\n' "$_C" "$_NC" "$_raw_dir" "$_wiki_dir"
              fi
            fi
          fi
          if [ -x "$NEXUS_DIR/.githooks/pre-commit" ]; then
            "$NEXUS_DIR/.githooks/pre-commit" "$@" || return $?
          fi
          return 0
          ;;
        pre-push)
          if yaml_plugin_enabled "karpathy-llm"; then
            _trigger="$(yaml_plugin_get "karpathy-llm" "lint_trigger")"
            if [ "$_trigger" = "git-pre-push" ] || [ "$_trigger" = "pre-push" ]; then
              _wiki_dir="$(karpathy_wiki_dir)"
              printf '%b[WIKI]%b Pre-push trigger: verifying wiki changes in %s/.\n' "$_C" "$_NC" "$_wiki_dir"
            fi
          fi
          if [ -x "$NEXUS_DIR/.githooks/pre-push" ]; then
            "$NEXUS_DIR/.githooks/pre-push" "$@" || return $?
          fi
          return 0
          ;;
      esac
      return 0
      ;;
    *)
      die "Unknown hooks command: $1. Usage: rnex hooks <install|uninstall|status>"
      ;;
  esac
}
