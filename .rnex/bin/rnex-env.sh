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

rnex_register_user_skill() {
  skill_name="$1"
  target_path="$2"
  _dirs="${RNEX_PROVIDER_SKILL_DIRS:-}"
  _r="${RNEX_ROOT:-.}"

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
    _skill_desc="Repo Nexus agentic skill protocol for ${skill_name}."
  fi
  _skill_desc="$(printf '%s' "$_skill_desc" | tr '\n\r' '  ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/"/\\"/g')"

  for provider_dir in $_dirs; do
    case "$provider_dir" in
      *rules*)
        mkdir -p "$_r/$provider_dir"
        rm -rf "$_r/$provider_dir/rnex-${skill_name}" 2>/dev/null || true
        cat << EOF > "$_r/$provider_dir/rnex-${skill_name}.md"
# User Skill: rnex-${skill_name}

CRITICAL: Do not execute inline heuristics. Read and strictly follow the agentic skill protocol at:
\`${target_path}\`
EOF
        ;;
      *)
        mkdir -p "$_r/$provider_dir/rnex-${skill_name}"
        rm -f "$_r/$provider_dir/rnex-${skill_name}.md" 2>/dev/null || true
        cat << EOF > "$_r/$provider_dir/rnex-${skill_name}/SKILL.md"
---
name: rnex-${skill_name}
description: "${_skill_desc}"
---

# User Skill: rnex-${skill_name}

CRITICAL: Do not execute inline heuristics. Read and strictly follow the agentic skill protocol at:
\`${target_path}\`
EOF
        ;;
    esac
  done
}

rnex_unregister_user_skill() {
  skill_name="$1"
  _dirs="${RNEX_PROVIDER_SKILL_DIRS:-}"
  _r="${RNEX_ROOT:-.}"
  for provider_dir in $_dirs; do
    rm -f "$_r/$provider_dir/rnex-${skill_name}.md"
    rm -rf "$_r/$provider_dir/rnex-${skill_name}"
  done
}
