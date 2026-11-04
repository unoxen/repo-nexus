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
        # Check plugin suite by exact or prefix match
        elif [ -f "$PLUGINS_DIR/$arg/tests/test_plugin.sh" ]; then
          SUITES="${SUITES:+$SUITES }$PLUGINS_DIR/$arg/tests/test_plugin.sh"
        else
          _pmatch="$(find "$PLUGINS_DIR" -maxdepth 1 -name "${arg}*" 2>/dev/null | head -n1)"
          if [ -n "$_pmatch" ] && [ -f "$_pmatch/tests/test_plugin.sh" ]; then
            SUITES="${SUITES:+$SUITES }$_pmatch/tests/test_plugin.sh"
          else
            echo "Error: Test suite matching '$arg' not found in $SUITES_DIR or $PLUGINS_DIR." >&2
            exit 1
          fi
        fi
        ;;
    esac
  done
else
  SUITES="$CORE_SUITES $PLUGIN_SUITES"
fi

# Count suites to execute
_suite_count=0
for suite in $SUITES; do
  [ -f "$suite" ] || continue
  _suite_count=$((_suite_count + 1))
done

if [ "$_suite_count" -le 1 ] || [ "${RNEX_TEST_PARALLEL:-1}" -eq 0 ]; then
  # Single suite or forced sequential: execute in foreground
  _STANDALONE_RUN=0
  for suite in $SUITES; do
    [ -f "$suite" ] || continue
    # shellcheck source=/dev/null
    . "$suite"
  done
  report_results
else
  # Multi-suite parallel execution: execute concurrently in isolated subshells
  _pids=""
  _logs=""
  _metrics=""
  _suite_paths=""

  for suite in $SUITES; do
    [ -f "$suite" ] || continue
    _s_log="$(mktemp)"
    _s_metric="$(mktemp)"

    (
      _iso_tmp="$(mktemp -d)"
      export TEST_TMP="$_iso_tmp"
      export TEST_METRICS_FILE="$_s_metric"
      export _STANDALONE_RUN=1
      trap 'rm -rf "$_iso_tmp"' EXIT INT TERM
      sh "$suite"
    ) > "$_s_log" 2>&1 &
    _sub_pid=$!

    _pids="${_pids:+$_pids }$_sub_pid"
    _logs="${_logs:+$_logs }$_s_log"
    _metrics="${_metrics:+$_metrics }$_s_metric"
    _suite_paths="${_suite_paths:+$_suite_paths }$suite"
  done

  # Collect results deterministically in submission order
  _any_failed=0
  PASS=0
  FAIL=0
  TOTAL=0

  # Pair up pids, logs, metrics, suites
  # shellcheck disable=SC2086
  set -- $_pids
  for _s_log in $_logs; do
    _cur_pid="$1"
    shift

    # Retrieve matching metric file
    _cur_metric="${_metrics%% *}"
    case "$_metrics" in
      *" "*) _metrics="${_metrics#* }" ;;
      *)     _metrics="" ;;
    esac

    # Retrieve matching suite name
    _cur_suite="${_suite_paths%% *}"
    case "$_suite_paths" in
      *" "*) _suite_paths="${_suite_paths#* }" ;;
      *)     _suite_paths="" ;;
    esac

    # Wait for suite to finish and capture exit status safely under set -e
    _exit_rc=0
    wait "$_cur_pid" 2>/dev/null || _exit_rc=$?
    if [ "$_exit_rc" -ne 0 ]; then
      _any_failed=1
    fi

    # Emit captured log output
    if [ -f "$_s_log" ]; then
      cat "$_s_log"
      rm -f "$_s_log"
    fi

    # Aggregate metrics
    if [ -f "$_cur_metric" ] && [ -s "$_cur_metric" ]; then
      read -r _m_tot _m_pass _m_fail < "$_cur_metric"
      TOTAL=$((TOTAL + _m_tot))
      PASS=$((PASS + _m_pass))
      FAIL=$((FAIL + _m_fail))
      rm -f "$_cur_metric"
    elif [ "$_exit_rc" -ne 0 ]; then
      TOTAL=$((TOTAL + 1))
      FAIL=$((FAIL + 1))
      echo "  [✗] FAILED: Suite $_cur_suite exited with status $_exit_rc"
      rm -f "$_cur_metric" 2>/dev/null || true
    fi
  done

  report_results
fi
