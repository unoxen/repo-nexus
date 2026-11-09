#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/hooks/after_sync.sh
# Architectural Layer: Plugin Lifecycle Hook (after_sync)
# Single Responsibility: Project plugin user skills into active AI providers.
# Purity: Zero automatic ingestion or wiki compilation (SRP).
# =============================================================================
set -e

[ -z "$RNEX_ROOT" ] && { echo "Error: RNEX_ROOT not set"; exit 1; }

# Register plugin User Skills via contract helper
if ! command -v rnex_generate_user_skill >/dev/null 2>&1; then
  if [ -f "$RNEX_ROOT/.rnex/bin/rnex-env.sh" ]; then
    # shellcheck source=/dev/null
    . "$RNEX_ROOT/.rnex/bin/rnex-env.sh"
  fi
fi

if command -v rnex_generate_user_skill >/dev/null 2>&1; then
  for skill_file in "$RNEX_ROOT/.rnex/plugins/karpathy-llm/skills"/*.md; do
    [ -f "$skill_file" ] || continue
    skill_name=$(basename "$skill_file" .md)
    rnex_generate_user_skill "$skill_name" ".rnex/plugins/karpathy-llm/skills/${skill_name}.md" "karpathy-llm"
  done
fi
