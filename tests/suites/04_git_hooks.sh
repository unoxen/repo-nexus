#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/04_git_hooks.sh — Automated Git Hooks Lifecycle Tests (Tests 28-31)
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/tests/test_helper.sh"

# --------------------------------------------------------------------------
run_test "Git hooks install, status, dispatch, and uninstall"
TEST_HOOKS_WS="$TEST_TMP/hooks-workspace"
mkdir -p "$TEST_HOOKS_WS"
cp "$CLI" "$TEST_HOOKS_WS/rnex"
chmod +x "$TEST_HOOKS_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_HOOKS_WS/toolkit"
cp "$DIR/package.json" "$TEST_HOOKS_WS/package.json"
git -C "$TEST_HOOKS_WS" init -q

# Initialize without hooks first
(cd "$TEST_HOOKS_WS" && ./rnex init -y --no-hooks >/dev/null)
grep -q "^git_hooks: false" "$TEST_HOOKS_WS/rnex.yaml" || { fail "init --no-hooks did not record git_hooks: false in rnex.yaml"; exit 1; }
_pre_status="$(cd "$TEST_HOOKS_WS" && ./rnex status 2>&1)"
echo "$_pre_status" | grep -q "Git Hooks:[ ]*disabled in configuration" || { fail "Status did not report disabled hooks"; exit 1; }

# Install hooks
(cd "$TEST_HOOKS_WS" && ./rnex hooks install >/dev/null)
grep -q "^git_hooks: true" "$TEST_HOOKS_WS/rnex.yaml" || { fail "hooks install did not record git_hooks: true in rnex.yaml"; exit 1; }
[ -d "$TEST_HOOKS_WS/.rnex/hooks" ] || { fail ".rnex/hooks directory missing"; exit 1; }
[ -x "$TEST_HOOKS_WS/.rnex/hooks/post-merge" ] || { fail "post-merge hook missing or not executable"; exit 1; }
[ -x "$TEST_HOOKS_WS/.rnex/hooks/post-commit" ] || { fail "post-commit hook missing or not executable"; exit 1; }
[ -x "$TEST_HOOKS_WS/.rnex/hooks/pre-commit" ] || { fail "pre-commit hook missing or not executable"; exit 1; }
[ -x "$TEST_HOOKS_WS/.rnex/hooks/pre-push" ] || { fail "pre-push hook missing or not executable"; exit 1; }

_hooks_path_val="$(git -C "$TEST_HOOKS_WS" config --get core.hooksPath)"
[ "$_hooks_path_val" = ".rnex/hooks" ] || { fail "core.hooksPath not set to .rnex/hooks (got: $_hooks_path_val)"; exit 1; }

# Verify hooks status command
_h_status="$(cd "$TEST_HOOKS_WS" && ./rnex hooks status 2>&1)"
echo "$_h_status" | grep -q "git_hooks: true" || { fail "hooks status did not report git_hooks: true"; exit 1; }
echo "$_h_status" | grep -q "core.hooksPath: .rnex/hooks" || { fail "hooks status did not report active core.hooksPath"; exit 1; }
echo "$_h_status" | grep -q "post-merge[ ]*(installed)" || { fail "hooks status did not report post-merge installed"; exit 1; }

# Verify status integration
_post_status="$(cd "$TEST_HOOKS_WS" && ./rnex status 2>&1)"
echo "$_post_status" | grep -q "Git Hooks:[ ]*active" || { fail "Status did not report active git hooks"; exit 1; }

# Test hooks run post-merge invokes fix quietly
(cd "$TEST_HOOKS_WS" && ./rnex hooks run post-merge >/dev/null)

# Uninstall hooks
(cd "$TEST_HOOKS_WS" && ./rnex hooks uninstall >/dev/null)
[ ! -d "$TEST_HOOKS_WS/.rnex/hooks" ] || { fail ".rnex/hooks still exists after uninstall"; exit 1; }
_uninstalled_hp="$(git -C "$TEST_HOOKS_WS" config --get core.hooksPath 2>/dev/null || true)"
[ -z "$_uninstalled_hp" ] || { fail "core.hooksPath still set after uninstall"; exit 1; }
grep -q "^git_hooks: false" "$TEST_HOOKS_WS/rnex.yaml" || { fail "hooks uninstall did not record git_hooks: false in rnex.yaml"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Init with git repo configures hooks automatically"
TEST_INIT_HOOKS="$TEST_TMP/init-hooks-ws"
mkdir -p "$TEST_INIT_HOOKS"
cp "$CLI" "$TEST_INIT_HOOKS/rnex"
chmod +x "$TEST_INIT_HOOKS/rnex"
cp -r "$DIR/toolkit" "$TEST_INIT_HOOKS/toolkit"
cp "$DIR/package.json" "$TEST_INIT_HOOKS/package.json"
git -C "$TEST_INIT_HOOKS" init -q

"$TEST_INIT_HOOKS/rnex" init -y "$TEST_INIT_HOOKS" >/dev/null
_init_hp="$(git -C "$TEST_INIT_HOOKS" config --get core.hooksPath 2>/dev/null || true)"
[ "$_init_hp" = ".rnex/hooks" ] || { fail "init -y did not configure Git hooks in git repo"; exit 1; }
[ -x "$TEST_INIT_HOOKS/.rnex/hooks/post-merge" ] || { fail "init -y did not create executable post-merge hook"; exit 1; }
grep -q "^git_hooks: true" "$TEST_INIT_HOOKS/rnex.yaml" || { fail "init -y did not record git_hooks: true in rnex.yaml"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Two-level git_hooks configuration (--local) and fix reconciliation"
TEST_LOCAL_HOOKS="$TEST_TMP/local-hooks-ws"
mkdir -p "$TEST_LOCAL_HOOKS"
cp "$CLI" "$TEST_LOCAL_HOOKS/rnex"
chmod +x "$TEST_LOCAL_HOOKS/rnex"
cp -r "$DIR/toolkit" "$TEST_LOCAL_HOOKS/toolkit"
cp "$DIR/package.json" "$TEST_LOCAL_HOOKS/package.json"
git -C "$TEST_LOCAL_HOOKS" init -q

"$TEST_LOCAL_HOOKS/rnex" init -y "$TEST_LOCAL_HOOKS" >/dev/null
grep -q "^git_hooks: true" "$TEST_LOCAL_HOOKS/rnex.yaml" || { fail "Base config does not have git_hooks: true"; exit 1; }

# Disable hooks locally (--local)
(cd "$TEST_LOCAL_HOOKS" && ./rnex hooks uninstall --local >/dev/null)
[ -f "$TEST_LOCAL_HOOKS/.local.rnex.yaml" ] || { fail ".local.rnex.yaml was not created"; exit 1; }
grep -q "^git_hooks: false" "$TEST_LOCAL_HOOKS/.local.rnex.yaml" || { fail ".local.rnex.yaml missing git_hooks: false"; exit 1; }
grep -q "^git_hooks: true" "$TEST_LOCAL_HOOKS/rnex.yaml" || { fail "Base rnex.yaml was modified by --local"; exit 1; }
_loc_hp="$(git -C "$TEST_LOCAL_HOOKS" config --get core.hooksPath 2>/dev/null || true)"
[ -z "$_loc_hp" ] || { fail "core.hooksPath still set after hooks uninstall --local"; exit 1; }

# Simulate someone manually configuring core.hooksPath, then rnex sync should uninstall it based on local override
git -C "$TEST_LOCAL_HOOKS" config core.hooksPath .rnex/hooks
mkdir -p "$TEST_LOCAL_HOOKS/.rnex/hooks"
(cd "$TEST_LOCAL_HOOKS" && ./rnex sync --quiet >/dev/null)
_reconciled_hp="$(git -C "$TEST_LOCAL_HOOKS" config --get core.hooksPath 2>/dev/null || true)"
[ -z "$_reconciled_hp" ] || { fail "rnex sync did not uninstall hooks when overridden by .local.rnex.yaml git_hooks: false"; exit 1; }

# Re-enable hooks locally (--local)
(cd "$TEST_LOCAL_HOOKS" && ./rnex hooks install --local >/dev/null)
grep -q "^git_hooks: true" "$TEST_LOCAL_HOOKS/.local.rnex.yaml" || { fail ".local.rnex.yaml missing git_hooks: true"; exit 1; }
_loc_hp2="$(git -C "$TEST_LOCAL_HOOKS" config --get core.hooksPath 2>/dev/null || true)"
[ "$_loc_hp2" = ".rnex/hooks" ] || { fail "hooks install --local did not set core.hooksPath"; exit 1; }

# Simulate someone manually unsetting core.hooksPath, then rnex sync should reinstall it based on config
git -C "$TEST_LOCAL_HOOKS" config --unset core.hooksPath
(cd "$TEST_LOCAL_HOOKS" && ./rnex sync --quiet >/dev/null)
_reconciled_hp2="$(git -C "$TEST_LOCAL_HOOKS" config --get core.hooksPath 2>/dev/null || true)"
[ "$_reconciled_hp2" = ".rnex/hooks" ] || { fail "rnex sync did not reinstall hooks based on config"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Git hooks: custom wrapper preservation, self-rewrite avoidance, and scripts/githooks chaining"
TEST_WRAPPER_WS="$TEST_TMP/wrapper-hooks-ws"
mkdir -p "$TEST_WRAPPER_WS"
cp "$CLI" "$TEST_WRAPPER_WS/rnex"
chmod +x "$TEST_WRAPPER_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_WRAPPER_WS/toolkit"
cp "$DIR/package.json" "$TEST_WRAPPER_WS/package.json"
git -C "$TEST_WRAPPER_WS" init -q

"$TEST_WRAPPER_WS/rnex" init -y "$TEST_WRAPPER_WS" >/dev/null

# 1. Custom wrapper in .rnex/hooks/post-commit must not be overwritten
cat <<'WRAPPER_EOF' > "$TEST_WRAPPER_WS/.rnex/hooks/post-commit"
#!/bin/sh
# Custom tested team wrapper (not managed by rnex)
echo "CUSTOM_WRAPPER_ACTIVE"
WRAPPER_EOF
chmod +x "$TEST_WRAPPER_WS/.rnex/hooks/post-commit"

# Run sync to ensure custom wrapper is preserved
(cd "$TEST_WRAPPER_WS" && ./rnex sync --quiet >/dev/null)
grep -q "CUSTOM_WRAPPER_ACTIVE" "$TEST_WRAPPER_WS/.rnex/hooks/post-commit" || { fail "rnex sync overwrote custom wrapper in .rnex/hooks/post-commit"; exit 1; }

# 2. Existing scripts/githooks chaining
mkdir -p "$TEST_WRAPPER_WS/scripts/githooks"
cat <<GITHOOKS_EOF > "$TEST_WRAPPER_WS/scripts/githooks/pre-commit"
#!/bin/sh
echo "CHAINED_SCRIPTS_GITHOOKS_PRE_COMMIT" > "$TEST_WRAPPER_WS/githooks_marker"
GITHOOKS_EOF
chmod +x "$TEST_WRAPPER_WS/scripts/githooks/pre-commit"

(cd "$TEST_WRAPPER_WS" && ./rnex hooks run pre-commit >/dev/null)
[ -f "$TEST_WRAPPER_WS/githooks_marker" ] || { fail "rnex hooks run pre-commit did not chain to scripts/githooks/pre-commit"; exit 1; }
grep -q "CHAINED_SCRIPTS_GITHOOKS_PRE_COMMIT" "$TEST_WRAPPER_WS/githooks_marker" || { fail "Chained scripts/githooks/pre-commit did not execute properly"; exit 1; }

# 3. Avoidance of self-rewrite during hooks run post-merge
# shellcheck disable=SC2012
_inode_before="$(ls -i "$TEST_WRAPPER_WS/.rnex/hooks/post-merge" | awk '{print $1}')"
(cd "$TEST_WRAPPER_WS" && ./rnex hooks run post-merge >/dev/null)
# shellcheck disable=SC2012
_inode_after="$(ls -i "$TEST_WRAPPER_WS/.rnex/hooks/post-merge" | awk '{print $1}')"
[ "$_inode_before" = "$_inode_after" ] || { fail "post-merge hook was rewritten/replaced during hook execution (self-rewrite bug)"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
