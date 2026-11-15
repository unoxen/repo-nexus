#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/repos.sh — Physical repository path resolution and member repo .rnex isolation
# ============================================================================

# ---- Physical Repository Path Resolution ----------------------------------

# Extract a clean repository name from a path or Git URL:
# Handles HTTPS URLs, SSH URLs (including scp-like git@host:repo.git syntax),
# relative and absolute local paths, with or without trailing slashes or .git suffix.
# Examples:
#   https://github.com/org/repo.git -> repo
#   git@github.com:org/repo.git     -> repo
#   git@github.com:repo.git         -> repo
#   /path/to/my-repo/               -> my-repo
#   ./relative/repo                 -> repo
repo_name_from_path() {
  _rn_raw="$1"
  # Strip trailing slashes safely in POSIX shell
  while [ "$_rn_raw" != "${_rn_raw%/}" ] && [ -n "${_rn_raw%/}" ]; do
    _rn_raw="${_rn_raw%/}"
  done
  # Extract the last component after the last / or : delimiter
  _rn_base="${_rn_raw##*[/:]}"
  # Strip trailing .git suffix if present
  _rn_base="${_rn_base%.git}"
  printf '%s' "$_rn_base"
}

# Resolve the absolute filesystem path for a member repository.
# If a custom "path:" is declared in configuration, it is resolved relative to NEXUS_DIR
# (or kept absolute if it starts with /). Otherwise, defaults to "$REPOS_DIR/<name>".
resolve_repo_path() {
  get_repo_path "$1"
}

# Ensure the repositories root folder exists on disk (creates directory if missing).
ensure_repos_dir() {
  [ -n "$REPOS_DIR" ] || REPOS_DIR="$(get_repos_root)"
  mkdir -p "$REPOS_DIR"
  [ -f "$REPOS_DIR/.gitkeep" ] || touch "$REPOS_DIR/.gitkeep"
}

# Reconcile the repositories root directory (<repos_dir>) by detecting and
# pruning unlisted or deleted repository directories so that <repos_dir>
# contains strictly the repositories currently declared in configuration.
#
# Responsibility:
#   Audits all subdirectories within the active <repos_dir>. Any directory
#   that does not match the resolved path of a repository registered in
#   rnex.yaml or .local.rnex.yaml is recognized as deleted/unlisted and purged.
#
# Safety Invariants:
#   - Preserves .gitkeep and all dotfiles/hidden directories.
#   - Strictly validates target paths to prevent accidental deletion of
#     workspace root, root directory '/', or empty variable expansions.
#   - Operates idempotently across repeated invocations.
#
# @param $1  Optional path to repositories root directory (defaults to $REPOS_DIR)
# @returns 0 on successful reconciliation
# @sideEffects Removes orphaned directories and outputs informational log messages
prune_unlisted_repos() {
  _pur_rd="${1:-$REPOS_DIR}"
  [ -n "$_pur_rd" ] || _pur_rd="$(get_repos_root)"
  while [ "$_pur_rd" != "${_pur_rd%/}" ] && [ -n "${_pur_rd%/}" ]; do
    _pur_rd="${_pur_rd%/}"
  done
  [ -d "$_pur_rd" ] || return 0

  # Collect all resolved filesystem paths for currently listed repositories
  _pur_listed_paths="$(yaml_list_repos 2>/dev/null | while read -r _pur_name; do
    [ -n "$_pur_name" ] || continue
    _pur_p="$(resolve_repo_path "$_pur_name")"
    while [ "$_pur_p" != "${_pur_p%/}" ] && [ -n "${_pur_p%/}" ]; do
      _pur_p="${_pur_p%/}"
    done
    printf '%s\n' "$_pur_p"
  done)"

  # Inspect every non-hidden entry in the repos directory
  for _pur_entry in "$_pur_rd"/*; do
    [ -e "$_pur_entry" ] || [ -L "$_pur_entry" ] || continue
    _pur_base="$(basename "$_pur_entry")"
    case "$_pur_base" in
      .*|"*") continue ;;
    esac

    # Normalize trailing slashes on entry path for robust comparison
    _pur_clean_entry="$_pur_entry"
    while [ "$_pur_clean_entry" != "${_pur_clean_entry%/}" ] && [ -n "${_pur_clean_entry%/}" ]; do
      _pur_clean_entry="${_pur_clean_entry%/}"
    done

    # If the entry matches the resolved path of a registered repository, keep it
    if [ -n "$_pur_listed_paths" ] && printf '%s\n' "$_pur_listed_paths" | grep -F -x "$_pur_clean_entry" >/dev/null 2>&1; then
      continue
    fi

    # Security check: guard against accidental deletion of root or workspace dirs
    _pur_ws_root="${NEXUS_DIR:-${RNEX_ROOT:-.}}"
    while [ "$_pur_ws_root" != "${_pur_ws_root%/}" ] && [ -n "${_pur_ws_root%/}" ]; do
      _pur_ws_root="${_pur_ws_root%/}"
    done

    if [ -n "$_pur_clean_entry" ] && \
       [ "$_pur_clean_entry" != "/" ] && \
       [ "$_pur_clean_entry" != "$_pur_ws_root" ] && \
       [ "$_pur_clean_entry" != "$_pur_rd" ]; then
      rm -rf "${_pur_clean_entry:?}"
      log_ok "Removed deleted repo directory '$_pur_base' from $(basename "$_pur_rd")"
    fi
  done
  return 0
}

# Check if a member repository is configured as read-only (information-only).
repo_readonly() {
  yaml_repo_readonly "$1"
}
