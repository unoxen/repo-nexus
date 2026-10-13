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
    cp -r "$DIR/lib" "$TEST_WORKSPACE/lib"
  fi
  if [ -d "$DIR/docs" ] && [ ! -d "$TEST_WORKSPACE/docs" ]; then
    cp -r "$DIR/docs" "$TEST_WORKSPACE/docs"
  fi
  if [ -d "$DIR/toolkit" ] && [ ! -d "$TEST_WORKSPACE/toolkit" ]; then
    cp -r "$DIR/toolkit" "$TEST_WORKSPACE/toolkit"
  fi
  if [ -d "$DIR/templates" ] && [ ! -d "$TEST_WORKSPACE/templates" ]; then
    cp -r "$DIR/templates" "$TEST_WORKSPACE/templates"
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
  [ "$FAIL" -eq 0 ] || exit 1
}
