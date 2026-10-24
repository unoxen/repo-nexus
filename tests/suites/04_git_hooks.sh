#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/04_git_hooks.sh — Automated Git Hooks Lifecycle Tests (Tests 28-31)
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/tests/test_helper.sh"

# --------------------------------------------------------------------------
run_test "Git hooks configuration, wrapper installation, status, and command execution"
TEST_HOOKS_WS="$TEST_TMP/hooks-workspace"
mkdir -p "$TEST_HOOKS_WS"
cp "$CLI" "$TEST_HOOKS_WS/rnex"
chmod +x "$TEST_HOOKS_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_HOOKS_WS/toolkit"
cp "$DIR/package.json" "$TEST_HOOKS_WS/package.json"
git -C "$TEST_HOOKS_WS" init -q

# Initialize workspace
(cd "$TEST_HOOKS_WS" && ./rnex init -y >/dev/null)
grep -q "git:" "$TEST_HOOKS_WS/rnex.yaml" || { fail "init -y did not record git: in rnex.yaml"; exit 1; }
grep -q "post-merge:" "$TEST_HOOKS_WS/rnex.yaml" || { fail "init -y did not record git.hooks.post-merge in rnex.yaml"; exit 1; }
! grep -q "git_hooks:" "$TEST_HOOKS_WS/rnex.yaml" || { fail "legacy git_hooks was written to rnex.yaml"; exit 1; }

# Wrappers in .git/hooks must be installed and executable
[ -x "$TEST_HOOKS_WS/.git/hooks/post-merge" ] || { fail "post-merge hook missing or not executable in .git/hooks"; exit 1; }
[ -x "$TEST_HOOKS_WS/.git/hooks/post-commit" ] || { fail "post-commit hook missing or not executable in .git/hooks"; exit 1; }
[ -x "$TEST_HOOKS_WS/.git/hooks/pre-commit" ] || { fail "pre-commit hook missing or not executable in .git/hooks"; exit 1; }
[ -x "$TEST_HOOKS_WS/.git/hooks/pre-push" ] || { fail "pre-push hook missing or not executable in .git/hooks"; exit 1; }

# Verify status reports active git hooks
_h_status="$(cd "$TEST_HOOKS_WS" && ./rnex status 2>&1)"
echo "$_h_status" | grep -q "Git Hooks:[ ]*active" || { fail "hooks status did not report active hooks"; exit 1; }
echo "$_h_status" | grep -q "Git Ignore:" || { fail "status did not report git ignore"; exit 1; }

# Verify deleted public rnex hooks command fails with unknown command
! (cd "$TEST_HOOKS_WS" && ./rnex hooks >/dev/null 2>&1) || { fail "rnex hooks succeeded but should be removed"; exit 1; }

# Test hooks run via _hook post-merge quietly
(cd "$TEST_HOOKS_WS" && ./rnex _hook post-merge >/dev/null)

# Test blocking hook execution on failure
cat <<'EOF' > "$TEST_HOOKS_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    pre-commit:
      - "exit 42"
repos:
plugins:
EOF
_exit_code=0
(cd "$TEST_HOOKS_WS" && ./rnex _hook pre-commit >/dev/null 2>&1) || _exit_code=$?
[ "$_exit_code" -eq 42 ] || { fail "pre-commit hook did not exit with code 42 (got: $_exit_code)"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Init with --no-hooks disables hook commands"
TEST_INIT_HOOKS="$TEST_TMP/init-hooks-ws"
mkdir -p "$TEST_INIT_HOOKS"
cp "$CLI" "$TEST_INIT_HOOKS/rnex"
chmod +x "$TEST_INIT_HOOKS/rnex"
cp -r "$DIR/toolkit" "$TEST_INIT_HOOKS/toolkit"
cp "$DIR/package.json" "$TEST_INIT_HOOKS/package.json"
git -C "$TEST_INIT_HOOKS" init -q

"$TEST_INIT_HOOKS/rnex" init -y --no-hooks "$TEST_INIT_HOOKS" >/dev/null
grep -q "post-merge:[ ]*\[\]" "$TEST_INIT_HOOKS/rnex.yaml" || { fail "init --no-hooks did not record post-merge: [] in rnex.yaml"; exit 1; }
[ -x "$TEST_INIT_HOOKS/.git/hooks/post-merge" ] || { fail "init -y did not create hook wrappers in .git/hooks"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Two-level git.hooks configuration (.local.rnex.yaml) and override priority"
TEST_LOCAL_HOOKS="$TEST_TMP/local-hooks-ws"
mkdir -p "$TEST_LOCAL_HOOKS"
cp "$CLI" "$TEST_LOCAL_HOOKS/rnex"
chmod +x "$TEST_LOCAL_HOOKS/rnex"
cp -r "$DIR/toolkit" "$TEST_LOCAL_HOOKS/toolkit"
cp "$DIR/package.json" "$TEST_LOCAL_HOOKS/package.json"
git -C "$TEST_LOCAL_HOOKS" init -q

"$TEST_LOCAL_HOOKS/rnex" init -y "$TEST_LOCAL_HOOKS" >/dev/null

# Configure a failing pre-commit in rnex.yaml
cat <<'EOF' > "$TEST_LOCAL_HOOKS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    pre-commit:
      - "exit 42"
    post-merge:
      - "echo 'BASE_HOOK' > base_marker"
repos:
plugins:
EOF

# Override pre-commit in .local.rnex.yaml to empty list [] (should override failure)
cat <<'EOF' > "$TEST_LOCAL_HOOKS/.local.rnex.yaml"
git:
  hooks:
    pre-commit: []
    post-merge:
      - "echo 'LOCAL_HOOK_RAN' > local_marker"
EOF

# Pre-commit should succeed because .local.rnex.yaml overrides to empty []
(cd "$TEST_LOCAL_HOOKS" && ./rnex _hook pre-commit >/dev/null)

# Post-merge should execute local hook
(cd "$TEST_LOCAL_HOOKS" && ./rnex _hook post-merge >/dev/null)
[ -f "$TEST_LOCAL_HOOKS/local_marker" ] || { fail "local hook did not create local_marker"; exit 1; }
grep -q "LOCAL_HOOK_RAN" "$TEST_LOCAL_HOOKS/local_marker" || { fail "local_marker did not contain LOCAL_HOOK_RAN"; exit 1; }
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

# 1. Custom wrapper in .git/hooks/post-commit must not be overwritten
cat <<'WRAPPER_EOF' > "$TEST_WRAPPER_WS/.git/hooks/post-commit"
#!/bin/sh
# Custom tested team wrapper (not managed by rnex)
echo "CUSTOM_WRAPPER_ACTIVE"
WRAPPER_EOF
chmod +x "$TEST_WRAPPER_WS/.git/hooks/post-commit"

# Run sync to ensure custom wrapper is preserved
(cd "$TEST_WRAPPER_WS" && ./rnex sync --quiet >/dev/null)
grep -q "CUSTOM_WRAPPER_ACTIVE" "$TEST_WRAPPER_WS/.git/hooks/post-commit" || { fail "rnex sync overwrote custom wrapper in .git/hooks/post-commit"; exit 1; }

# 2. Existing scripts/githooks chaining
mkdir -p "$TEST_WRAPPER_WS/scripts/githooks"
cat <<GITHOOKS_EOF > "$TEST_WRAPPER_WS/scripts/githooks/pre-commit"
#!/bin/sh
echo "CHAINED_SCRIPTS_GITHOOKS_PRE_COMMIT" > "$TEST_WRAPPER_WS/githooks_marker"
GITHOOKS_EOF
chmod +x "$TEST_WRAPPER_WS/scripts/githooks/pre-commit"

(cd "$TEST_WRAPPER_WS" && ./rnex _hook pre-commit >/dev/null)
[ -f "$TEST_WRAPPER_WS/githooks_marker" ] || { fail "rnex _hook pre-commit did not chain to scripts/githooks/pre-commit"; exit 1; }
grep -q "CHAINED_SCRIPTS_GITHOOKS_PRE_COMMIT" "$TEST_WRAPPER_WS/githooks_marker" || { fail "Chained scripts/githooks/pre-commit did not execute properly"; exit 1; }

# 3. Avoidance of self-rewrite during hooks run post-merge
# shellcheck disable=SC2012
_inode_before="$(ls -i "$TEST_WRAPPER_WS/.git/hooks/post-merge" | awk '{print $1}')"
(cd "$TEST_WRAPPER_WS" && ./rnex _hook post-merge >/dev/null)
# shellcheck disable=SC2012
_inode_after="$(ls -i "$TEST_WRAPPER_WS/.git/hooks/post-merge" | awk '{print $1}')"
[ "$_inode_before" = "$_inode_after" ] || { fail "post-merge hook was rewritten/replaced during hook execution (self-rewrite bug)"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
