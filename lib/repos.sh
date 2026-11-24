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
  _rn_raw="$(strip_trailing_slashes "$1")"
  # Extract the last component after the last / or : delimiter
  _rn_base="${_rn_raw##*[/:]}"
  # Strip trailing .git suffix if present
  _rn_base="${_rn_base%.git}"
  printf '%s' "$_rn_base"
}

# Resolve the active Git branch name (or short commit SHA if detached) for a cloned repository.
# @param $1 Cloned repository directory path.
# @returns Branch name or short SHA on stdout (empty if unreadable).
# @pure
get_repo_active_branch() {
  _grab_dir="$1"
  [ -d "$_grab_dir/.git" ] || [ -e "$_grab_dir/.git" ] || return 0
  git -C "$_grab_dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$_grab_dir" rev-parse --short HEAD 2>/dev/null || true
}

# Clone a member repository into its destination directory, honoring an optional target branch.
# @param $1 Repository logical name.
# @param $2 Git clone URL or local path.
# @param $3 Destination directory path.
# @param $4 Optional target branch name.
# @returns 0 on successful clone; non-zero on git clone failure.
# @sideEffects Clones git repository into $3 and logs progress.
git_clone_member_repo() {
  _gcm_name="$1"; _gcm_url="$2"; _gcm_dest="$3"; _gcm_branch="${4:-}"
  if [ -n "$_gcm_branch" ]; then
    log_info "Cloning $_gcm_name (branch: $_gcm_branch) from $_gcm_url into $_gcm_dest..."
    git clone -b "$_gcm_branch" "$_gcm_url" "$_gcm_dest"
  else
    log_info "Cloning $_gcm_name from $_gcm_url into $_gcm_dest..."
    git clone "$_gcm_url" "$_gcm_dest"
  fi
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

# Reconcile the repositories root directory (<reposDir>) by detecting and
# pruning unlisted or deleted repository directories so that <reposDir>
# contains strictly the repositories currently declared in configuration.
#
# Responsibility:
#   Audits all subdirectories within the active <reposDir>. Any directory
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
  _pur_rd="$(strip_trailing_slashes "$_pur_rd")"
  [ -d "$_pur_rd" ] || return 0

  # Collect all resolved filesystem paths for currently listed repositories
  _pur_listed_paths="$(yaml_list_repos 2>/dev/null | while read -r _pur_name; do
    [ -n "$_pur_name" ] || continue
    strip_trailing_slashes "$(resolve_repo_path "$_pur_name")"
    printf '\n'
  done)"

  _pur_ws_root="$(strip_trailing_slashes "${NEXUS_DIR:-${RNEX_ROOT:-.}}")"

  # Inspect every non-hidden entry in the repos directory
  for _pur_entry in "$_pur_rd"/*; do
    [ -e "$_pur_entry" ] || [ -L "$_pur_entry" ] || continue
    _pur_base="$(basename "$_pur_entry")"
    case "$_pur_base" in
      .*|"*") continue ;;
    esac

    _pur_clean_entry="$(strip_trailing_slashes "$_pur_entry")"

    # If the entry matches the resolved path of a registered repository, keep it
    if [ -n "$_pur_listed_paths" ] && printf '%s\n' "$_pur_listed_paths" | grep -F -x "$_pur_clean_entry" >/dev/null 2>&1; then
      continue
    fi

    # Security check: guard against accidental deletion of root or workspace dirs
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
