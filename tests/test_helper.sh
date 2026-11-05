#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/test_helper.sh — Common test harness and setup utilities
# ============================================================================
set -e

if [ -z "$DIR" ] || [ ! -f "$DIR/rnex" ]; then
  _D="$(cd "$(dirname "$0")" && pwd)"
  while [ "$_D" != "/" ]; do
    if [ -f "$_D/rnex" ] && [ -f "$_D/package.json" ]; then
      DIR="$_D"
      break
    fi
    _D="$(dirname "$_D")"
  done
fi
CLI="$DIR/rnex"
export RNEX_LIB_DIR="$DIR/lib"
export PATH="$DIR:$PATH"

# Configure git identity for test repository commits
export GIT_AUTHOR_NAME="Test Runner"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test Runner"
export GIT_COMMITTER_EMAIL="test@example.com"

# Setup temporary sandbox for testing if not already initialized
if [ -z "$TEST_TMP" ]; then
  TEST_TMP="$(mktemp -d)"
  _STANDALONE_RUN=1
  trap 'rm -rf "$TEST_TMP"' EXIT INT TERM
fi

TEST_WORKSPACE="${TEST_WORKSPACE:-$TEST_TMP/nexus-workspace}"
TEST_REPO="${TEST_REPO:-$TEST_TMP/dummy-repo}"
TEST_OUTSIDE="${TEST_OUTSIDE:-$TEST_TMP/outside-dir}"

PASS="${PASS:-0}"
FAIL="${FAIL:-0}"
TOTAL="${TOTAL:-0}"

run_test() {
  TOTAL=$((TOTAL + 1))
  _desc="$1"
  echo "==> Test $TOTAL: $_desc"
}

pass() {
  PASS=$((PASS + 1))
  echo "  [✓] Passed"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  [✗] FAILED: $1"
}

link_dir_contents() {
  _ldc_src="$1"
  _ldc_dst="$2"
  [ -d "$_ldc_src" ] || return 0
  mkdir -p "$_ldc_dst"
  for _ldc_item in "$_ldc_src"/*; do
    [ -e "$_ldc_item" ] || continue
    _ldc_base="$(basename "$_ldc_item")"
    if [ ! -e "$_ldc_dst/$_ldc_base" ]; then
      ln -s "$_ldc_item" "$_ldc_dst/$_ldc_base" 2>/dev/null || cp -R "$_ldc_item" "$_ldc_dst/$_ldc_base"
    fi
  done
}

setup_dummy_repo() {
  if [ ! -d "$TEST_REPO/.git" ]; then
    mkdir -p "$TEST_REPO/src"
    echo 'console.log("hello world");' > "$TEST_REPO/src/app.js"
    git -C "$TEST_REPO" init -q
    git -C "$TEST_REPO" add .
    git -C "$TEST_REPO" commit -m "init" -q
  fi
}

setup_test_workspace() {
  mkdir -p "$TEST_WORKSPACE" "$TEST_OUTSIDE"
  setup_dummy_repo

  if [ ! -f "$TEST_WORKSPACE/rnex" ]; then
    cp "$CLI" "$TEST_WORKSPACE/rnex"
    chmod +x "$TEST_WORKSPACE/rnex"
  fi
  if [ -f "$DIR/package.json" ] && [ ! -f "$TEST_WORKSPACE/package.json" ]; then
    cp "$DIR/package.json" "$TEST_WORKSPACE/package.json"
  fi
  if [ -d "$DIR/lib" ] && [ ! -d "$TEST_WORKSPACE/lib" ]; then
    link_dir_contents "$DIR/lib" "$TEST_WORKSPACE/lib"
  fi
  if [ -d "$DIR/plugins" ] && [ ! -d "$TEST_WORKSPACE/plugins" ]; then
    link_dir_contents "$DIR/plugins" "$TEST_WORKSPACE/plugins"
  fi
  if [ -d "$DIR/skills" ] && [ ! -d "$TEST_WORKSPACE/skills" ]; then
    link_dir_contents "$DIR/skills" "$TEST_WORKSPACE/skills"
  fi
  if [ -d "$DIR/templates" ] && [ ! -d "$TEST_WORKSPACE/templates" ]; then
    link_dir_contents "$DIR/templates" "$TEST_WORKSPACE/templates"
  fi
}

setup_plugin_test_workspace() {
  _plugin_name="$1"
  _ws="${2:-$TEST_WORKSPACE}"
  mkdir -p "$_ws" "$TEST_OUTSIDE"
  setup_dummy_repo

  if [ ! -f "$_ws/rnex" ]; then
    cp "$CLI" "$_ws/rnex"
    chmod +x "$_ws/rnex"
  fi
  if [ -f "$DIR/package.json" ] && [ ! -f "$_ws/package.json" ]; then
    cp "$DIR/package.json" "$_ws/package.json"
  fi
  if [ -d "$DIR/lib" ] && [ ! -d "$_ws/lib" ]; then
    link_dir_contents "$DIR/lib" "$_ws/lib"
  fi
  if [ -d "$DIR/templates" ] && [ ! -d "$_ws/templates" ]; then
    link_dir_contents "$DIR/templates" "$_ws/templates"
  fi
  if [ -d "$DIR/skills" ] && [ ! -d "$_ws/skills" ]; then
    link_dir_contents "$DIR/skills" "$_ws/skills"
  fi
  if [ -n "$_plugin_name" ]; then
    if [ -d "$DIR/plugins/$_plugin_name" ] && [ ! -d "$_ws/plugins/$_plugin_name" ]; then
      mkdir -p "$_ws/plugins"
      ln -s "$DIR/plugins/$_plugin_name" "$_ws/plugins/$_plugin_name" 2>/dev/null || cp -R "$DIR/plugins/$_plugin_name" "$_ws/plugins/$_plugin_name"
    fi
  fi
}

report_results() {
  echo ""
  echo "===================================="
  if [ "$FAIL" -eq 0 ]; then
    echo "  All $TOTAL Automated Tests Passed! ✓"
  else
    echo "  $PASS/$TOTAL passed, $FAIL FAILED"
  fi
  echo "===================================="
  if [ -n "${TEST_METRICS_FILE:-}" ]; then
    printf '%s %s %s\n' "$TOTAL" "$PASS" "$FAIL" > "$TEST_METRICS_FILE"
  fi
  [ "$FAIL" -eq 0 ] || exit 1
}
