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
  for provider_dir in $RNEX_PROVIDER_SKILL_DIRS; do
    mkdir -p "$RNEX_ROOT/$provider_dir"
    cat << EOF > "$RNEX_ROOT/$provider_dir/rnex-${skill_name}.md"
# User Skill: rnex-${skill_name}

CRITICAL: Do not execute inline heuristics. Read and strictly follow the agentic skill protocol at:
\`${target_path}\`
EOF
  done
}

rnex_unregister_user_skill() {
  skill_name="$1"
  for provider_dir in $RNEX_PROVIDER_SKILL_DIRS; do
    rm -f "$RNEX_ROOT/$provider_dir/rnex-${skill_name}.md"
  done
}
