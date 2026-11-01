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
run_test "Swallowed exit codes in cmd_exec and repo exec properly propagated"
"$TEST_WORKSPACE/rnex" repo add "$TEST_REPO" --name repo-exec >/dev/null

set +e
"$TEST_WORKSPACE/rnex" exec "false" >/dev/null 2>&1
_exec_rc=$?
"$TEST_WORKSPACE/rnex" exec "exit 42" >/dev/null 2>&1
_exec_rc42=$?
"$TEST_WORKSPACE/rnex" repo exec repo-exec "exit 42" >/dev/null 2>&1
_repo_exec_rc42=$?
set -e
[ "$_exec_rc" -ne 0 ] || { fail "rnex exec false returned 0"; exit 1; }
[ "$_exec_rc42" -eq 42 ] || { fail "rnex exec exit 42 returned $_exec_rc42 (expected 42)"; exit 1; }
[ "$_repo_exec_rc42" -eq 42 ] || { fail "rnex repo exec exit 42 returned $_repo_exec_rc42 (expected 42)"; exit 1; }
"$TEST_WORKSPACE/rnex" exec "true" >/dev/null
pass

# --------------------------------------------------------------------------
run_test "Shell completion generator (bash, zsh, fish) including readonly"
_zsh_comp="$("$TEST_WORKSPACE/rnex" completion zsh 2>&1)"
echo "$_zsh_comp" | grep -q "compdef rnex" || { fail "zsh completion missing compdef"; exit 1; }
echo "$_zsh_comp" | grep -q "readonly" || { fail "zsh completion missing readonly"; exit 1; }
_bash_comp="$("$TEST_WORKSPACE/rnex" completion bash 2>&1)"
echo "$_bash_comp" | grep -q "complete -F _rnex_completions" || { fail "bash completion missing complete -F"; exit 1; }
_fish_comp="$("$TEST_WORKSPACE/rnex" completion fish 2>&1)"
echo "$_fish_comp" | grep -q "readonly" || { fail "fish completion missing readonly"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "--config / -c pre-flight check_auto_sync detects changes from outside directory"
TEST_CFG_EXT_WS="$TEST_TMP/cfg-ext-ws"
mkdir -p "$TEST_CFG_EXT_WS"
cp "$CLI" "$TEST_CFG_EXT_WS/rnex"
chmod +x "$TEST_CFG_EXT_WS/rnex"
cp "$DIR/package.json" "$TEST_CFG_EXT_WS/package.json"
cp -r "$DIR/lib" "$TEST_CFG_EXT_WS/lib"
cp -r "$DIR/templates" "$TEST_CFG_EXT_WS/templates"
(cd "$TEST_CFG_EXT_WS" && ./rnex init -y >/dev/null)
[ -f "$TEST_CFG_EXT_WS/.rnex/sync_stamp" ] || { fail "sync stamp missing after init"; exit 1; }

printf "\n# modified config\n" >> "$TEST_CFG_EXT_WS/rnex.yaml"

cd "$TEST_OUTSIDE"
_outside_out="$("$TEST_CFG_EXT_WS/rnex" -c "$TEST_CFG_EXT_WS/rnex.yaml" list 2>&1)"
cd "$DIR"

_new_sum="$(cd "$TEST_CFG_EXT_WS" && cksum rnex.yaml .local.rnex.yaml 2>/dev/null | cksum | awk '{print $1, $2}')"
_stamp_val="$(cat "$TEST_CFG_EXT_WS/.rnex/sync_stamp" 2>/dev/null)"
[ "$_new_sum" = "$_stamp_val" ] || { fail "Auto-sync was not triggered for custom config from external directory"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Exclude docs/ and tests/ from installations, npm packaging, and remove remaining .gitkeep files"
# 1. Verify package.json files array excludes docs/
grep -q '"docs/"' "$DIR/package.json" && { fail "package.json files array still includes docs/"; exit 1; }
grep -q '"rnex"' "$DIR/package.json" || { fail "package.json missing rnex in files"; exit 1; }
grep -q '"lib/"' "$DIR/package.json" || { fail "package.json missing lib/ in files"; exit 1; }
grep -q '"templates/"' "$DIR/package.json" || { fail "package.json missing templates/ in files"; exit 1; }
grep -q '"plugins/"' "$DIR/package.json" || { fail "package.json missing plugins/ in files"; exit 1; }
grep -q '"skills/"' "$DIR/package.json" || { fail "package.json missing skills/ in files"; exit 1; }

# 2. Verify .npmignore contains /docs/ and plugins/*/tests/
grep -q '/docs/' "$DIR/.npmignore" || { fail ".npmignore missing /docs/"; exit 1; }
grep -q 'plugins/\*/tests/' "$DIR/.npmignore" || { fail ".npmignore missing plugins/*/tests/"; exit 1; }

# 3. Verify no tracked .gitkeep files remain in repository
_gitkeep_count="$(git -C "$DIR" ls-files "*.gitkeep" 2>/dev/null | wc -l | tr -d ' ')"
[ "$_gitkeep_count" -eq 0 ] || { fail "Found $_gitkeep_count tracked .gitkeep files"; exit 1; }

# 4. Verify rnex install copies runtime assets and excludes docs/ and tests/
TEST_CLI_INST_BIN="$TEST_TMP/test-cli-inst-bin"
TEST_CLI_INST_SHARE="$TEST_TMP/test-cli-inst-share"
mkdir -p "$TEST_CLI_INST_BIN" "$TEST_CLI_INST_SHARE"
RNEX_INSTALL_DIR="$TEST_CLI_INST_SHARE" "$DIR/rnex" install "$TEST_CLI_INST_BIN" >/dev/null
[ -x "$TEST_CLI_INST_BIN/rnex" ] || { fail "rnex install did not create executable in bin dir"; exit 1; }
[ -d "$TEST_CLI_INST_SHARE/lib" ] || { fail "rnex install did not copy lib/ to install dir"; exit 1; }
[ -d "$TEST_CLI_INST_SHARE/templates" ] || { fail "rnex install did not copy templates/ to install dir"; exit 1; }
[ -d "$TEST_CLI_INST_SHARE/plugins" ] || { fail "rnex install did not copy plugins/ to install dir"; exit 1; }
[ -d "$TEST_CLI_INST_SHARE/skills" ] || { fail "rnex install did not copy skills/ to install dir"; exit 1; }
[ ! -d "$TEST_CLI_INST_SHARE/docs" ] || { fail "rnex install leaked docs/ into install dir"; exit 1; }
[ ! -d "$TEST_CLI_INST_SHARE/plugins/claude/tests" ] || { fail "rnex install leaked tests into install dir"; exit 1; }

# 5. Verify scripts/install.sh copies runtime assets and excludes docs/ and tests/
TEST_SCRIPT_INST_BIN="$TEST_TMP/test-script-inst-bin"
TEST_SCRIPT_INST_SHARE="$TEST_TMP/test-script-inst-share"
mkdir -p "$TEST_SCRIPT_INST_BIN" "$TEST_SCRIPT_INST_SHARE"
RNEX_REPO_URL="$DIR" RNEX_INSTALL_DIR="$TEST_SCRIPT_INST_SHARE" RNEX_BIN_DIR="$TEST_SCRIPT_INST_BIN" sh "$DIR/scripts/install.sh" >/dev/null
[ -x "$TEST_SCRIPT_INST_BIN/rnex" ] || { fail "scripts/install.sh did not create executable in bin dir"; exit 1; }
[ -d "$TEST_SCRIPT_INST_SHARE/lib" ] || { fail "scripts/install.sh did not copy lib/ to install dir"; exit 1; }
[ -d "$TEST_SCRIPT_INST_SHARE/templates" ] || { fail "scripts/install.sh did not copy templates/ to install dir"; exit 1; }
[ -d "$TEST_SCRIPT_INST_SHARE/plugins" ] || { fail "scripts/install.sh did not copy plugins/ to install dir"; exit 1; }
[ -d "$TEST_SCRIPT_INST_SHARE/skills" ] || { fail "scripts/install.sh did not copy skills/ to install dir"; exit 1; }
[ ! -d "$TEST_SCRIPT_INST_SHARE/docs" ] || { fail "scripts/install.sh leaked docs/ into install dir"; exit 1; }
[ ! -d "$TEST_SCRIPT_INST_SHARE/plugins/claude/tests" ] || { fail "scripts/install.sh leaked tests into install dir"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Terminology audit (zero 'companion' occurrences), SEO keyword presence, and top README image"
if grep -ri "companion" "$DIR/README.md" "$DIR/package.json" "$DIR/docs" "$DIR/rnex" "$DIR/lib" "$DIR/templates" "$DIR/plugins" "$DIR/skills" >/dev/null 2>&1; then
  fail "Obsolete term 'companion' found in repository codebase"; exit 1
fi

for _kw in "nexus repository" "meta repository" "nexus repo" "meta repo"; do
  for _file in "$DIR/README.md" "$DIR/package.json" "$DIR/docs/index.md" "$DIR/docs/.vitepress/config.mts"; do
    if ! grep -iq "$_kw" "$_file"; then
      fail "Required SEO keyword '$_kw' missing in $_file"; exit 1
    fi
  done
done

_img_src="$(head -n 10 "$DIR/README.md" | grep '<img ' | sed 's/.*src="\([^"]*\)".*/\1/')"
[ -n "$_img_src" ] || { fail "README.md top 10 lines do not contain an <img> tag"; exit 1; }
[ -f "$DIR/$_img_src" ] || { fail "Hero image '$_img_src' referenced in README.md does not exist"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
