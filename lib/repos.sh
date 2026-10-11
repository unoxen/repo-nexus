#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/repos.sh — Physical repository path resolution and member repo .rnex isolation
# ============================================================================

# ---- Physical Repository Path Resolution ----------------------------------

resolve_repo_path() {
  _name="$1"
  _raw_path="$(yaml_get "$_name" "path")"
  if [ -n "$_raw_path" ]; then
    case "$_raw_path" in
      /*) printf '%s' "$_raw_path" ;;
      *)  printf '%s/%s' "$NEXUS_DIR" "$_raw_path" ;;
    esac
  else
    printf '%s/%s' "$REPOS_DIR" "$_name"
  fi
}

ensure_repos_dir() {
  mkdir -p "$REPOS_DIR"
  [ -f "$REPOS_DIR/.gitkeep" ] || touch "$REPOS_DIR/.gitkeep"
}

# ---- Member Repo .rnex Isolation ------------------------------------------

repo_rnex_dir_enabled() {
  _name="$1"
  _val="$(yaml_get "$_name" "rnex_dir")"
  _val="$(printf '%s' "$_val" | tr '[:upper:]' '[:lower:]')"
  case "$_val" in
    false|no|0|disabled|off) return 1 ;;
    *) return 0 ;;
  esac
}

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

sync_repo_rnex() {
  _name="$1"
  _repo_path="$(resolve_repo_path "$_name")"
  [ -d "$_repo_path" ] || return 0

  if ! repo_rnex_dir_enabled "$_name"; then
    clean_repo_rnex "$_name"
    return 0
  fi

  _r_rnex="$_repo_path/.rnex"
  mkdir -p "$_r_rnex"

  # Create default .rnex/README.md if not present
  if [ ! -f "$_r_rnex/README.md" ]; then
    cat <<EOF > "$_r_rnex/README.md"
# .rnex — Repo Nexus Workspace Integration

This directory is managed by [Repo Nexus](https://github.com/unoxen/repo-nexus).
It stores documents, scripts, instructions, and workflows related to Repo Nexus for this member repository.

AI tools operating at the Repo Nexus workspace level inspect this directory (\`repos/$_name/.rnex/\`) for repository-specific context and instructions.
EOF
    log_ok "Initialized .rnex in $(basename "$_repo_path")"
  fi

  # Sync scoped active plugins into member repo under .rnex/plugins/<plugin-name>/
  yaml_list_plugins | while read -r _pname; do
    [ -n "$_pname" ] || continue
    _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
    [ -n "$_pdir" ] || continue

    _dest_pdir="$_r_rnex/plugins/$_pname"
    mkdir -p "$_dest_pdir"

    # Deterministically sync plugin asset directories into member repo
    for _sub in rules workflows instructions prompts skills agents templates; do
      if [ -d "$_pdir/$_sub" ]; then
        rm -rf "$_dest_pdir/$_sub"
        mkdir -p "$_dest_pdir/$_sub"
        cp -R "$_pdir/$_sub"/. "$_dest_pdir/$_sub"/ 2>/dev/null || true
      else
        rm -rf "$_dest_pdir/$_sub"
      fi
    done
    if [ -f "$_pdir/plugin.yaml" ]; then
      cp "$_pdir/plugin.yaml" "$_dest_pdir/plugin.yaml"
    fi
    if [ -f "$_pdir/README.md" ]; then
      cp "$_pdir/README.md" "$_dest_pdir/README.md"
    fi
  done
}
