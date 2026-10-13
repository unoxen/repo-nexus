#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/test_cli.sh — Main test runner for Repo Nexus test suites
# ============================================================================
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DIR

# Source shared test helper
. "$DIR/tests/test_helper.sh"

SUITES_DIR="$DIR/tests/suites"

# Resolve suites to run (all suites by default, or specific suites if arguments provided)
if [ $# -gt 0 ]; then
  SUITES=""
  for arg in "$@"; do
    case "$arg" in
      *.sh)
        if [ -f "$arg" ]; then
          _s="$arg"
        elif [ -f "$SUITES_DIR/$arg" ]; then
          _s="$SUITES_DIR/$arg"
        else
          echo "Error: Test suite '$arg' not found." >&2
          exit 1
        fi
        ;;
      *)
        _match="$(find "$SUITES_DIR" -name "${arg}*.sh" | head -n1)"
        if [ -n "$_match" ] && [ -f "$_match" ]; then
          _s="$_match"
        else
          echo "Error: Test suite matching '$arg' not found in $SUITES_DIR." >&2
          exit 1
        fi
        ;;
    esac
    SUITES="$SUITES $_s"
  done
else
  SUITES="$SUITES_DIR/01_core_cli.sh $SUITES_DIR/02_plugins_basic.sh $SUITES_DIR/03_config_workspace.sh $SUITES_DIR/04_git_hooks.sh $SUITES_DIR/05_ai_providers.sh $SUITES_DIR/06_plugins_advanced.sh"
fi

# Execute test suites sequentially
_STANDALONE_RUN=0
for suite in $SUITES; do
  [ -f "$suite" ] || continue
  # shellcheck source=/dev/null
  . "$suite"
done

# Output final test execution summary
report_results
