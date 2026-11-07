#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/hooks/post-sync.sh
# Architectural Layer: Lifecycle Hook (after_sync / post-sync)
# Single Responsibility: Run wiki lint and synchronization during rnex sync.
# =============================================================================
set -e

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"

"${PLUGIN_ROOT}/bin/lint.sh" >/dev/null 2>&1 || true
