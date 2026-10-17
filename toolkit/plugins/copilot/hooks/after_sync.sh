#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
NEXUS_DIR="${NEXUS_DIR:-$_root}"
WORKSPACE_YAML="${WORKSPACE_YAML:-$_root/rnex.yaml}"
WORKSPACE_LOCAL_YAML="${WORKSPACE_LOCAL_YAML:-$_root/.local.rnex.yaml}"
export RNEX_ROOT NEXUS_DIR WORKSPACE_YAML WORKSPACE_LOCAL_YAML

# Explicitly locate and source core helper library if functions not preloaded
if ! command -v merge_rnex_instructions >/dev/null 2>&1 || ! command -v provider_option_enabled >/dev/null 2>&1; then
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
    [ -f "$RNEX_LIB_DIR/core.sh" ] && . "$RNEX_LIB_DIR/core.sh" 2>/dev/null || true
    [ -f "$RNEX_LIB_DIR/workspace.sh" ] && . "$RNEX_LIB_DIR/workspace.sh" 2>/dev/null || true
    [ -f "$RNEX_LIB_DIR/yaml.sh" ] && . "$RNEX_LIB_DIR/yaml.sh" 2>/dev/null || true
    [ -f "$RNEX_LIB_DIR/ai.sh" ] && . "$RNEX_LIB_DIR/ai.sh" 2>/dev/null || true
  fi
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

# Complete guarded fallback contract for standalone or restricted hook runners
if ! command -v provider_option_enabled >/dev/null 2>&1; then
  provider_option_enabled() {
    _p="$1"; _opt="$2"
    _val=""
    if [ -f "$_root/.local.rnex.yaml" ]; then
      _val="$(awk -v p="$_p" -v o="$_opt" '
        /^plugins:/ { in_p=1; next }
        in_p && /^[^ #]/ { in_p=0; in_target=0 }
        in_p && match($0, "^[ ]*" p ":[ ]*(#.*)?$") { in_target=1; next }
        in_target && (/^[ ]{1,2}[^ #]/ || /^[^ #]/) { in_target=0 }
        in_target && $0 ~ ("^[ ]*" o ":") {
          sub("^[ ]*" o ":[ ]*", "")
          sub(/[ ]*#.*/, "")
          gsub(/["\047]/, "")
          print
          exit
        }
      ' "$_root/.local.rnex.yaml")"
    fi
    if [ -z "$_val" ] && [ -f "$_root/rnex.yaml" ]; then
      _val="$(awk -v p="$_p" -v o="$_opt" '
        /^plugins:/ { in_p=1; next }
        in_p && /^[^ #]/ { in_p=0; in_target=0 }
        in_p && match($0, "^[ ]*" p ":[ ]*(#.*)?$") { in_target=1; next }
        in_target && (/^[ ]{1,2}[^ #]/ || /^[^ #]/) { in_target=0 }
        in_target && $0 ~ ("^[ ]*" o ":") {
          sub("^[ ]*" o ":[ ]*", "")
          sub(/[ ]*#.*/, "")
          gsub(/["\047]/, "")
          print
          exit
        }
      ' "$_root/rnex.yaml")"
    fi
    _val="$(printf '%s' "$_val" | tr '[:upper:]' '[:lower:]')"
    case "$_val" in
      false|no|0|disabled|off) return 1 ;;
      *) return 0 ;;
    esac
  }
fi

if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  merge_rnex_instructions() {
    _dst="$1"
    _m_start="<!-- REPO-NEXUS:START -->"
    _m_end="<!-- REPO-NEXUS:END -->"
    _instr="CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace."
    if [ ! -f "$_dst" ]; then
      mkdir -p "$(dirname "$_dst")"
      printf '%s\n%s\n%s\n' "$_m_start" "$_instr" "$_m_end" > "$_dst"
      return 0
    fi
    if grep -qF "$_m_start" "$_dst" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk -v s="$_m_start" -v e="$_m_end" -v msg="$_instr" '
        $0 == s { in_b = 1; print s; print msg; next }
        $0 == e { in_b = 0; print e; next }
        !in_b { print }
      ' "$_dst" > "$_tmp" && mv "$_tmp" "$_dst"
      return 0
    fi
    _tmp="$(mktemp)"
    cp "$_dst" "$_tmp"
    if [ -s "$_tmp" ] && [ -n "$(tail -c 1 "$_tmp" 2>/dev/null)" ]; then
      printf '\n' >> "$_tmp"
    fi
    printf '\n%s\n%s\n%s\n' "$_m_start" "$_instr" "$_m_end" >> "$_tmp"
    mv "$_tmp" "$_dst"
  }
fi

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

_inst="$(provider_option_enabled "copilot" "instructions" 2>/dev/null && echo "true" || echo "false")"
if [ "$_inst" = "true" ]; then
  mkdir -p "$_root/.github"
  if command -v merge_rnex_instructions >/dev/null 2>&1; then
    merge_rnex_instructions "$_root/.github/copilot-instructions.md"
  fi
else
  if command -v clean_rnex_instructions >/dev/null 2>&1; then
    clean_rnex_instructions "$_root/.github/copilot-instructions.md"
  fi
fi

_sk="$(provider_option_enabled "copilot" "skills" 2>/dev/null && echo "true" || echo "false")"
if [ "$_sk" != "true" ]; then
  if command -v clean_provider_user_skills >/dev/null 2>&1; then
    clean_provider_user_skills "$_root/.github/skills"
  fi
fi
