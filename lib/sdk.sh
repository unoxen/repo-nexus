#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/sdk.sh — Repo Nexus Plugin & Skill SDK (Single Source of Truth)
# ============================================================================
# Provides reusable helpers for plugin hooks and core synchronization:
#   - Delimited instruction block merge & cleanup
#   - Ignore-file (!repos/*) provisioning & cleanup
#   - User skill & agent registration and cleanup
#   - JSON lifecycle hook (Claude settings.json / Agents hooks.json) management
#   - Standalone fallback configuration readers when invoked outside rnex CLI
# ============================================================================

# ---- Standalone Bootstrap (when invoked via env -i outside rnex CLI) -------

if [ -n "${NEXUS_DIR:-}" ]; then
  export RNEX_ROOT="${RNEX_ROOT:-$NEXUS_DIR}"
fi

if ! command -v log_ok >/dev/null 2>&1; then
  export RNEX_ROOT="${RNEX_ROOT:-${NEXUS_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P)}}"
  if [ -z "${RNEX_LIB_DIR:-}" ]; then
    for _sdk_cand in \
      "$RNEX_ROOT/lib" \
      "$(dirname "$0")/../lib" \
      "$(dirname "$0")/../../../lib" \
      "$(dirname "$0")/../../../../lib"; do
      if [ -d "$_sdk_cand" ] && [ -f "$_sdk_cand/core.sh" ]; then
        RNEX_LIB_DIR="$(cd "$_sdk_cand" 2>/dev/null && pwd -P)"
        break
      fi
    done
  fi
  if [ -n "${RNEX_LIB_DIR:-}" ] && [ -f "$RNEX_LIB_DIR/core.sh" ]; then
    # shellcheck source=/dev/null
    . "$RNEX_LIB_DIR/core.sh" 2>/dev/null || true
    # shellcheck source=/dev/null
    [ -f "$RNEX_LIB_DIR/yaml.sh" ] && . "$RNEX_LIB_DIR/yaml.sh" 2>/dev/null || true
  fi
fi

# Export workspace repos directory variables for subshells, plugins, and hooks
if command -v yaml_get_repos_dir >/dev/null 2>&1; then
  RNEX_REPOS_DIR="$(yaml_get_repos_dir 2>/dev/null || printf 'repos')"
else
  RNEX_REPOS_DIR="${REPOS_DIR_REL:-repos}"
fi
[ -n "$RNEX_REPOS_DIR" ] || RNEX_REPOS_DIR="repos"
export RNEX_REPOS_DIR
REPOS_DIR="${REPOS_DIR:-${RNEX_ROOT:-.}/$RNEX_REPOS_DIR}"
export REPOS_DIR

# Minimal logging & boolean fallbacks if lib/core.sh is not present on disk
if ! command -v log_ok >/dev/null 2>&1; then
  log_ok()   { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '[✓] %s\n' "$1"; }
  log_warn() { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '[!] %s\n' "$1"; }
  log_err()  { printf '[✗] %s\n' "$1" >&2; }
  log_info() { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '[i] %s\n' "$1"; }
  log_dim()  { [ "${RNEX_QUIET:-0}" -eq 1 ] || [ "${_sync_quiet:-0}" -eq 1 ] && return 0; printf '    %s\n' "$1"; }
fi

if ! command -v is_enabled_val >/dev/null 2>&1; then
  is_enabled_val() {
    _iev="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$_iev" in
      false|no|0|disabled|off|none) return 1 ;;
      *) return 0 ;;
    esac
  }
fi

if [ -z "${RNEX_PROVIDER_SKILL_DIRS:-}" ]; then
  _sdk_dirs=""
  [ -d "$RNEX_ROOT/.github/skills" ] && _sdk_dirs="${_sdk_dirs:+$_sdk_dirs }.github/skills"
  [ -d "$RNEX_ROOT/.cursor" ] && _sdk_dirs="${_sdk_dirs:+$_sdk_dirs }.cursor/rules"
  [ -d "$RNEX_ROOT/.claude" ] && _sdk_dirs="${_sdk_dirs:+$_sdk_dirs }.claude/skills"
  [ -d "$RNEX_ROOT/.windsurf" ] && _sdk_dirs="${_sdk_dirs:+$_sdk_dirs }.windsurf/rules"
  [ -d "$RNEX_ROOT/.agents" ] && _sdk_dirs="${_sdk_dirs:+$_sdk_dirs }.agents/skills"
  [ -d "$RNEX_ROOT/.codex" ] && _sdk_dirs="${_sdk_dirs:+$_sdk_dirs }.codex/skills"
  export RNEX_PROVIDER_SKILL_DIRS="$_sdk_dirs"
fi

# ---- Standalone Config Fallback Readers (when lib/yaml.sh is not loaded) ---

_sdk_yaml_plugin_query() {
  _syp_file="$1"; _syp_plugin="$2"; _syp_key="$3"
  [ -f "$_syp_file" ] || return 0
  awk -v p="$_syp_plugin" -v o="$_syp_key" '
    /^plugins:/ { in_p=1; next }
    in_p && /^[^ #]/ { in_p=0; in_target=0 }
    in_p && match($0, "^[ ]*" p ":[ ]*(\\{\\})?[ ]*(#.*)?$") {
      if (o == "__exists__") { print "true"; exit }
      in_target=1; next
    }
    in_p && match($0, "^[ ]*-[ ]*" p "[ ]*(#.*)?$") {
      if (o == "__exists__" || o == "enabled") { print "true"; exit }
    }
    in_target && (/^[ ]{1,2}[^ #]/ || /^[^ #]/) { in_target=0 }
    in_target && $0 ~ ("^[ ]*" o ":[ ]*") {
      sub("^[ ]*" o ":[ ]*", "")
      sub(/[ ]*#.*/, "")
      gsub(/["\047]/, "")
      print
      exit
    }
  ' "$_syp_file"
}

if ! command -v provider_option_get >/dev/null 2>&1; then
  provider_option_get() {
    _p="$1"; _opt="$2"
    if command -v yaml_plugin_get >/dev/null 2>&1; then
      yaml_plugin_get "$_p" "$_opt"
      return 0
    fi
    _r="${NEXUS_DIR:-${RNEX_ROOT:-.}}"
    _val="$(_sdk_yaml_plugin_query "$_r/.local.rnex.yaml" "$_p" "$_opt")"
    [ -n "$_val" ] || _val="$(_sdk_yaml_plugin_query "$_r/rnex.yaml" "$_p" "$_opt")"
    printf '%s' "$_val"
  }
fi

if ! command -v provider_plugin_enabled >/dev/null 2>&1; then
  provider_plugin_enabled() {
    _p="$1"
    if command -v yaml_plugin_enabled >/dev/null 2>&1; then
      yaml_plugin_enabled "$_p"
      return $?
    fi
    _r="${NEXUS_DIR:-${RNEX_ROOT:-.}}"
    _ex="$(_sdk_yaml_plugin_query "$_r/.local.rnex.yaml" "$_p" "__exists__")"
    [ -n "$_ex" ] || _ex="$(_sdk_yaml_plugin_query "$_r/rnex.yaml" "$_p" "__exists__")"
    [ -n "$_ex" ] || return 1
    is_enabled_val "$(provider_option_get "$_p" "enabled")"
  }
fi

if ! command -v provider_option_enabled >/dev/null 2>&1; then
  provider_option_enabled() {
    _p="$1"; _opt="$2"
    is_enabled_val "$(provider_option_get "$_p" "$_opt")"
  }
fi

if ! command -v provider_hooks_list >/dev/null 2>&1; then
  provider_hooks_list() {
    _p="$1"
    if command -v yaml_list_plugin_hooks >/dev/null 2>&1; then
      yaml_list_plugin_hooks "$_p"
    fi
  }
fi

if ! command -v provider_hook_commands >/dev/null 2>&1; then
  provider_hook_commands() {
    _p="$1"; _ev="$2"
    if command -v yaml_get_plugin_hook_commands >/dev/null 2>&1; then
      yaml_get_plugin_hook_commands "$_p" "$_ev"
    fi
  }
fi

# ---- Routing Instructions Block Management ---------------------------------

AI_MARKER_START="<!-- REPO-NEXUS:START -->"
AI_MARKER_END="<!-- REPO-NEXUS:END -->"

# Emit the single critical routing directive for initial provider instruction files.
# All detailed execution rules, constraints, and workspace context reside in .rnex/ai-instructions.md.
get_rnex_instructions() {
  printf "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace.\n"
}

# Safely merge delimited Repo Nexus routing instructions (<!-- REPO-NEXUS:START -->)
# into an AI context file (e.g. AGENTS.md, CLAUDE.md), preserving any existing user content.
merge_rnex_instructions() {
  _dst="$1"
  _body_tmp="$(mktemp)"
  get_rnex_instructions > "$_body_tmp"

  if [ ! -f "$_dst" ]; then
    mkdir -p "$(dirname "$_dst")"
    {
      printf '%s\n' "$AI_MARKER_START"
      cat "$_body_tmp"
      printf '%s\n' "$AI_MARKER_END"
    } > "$_dst"
    rm -f "$_body_tmp"
    log_ok "Created $(basename "$_dst") with Repo Nexus routing instructions"
    return 0
  fi

  if grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$_dst" 2>/dev/null && ! grep -qF "$AI_MARKER_START" "$_dst" 2>/dev/null; then
    {
      printf '%s\n' "$AI_MARKER_START"
      cat "$_body_tmp"
      printf '%s\n' "$AI_MARKER_END"
    } > "$_dst"
    rm -f "$_body_tmp"
    return 0
  fi

  # Case 1: If delimiters already exist, update the block in-place
  if grep -qF "$AI_MARKER_START" "$_dst" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" -v src="$_body_tmp" '
      $0 == s {
        in_b = 1
        print s
        while ((getline line < src) > 0) print line
        close(src)
        next
      }
      $0 == e {
        in_b = 0
        print e
        next
      }
      !in_b { print }
    ' "$_dst" > "$_tmp" && mv "$_tmp" "$_dst"
    rm -f "$_body_tmp"
    log_ok "Updated Repo Nexus routing instructions in $(basename "$_dst")"
    return 0
  fi

  # Case 2: If no delimiters, check for legacy un-delimited Repo Nexus block
  if grep -q "Multi-Repo AI Workspace Context" "$_dst" 2>/dev/null || grep -q "Symlink Write-Through" "$_dst" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" -v src="$_body_tmp" '
      BEGIN { in_legacy = 0; replaced = 0 }
      /^# Multi-Repo AI Workspace Context/ {
        in_legacy = 1
        if (!replaced) {
          print s
          while ((getline line < src) > 0) print line
          close(src)
          print e
          replaced = 1
        }
        next
      }
      in_legacy {
        if (/^# [^#]/ && !/^# Multi-Repo/) {
          in_legacy = 0
          print
          next
        }
        next
      }
      !in_legacy { print }
      END {
        if (!replaced) {
          print s
          while ((getline line < src) > 0) print line
          close(src)
          print e
        }
      }
    ' "$_dst" > "$_tmp" && mv "$_tmp" "$_dst"
    rm -f "$_body_tmp"
    log_ok "Upgraded legacy instructions to Repo Nexus routing block in $(basename "$_dst")"
    return 0
  fi

  # Case 3: Completely custom instructions file without rnex context — append delimited block
  _tmp="$(mktemp)"
  cp "$_dst" "$_tmp"
  if [ -s "$_tmp" ] && [ -n "$(tail -c 1 "$_tmp" 2>/dev/null)" ]; then
    printf '\n' >> "$_tmp"
  fi
  {
    printf '\n%s\n' "$AI_MARKER_START"
    cat "$_body_tmp"
    printf '%s\n' "$AI_MARKER_END"
  } >> "$_tmp"
  mv "$_tmp" "$_dst"
  rm -f "$_body_tmp"
  log_ok "Merged Repo Nexus routing instructions with existing $(basename "$_dst")"
}

rnex_block_merge() {
  merge_rnex_instructions "$@"
}

# Strip delimited Repo Nexus routing instructions block from an AI context file,
# removing the file entirely if it was solely created by Repo Nexus (empty outside the block).
clean_rnex_instructions() {
  _dst="$1"
  [ -f "$_dst" ] || return 0

  if grep -qF "$AI_MARKER_START" "$_dst" 2>/dev/null; then
    _non_rnex="$(awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$_dst" | sed -e '/^[[:space:]]*$/d')"
    if [ -z "$_non_rnex" ]; then
      rm -f "$_dst"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed $(basename "$_dst")"
    else
      _tmp="$(mktemp)"
      awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" '
        $0 == s { skip=1; next }
        $0 == e { skip=0; next }
        !skip { print }
      ' "$_dst" > "$_tmp" && mv "$_tmp" "$_dst"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed Repo Nexus routing instructions from $(basename "$_dst")"
    fi
    return 0
  fi

  if grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$_dst" 2>/dev/null; then
    _non_rnex="$(grep -v "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$_dst" 2>/dev/null | grep -v "Multi-Repo AI Workspace Context" | sed -e '/^[[:space:]]*$/d')"
    if [ -z "$_non_rnex" ]; then
      rm -f "$_dst"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed $(basename "$_dst")"
    else
      _tmp="$(mktemp)"
      grep -v "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$_dst" > "$_tmp" && mv "$_tmp" "$_dst"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed Repo Nexus routing instructions from $(basename "$_dst")"
    fi
  fi
}

rnex_block_clean() {
  clean_rnex_instructions "$@"
}

# ---- Ignore File Helpers (!repos/*) ----------------------------------------

IGNORE_MARKER_START="# REPO-NEXUS:START"
IGNORE_MARKER_END="# REPO-NEXUS:END"

# Reconcile scoped ignore rules inside # REPO-NEXUS:START ... # REPO-NEXUS:END markers
ensure_provider_ignore() {
  _epi_file="$1"
  _epi_comment="${2:-Repo Nexus file discovery un-ignore for member repos}"
  _epi_created_msg="${3:-Created $(basename "$_epi_file")}"
  _epi_rd="$(yaml_get_repos_dir 2>/dev/null || printf '%s' "${REPOS_DIR_REL:-repos}")"
  [ -n "$_epi_rd" ] || _epi_rd="repos"
  _epi_entry="${4:-!${_epi_rd}/*}"

  _sec_tmp="$(mktemp)"
  cat > "$_sec_tmp" <<EPI_EOF
${IGNORE_MARKER_START}
# $_epi_comment
$_epi_entry
${IGNORE_MARKER_END}
EPI_EOF

  if [ ! -f "$_epi_file" ]; then
    mkdir -p "$(dirname "$_epi_file")"
    mv "$_sec_tmp" "$_epi_file"
    [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "$_epi_created_msg"
    return 0
  fi

  # 1. If delimited section exists, replace it in-place
  if grep -qFx -- "$IGNORE_MARKER_START" "$_epi_file" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk -v s="$IGNORE_MARKER_START" -v e="$IGNORE_MARKER_END" -v src="$_sec_tmp" '
      $0 == s {
        in_b = 1
        while ((getline line < src) > 0) print line
        close(src)
        next
      }
      $0 == e {
        in_b = 0
        next
      }
      !in_b { print }
    ' "$_epi_file" > "$_tmp" && mv "$_tmp" "$_epi_file"
    rm -f "$_sec_tmp"
    return 0
  fi

  # 2. Upgrade legacy un-delimited ignore file while preserving custom user rules
  _user_tmp="$(mktemp)"
  awk -v erd="$_epi_rd" '
    /^[ ]*#.*(Cursor|Gemini|Repo Nexus|member repos)/ { next }
    $0 == "!repos/*" || $0 == ("!" erd "/*") { next }
    { lines[++n] = $0 }
    END {
      start = 1
      while (start <= n && lines[start] ~ /^[[:space:]]*$/) start++
      end = n
      while (end >= start && lines[end] ~ /^[[:space:]]*$/) end--
      for (i = start; i <= end; i++) print lines[i]
    }
  ' "$_epi_file" > "$_user_tmp"

  _tmp="$(mktemp)"
  if [ -s "$_user_tmp" ]; then
    cat "$_user_tmp" > "$_tmp"
    printf '\n' >> "$_tmp"
  fi
  cat "$_sec_tmp" >> "$_tmp"
  mv "$_tmp" "$_epi_file"
  rm -f "$_user_tmp" "$_sec_tmp"
}

rnex_ignore_ensure() {
  ensure_provider_ignore "$@"
}

# Clean scoped ignore rules, removing the file entirely if it contains no other instructions
clean_provider_ignore() {
  _file="$1"
  [ -f "$_file" ] || return 0
  _cpi_rd="$(yaml_get_repos_dir 2>/dev/null || printf '%s' "${REPOS_DIR_REL:-repos}")"
  [ -n "$_cpi_rd" ] || _cpi_rd="repos"

  if grep -qFx -- "${IGNORE_MARKER_START:-# REPO-NEXUS:START}" "$_file" 2>/dev/null; then
    _non_rnex="$(awk -v s="${IGNORE_MARKER_START:-# REPO-NEXUS:START}" -v e="${IGNORE_MARKER_END:-# REPO-NEXUS:END}" '
      $0 == s { in_b = 1; next }
      $0 == e { in_b = 0; next }
      !in_b { print }
    ' "$_file" | sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d')"

    if [ -z "$_non_rnex" ]; then
      rm -f "$_file"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed $(basename "$_file")"
    else
      _tmp="$(mktemp)"
      awk -v s="${IGNORE_MARKER_START:-# REPO-NEXUS:START}" -v e="${IGNORE_MARKER_END:-# REPO-NEXUS:END}" '
        $0 == s { in_b = 1; next }
        $0 == e { in_b = 0; next }
        !in_b { print }
      ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed Repo Nexus ignore rules from $(basename "$_file")"
    fi
    return 0
  fi

  if grep -q '!repos/\*' "$_file" 2>/dev/null || grep -q "!${_cpi_rd}/\*" "$_file" 2>/dev/null; then
    _non_rnex="$(awk -v erd="$_cpi_rd" '
      /^[ ]*#.*(Cursor|Gemini|Repo Nexus|member repos)/ { next }
      $0 == "!repos/*" || $0 == ("!" erd "/*") { next }
      /^[[:space:]]*$/ { next }
      { print }
    ' "$_file")"

    if [ -z "$_non_rnex" ]; then
      rm -f "$_file"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed $(basename "$_file")"
    else
      _tmp="$(mktemp)"
      awk -v erd="$_cpi_rd" '
        /^[ ]*#.*(Cursor|Gemini|Repo Nexus|member repos)/ { next }
        $0 == "!repos/*" || $0 == ("!" erd "/*") { next }
        { print }
      ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed un-ignore rule from $(basename "$_file")"
    fi
  fi
}

rnex_ignore_clean() {
  clean_provider_ignore "$@"
}

# ---- User Skill & Agent Management -----------------------------------------

# Usage: rnex_generate_user_skill <skill_name> <target_path_in_rnex> [plugin_name]
rnex_generate_user_skill() {
  skill_name="$1"
  target_path="$2"
  plugin_name="${3:-}"

  if [ -n "$plugin_name" ]; then
    full_name="rnex-${plugin_name}-${skill_name}"
  else
    full_name="rnex-${skill_name}"
  fi

  _dirs="${RNEX_PROVIDER_SKILL_DIRS:-$(command -v get_active_provider_skill_dirs >/dev/null 2>&1 && get_active_provider_skill_dirs 2>/dev/null || true)}"
  _r="${NEXUS_DIR:-${RNEX_ROOT:-.}}"

  _target_file=""
  if [ -f "$_r/$target_path" ]; then
    _target_file="$_r/$target_path"
  elif [ -f "$target_path" ]; then
    _target_file="$target_path"
  fi

  _skill_desc=""
  if [ -n "$_target_file" ]; then
    _skill_desc="$(awk 'NF && !/^#/ { print; exit }' "$_target_file" 2>/dev/null)"
  fi
  if [ -z "$_skill_desc" ]; then
    _skill_desc="Repo Nexus agentic skill protocol for ${full_name}."
  fi
  _skill_desc="$(printf '%s' "$_skill_desc" | tr '\n\r' '  ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/"/\\"/g')"

  for provider_dir in $_dirs; do
    case "$provider_dir" in
      *rules*)
        mkdir -p "$_r/$provider_dir"
        rm -rf "${_r:?}/${provider_dir:?}/${full_name:?}" 2>/dev/null || true
        cat << EOF > "$_r/$provider_dir/${full_name}.md"
# User Skill: ${full_name}

CRITICAL: Do not execute inline heuristics. Read and strictly follow the agentic skill protocol at:
\`${target_path}\`
EOF
        ;;
      *)
        mkdir -p "$_r/$provider_dir/${full_name}"
        rm -f "$_r/$provider_dir/${full_name}.md" 2>/dev/null || true
        cat << EOF > "$_r/$provider_dir/${full_name}/SKILL.md"
---
name: ${full_name}
description: "${_skill_desc}"
---

# User Skill: ${full_name}

CRITICAL: Do not execute inline heuristics. Read and strictly follow the agentic skill protocol at:
\`${target_path}\`
EOF
        ;;
    esac
  done
}

# Usage: rnex_register_user_skill <skill_name> <target_path_in_rnex> [plugin_name]
rnex_register_user_skill() {
  rnex_generate_user_skill "$@"
}

# Usage: rnex_unregister_user_skill <skill_name> [plugin_name]
rnex_unregister_user_skill() {
  skill_name="$1"
  plugin_name="${2:-}"
  if [ -n "$plugin_name" ]; then
    full_name="rnex-${plugin_name}-${skill_name}"
  else
    case "$skill_name" in
      rnex-*) full_name="$skill_name" ;;
      *)      full_name="rnex-${skill_name}" ;;
    esac
  fi

  _dirs="${RNEX_PROVIDER_SKILL_DIRS:-$(command -v get_active_provider_skill_dirs >/dev/null 2>&1 && get_active_provider_skill_dirs 2>/dev/null || true)}"
  _r="${NEXUS_DIR:-${RNEX_ROOT:-.}}"
  for provider_dir in $_dirs; do
    rm -f "$_r/$provider_dir/${full_name}.md"
    rm -rf "${_r:?}/${provider_dir:?}/${full_name:?}"
    if [ -n "$plugin_name" ]; then
      rm -f "$_r/$provider_dir/rnex-${skill_name}.md"
      rm -rf "${_r:?}/${provider_dir:?}/rnex-${skill_name:?}"
    fi
  done
}

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

clean_plugin_user_skills() {
  _pdir="$1"
  [ -d "$_pdir" ] || return 0
  _pname="$(basename "$_pdir")"
  if [ -d "$_pdir/skills" ]; then
    for _sk_file in "$_pdir/skills"/*.md; do
      [ -f "$_sk_file" ] || continue
      _sk_name="$(basename "$_sk_file" .md)"
      rnex_unregister_user_skill "$_sk_name" "$_pname"
      rnex_unregister_user_skill "$_sk_name"
    done
  fi
}

clean_provider_agents() {
  _ag_dir="$1"
  _ext="${2:-.md}"
  _r="${NEXUS_DIR:-${RNEX_ROOT:-.}}"
  [ -d "$_ag_dir" ] || return 0

  for _pdir in "${SCRIPT_LOCATION:-$_r}/plugins"/* "$_r/plugins"/* "${SCRIPT_LOCATION:-$_r}/toolkit/plugins"/* "$_r/toolkit/plugins"/* "$_r/.rnex/plugins"/*; do
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

# ---- AI Provider Hooks Management (Two-Tier .rnex/ Working Files + rnex-* Pointers) ----

_sdk_inject_ignore_hooks() {
  printf '%s\n' "$1" | sed -e 's|^\([ \t]*\)\./rnex\([ \t]\)|\1./rnex --ignore-hooks\2|g' \
                           -e 's|^\([ \t]*\)rnex\([ \t]\)|\1rnex --ignore-hooks\2|g' \
                           -e 's|\([;&|][ \t]*\)\./rnex\([ \t]\)|\1./rnex --ignore-hooks\2|g' \
                           -e 's|\([;&|][ \t]*\)rnex\([ \t]\)|\1rnex --ignore-hooks\2|g'
}

_clean_claude_rnex_hooks() {
  _settings="$1"
  [ -f "$_settings" ] || return 0
  if grep -qE '(auto-sync\.sh|rnex-hook-)' "$_settings" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk '
      /\{[ \t]*"command"[ \t]*:[ \t]*"[^"]*(auto-sync\.sh|rnex-hook-)[^"]*"[ \t]*\}/ { next }
      /"command"[ \t]*:[ \t]*"[^"]*(auto-sync\.sh|rnex-hook-)[^"]*"/ { next }
      { print }
    ' "$_settings" > "$_tmp"
    # Remove any empty event arrays like "SessionStart": [ ]
    _tmp2="$(mktemp)"
    awk '
      { lines[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          if (lines[i] ~ /"[a-zA-Z0-9_.-]+"[ \t]*:[ \t]*\[[ \t]*\][ \t]*,?[ \t]*$/) continue
          if (lines[i] ~ /"[a-zA-Z0-9_.-]+"[ \t]*:[ \t]*\[[ \t]*$/) {
            j = i + 1
            while (j <= NR && lines[j] ~ /^[ \t]*$/) j++
            if (j <= NR && lines[j] ~ /^[ \t]*\][ \t]*,?[ \t]*$/) {
              i = j
              continue
            }
          }
          out[++m] = lines[i]
        }
        for (i = 1; i <= m; i++) print out[i]
      }
    ' "$_tmp" > "$_tmp2"
    rm -f "$_tmp"
    _clean="$(sed -e 's/"hooks"//g' < "$_tmp2" | tr -d ' \t\r\n[]{}:,"')"
    if [ -z "$_clean" ]; then
      rm -f "$_tmp2" "$_settings"
    else
      awk '
        { lines[NR] = $0 }
        END {
          for (i = 1; i <= NR; i++) {
            if (i < NR && lines[i] ~ /,[ \t]*$/) {
              next_is_bracket = 0
              for (j = i + 1; j <= NR; j++) {
                if (lines[j] ~ /^[ \t]*$/) continue
                if (lines[j] ~ /^[ \t]*[\]\}]/) next_is_bracket = 1
                break
              }
              if (next_is_bracket) {
                sub(/,[ \t]*$/, "", lines[i])
              }
            }
            print lines[i]
          }
        }
      ' "$_tmp2" > "$_settings"
      rm -f "$_tmp2"
    fi
  fi
}

_sync_claude_rnex_hook_event() {
  _settings="$1"
  _ev="$2"
  _cmd_path="$3"
  mkdir -p "$(dirname "$_settings")"
  if [ ! -f "$_settings" ]; then
    cat > "$_settings" <<EOF
{
  "hooks": {
    "$_ev": [
      { "command": "$_cmd_path" }
    ]
  }
}
EOF
  elif ! grep -qF "$_cmd_path" "$_settings" 2>/dev/null; then
    if grep -q "\"$_ev\"" "$_settings" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk -v ev="\"$_ev\"" -v cmd="$_cmd_path" '
        $0 ~ (ev "[ ]*:[ ]*\\[") {
          print
          print "      { \"command\": \"" cmd "\" },"
          next
        }
        { print }
      ' "$_settings" > "$_tmp" && mv "$_tmp" "$_settings"
    elif grep -q '"hooks"' "$_settings" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk -v ev="$_ev" -v cmd="$_cmd_path" '
        /"hooks"[ ]*:[ ]*\{/ {
          print
          print "    \"" ev "\": [ { \"command\": \"" cmd "\" } ],"
          next
        }
        { print }
      ' "$_settings" > "$_tmp" && mv "$_tmp" "$_settings"
    fi
  fi
}

_clean_agents_rnex_hooks() {
  _hooks="$1"
  [ -f "$_hooks" ] || return 0
  if grep -qE '"(rnex-auto-sync|rnex-hooks)"' "$_hooks" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk '
      BEGIN { skip=0; depth=0 }
      /"(rnex-auto-sync|rnex-hooks)"[ \t]*:[ \t]*\{/ { skip=1; depth=1; next }
      skip {
        for (i=1; i<=length($0); i++) {
          c = substr($0, i, 1)
          if (c == "{") depth++
          if (c == "}") {
            depth--
            if (depth == 0) {
              skip = 0
              next
            }
          }
        }
        next
      }
      { print }
    ' "$_hooks" > "$_tmp"
    _clean="$(tr -d " \t\r\n{}" < "$_tmp")"
    if [ -z "$_clean" ]; then
      rm -f "$_tmp" "$_hooks"
    else
      awk '
        { lines[NR] = $0 }
        END {
          for (i = 1; i <= NR; i++) {
            if (i < NR && lines[i] ~ /,[ \t]*$/) {
              next_is_brace = 0
              for (j = i + 1; j <= NR; j++) {
                if (lines[j] ~ /^[ \t]*$/) continue
                if (lines[j] ~ /^[ \t]*\}/) next_is_brace = 1
                break
              }
              if (next_is_brace) {
                sub(/,[ \t]*$/, "", lines[i])
              }
            }
            print lines[i]
          }
        }
      ' "$_tmp" > "$_hooks"
      rm -f "$_tmp"
    fi
  fi
}

# Synchronize configurable AI provider hooks following RNEX principles:
# 1. Generates deterministic working hook script at .rnex/plugins/<provider>/hooks/rnex-hook-<event>.sh
# 2. Generates deterministic rnex-* pointer script at <provider_dir>/hooks/rnex-hook-<event>.sh referencing the .rnex/ working script
# 3. Generates deterministic <provider_dir>/hooks/rnex-hooks.json manifest (and updates native .claude/settings.json or .agents/hooks.json if specified)
sync_provider_hooks() {
  _sph_provider="$1"
  _sph_pdir="$2"
  _sph_native_json="${3:-}"
  _sph_ws="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

  _sph_rel_pdir="${_sph_pdir#"$_sph_ws"/}"
  _sph_rel_pdir="${_sph_rel_pdir#./}"
  _sph_rel_pdir="${_sph_rel_pdir%/}"
  _sph_abs_pdir="$_sph_ws/$_sph_rel_pdir"

  _sph_work_dir="$_sph_ws/.rnex/plugins/$_sph_provider/hooks"
  _sph_ptr_dir="$_sph_abs_pdir/hooks"

  # Remove stale generated rnex-hook-* scripts before regenerating active ones
  rm -f "$_sph_work_dir"/rnex-hook-*.sh 2>/dev/null || true
  rm -f "$_sph_ptr_dir"/rnex-hook-*.sh "$_sph_ptr_dir/rnex-hooks.json" 2>/dev/null || true
  if [ -n "$_sph_native_json" ]; then
    case "$_sph_provider" in
      claude) _clean_claude_rnex_hooks "$_sph_native_json" ;;
      gemini) _clean_agents_rnex_hooks "$_sph_native_json" ;;
    esac
  fi

  provider_plugin_enabled "$_sph_provider" 2>/dev/null || {
    rmdir "$_sph_ptr_dir" 2>/dev/null || true
    rmdir "$_sph_abs_pdir" 2>/dev/null || true
    return 0
  }

  _sph_events="$(provider_hooks_list "$_sph_provider" 2>/dev/null || true)"
  _sph_active_events=""

  for _sph_ev in $_sph_events; do
    [ -n "$_sph_ev" ] || continue
    _sph_cmds="$(provider_hook_commands "$_sph_provider" "$_sph_ev" 2>/dev/null || true)"
    [ -n "$_sph_cmds" ] || continue

    _sph_ev_slug="$(printf '%s' "$_sph_ev" | sed -e 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' -e 's/[_ ]/-/g' | tr '[:upper:]' '[:lower:]')"
    mkdir -p "$_sph_work_dir" "$_sph_ptr_dir"
    _sph_work_file="$_sph_work_dir/rnex-hook-${_sph_ev_slug}.sh"
    _sph_ptr_file="$_sph_ptr_dir/rnex-hook-${_sph_ev_slug}.sh"

    # 1. Write deterministic working hook script inside .rnex/plugins/<provider>/hooks/
    {
      printf '#!/bin/sh\n'
      printf '# Managed by Repo Nexus (rnex) — Working hook script for %s (%s)\n' "$_sph_provider" "$_sph_ev"
      cat <<'WORK_HDR_EOF'
set -e
RNEX_IGNORE_HOOKS=1
export RNEX_IGNORE_HOOKS
_ws="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd -P)"
[ -n "$_ws" ] && cd "$_ws" 2>/dev/null || true
rnex() {
  if [ -x "$_ws/rnex" ]; then
    "$_ws/rnex" --ignore-hooks "$@"
  elif command -v rnex >/dev/null 2>&1; then
    command rnex --ignore-hooks "$@"
  fi
}
WORK_HDR_EOF
      _old_ifs="$IFS"
      IFS='
'
      for _sph_c in $_sph_cmds; do
        IFS="$_old_ifs"
        [ -n "$_sph_c" ] || continue
        _sdk_inject_ignore_hooks "$_sph_c"
      done
      IFS="$_old_ifs"
    } > "$_sph_work_file"
    chmod +x "$_sph_work_file"

    # 2. Write deterministic rnex-* pointer script in provider hooks directory referencing .rnex/ working script
    cat > "$_sph_ptr_file" <<PTR_EOF
#!/bin/sh
# Managed by Repo Nexus (rnex) — Pointer to .rnex/plugins/${_sph_provider}/hooks/rnex-hook-${_sph_ev_slug}.sh
_ws="\$(cd "\$(dirname "\$0")/../.." 2>/dev/null && pwd -P)"
exec sh "\$_ws/.rnex/plugins/${_sph_provider}/hooks/rnex-hook-${_sph_ev_slug}.sh" "\$@"
PTR_EOF
    chmod +x "$_sph_ptr_file"

    _sph_active_events="${_sph_active_events:+$_sph_active_events }$_sph_ev"
  done

  if [ -z "$_sph_active_events" ]; then
    rmdir "$_sph_ptr_dir" 2>/dev/null || true
    rmdir "$_sph_abs_pdir" 2>/dev/null || true
    return 0
  fi

  # 3. Write deterministic rnex-hooks.json manifest in provider hooks directory referencing .rnex/ working files
  _sph_json_manifest="$_sph_ptr_dir/rnex-hooks.json"
  {
    printf '{\n  "hooks": {\n'
    _first_ev=1
    for _sph_ev in $_sph_active_events; do
      _sph_ev_slug="$(printf '%s' "$_sph_ev" | sed -e 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' -e 's/[_ ]/-/g' | tr '[:upper:]' '[:lower:]')"
      if [ "$_first_ev" -eq 0 ]; then
        printf ',\n'
      fi
      _first_ev=0
      printf '    "%s": [\n      {\n        "name": "rnex-hook-%s",\n        "type": "command",\n        "command": "%s/hooks/rnex-hook-%s.sh",\n        "working_file": ".rnex/plugins/%s/hooks/rnex-hook-%s.sh"\n      }\n    ]' \
        "$_sph_ev" "$_sph_ev_slug" "$_sph_rel_pdir" "$_sph_ev_slug" "$_sph_provider" "$_sph_ev_slug"
    done
    printf '\n  }\n}\n'
  } > "$_sph_json_manifest"

  # 4. Sync native provider settings file if applicable (.claude/settings.json or .agents/hooks.json)
  if [ -n "$_sph_native_json" ]; then
    case "$_sph_provider" in
      claude)
        for _sph_ev in $_sph_active_events; do
          _sph_ev_slug="$(printf '%s' "$_sph_ev" | sed -e 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' -e 's/[_ ]/-/g' | tr '[:upper:]' '[:lower:]')"
          _sync_claude_rnex_hook_event "$_sph_native_json" "$_sph_ev" "${_sph_rel_pdir}/hooks/rnex-hook-${_sph_ev_slug}.sh"
        done
        ;;
      gemini)
        _sph_block_tmp="$(mktemp)"
        {
          printf '  "rnex-hooks": {\n'
          _first_ev=1
          for _sph_ev in $_sph_active_events; do
            _sph_ev_slug="$(printf '%s' "$_sph_ev" | sed -e 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' -e 's/[_ ]/-/g' | tr '[:upper:]' '[:lower:]')"
            if [ "$_first_ev" -eq 0 ]; then
              printf ',\n'
            fi
            _first_ev=0
            printf '    "%s": [\n      {\n        "name": "rnex-hook-%s",\n        "type": "command",\n        "command": "%s/hooks/rnex-hook-%s.sh",\n        "working_file": ".rnex/plugins/%s/hooks/rnex-hook-%s.sh"\n      }\n    ]' \
              "$_sph_ev" "$_sph_ev_slug" "$_sph_rel_pdir" "$_sph_ev_slug" "$_sph_provider" "$_sph_ev_slug"
          done
          printf '\n  }'
        } > "$_sph_block_tmp"
        if [ ! -f "$_sph_native_json" ]; then
          mkdir -p "$(dirname "$_sph_native_json")"
          {
            printf '{\n'
            cat "$_sph_block_tmp"
            printf '\n}\n'
          } > "$_sph_native_json"
        else
          _tmp="$(mktemp)"
          awk -v bfile="$_sph_block_tmp" '
            /^[ \t]*\{/ && !done {
              print
              while ((getline line < bfile) > 0) print line ","
              close(bfile)
              done = 1
              next
            }
            { print }
          ' "$_sph_native_json" > "$_tmp" && mv "$_tmp" "$_sph_native_json"
        fi
        rm -f "$_sph_block_tmp"
        ;;
    esac
  fi
}

clean_provider_hooks() {
  _cph_provider="$1"
  _cph_pdir="$2"
  _cph_native_json="${3:-}"
  _cph_ws="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

  _cph_rel_pdir="${_cph_pdir#"$_cph_ws"/}"
  _cph_rel_pdir="${_cph_rel_pdir#./}"
  _cph_rel_pdir="${_cph_rel_pdir%/}"
  _cph_abs_pdir="$_cph_ws/$_cph_rel_pdir"

  rm -f "$_cph_ws/.rnex/plugins/$_cph_provider/hooks"/rnex-hook-*.sh 2>/dev/null || true
  rm -f "$_cph_abs_pdir/hooks"/rnex-hook-*.sh "$_cph_abs_pdir/hooks/rnex-hooks.json" 2>/dev/null || true
  if [ -n "$_cph_native_json" ]; then
    case "$_cph_provider" in
      claude) _clean_claude_rnex_hooks "$_cph_native_json" ;;
      gemini) _clean_agents_rnex_hooks "$_cph_native_json" ;;
    esac
  fi
  rmdir "$_cph_abs_pdir/hooks" 2>/dev/null || true
  rmdir "$_cph_abs_pdir" 2>/dev/null || true
}
