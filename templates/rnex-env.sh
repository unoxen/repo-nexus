#!/bin/sh
# Repo Nexus Plugin & Skill Contract Environment
export RNEX_ROOT="${RNEX_ROOT:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P)}"

if [ -z "$RNEX_PROVIDER_SKILL_DIRS" ]; then
  _dirs=""
  [ -d "$RNEX_ROOT/.github/skills" ] && _dirs="${_dirs:+$_dirs }.github/skills"
  [ -d "$RNEX_ROOT/.cursor" ] && _dirs="${_dirs:+$_dirs }.cursor/rules"
  [ -d "$RNEX_ROOT/.claude" ] && _dirs="${_dirs:+$_dirs }.claude/skills"
  [ -d "$RNEX_ROOT/.windsurf" ] && _dirs="${_dirs:+$_dirs }.windsurf/rules"
  [ -d "$RNEX_ROOT/.agents" ] && _dirs="${_dirs:+$_dirs }.agents/skills"
  export RNEX_PROVIDER_SKILL_DIRS="$_dirs"
fi

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

  _dirs="${RNEX_PROVIDER_SKILL_DIRS:-$(get_active_provider_skill_dirs 2>/dev/null || true)}"
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

  _dirs="${RNEX_PROVIDER_SKILL_DIRS:-$(get_active_provider_skill_dirs 2>/dev/null || true)}"
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

# Provider configuration check helper
if ! command -v provider_plugin_enabled >/dev/null 2>&1; then
  provider_plugin_enabled() {
    _p="$1"
    _r="${NEXUS_DIR:-${RNEX_ROOT:-.}}"
    _val=""
    if [ -f "$_r/.local.rnex.yaml" ]; then
      _val="$(awk -v p="$_p" '
        /^plugins:/ { in_p=1; next }
        in_p && /^[^ #]/ { in_p=0; in_target=0 }
        in_p && match($0, "^[ ]*" p ":[ ]*(#.*)?$") { in_target=1; next }
        in_p && match($0, "^[ ]*-[ ]*" p "[ ]*(#.*)?$") { print "true"; exit }
        in_target && (/^[ ]{1,2}[^ #]/ || /^[^ #]/) { in_target=0 }
        in_target && $0 ~ "^[ ]*enabled:[ ]*" {
          sub("^[ ]*enabled:[ ]*", "")
          sub(/[ ]*#.*/, "")
          gsub(/["\047]/, "")
          print
          exit
        }
      ' "$_r/.local.rnex.yaml")"
    fi
    if [ -z "$_val" ] && [ -f "$_r/rnex.yaml" ]; then
      _val="$(awk -v p="$_p" '
        /^plugins:/ { in_p=1; next }
        in_p && /^[^ #]/ { in_p=0; in_target=0 }
        in_p && match($0, "^[ ]*" p ":[ ]*(#.*)?$") { in_target=1; next }
        in_p && match($0, "^[ ]*-[ ]*" p "[ ]*(#.*)?$") { print "true"; exit }
        in_target && (/^[ ]{1,2}[^ #]/ || /^[^ #]/) { in_target=0 }
        in_target && $0 ~ "^[ ]*enabled:[ ]*" {
          sub("^[ ]*enabled:[ ]*", "")
          sub(/[ ]*#.*/, "")
          gsub(/["\047]/, "")
          print
          exit
        }
      ' "$_r/rnex.yaml")"
    fi
    [ -n "$_val" ] || return 1
    _val="$(printf '%s' "$_val" | tr '[:upper:]' '[:lower:]')"
    case "$_val" in
      false|no|0|disabled|off) return 1 ;;
      *) return 0 ;;
    esac
  }
fi

if ! command -v provider_option_get >/dev/null 2>&1; then
  provider_option_get() {
    _p="$1"; _opt="$2"
    _r="${NEXUS_DIR:-${RNEX_ROOT:-.}}"
    _val=""
    if [ -f "$_r/.local.rnex.yaml" ]; then
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
      ' "$_r/.local.rnex.yaml")"
    fi
    if [ -z "$_val" ] && [ -f "$_r/rnex.yaml" ]; then
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
      ' "$_r/rnex.yaml")"
    fi
    printf '%s' "$_val"
  }
fi

if ! command -v provider_option_enabled >/dev/null 2>&1; then
  provider_option_enabled() {
    _p="$1"; _opt="$2"
    _val="$(provider_option_get "$_p" "$_opt")"
    _val="$(printf '%s' "$_val" | tr '[:upper:]' '[:lower:]')"
    case "$_val" in
      false|no|0|disabled|off) return 1 ;;
      *) return 0 ;;
    esac
  }
fi

if ! command -v provider_auto_sync_enabled >/dev/null 2>&1; then
  provider_auto_sync_enabled() {
    _p="$1"
    _val="$(provider_option_get "$_p" "auto_sync_on")"
    [ -z "$_val" ] && _val="$(provider_option_get "$_p" "autoSyncOn")"
    [ -z "$_val" ] && _val="SessionStart"
    _val="$(printf '%s' "$_val" | tr '[:upper:]' '[:lower:]')"
    case "$_val" in
      false|no|0|disabled|off|none) return 1 ;;
      *) return 0 ;;
    esac
  }
fi

if ! command -v has_active_provider_instructions >/dev/null 2>&1; then
  has_active_provider_instructions() {
    provider_plugin_enabled "copilot" 2>/dev/null && return 0
    provider_plugin_enabled "claude" 2>/dev/null && return 0
    provider_plugin_enabled "gemini" 2>/dev/null && return 0
    provider_plugin_enabled "cursor" 2>/dev/null && return 0
    provider_plugin_enabled "windsurf" 2>/dev/null && return 0
    return 1
  }
fi

if ! command -v clean_claude_auto_sync_hook >/dev/null 2>&1; then
  clean_claude_auto_sync_hook() {
    _settings="$1"
    [ -f "$_settings" ] || return 0
    if grep -q "auto-sync.sh" "$_settings" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk '
        /\{[ \t]*"command"[ \t]*:[ \t]*"\.rnex\/bin\/auto-sync\.sh"[ \t]*\}/ { next }
        /"command"[ \t]*:[ \t]*"\.rnex\/bin\/auto-sync\.sh"/ { next }
        { print }
      ' "$_settings" > "$_tmp"
      _clean="$(tr -d " \t\r\n[]{}:,\"hooksSessionStart" < "$_tmp")"
      if [ -z "$_clean" ]; then
        rm -f "$_tmp" "$_settings"
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
        ' "$_tmp" > "$_settings"
        rm -f "$_tmp"
      fi
    fi
  }
fi

if ! command -v clean_agents_auto_sync_hook >/dev/null 2>&1; then
  clean_agents_auto_sync_hook() {
    _hooks="$1"
    [ -f "$_hooks" ] || return 0
    if grep -q '"rnex-auto-sync"' "$_hooks" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk '
        BEGIN { skip=0; depth=0 }
        /"rnex-auto-sync"[ \t]*:[ \t]*\{/ { skip=1; depth=1; next }
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
fi

# Instructions routing helpers
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

if ! command -v clean_provider_agents >/dev/null 2>&1; then
  clean_provider_agents() {
    _ag_dir="$1"
    _ext="${2:-.md}"
    _r="${NEXUS_DIR:-${RNEX_ROOT:-.}}"
    [ -d "$_ag_dir" ] || return 0
    for _pdir in "$_r/toolkit/plugins"/* "$_r/.rnex/plugins"/*; do
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
