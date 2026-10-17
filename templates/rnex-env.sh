#!/bin/sh
# Repo Nexus Plugin & Skill Contract Environment
export RNEX_ROOT="${RNEX_ROOT:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P)}"

if [ -z "$RNEX_PROVIDER_SKILL_DIRS" ]; then
  _dirs=""
  [ -d "$RNEX_ROOT/.github/skills" ] && _dirs="${_dirs:+$_dirs }.github/skills"
  [ -d "$RNEX_ROOT/.cursor" ] && _dirs="${_dirs:+$_dirs }.cursor/rules"
  [ -d "$RNEX_ROOT/.claude" ] && _dirs="${_dirs:+$_dirs }.claude/skills"
  [ -d "$RNEX_ROOT/.windsurf" ] && _dirs="${_dirs:+$_dirs }.windsurf/rules"
  [ -d "$RNEX_ROOT/.gemini" ] && _dirs="${_dirs:+$_dirs }.gemini/skills"
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
