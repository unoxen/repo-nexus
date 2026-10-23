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

export RNEX_ROOT="${RNEX_ROOT:-${NEXUS_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P)}}"

# ---- Standalone Bootstrap (when invoked via env -i outside rnex CLI) -------

if ! command -v log_ok >/dev/null 2>&1; then
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

if ! command -v provider_auto_sync_enabled >/dev/null 2>&1; then
  provider_auto_sync_enabled() {
    _p="$1"
    _val="$(provider_option_get "$_p" "auto_sync_on")"
    [ -n "$_val" ] || _val="$(provider_option_get "$_p" "autoSyncOn")"
    [ -n "$_val" ] || _val="SessionStart"
    is_enabled_val "$_val"
  }
fi

if ! command -v has_active_provider_instructions >/dev/null 2>&1; then
  has_active_provider_instructions() {
    for _hapi_p in copilot claude gemini cursor windsurf codex; do
      provider_plugin_enabled "$_hapi_p" 2>/dev/null && return 0
    done
    return 1
  }
fi

# ---- Routing Instructions Block Management ---------------------------------

AI_MARKER_START="<!-- REPO-NEXUS:START -->"
AI_MARKER_END="<!-- REPO-NEXUS:END -->"

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
    printf '\n%s\n' "$AI_MARKER_END"
  } >> "$_tmp"
  mv "$_tmp" "$_dst"
  rm -f "$_body_tmp"
  log_ok "Merged Repo Nexus routing instructions with existing $(basename "$_dst")"
}

rnex_block_merge() {
  merge_rnex_instructions "$@"
}

# Strip delimited Repo Nexus routing instructions block from an AI context file,
# removing the file entirely if it was solely created by Repo Nexus.
clean_rnex_instructions() {
  _dst="$1"
  [ -f "$_dst" ] || return 0
  if grep -qF "$AI_MARKER_START" "$_dst" 2>/dev/null; then
    _non_rnex="$(awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$_dst" | tr -d " \t\r\n")"
    if [ -z "$_non_rnex" ]; then
      rm -f "$_dst"
      log_ok "Removed $(basename "$_dst")"
    else
      _tmp="$(mktemp)"
      awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" '
        $0 == s { skip=1; next }
        $0 == e { skip=0; next }
        !skip { print }
      ' "$_dst" > "$_tmp" && mv "$_tmp" "$_dst"
      log_ok "Removed Repo Nexus routing instructions from $(basename "$_dst")"
    fi
  fi
}

rnex_block_clean() {
  clean_rnex_instructions "$@"
}

# ---- Ignore File Helpers (!repos/*) ----------------------------------------

ensure_provider_ignore() {
  _epi_file="$1"
  _epi_comment="${2:-Repo Nexus file discovery un-ignore for member repos}"
  _epi_created_msg="${3:-Created $(basename "$_epi_file")}"
  if [ ! -f "$_epi_file" ]; then
    cat > "$_epi_file" <<EPI_EOF
# $_epi_comment
!repos/*
EPI_EOF
    [ "${RNEX_QUIET:-0}" -eq 0 ] && log_ok "$_epi_created_msg"
  elif ! grep -q '!repos/\*' "$_epi_file" 2>/dev/null; then
    printf '\n# %s\n!repos/*\n' "$_epi_comment" >> "$_epi_file"
    [ "${RNEX_QUIET:-0}" -eq 0 ] && log_dim "Added !repos/* to $(basename "$_epi_file")"
  fi
}

rnex_ignore_ensure() {
  ensure_provider_ignore "$@"
}

clean_provider_ignore() {
  _file="$1"
  [ -f "$_file" ] || return 0
  if grep -q '!repos/\*' "$_file" 2>/dev/null; then
    _non_rnex="$(grep -vE '^[ ]*#.*(Cursor|Gemini|Repo Nexus|member repos)' "$_file" 2>/dev/null | grep -v '^!repos/\*' | tr -d " \t\r\n")"
    if [ -z "$_non_rnex" ]; then
      rm -f "$_file"
      log_ok "Removed $(basename "$_file")"
    else
      _tmp="$(mktemp)"
      grep -vE '(^[ ]*#.*(Cursor|Gemini|Repo Nexus|member repos)|!repos/\*)' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
      log_ok "Removed !repos/* un-ignore from $(basename "$_file")"
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

  for _pdir in "${SCRIPT_LOCATION:-$_r}/toolkit/plugins"/* "$_r/toolkit/plugins"/* "$_r/.rnex/plugins"/*; do
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

# ---- JSON SessionStart Hook Management -------------------------------------

sync_claude_auto_sync_hook() {
  _settings="$1"
  mkdir -p "$(dirname "$_settings")"
  if [ ! -f "$_settings" ]; then
    cat > "$_settings" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "command": ".rnex/bin/auto-sync.sh"
      }
    ]
  }
}
EOF
  elif ! grep -q "auto-sync.sh" "$_settings" 2>/dev/null; then
    if grep -q '"SessionStart"' "$_settings" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk '
        /"SessionStart"[ ]*:[ ]*\[/ {
          print
          print "      { \"command\": \".rnex/bin/auto-sync.sh\" },"
          next
        }
        { print }
      ' "$_settings" > "$_tmp" && mv "$_tmp" "$_settings"
    elif grep -q '"hooks"' "$_settings" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk '
        /"hooks"[ ]*:[ ]*\{/ {
          print
          print "    \"SessionStart\": [ { \"command\": \".rnex/bin/auto-sync.sh\" } ],"
          next
        }
        { print }
      ' "$_settings" > "$_tmp" && mv "$_tmp" "$_settings"
    fi
  fi
}

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
    _clean="$(sed -e 's/"hooks"//g' -e 's/"SessionStart"//g' < "$_tmp" | tr -d ' \t\r\n[]{}:,"')"
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

sync_agents_auto_sync_hook() {
  _hooks_file="$1"
  if [ ! -f "$_hooks_file" ]; then
    mkdir -p "$(dirname "$_hooks_file")"
    cat > "$_hooks_file" <<'EOF'
{
  "rnex-auto-sync": {
    "SessionStart": [
      {
        "type": "command",
        "command": ".rnex/bin/auto-sync.sh"
      }
    ]
  }
}
EOF
  elif ! grep -q '"rnex-auto-sync"' "$_hooks_file" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk '
      /^[ \t]*\{/ && !done {
        print
        print "  \"rnex-auto-sync\": {"
        print "    \"SessionStart\": ["
        print "      {"
        print "        \"type\": \"command\","
        print "        \"command\": \".rnex/bin/auto-sync.sh\""
        print "      }"
        print "    ]"
        print "  },"
        done = 1
        next
      }
      { print }
    ' "$_hooks_file" > "$_tmp" && mv "$_tmp" "$_hooks_file"
  fi
}

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
