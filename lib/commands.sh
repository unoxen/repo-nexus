#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/commands.sh — Loader for all CLI command implementations
# ============================================================================

. "$RNEX_LIB_DIR/commands/init.sh"
. "$RNEX_LIB_DIR/commands/repo.sh"
. "$RNEX_LIB_DIR/commands/status.sh"
. "$RNEX_LIB_DIR/commands/sync.sh"
. "$RNEX_LIB_DIR/commands/plugin.sh"
. "$RNEX_LIB_DIR/commands/completion.sh"
. "$RNEX_LIB_DIR/commands/system.sh"
