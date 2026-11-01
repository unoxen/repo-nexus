#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/test_cli.sh — Main test runner for Repo Nexus test suites
# ============================================================================
# Architectural Layer: Quality Assurance / Test Automation Framework
# Design Pattern: Test Runner & Aggregator (Template Method)
# Responsibilities:
#   - Discovers and executes core and per-plugin test suites sequentially.
#   - Supports selective execution (e.g., 'core', 'plugins', '01', 'claude').
#   - Aggregates PASS/FAIL metrics across all executed suites.
# ============================================================================
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
export DIR

# Source shared test helper
# shellcheck source=tests/test_helper.sh
. "$DIR/tests/test_helper.sh"

SUITES_DIR="$DIR/tests/suites"
PLUGINS_DIR="$DIR/plugins"
[ -d "$PLUGINS_DIR" ] || PLUGINS_DIR="$DIR/toolkit/plugins"

CORE_SUITES="$SUITES_DIR/01_core_cli.sh $SUITES_DIR/02_plugins_basic.sh $SUITES_DIR/03_config_workspace.sh $SUITES_DIR/04_git_hooks.sh"

PLUGIN_SUITES=""
for _p_test in "$PLUGINS_DIR"/*/tests/test_plugin.sh; do
  [ -f "$_p_test" ] || continue
  PLUGIN_SUITES="${PLUGIN_SUITES:+$PLUGIN_SUITES }$_p_test"
done

# Resolve suites to run (all suites by default, or specific suites if arguments provided)
if [ $# -gt 0 ]; then
  SUITES=""
  for arg in "$@"; do
    case "$arg" in
      core)
        SUITES="${SUITES:+$SUITES }$CORE_SUITES"
        ;;
      plugins|plugin)
        SUITES="${SUITES:+$SUITES }$PLUGIN_SUITES"
        ;;
      *.sh)
        if [ -f "$arg" ]; then
          SUITES="${SUITES:+$SUITES }$arg"
        elif [ -f "$SUITES_DIR/$arg" ]; then
          SUITES="${SUITES:+$SUITES }$SUITES_DIR/$arg"
        elif [ -f "$PLUGINS_DIR/$arg" ]; then
          SUITES="${SUITES:+$SUITES }$PLUGINS_DIR/$arg"
        else
          echo "Error: Test suite '$arg' not found." >&2
          exit 1
        fi
        ;;
      *)
        # Check core suites by prefix match
        _match="$(find "$SUITES_DIR" -name "${arg}*.sh" 2>/dev/null | head -n1)"
        if [ -n "$_match" ] && [ -f "$_match" ]; then
          SUITES="${SUITES:+$SUITES }$_match"
        # Check plugin suite by plugin name
        elif [ -f "$PLUGINS_DIR/$arg/tests/test_plugin.sh" ]; then
          SUITES="${SUITES:+$SUITES }$PLUGINS_DIR/$arg/tests/test_plugin.sh"
        else
          echo "Error: Test suite matching '$arg' not found in $SUITES_DIR or $PLUGINS_DIR." >&2
          exit 1
        fi
        ;;
    esac
  done
else
  SUITES="$CORE_SUITES $PLUGIN_SUITES"
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
