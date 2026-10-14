#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/01_core_cli.sh — Core CLI & Workspace Lifecycle Tests (Tests 1-11)
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/tests/test_helper.sh"
setup_test_workspace
cd "$TEST_WORKSPACE"

# --------------------------------------------------------------------------
run_test "Initialize workspace with gitignore and routing instructions"
"$TEST_WORKSPACE/rnex" init -y "$TEST_WORKSPACE" >/dev/null
[ -f "$TEST_WORKSPACE/rnex.yaml" ] || { fail "rnex.yaml missing"; exit 1; }
[ -f "$TEST_WORKSPACE/AGENTS.md" ] || { fail "AGENTS.md missing"; exit 1; }
[ -d "$TEST_WORKSPACE/repos" ] || { fail "repos/ dir missing"; exit 1; }
[ -f "$TEST_WORKSPACE/repos/.gitkeep" ] || { fail "repos/.gitkeep missing"; exit 1; }
[ -f "$TEST_WORKSPACE/.gitignore" ] || { fail ".gitignore missing"; exit 1; }
grep -q 'repos/\*' "$TEST_WORKSPACE/.gitignore" || { fail "repos/* not in .gitignore"; exit 1; }
! grep -q '^\.rnex/' "$TEST_WORKSPACE/.gitignore" || { fail ".rnex/ should not be in .gitignore"; exit 1; }
grep -q '.local.rnex.yaml' "$TEST_WORKSPACE/.gitignore" || { fail ".local.rnex.yaml not in .gitignore"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Re-init warns and suggests sync --fix"
_reinit_output="$("$TEST_WORKSPACE/rnex" init -y "$TEST_WORKSPACE" 2>&1)"
echo "$_reinit_output" | grep -qi "already" || { fail "No already-initialized warning"; exit 1; }
echo "$_reinit_output" | grep -q "rnex sync --fix" || { fail "No rnex sync --fix suggestion"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Add member repository (clones into repos/ and creates member .rnex/)"
"$TEST_WORKSPACE/rnex" add test-app "$TEST_REPO" >/dev/null
[ -d "$TEST_WORKSPACE/repos/test-app/.git" ] || { fail "Physical clone in repos/test-app missing"; exit 1; }
[ -d "$TEST_WORKSPACE/repos/test-app/.rnex" ] || { fail ".rnex/ missing in member repo"; exit 1; }
[ -f "$TEST_WORKSPACE/repos/test-app/.rnex/README.md" ] || { fail ".rnex/README.md missing in member repo"; exit 1; }
grep -q "test-app:" "$TEST_WORKSPACE/rnex.yaml" || { fail "test-app not in rnex.yaml"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Batch command execution (rnex exec)"
_exec_out="$("$TEST_WORKSPACE/rnex" exec "git status -s" 2>&1)"
echo "$_exec_out" | grep -q "test-app" || { fail "rnex exec did not execute in test-app"; exit 1; }
echo "$_exec_out" | grep -q "succeeded" || { fail "rnex exec reported failure"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Disable and enable repository"
"$TEST_WORKSPACE/rnex" disable test-app >/dev/null
_list_out="$("$TEST_WORKSPACE/rnex" list 2>&1)"
echo "$_list_out" | grep "test-app" | grep -q "disabled" || { fail "test-app not listed as disabled"; exit 1; }

# Disabled repos are skipped by rnex exec
_exec_dis="$("$TEST_WORKSPACE/rnex" exec "echo running" 2>&1)"
! echo "$_exec_dis" | grep -q "running" || { fail "Disabled repo should be skipped by exec"; exit 1; }

"$TEST_WORKSPACE/rnex" enable test-app >/dev/null
_list_en="$("$TEST_WORKSPACE/rnex" list 2>&1)"
echo "$_list_en" | grep "test-app" | grep -q "enabled" || { fail "test-app not listed as enabled"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Clone command restores missing repositories"
# Temporarily remove test-app physical folder
rm -rf "$TEST_WORKSPACE/repos/test-app"
[ ! -d "$TEST_WORKSPACE/repos/test-app" ] || { fail "Failed to remove test-app dir"; exit 1; }

"$TEST_WORKSPACE/rnex" clone >/dev/null
[ -d "$TEST_WORKSPACE/repos/test-app/.git" ] || { fail "rnex clone did not restore test-app"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Idempotent sync --fix (and deprecated fix alias)"
_fix_out="$("$TEST_WORKSPACE/rnex" fix 2>&1)"
echo "$_fix_out" | grep -q "deprecated" || { fail "rnex fix did not print deprecation warning"; exit 1; }
[ -d "$TEST_WORKSPACE/repos/test-app/.rnex" ] || { fail ".rnex missing after fix"; exit 1; }
"$TEST_WORKSPACE/rnex" sync >/dev/null
# Verify dry-run sync audits inconsistencies without mutating files
rm -f "$TEST_WORKSPACE/.ignore"
_sync_out="$("$TEST_WORKSPACE/rnex" sync 2>&1 || true)"
echo "$_sync_out" | grep -q "inconsistency" || { fail "rnex sync did not report missing .ignore"; exit 1; }
[ ! -f "$TEST_WORKSPACE/.ignore" ] || { fail "rnex sync mutated files without --fix"; exit 1; }
"$TEST_WORKSPACE/rnex" sync --fix >/dev/null
[ -f "$TEST_WORKSPACE/.ignore" ] || { fail "rnex sync --fix did not recreate .ignore"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Explicit --config / -c from an external directory"
cd "$TEST_OUTSIDE"
"$TEST_WORKSPACE/rnex" --config "$TEST_WORKSPACE/rnex.yaml" status >/dev/null
"$TEST_WORKSPACE/rnex" -c "$TEST_WORKSPACE/rnex.yaml" list >/dev/null
cd "$TEST_WORKSPACE"
pass

# --------------------------------------------------------------------------
run_test "Remove member repository (unregisters and deletes repos/<name>)"
"$TEST_WORKSPACE/rnex" remove test-app >/dev/null
[ ! -e "$TEST_WORKSPACE/repos/test-app" ] || { fail "Physical repo folder was not deleted on remove"; exit 1; }
! grep -q "test-app:" "$TEST_WORKSPACE/rnex.yaml" || { fail "test-app still in rnex.yaml"; exit 1; }
[ -d "$TEST_REPO/src" ] || { fail "Original source repo was deleted"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Version command outputs version dynamically from package.json"
_expected_ver="$(grep '"version"' "$DIR/package.json" 2>/dev/null | head -n1 | sed -e 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/')"
_ver="$("$TEST_WORKSPACE/rnex" version 2>&1)"
echo "$_ver" | grep -q "$_expected_ver" || { fail "Version $_expected_ver not displayed: got $_ver"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Shell completion generator"
_zsh_comp="$("$TEST_WORKSPACE/rnex" completion zsh 2>&1)"
echo "$_zsh_comp" | grep -q "compdef rnex" || { fail "zsh completion missing compdef"; exit 1; }
_bash_comp="$("$TEST_WORKSPACE/rnex" completion bash 2>&1)"
echo "$_bash_comp" | grep -q "complete -F _rnex_completions" || { fail "bash completion missing complete -F"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
