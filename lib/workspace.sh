#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# File: lib/workspace.sh
# Architectural Layer: Core Workspace Management
# Single Responsibility: Workspace root discovery, configuration context
# initialization, sync stamp checksum verification, and auto-reconciliation.
# ============================================================================

RNEX_CONFIG_FILE="rnex.yaml"
RNEX_LOCAL_CONFIG_FILE=".local.rnex.yaml"

# ----------------------------------------------------------------------------
# find_workspace_dir
# Summary: Searches upwards from the current working directory to the
#          filesystem root for rnex.yaml or .rnex.yaml.
# @returns: Absolute path of workspace root on stdout, or returns 1 if absent.
# @pure (Read-only filesystem traversal)
# ----------------------------------------------------------------------------
find_workspace_dir() {
  _curr="$(pwd -P 2>/dev/null || pwd)"
  while [ -n "$_curr" ] && [ "$_curr" != "/" ]; do
    if [ -f "$_curr/$RNEX_CONFIG_FILE" ] || [ -f "$_curr/.rnex.yaml" ]; then
      printf '%s' "$_curr"
      return 0
    fi
    _curr="$(dirname "$_curr")"
  done
  if [ -f "/$RNEX_CONFIG_FILE" ] || [ -f "/.rnex.yaml" ]; then
    printf '/'
    return 0
  fi
  return 1
}

# ----------------------------------------------------------------------------
# get_config_sum
# Summary: Computes a combined POSIX cksum digest of rnex.yaml and
#          .local.rnex.yaml to detect configuration drift.
# @param $1: ws_dir - Optional workspace directory (defaults to NEXUS_DIR).
# @returns: Checksum string on stdout.
# @pure
# ----------------------------------------------------------------------------
get_config_sum() {
  _dir="${1:-${NEXUS_DIR:-.}}"
  _yaml="rnex.yaml"
  if [ -n "$CUSTOM_CONFIG" ]; then
    _yaml="$(basename "$CUSTOM_CONFIG")"
  elif [ -n "$WORKSPACE_YAML" ]; then
    _yaml="$(basename "$WORKSPACE_YAML")"
  fi
  ( cd "$_dir" 2>/dev/null && cksum "$_yaml" .local.rnex.yaml 2>/dev/null | cksum | awk '{print $1, $2}' )
}

# ----------------------------------------------------------------------------
# update_sync_stamp
# Summary: Updates .rnex/sync_stamp with the current configuration checksum
#          and ensures sync_stamp is listed in .rnex/.gitignore.
# @param $1: ws_dir - Optional workspace directory (defaults to NEXUS_DIR).
# @returns: 0 on success.
# @sideEffects: Writes .rnex/sync_stamp and .rnex/.gitignore.
# ----------------------------------------------------------------------------
update_sync_stamp() {
  _dir="${1:-${NEXUS_DIR:-.}}"
  mkdir -p "$_dir/.rnex"
  if [ ! -f "$_dir/.rnex/.gitignore" ]; then
    printf "sync_stamp\n" > "$_dir/.rnex/.gitignore"
  elif ! grep -q "^sync_stamp" "$_dir/.rnex/.gitignore" 2>/dev/null; then
    printf "sync_stamp\n" >> "$_dir/.rnex/.gitignore"
  fi
  _csum="$(get_config_sum "$_dir")"
  printf '%s\n' "$_csum" > "$_dir/.rnex/sync_stamp"
}

# ----------------------------------------------------------------------------
# check_auto_sync
# Summary: Compares the current configuration checksum against .rnex/sync_stamp
#          and triggers a silent reconciliation (`cmd_sync -y --quiet`) if stale.
# @returns: 0 on success.
# @sideEffects: May invoke cmd_sync if configuration checksum changed.
# ----------------------------------------------------------------------------
check_auto_sync() {
  _ws="${NEXUS_DIR:-}"
  if [ -z "$_ws" ]; then
    if [ -n "$CUSTOM_CONFIG" ]; then
      _cfg_path="$(resolve_path "$CUSTOM_CONFIG" 2>/dev/null || true)"
      if [ -f "$_cfg_path" ]; then
        _ws="$(cd -P "$(dirname "$_cfg_path")" 2>/dev/null && pwd -P)"
      fi
    elif [ -f rnex.yaml ]; then
      _ws="."
    else
      _ws="$(find_workspace_dir 2>/dev/null || true)"
    fi
  fi
  [ -z "$_ws" ] && return 0
  _cfg_file="$_ws/rnex.yaml"
  if [ -n "$CUSTOM_CONFIG" ]; then
    _cfg_file="$(resolve_path "$CUSTOM_CONFIG" 2>/dev/null || true)"
  fi
  [ -f "$_cfg_file" ] || return 0
  _stamp="$_ws/.rnex/sync_stamp"
  if [ ! -f "$_stamp" ] || [ "$(get_config_sum "$_ws")" != "$(cat "$_stamp" 2>/dev/null)" ]; then
    _prev_ignore="${RNEX_IGNORE_HOOKS:-0}"
    RNEX_IGNORE_HOOKS=1
    export RNEX_IGNORE_HOOKS
    cmd_sync -y --quiet
    RNEX_IGNORE_HOOKS="$_prev_ignore"
    export RNEX_IGNORE_HOOKS
  fi
}

auto_sync_if_needed() {
  check_auto_sync "$@"
}

# ----------------------------------------------------------------------------
# require_workspace
# Summary: Resolves and validates the active Repo Nexus workspace root and
#          exports NEXUS_DIR, RNEX_ROOT, WORKSPACE_YAML, and REPOS_DIR.
# @throws: Terminates with exit status 1 if no workspace configuration exists.
# @sideEffects: Exports workspace environment variables.
# ----------------------------------------------------------------------------
require_workspace() {
  if [ -n "$CUSTOM_CONFIG" ]; then
    _cfg_path="$(resolve_path "$CUSTOM_CONFIG")"
    if [ ! -f "$_cfg_path" ]; then
      die "Specified config file does not exist: $_cfg_path"
    fi
    NEXUS_DIR="$(cd -P "$(dirname "$_cfg_path")" 2>/dev/null && pwd -P)"
    RNEX_ROOT="$NEXUS_DIR"
    WORKSPACE_YAML="$_cfg_path"
    export NEXUS_DIR RNEX_ROOT WORKSPACE_YAML
    _init_local_yaml
    _load_workspace_version
    _load_repos_dir
    _load_code_workspace
    log_info "Using workspace at ${_BOLD}$NEXUS_DIR${_NC} ${_DIM}(via config: $WORKSPACE_YAML)${_NC}"
    return 0
  fi

  _found_dir="$(find_workspace_dir || true)"
  if [ -z "$_found_dir" ]; then
    log_err "No '$RNEX_CONFIG_FILE' found in current directory ($PWD) or parent directories."
    log_dim "To initialize a new Repo Nexus workspace here, run:"
    log_dim "  rnex init"
    log_dim "Or specify a workspace config file directly:"
    log_dim "  rnex --config /path/to/$RNEX_CONFIG_FILE <command>"
    log_dim "Or change directory to an existing workspace:"
    log_dim "  cd /path/to/workspace"
    exit 1
  fi

  NEXUS_DIR="$_found_dir"
  RNEX_ROOT="$NEXUS_DIR"
  if [ -f "$NEXUS_DIR/$RNEX_CONFIG_FILE" ]; then
    WORKSPACE_YAML="$NEXUS_DIR/$RNEX_CONFIG_FILE"
  elif [ -f "$NEXUS_DIR/.rnex.yaml" ]; then
    WORKSPACE_YAML="$NEXUS_DIR/.rnex.yaml"
  else
    WORKSPACE_YAML="$NEXUS_DIR/$RNEX_CONFIG_FILE"
  fi
  export NEXUS_DIR RNEX_ROOT WORKSPACE_YAML
  _init_local_yaml
  _load_workspace_version
  _load_repos_dir
  _load_code_workspace

  log_info "Using workspace at ${_BOLD}$NEXUS_DIR${_NC} ${_DIM}($(basename "$WORKSPACE_YAML") found)${_NC}"
}

_init_local_yaml() {
  WORKSPACE_LOCAL_YAML="$NEXUS_DIR/$RNEX_LOCAL_CONFIG_FILE"
}

_load_workspace_version() {
  WORKSPACE_CONFIG_VERSION="$(yaml_get_top_level "version")"
}

_load_repos_dir() {
  REPOS_DIR_REL="$(yaml_get_repos_dir)"
  REPOS_DIR="$(get_repos_root)"
  export REPOS_DIR_REL REPOS_DIR
}

_load_code_workspace() {
  _cw="${1:-}"
  [ -n "$_cw" ] || _cw="$(yaml_get_top_level "codeWorkspace")"
  case "$_cw" in
    true|yes|1)
      _ws_basename="$(basename "$NEXUS_DIR")"
      CODE_WORKSPACE_FILE="$_ws_basename.code-workspace"
      ;;
    false|no|0|none|"")
      CODE_WORKSPACE_FILE=""
      ;;
    *)
      case "$_cw" in
        *.code-workspace) CODE_WORKSPACE_FILE="$_cw" ;;
        *) CODE_WORKSPACE_FILE="$_cw.code-workspace" ;;
      esac
      ;;
  esac
}

# ----------------------------------------------------------------------------
# sync_workspace_config_version
# Summary: Updates the top-level `version:` property in $WORKSPACE_YAML to
#          match $RNEX_VERSION whenever the existing version is missing or older
#          than the active CLI version. Never downgrades a newer version.
# @param $1: quiet - Optional quiet flag (0 = log update notice, 1 = silent).
# @returns: 0 if up to date or updated successfully; 1 on write failure.
# @sideEffects: May update `version:` in $WORKSPACE_YAML, reload
#               WORKSPACE_CONFIG_VERSION, and refresh .rnex/sync_stamp.
# ----------------------------------------------------------------------------
sync_workspace_config_version() {
  _swv_quiet="${1:-0}"
  [ -n "${RNEX_VERSION:-}" ] || return 0
  [ -f "${WORKSPACE_YAML:-}" ] || return 0

  # Read version strictly from primary workspace config so local overrides
  # cannot mask a stale or missing team config version.
  _swv_cur="$(_yaml_top_level_from_file "$WORKSPACE_YAML" "version")"
  _swv_norm_cur="${_swv_cur#v}"
  _swv_norm_cur="${_swv_norm_cur#V}"
  _swv_norm_cli="${RNEX_VERSION#v}"
  _swv_norm_cli="${_swv_norm_cli#V}"

  _swv_cmp=0
  version_cmp "$_swv_norm_cur" "$_swv_norm_cli" || _swv_cmp=$?
  [ "$_swv_cmp" -eq 2 ] || return 0

  if yaml_set_top_level "version" "$_swv_norm_cli"; then
    _load_workspace_version
    if [ -n "${NEXUS_DIR:-}" ]; then
      update_sync_stamp "$NEXUS_DIR"
    fi
    if [ "$_swv_quiet" -eq 0 ]; then
      if [ -n "$_swv_cur" ]; then
        log_ok "Updated workspace configuration version from v$_swv_cur to v$_swv_norm_cli"
      else
        log_ok "Set workspace configuration version to v$_swv_norm_cli"
      fi
    fi
    return 0
  fi
  return 1
}
