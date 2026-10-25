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
[ -f "$TEST_WORKSPACE/.ignore" ] || { fail ".ignore missing on 1st init/sync run"; exit 1; }
grep -q '!repos/\*' "$TEST_WORKSPACE/.ignore" || { fail "!repos/* not in .ignore on 1st run"; exit 1; }
grep -q '^sync_stamp$' "$TEST_WORKSPACE/.rnex/.gitignore" || { fail "sync_stamp not in .rnex/.gitignore"; exit 1; }
! grep -q '^\.sync_stamp' "$TEST_WORKSPACE/.rnex/.gitignore" || { fail "legacy .sync_stamp should not be in .rnex/.gitignore"; exit 1; }
grep -q 'repos/\*' "$TEST_WORKSPACE/.gitignore" || { fail "repos/* not in .gitignore"; exit 1; }
! grep -q '^\.rnex/' "$TEST_WORKSPACE/.gitignore" || { fail ".rnex/ should not be in .gitignore"; exit 1; }
grep -q '.local.rnex.yaml' "$TEST_WORKSPACE/.gitignore" || { fail ".local.rnex.yaml not in .gitignore"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Re-init warns and suggests rnex sync"
_reinit_output="$("$TEST_WORKSPACE/rnex" init -y "$TEST_WORKSPACE" 2>&1)"
echo "$_reinit_output" | grep -qi "already" || { fail "No already-initialized warning"; exit 1; }
echo "$_reinit_output" | grep -q "rnex sync" || { fail "No rnex sync suggestion"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Add member repository (clones into repos/ cleanly without member .rnex/)"
"$TEST_WORKSPACE/rnex" repo add "$TEST_REPO" --name test-app >/dev/null
[ -d "$TEST_WORKSPACE/repos/test-app/.git" ] || { fail "Physical clone in repos/test-app missing"; exit 1; }
[ ! -d "$TEST_WORKSPACE/repos/test-app/.rnex" ] || { fail ".rnex/ should not be created in member repo by default"; exit 1; }
grep -q "test-app:" "$TEST_WORKSPACE/rnex.yaml" || { fail "test-app not in rnex.yaml"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Batch command execution (rnex exec)"
_exec_out="$("$TEST_WORKSPACE/rnex" exec "git status -s" 2>&1)"
echo "$_exec_out" | grep -q "test-app" || { fail "rnex exec did not execute in test-app"; exit 1; }
echo "$_exec_out" | grep -q "succeeded" || { fail "rnex exec reported failure"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Disable and enable repository (rnex repo set)"
"$TEST_WORKSPACE/rnex" repo set test-app --disable >/dev/null
_list_out="$("$TEST_WORKSPACE/rnex" list 2>&1)"
echo "$_list_out" | grep "test-app" | grep -q "disabled" || { fail "test-app not listed as disabled"; exit 1; }

# Disabled repos are skipped by rnex exec
_exec_dis="$("$TEST_WORKSPACE/rnex" exec "echo running" 2>&1)"
! echo "$_exec_dis" | grep -q "running" || { fail "Disabled repo should be skipped by exec"; exit 1; }

"$TEST_WORKSPACE/rnex" repo set test-app --enable >/dev/null
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

# Test single-repo clone (rnex repo clone <name>) restores targeted repository
rm -rf "$TEST_WORKSPACE/repos/test-app"
[ ! -d "$TEST_WORKSPACE/repos/test-app" ] || { fail "Failed to remove test-app dir"; exit 1; }
"$TEST_WORKSPACE/rnex" repo clone test-app >/dev/null
[ -d "$TEST_WORKSPACE/repos/test-app/.git" ] || { fail "rnex repo clone did not restore test-app"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Idempotent rnex sync, read-only status, rejection of status --fix, and removal of fix"
# Assert that running rnex fix exits with non-zero status and unknown command error
_fix_err="$("$TEST_WORKSPACE/rnex" fix 2>&1 || true)"
echo "$_fix_err" | grep -q "Unknown command: fix" || { fail "rnex fix did not fail with Unknown command"; exit 1; }

# Assert that status --fix is rejected with error pointing to rnex sync
_status_fix_err="$("$TEST_WORKSPACE/rnex" status --fix 2>&1 || true)"
echo "$_status_fix_err" | grep -q "Use 'rnex sync'" || { fail "rnex status --fix did not fail with migration message"; exit 1; }

# Read-only status reports out of sync when sync stamp is missing
rm -f "$TEST_WORKSPACE/.rnex/sync_stamp" "$TEST_WORKSPACE/.rnex/.sync_stamp"
_status_out="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_out" | grep -q "out of sync" || { fail "rnex status did not report missing sync stamp"; exit 1; }

# Reconcile with rnex sync (verify .ignore created on 1st sync even when .gitignore is missing, and legacy .sync_stamp stripped from .rnex/.gitignore)
rm -f "$TEST_WORKSPACE/.ignore" "$TEST_WORKSPACE/.gitignore"
printf ".sync_stamp\nsync_stamp\n" > "$TEST_WORKSPACE/.rnex/.gitignore"
"$TEST_WORKSPACE/rnex" sync >/dev/null
[ -f "$TEST_WORKSPACE/.gitignore" ] || { fail "rnex sync did not recreate .gitignore"; exit 1; }
[ -f "$TEST_WORKSPACE/.ignore" ] || { fail "rnex sync did not recreate .ignore on 1st run"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/sync_stamp" ] || { fail "rnex sync did not create sync_stamp"; exit 1; }
[ ! -f "$TEST_WORKSPACE/.rnex/.sync_stamp" ] || { fail "legacy .sync_stamp still exists after rnex sync"; exit 1; }
! grep -q '^\.sync_stamp' "$TEST_WORKSPACE/.rnex/.gitignore" || { fail "legacy .sync_stamp still in .rnex/.gitignore after rnex sync"; exit 1; }
_status_synced="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_synced" | grep -q "synchronized" || { fail "rnex status did not report synchronized status"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Auto-sync triggers on config change across commands and prompt hook"
# 1. Edit rnex.yaml: invalidate stamp
rm -f "$TEST_WORKSPACE/.ignore"
echo "# modified config" >> "$TEST_WORKSPACE/rnex.yaml"
# Next workspace command (e.g. rnex list) should auto-reconcile and recreate .ignore and update stamp
"$TEST_WORKSPACE/rnex" list >/dev/null
[ -f "$TEST_WORKSPACE/.ignore" ] || { fail "rnex list did not auto-sync when rnex.yaml changed"; exit 1; }
_stamp_after_edit="$(cat "$TEST_WORKSPACE/.rnex/sync_stamp" 2>/dev/null)"

# 2. Create .local.rnex.yaml: invalidate stamp
rm -f "$TEST_WORKSPACE/.ignore"
echo "git_hooks: false" > "$TEST_WORKSPACE/.local.rnex.yaml"
"$TEST_WORKSPACE/rnex" list >/dev/null
[ -f "$TEST_WORKSPACE/.ignore" ] || { fail "rnex list did not auto-sync when .local.rnex.yaml created"; exit 1; }
_stamp_after_local="$(cat "$TEST_WORKSPACE/.rnex/sync_stamp" 2>/dev/null)"
[ "$_stamp_after_local" != "$_stamp_after_edit" ] || { fail "sync stamp was not updated after .local.rnex.yaml created"; exit 1; }

# 3. Delete .local.rnex.yaml: invalidate stamp
rm -f "$TEST_WORKSPACE/.ignore"
rm -f "$TEST_WORKSPACE/.local.rnex.yaml"
"$TEST_WORKSPACE/rnex" list >/dev/null
[ -f "$TEST_WORKSPACE/.ignore" ] || { fail "rnex list did not auto-sync when .local.rnex.yaml deleted"; exit 1; }
_stamp_after_del="$(cat "$TEST_WORKSPACE/.rnex/sync_stamp" 2>/dev/null)"
[ "$_stamp_after_del" != "$_stamp_after_local" ] || { fail "sync stamp was not updated after .local.rnex.yaml deleted"; exit 1; }

# 4. Shell prompt hook _rnex_auto_sync triggers reconciliation
rm -f "$TEST_WORKSPACE/.ignore"
sleep 1
echo "# prompt hook change" >> "$TEST_WORKSPACE/rnex.yaml"
(
  cd "$TEST_WORKSPACE"
  _rnex_auto_sync() {
    [ -f rnex.yaml ] || return 0
    # shellcheck disable=SC3013
    if [ ! -f .rnex/sync_stamp ] || [ rnex.yaml -nt .rnex/sync_stamp ] || \
       { [ -f .local.rnex.yaml ] && [ .local.rnex.yaml -nt .rnex/sync_stamp ]; }; then
      ./rnex sync -y --quiet
    fi
  }
  _rnex_auto_sync
)
[ -f "$TEST_WORKSPACE/.ignore" ] || { fail "_rnex_auto_sync did not auto-reconcile workspace"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Explicit --config / -c from an external directory"
cd "$TEST_OUTSIDE"
"$TEST_WORKSPACE/rnex" --config "$TEST_WORKSPACE/rnex.yaml" status >/dev/null
"$TEST_WORKSPACE/rnex" -c "$TEST_WORKSPACE/rnex.yaml" list >/dev/null
cd "$TEST_WORKSPACE"
pass

# --------------------------------------------------------------------------
run_test "Remove member repository (unregisters and deletes repos/<name> via --purge)"
"$TEST_WORKSPACE/rnex" repo remove test-app --purge >/dev/null
[ ! -e "$TEST_WORKSPACE/repos/test-app" ] || { fail "Physical repo folder was not deleted on remove --purge"; exit 1; }
! grep -q "test-app:" "$TEST_WORKSPACE/rnex.yaml" || { fail "test-app still in rnex.yaml"; exit 1; }
[ -d "$TEST_REPO/src" ] || { fail "Original source repo was deleted"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Legacy top-level single-repo and deleted commands fail with unknown command"
for _bad_cmd in add remove enable disable readonly update upgrade hooks rnex-dir; do
  _err_out="$("$TEST_WORKSPACE/rnex" "$_bad_cmd" 2>&1 || true)"
  echo "$_err_out" | grep -qi "Unknown command" || { fail "Command 'rnex $_bad_cmd' did not fail with Unknown command: got '$_err_out'"; exit 1; }
done
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
