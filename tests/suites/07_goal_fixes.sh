#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/07_goal_fixes.sh — Regression tests for audited CLI bugs
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/tests/test_helper.sh"

TEST_GOAL_WS="$TEST_TMP/goal-fixes-workspace"
mkdir -p "$TEST_GOAL_WS"
setup_dummy_repo

cp "$CLI" "$TEST_GOAL_WS/rnex"
chmod +x "$TEST_GOAL_WS/rnex"
cp "$DIR/package.json" "$TEST_GOAL_WS/package.json"
cp -r "$DIR/lib" "$TEST_GOAL_WS/lib"
cp -r "$DIR/toolkit" "$TEST_GOAL_WS/toolkit"
cp -r "$DIR/templates" "$TEST_GOAL_WS/templates"

# Initialize workspace with copilot and karpathy plugins
(cd "$TEST_GOAL_WS" && ./rnex init -y --copilot --karpathy >/dev/null)

# --------------------------------------------------------------------------
run_test "Fix 1: cmd_plugin_update logs Plugin 'name' updated instead of empty name"
_update_out="$(cd "$TEST_GOAL_WS" && ./rnex plugin update copilot 2>&1)"
echo "$_update_out" | grep -q "Plugin 'copilot' updated" || { fail "Expected 'Plugin '\''copilot'\'' updated', got: $_update_out"; exit 1; }
! echo "$_update_out" | grep -q "Plugin '' updated" || { fail "Found buggy 'Plugin '\'''\'' updated': $_update_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 2a: Lifecycle hooks before_sync and after_sync fire exactly once on rnex sync"
mkdir -p "$TEST_GOAL_WS/toolkit/plugins/karpathy-llm/hooks"
cat <<'EOF_BS' > "$TEST_GOAL_WS/toolkit/plugins/karpathy-llm/hooks/before_sync.sh"
#!/bin/sh
printf 'x\n' >> "$RNEX_ROOT/before_sync_counts"
EOF_BS
chmod +x "$TEST_GOAL_WS/toolkit/plugins/karpathy-llm/hooks/before_sync.sh"

# Pre-populate before_sync in .rnex so it exists for the before_sync hook run before sync_plugins
mkdir -p "$TEST_GOAL_WS/.rnex/plugins/karpathy-llm/hooks"
cp "$TEST_GOAL_WS/toolkit/plugins/karpathy-llm/hooks/before_sync.sh" "$TEST_GOAL_WS/.rnex/plugins/karpathy-llm/hooks/before_sync.sh"

# Append counter output to existing after_sync.sh in toolkit
cat <<'EOF_AS' >> "$TEST_GOAL_WS/toolkit/plugins/karpathy-llm/hooks/after_sync.sh"
printf 'y\n' >> "$RNEX_ROOT/after_sync_counts"
EOF_AS

rm -f "$TEST_GOAL_WS/before_sync_counts" "$TEST_GOAL_WS/after_sync_counts"

(cd "$TEST_GOAL_WS" && ./rnex sync -y >/dev/null)

[ -f "$TEST_GOAL_WS/before_sync_counts" ] || { fail "before_sync hook did not fire"; exit 1; }
[ -f "$TEST_GOAL_WS/after_sync_counts" ] || { fail "after_sync hook did not fire"; exit 1; }
_bs_count="$(wc -l < "$TEST_GOAL_WS/before_sync_counts" | tr -d ' ')"
_as_count="$(wc -l < "$TEST_GOAL_WS/after_sync_counts" | tr -d ' ')"
[ "$_bs_count" -eq 1 ] || { fail "before_sync fired $_bs_count times (expected 1)"; exit 1; }
[ "$_as_count" -eq 1 ] || { fail "after_sync fired $_as_count times (expected 1)"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 2b: Lifecycle hook after_init fires exactly once on rnex init"
TEST_INIT_HOOK_WS="$TEST_TMP/init-hook-ws"
mkdir -p "$TEST_INIT_HOOK_WS"
cp "$CLI" "$TEST_INIT_HOOK_WS/rnex"
chmod +x "$TEST_INIT_HOOK_WS/rnex"
cp "$DIR/package.json" "$TEST_INIT_HOOK_WS/package.json"
cp -r "$DIR/lib" "$TEST_INIT_HOOK_WS/lib"
cp -r "$DIR/toolkit" "$TEST_INIT_HOOK_WS/toolkit"
cp -r "$DIR/templates" "$TEST_INIT_HOOK_WS/templates"

# Create a custom after_init.sh in toolkit/plugins/copilot/hooks/
mkdir -p "$TEST_INIT_HOOK_WS/toolkit/plugins/copilot/hooks"
cat <<'EOF_AI' > "$TEST_INIT_HOOK_WS/toolkit/plugins/copilot/hooks/after_init.sh"
#!/bin/sh
printf 'init_fired\n' >> "$RNEX_ROOT/after_init_counts"
EOF_AI
chmod +x "$TEST_INIT_HOOK_WS/toolkit/plugins/copilot/hooks/after_init.sh"

(cd "$TEST_INIT_HOOK_WS" && ./rnex init -y --copilot >/dev/null)
[ -f "$TEST_INIT_HOOK_WS/after_init_counts" ] || { fail "after_init hook did not fire"; exit 1; }
_ai_count="$(wc -l < "$TEST_INIT_HOOK_WS/after_init_counts" | tr -d ' ')"
[ "$_ai_count" -eq 1 ] || { fail "after_init fired $_ai_count times (expected 1)"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 3: Swallowed exit codes in cmd_exec properly propagated"
(cd "$TEST_GOAL_WS" && ./rnex add repo-exec "$TEST_REPO" >/dev/null)
set +e
(cd "$TEST_GOAL_WS" && ./rnex exec "false" >/dev/null 2>&1)
_exec_rc=$?
set -e
[ "$_exec_rc" -ne 0 ] || { fail "rnex exec false returned 0 instead of non-zero exit code"; exit 1; }

set +e
(cd "$TEST_GOAL_WS" && ./rnex exec "exit 42" >/dev/null 2>&1)
_exec_rc42=$?
set -e
[ "$_exec_rc42" -eq 42 ] || { fail "rnex exec exit 42 returned $_exec_rc42 (expected 42)"; exit 1; }

# Successful exec returns 0
(cd "$TEST_GOAL_WS" && ./rnex exec "true" >/dev/null)
pass

# --------------------------------------------------------------------------
run_test "Fix 4: set -e prevents after_<cmd> hooks on failure in dispatch_action"
cat <<'EOF_AE' > "$TEST_GOAL_WS/.rnex/plugins/karpathy-llm/hooks/after_exec.sh"
#!/bin/sh
printf 'AFTER_EXEC_RAN\n' > "$RNEX_ROOT/after_exec_marker"
EOF_AE
chmod +x "$TEST_GOAL_WS/.rnex/plugins/karpathy-llm/hooks/after_exec.sh"
rm -f "$TEST_GOAL_WS/after_exec_marker"

set +e
(cd "$TEST_GOAL_WS" && ./rnex exec "false" >/dev/null 2>&1)
_fail_rc=$?
set -e

[ "$_fail_rc" -ne 0 ] || { fail "rnex exec failed command should have non-zero exit code"; exit 1; }
[ -f "$TEST_GOAL_WS/after_exec_marker" ] || { fail "after_exec hook was not executed when command failed under set -e"; exit 1; }
grep -q "AFTER_EXEC_RAN" "$TEST_GOAL_WS/after_exec_marker" || { fail "after_exec marker content mismatch"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 5: Re-enabling a disabled plugin in rnex.yaml updates enabled: true"
# Manually disable copilot in rnex.yaml
sed -e '/copilot:/,/skills:/ s/instructions: true/enabled: false/' "$TEST_GOAL_WS/rnex.yaml" > "$TEST_GOAL_WS/rnex.yaml.tmp"
mv "$TEST_GOAL_WS/rnex.yaml.tmp" "$TEST_GOAL_WS/rnex.yaml"
# Ensure enabled: false is in rnex.yaml
if ! grep -q "enabled: false" "$TEST_GOAL_WS/rnex.yaml"; then
  # Replace copilot block with enabled: false
  awk '
    /^  copilot:/ { print; print "    enabled: false"; next }
    { print }
  ' "$TEST_GOAL_WS/rnex.yaml" > "$TEST_GOAL_WS/rnex.yaml.tmp" && mv "$TEST_GOAL_WS/rnex.yaml.tmp" "$TEST_GOAL_WS/rnex.yaml"
fi
(cd "$TEST_GOAL_WS" && ./rnex sync -y >/dev/null)
# Now re-enable without --local
(cd "$TEST_GOAL_WS" && ./rnex plugin enable copilot >/dev/null)
grep -q "enabled: true" "$TEST_GOAL_WS/rnex.yaml" || { fail "rnex.yaml was not updated to enabled: true for copilot"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 6: Commented repo keys removed by _yaml_remove_repo_from_file"
(cd "$TEST_GOAL_WS" && ./rnex add commented-repo "$TEST_REPO" >/dev/null)
# Add inline comment to repo header line in rnex.yaml
sed -e 's/^  commented-repo:[ ]*$/  commented-repo: # inline comment for test/' "$TEST_GOAL_WS/rnex.yaml" > "$TEST_GOAL_WS/rnex.yaml.tmp"
mv "$TEST_GOAL_WS/rnex.yaml.tmp" "$TEST_GOAL_WS/rnex.yaml"
grep -q "commented-repo: # inline comment" "$TEST_GOAL_WS/rnex.yaml" || { fail "Failed to prepare inline comment in rnex.yaml"; exit 1; }

(cd "$TEST_GOAL_WS" && ./rnex remove commented-repo -y >/dev/null)
! grep -q "commented-repo" "$TEST_GOAL_WS/rnex.yaml" || { fail "commented-repo was not removed from rnex.yaml when having inline comment"; exit 1; }
[ ! -d "$TEST_GOAL_WS/repos/commented-repo" ] || { fail "repos/commented-repo directory was not deleted"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 7: cmd_plugin_disable does not print duplicate log message"
_disable_out="$(cd "$TEST_GOAL_WS" && ./rnex plugin disable copilot 2>&1)"
_disable_count="$(echo "$_disable_out" | grep -c "disabled from workspace" || true)"
[ "$_disable_count" -eq 1 ] || { fail "Expected 1 'disabled from workspace' log, got $_disable_count:\n$_disable_out"; exit 1; }
# Re-enable copilot for subsequent tests
(cd "$TEST_GOAL_WS" && ./rnex plugin enable copilot >/dev/null)
pass

# --------------------------------------------------------------------------
run_test "Fix 8: Path resolution & flag inconsistencies in repo commands"
# 8a: cmd_remove parses flags properly (-y before or after name)
(cd "$TEST_GOAL_WS" && ./rnex add remove-flag-repo "$TEST_REPO" >/dev/null)
(cd "$TEST_GOAL_WS" && ./rnex remove -y remove-flag-repo >/dev/null)
[ ! -d "$TEST_GOAL_WS/repos/remove-flag-repo" ] || { fail "remove -y <name> failed to delete repo directory"; exit 1; }
! grep -q "remove-flag-repo" "$TEST_GOAL_WS/rnex.yaml" || { fail "remove -y <name> failed to unregister repo from rnex.yaml"; exit 1; }

# 8b: cmd_rnex_dir supports --local
(cd "$TEST_GOAL_WS" && ./rnex add rnexdir-test "$TEST_REPO" >/dev/null)
(cd "$TEST_GOAL_WS" && ./rnex rnex-dir disable rnexdir-test --local >/dev/null)
[ -f "$TEST_GOAL_WS/.local.rnex.yaml" ] || { fail ".local.rnex.yaml not created by rnex-dir --local"; exit 1; }
grep -q "rnex_dir: false" "$TEST_GOAL_WS/.local.rnex.yaml" || { fail "rnex_dir: false not set in .local.rnex.yaml"; exit 1; }

# 8c: cmd_clone uses resolve_repo_path (custom path resolution)
mkdir -p "$TEST_GOAL_WS/custom-repos"
cat <<'EOF_CR' >> "$TEST_GOAL_WS/rnex.yaml"
  custom-path-repo:
    path: custom-repos/my-custom-repo
    url: ./dummy-url
EOF_CR
# Set valid url pointing to TEST_REPO
sed -e "s|\./dummy-url|$TEST_REPO|" "$TEST_GOAL_WS/rnex.yaml" > "$TEST_GOAL_WS/rnex.yaml.tmp"
mv "$TEST_GOAL_WS/rnex.yaml.tmp" "$TEST_GOAL_WS/rnex.yaml"
(cd "$TEST_GOAL_WS" && ./rnex clone >/dev/null)
[ -d "$TEST_GOAL_WS/custom-repos/my-custom-repo/.git" ] || { fail "cmd_clone did not use resolve_repo_path to clone into custom path"; exit 1; }

# 8d: completion.sh includes rnex-dir in zsh and fish
_zsh_out="$("$TEST_GOAL_WS/rnex" completion zsh)"
echo "$_zsh_out" | grep -q "rnex-dir" || { fail "zsh completion missing rnex-dir"; exit 1; }
_fish_out="$("$TEST_GOAL_WS/rnex" completion fish)"
echo "$_fish_out" | grep -q "rnex-dir" || { fail "fish completion missing rnex-dir"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 9: Incomplete copilot plugin CLI integration"
# 9a: status displays copilot instructions and options
_status_out="$(cd "$TEST_GOAL_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q ".github/copilot-instructions.md" || { fail "status did not check .github/copilot-instructions.md: $_status_out"; exit 1; }
echo "$_status_out" | grep "copilot" -A 2 | grep -q "Options: instructions=" || { fail "status did not display copilot options: $_status_out"; exit 1; }

# 9b: plugin info copilot shows configurable options with .github/skills/
_pinfo_copilot="$(cd "$TEST_GOAL_WS" && ./rnex plugin info copilot 2>&1)"
echo "$_pinfo_copilot" | grep -q "Configurable Options" || { fail "copilot plugin info missing Configurable Options: $_pinfo_copilot"; exit 1; }
echo "$_pinfo_copilot" | grep -q "\.github/skills/" || { fail "copilot plugin info missing .github/skills/: $_pinfo_copilot"; exit 1; }

# 9c: help lists --copilot and --karpathy in init syntax
_help_out="$("$TEST_GOAL_WS/rnex" help 2>&1)"
echo "$_help_out" | grep "init " | grep -q -- "--copilot" || { fail "help init missing --copilot: $_help_out"; exit 1; }
echo "$_help_out" | grep "init " | grep -q -- "--karpathy" || { fail "help init missing --karpathy: $_help_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 10: --config / -c pre-flight check_auto_sync detects changes from outside directory"
TEST_CFG_EXT_WS="$TEST_TMP/cfg-ext-ws"
mkdir -p "$TEST_CFG_EXT_WS"
cp "$CLI" "$TEST_CFG_EXT_WS/rnex"
chmod +x "$TEST_CFG_EXT_WS/rnex"
cp "$DIR/package.json" "$TEST_CFG_EXT_WS/package.json"
cp -r "$DIR/lib" "$TEST_CFG_EXT_WS/lib"
cp -r "$DIR/toolkit" "$TEST_CFG_EXT_WS/toolkit"
cp -r "$DIR/templates" "$TEST_CFG_EXT_WS/templates"
(cd "$TEST_CFG_EXT_WS" && ./rnex init -y >/dev/null)

# Verify sync stamp exists
[ -f "$TEST_CFG_EXT_WS/.rnex/.sync_stamp" ] || { fail "sync stamp missing after init"; exit 1; }

# Modify rnex.yaml in TEST_CFG_EXT_WS
printf "\n# modified config\n" >> "$TEST_CFG_EXT_WS/rnex.yaml"

# Run rnex with -c from outside directory (TEST_OUTSIDE)
mkdir -p "$TEST_OUTSIDE"
cd "$TEST_OUTSIDE"
_outside_out="$("$TEST_CFG_EXT_WS/rnex" -c "$TEST_CFG_EXT_WS/rnex.yaml" list 2>&1)"
cd "$DIR"

# Verify the stamp in TEST_CFG_EXT_WS was updated to match the new config sum
_new_sum="$(cd "$TEST_CFG_EXT_WS" && cksum rnex.yaml .local.rnex.yaml 2>/dev/null | cksum | awk '{print $1, $2}')"
_stamp_val="$(cat "$TEST_CFG_EXT_WS/.rnex/.sync_stamp" 2>/dev/null)"
[ "$_new_sum" = "$_stamp_val" ] || { fail "Auto-sync was not triggered for custom config from external directory (sum: $_new_sum, stamp: $_stamp_val)"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
