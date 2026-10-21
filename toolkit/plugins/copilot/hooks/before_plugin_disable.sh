#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
NEXUS_DIR="${NEXUS_DIR:-$_root}"
WORKSPACE_YAML="${WORKSPACE_YAML:-$_root/rnex.yaml}"
WORKSPACE_LOCAL_YAML="${WORKSPACE_LOCAL_YAML:-$_root/.local.rnex.yaml}"
export RNEX_ROOT NEXUS_DIR WORKSPACE_YAML WORKSPACE_LOCAL_YAML

# Explicitly locate and source core helper library if functions not preloaded
if ! command -v clean_rnex_instructions >/dev/null 2>&1 || ! command -v clean_provider_user_skills >/dev/null 2>&1 || ! command -v clean_provider_agents >/dev/null 2>&1; then
  if [ -z "${RNEX_LIB_DIR:-}" ]; then
    for _cand in \
      "$_root/lib" \
      "$(dirname "$0")/../../../../lib" \
      "$(dirname "$0")/../../../lib"; do
      if [ -d "$_cand" ] && [ -f "$_cand/ai.sh" ]; then
        RNEX_LIB_DIR="$(cd "$_cand" 2>/dev/null && pwd -P)"
        break
      fi
    done
  fi
  if [ -n "${RNEX_LIB_DIR:-}" ] && [ -d "$RNEX_LIB_DIR" ]; then
    if [ -f "$RNEX_LIB_DIR/core.sh" ]; then . "$RNEX_LIB_DIR/core.sh" 2>/dev/null || true; fi
    if [ -f "$RNEX_LIB_DIR/workspace.sh" ]; then . "$RNEX_LIB_DIR/workspace.sh" 2>/dev/null || true; fi
    if [ -f "$RNEX_LIB_DIR/yaml.sh" ]; then . "$RNEX_LIB_DIR/yaml.sh" 2>/dev/null || true; fi
    if [ -f "$RNEX_LIB_DIR/ai.sh" ]; then . "$RNEX_LIB_DIR/ai.sh" 2>/dev/null || true; fi
  fi
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

# Complete guarded fallback contract for standalone or restricted hook runners
if ! command -v clean_rnex_instructions >/dev/null 2>&1; then
  clean_rnex_instructions() {
    _dst="$1"
    [ -f "$_dst" ] || return 0
    _m_start="<!-- REPO-NEXUS:START -->"
    _m_end="<!-- REPO-NEXUS:END -->"
    if grep -qF "$_m_start" "$_dst" 2>/dev/null; then
      _non_rnex="$(awk -v s="$_m_start" -v e="$_m_end" '
        $0 == s { skip=1; next }
        $0 == e { skip=0; next }
        !skip { print }
      ' "$_dst" | tr -d " \t\r\n")"
      if [ -z "$_non_rnex" ]; then
        rm -f "$_dst"
      else
        _tmp="$(mktemp)"
        awk -v s="$_m_start" -v e="$_m_end" '
          $0 == s { skip=1; next }
          $0 == e { skip=0; next }
          !skip { print }
        ' "$_dst" > "$_tmp" && mv "$_tmp" "$_dst"
      fi
    fi
  }
fi

if ! command -v clean_provider_user_skills >/dev/null 2>&1; then
  clean_provider_user_skills() {
    _sk_dir="$1"
    [ -d "$_sk_dir" ] || return 0
    rm -f "$_sk_dir"/rnex-*.md 2>/dev/null || true
    for _d in "$_sk_dir"/rnex-*; do
      [ -d "$_d" ] || continue
      rm -rf "$_d" 2>/dev/null || true
    done
    rmdir "$_sk_dir" 2>/dev/null || true
  }
fi

if ! command -v clean_provider_agents >/dev/null 2>&1; then
  clean_provider_agents() {
    _ag_dir="$1"
    _ext="${2:-.md}"
    [ -d "$_ag_dir" ] || return 0
    for _pdir in "$_root/toolkit/plugins"/* "$_root/.rnex/plugins"/*; do
      [ -d "$_pdir" ] || continue
      [ -d "$_pdir/agents" ] || continue
      for _afile in "$_pdir/agents"/*.md; do
        [ -f "$_afile" ] || continue
        _aname="$(basename "$_afile" .agent.md)"
        _aname="$(basename "$_aname" .md)"
        rm -f "$_ag_dir/${_aname}${_ext}" 2>/dev/null || true
      done
    done
    rmdir "$_ag_dir" 2>/dev/null || true
  }
fi

if command -v clean_rnex_instructions >/dev/null 2>&1; then
  clean_rnex_instructions "$_root/.github/copilot-instructions.md"
fi
if command -v clean_provider_user_skills >/dev/null 2>&1; then
  clean_provider_user_skills "$_root/.github/skills"
fi
if command -v clean_provider_agents >/dev/null 2>&1; then
  clean_provider_agents "$_root/.github/agents" ".agent.md"
fi

# Remove only files owned by this plugin in .github/prompts/ and delete directory only if empty
if [ -d "$_root/.github/prompts" ]; then
  rm -f "$_root/.github/prompts"/rnex-*.prompt.md "$_root/.github/prompts"/rnex-*.md 2>/dev/null || true
  for _p in "$_root/.github/prompts"/rnex-*; do
    [ -e "$_p" ] || continue
    rm -rf "$_p" 2>/dev/null || true
  done
  rmdir "$_root/.github/prompts" 2>/dev/null || true
fi
rmdir "$_root/.github" 2>/dev/null || true
