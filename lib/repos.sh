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

# ---- Member Repo .rnex Isolation (Lazy / On-Demand Model) ------------------

# Check if a member repository has an active on-demand .rnex directory.
repo_has_rnex_dir() {
  _repo_path="$(resolve_repo_path "$1")"
  [ -d "$_repo_path/.rnex" ]
}

# Check if a member repository is configured as read-only (information-only).
repo_readonly() {
  yaml_repo_readonly "$1"
}

# Cleanly tear down .rnex in a member repository.
# Removes auto-generated plugins and boilerplate README, pruning empty directories
# while preserving any user-customized files.
clean_repo_rnex() {
  _name="$1"
  _repo_path="$(resolve_repo_path "$_name")"
  [ -d "$_repo_path/.rnex" ] || return 0

  # Clean plugins directory inside member repo
  if [ -d "$_repo_path/.rnex/plugins" ]; then
    rm -rf "$_repo_path/.rnex/plugins"
  fi

  # If README.md is the auto-generated rnex template, remove it
  if [ -f "$_repo_path/.rnex/README.md" ]; then
    if grep -q "Repo Nexus Workspace Integration" "$_repo_path/.rnex/README.md" 2>/dev/null; then
      rm -f "$_repo_path/.rnex/README.md"
    fi
  fi

  # Prune empty subdirectories and remove .rnex if completely empty
  find "$_repo_path/.rnex" -type d -empty -delete 2>/dev/null || true
  if [ -d "$_repo_path/.rnex" ] && [ -z "$(ls -A "$_repo_path/.rnex" 2>/dev/null)" ]; then
    rmdir "$_repo_path/.rnex" 2>/dev/null || true
  fi
}

# Reconcile .rnex in a member repository on-demand:
# Under the lazy/on-demand model, member repositories remain completely clean
# by default. A member repo only receives .rnex/ if a plugin or custom integration
# explicitly requires storing information at the member repository level.
# If .rnex/ already exists, prune orphaned plugins/boilerplate, preserving custom files.
sync_repo_rnex() {
  _name="$1"
  _repo_path="$(resolve_repo_path "$_name")"
  [ -d "$_repo_path" ] || return 0

  _r_rnex="$_repo_path/.rnex"

  # If .rnex does not exist, do not create it (lazy/on-demand model)
  [ -d "$_r_rnex" ] || return 0

  # Prune disabled plugins from member repo
  if [ -d "$_r_rnex/plugins" ]; then
    for _existing in "$_r_rnex/plugins"/*; do
      [ -d "$_existing" ] || continue
      _pname="$(basename "$_existing")"
      if ! yaml_plugin_enabled "$_pname"; then
        rm -rf "$_existing"
      fi
    done
    rmdir "$_r_rnex/plugins" 2>/dev/null || true
  fi

  # Prune legacy boilerplate README.md if present
  if [ -f "$_r_rnex/README.md" ]; then
    if grep -q "Repo Nexus Workspace Integration" "$_r_rnex/README.md" 2>/dev/null; then
      rm -f "$_r_rnex/README.md"
    fi
  fi

  # If .rnex is now empty, prune it cleanly
  find "$_r_rnex" -type d -empty -delete 2>/dev/null || true
  if [ -d "$_r_rnex" ] && [ -z "$(ls -A "$_r_rnex" 2>/dev/null)" ]; then
    rmdir "$_r_rnex" 2>/dev/null || true
  fi
}
