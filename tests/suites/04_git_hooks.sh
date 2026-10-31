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
grep -q "rnex_hooks:" "$TEST_HOOKS_WS/rnex.yaml" || { fail "init -y did not record rnex_hooks: in rnex.yaml"; exit 1; }
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

# --------------------------------------------------------------------------
run_test "rnex_hooks lifecycle command execution across workspace events"
TEST_RNEX_HOOKS_WS="$TEST_TMP/rnex-hooks-lifecycle-ws"
mkdir -p "$TEST_RNEX_HOOKS_WS"
cp "$CLI" "$TEST_RNEX_HOOKS_WS/rnex"
chmod +x "$TEST_RNEX_HOOKS_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_RNEX_HOOKS_WS/toolkit"
cp "$DIR/package.json" "$TEST_RNEX_HOOKS_WS/package.json"
git -C "$TEST_RNEX_HOOKS_WS" init -q

"$TEST_RNEX_HOOKS_WS/rnex" init -y "$TEST_RNEX_HOOKS_WS" >/dev/null

# Create a local dummy bare repo to use for cloning
TEST_DUMMY_REMOTE="$TEST_TMP/dummy-remote-repo.git"
mkdir -p "$TEST_TMP/dummy-src"
git -C "$TEST_TMP/dummy-src" init -q
git -C "$TEST_TMP/dummy-src" config user.email "test@example.com"
git -C "$TEST_TMP/dummy-src" config user.name "Test"
echo "# Dummy" > "$TEST_TMP/dummy-src/README.md"
git -C "$TEST_TMP/dummy-src" add .
git -C "$TEST_TMP/dummy-src" commit -q -m "initial"
git clone --bare -q "$TEST_TMP/dummy-src" "$TEST_DUMMY_REMOTE"

cat <<'HOOKS_YAML' > "$TEST_RNEX_HOOKS_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    post-merge: []
rnex_hooks:
  before_sync:
    - "echo 'BEFORE_SYNC' >> hook_log"
  after_sync:
    - "echo 'AFTER_SYNC' >> hook_log"
  before_repo_add:
    - "echo 'BEFORE_REPO_ADD' >> hook_log"
  after_repo_add:
    - "echo 'AFTER_REPO_ADD' >> hook_log"
  before_repo_set:
    - "echo 'BEFORE_REPO_SET' >> hook_log"
  after_repo_set:
    - "echo 'AFTER_REPO_SET' >> hook_log"
  before_clone:
    - "echo 'BEFORE_CLONE' >> hook_log"
  after_clone:
    - "echo 'AFTER_CLONE' >> hook_log"
  before_exec:
    - "echo 'BEFORE_EXEC' >> hook_log"
  after_exec:
    - "echo 'AFTER_EXEC' >> hook_log"
  before_repo_remove:
    - "echo 'BEFORE_REPO_REMOVE' >> hook_log"
  after_repo_remove:
    - "echo 'AFTER_REPO_REMOVE' >> hook_log"
  before_plugin_enable:
    - "echo 'BEFORE_PLUGIN_ENABLE' >> hook_log"
  after_plugin_enable:
    - "echo 'AFTER_PLUGIN_ENABLE' >> hook_log"
  before_plugin_disable:
    - "echo 'BEFORE_PLUGIN_DISABLE' >> hook_log"
  after_plugin_disable:
    - "echo 'AFTER_PLUGIN_DISABLE' >> hook_log"
repos:
plugins:
HOOKS_YAML

rm -f "$TEST_RNEX_HOOKS_WS/hook_log"

# 1. Sync
(cd "$TEST_RNEX_HOOKS_WS" && ./rnex sync --quiet)
grep -q "BEFORE_SYNC" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "before_sync hook did not execute"; exit 1; }
grep -q "AFTER_SYNC" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "after_sync hook did not execute"; exit 1; }

# 2. Repo add
(cd "$TEST_RNEX_HOOKS_WS" && ./rnex repo add "$TEST_DUMMY_REMOTE" --name dummy --branch master >/dev/null)
grep -q "BEFORE_REPO_ADD" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "before_repo_add hook did not execute"; exit 1; }
grep -q "AFTER_REPO_ADD" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "after_repo_add hook did not execute"; exit 1; }

# 3. Repo set
(cd "$TEST_RNEX_HOOKS_WS" && ./rnex repo set dummy --disable >/dev/null)
grep -q "BEFORE_REPO_SET" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "before_repo_set hook did not execute"; exit 1; }
grep -q "AFTER_REPO_SET" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "after_repo_set hook did not execute"; exit 1; }

# 4. Repo clone
(cd "$TEST_RNEX_HOOKS_WS" && ./rnex repo clone dummy >/dev/null)
grep -q "BEFORE_CLONE" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "before_clone hook did not execute"; exit 1; }
grep -q "AFTER_CLONE" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "after_clone hook did not execute"; exit 1; }

# 5. Repo exec
(cd "$TEST_RNEX_HOOKS_WS" && ./rnex repo exec dummy echo hi >/dev/null)
grep -q "BEFORE_EXEC" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "before_exec hook did not execute"; exit 1; }
grep -q "AFTER_EXEC" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "after_exec hook did not execute"; exit 1; }

# 6. Plugin enable
(cd "$TEST_RNEX_HOOKS_WS" && ./rnex plugin enable claude >/dev/null)
grep -q "BEFORE_PLUGIN_ENABLE" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "before_plugin_enable hook did not execute"; exit 1; }
grep -q "AFTER_PLUGIN_ENABLE" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "after_plugin_enable hook did not execute"; exit 1; }

# 7. Plugin disable
(cd "$TEST_RNEX_HOOKS_WS" && ./rnex plugin disable claude >/dev/null)
grep -q "BEFORE_PLUGIN_DISABLE" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "before_plugin_disable hook did not execute"; exit 1; }
grep -q "AFTER_PLUGIN_DISABLE" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "after_plugin_disable hook did not execute"; exit 1; }

# 8. Repo remove
(cd "$TEST_RNEX_HOOKS_WS" && ./rnex repo remove dummy -y >/dev/null)
grep -q "BEFORE_REPO_REMOVE" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "before_repo_remove hook did not execute"; exit 1; }
grep -q "AFTER_REPO_REMOVE" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "after_repo_remove hook did not execute"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Two-level rnex_hooks config (.local.rnex.yaml priority & hyphen/underscore keys)"
TEST_RNEX_LOCAL_WS="$TEST_TMP/rnex-hooks-local-ws"
mkdir -p "$TEST_RNEX_LOCAL_WS"
cp "$CLI" "$TEST_RNEX_LOCAL_WS/rnex"
chmod +x "$TEST_RNEX_LOCAL_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_RNEX_LOCAL_WS/toolkit"
cp "$DIR/package.json" "$TEST_RNEX_LOCAL_WS/package.json"
git -C "$TEST_RNEX_LOCAL_WS" init -q

"$TEST_RNEX_LOCAL_WS/rnex" init -y "$TEST_RNEX_LOCAL_WS" >/dev/null

cat <<'BASE_YAML' > "$TEST_RNEX_LOCAL_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    post-merge: []
rnex_hooks:
  before-sync:
    - "exit 42"
  after_sync:
    - "echo 'BASE_HOOK' > override_test_marker"
repos:
plugins:
BASE_YAML

cat <<'LOCAL_YAML' > "$TEST_RNEX_LOCAL_WS/.local.rnex.yaml"
rnex_hooks:
  before_sync: []
  after-sync:
    - "echo 'LOCAL_OVERRIDE_RAN' > override_test_marker"
LOCAL_YAML

# before-sync was exit 42 in rnex.yaml, but .local.rnex.yaml overrides before_sync to []
(cd "$TEST_RNEX_LOCAL_WS" && ./rnex sync --quiet)
[ -f "$TEST_RNEX_LOCAL_WS/override_test_marker" ] || { fail "override_test_marker was not created"; exit 1; }
grep -q "LOCAL_OVERRIDE_RAN" "$TEST_RNEX_LOCAL_WS/override_test_marker" || { fail "local override did not execute or did not override rnex.yaml"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Blocking before_* hook failure aborts action with exit code"
TEST_RNEX_BLOCK_WS="$TEST_TMP/rnex-hooks-block-ws"
mkdir -p "$TEST_RNEX_BLOCK_WS"
cp "$CLI" "$TEST_RNEX_BLOCK_WS/rnex"
chmod +x "$TEST_RNEX_BLOCK_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_RNEX_BLOCK_WS/toolkit"
cp "$DIR/package.json" "$TEST_RNEX_BLOCK_WS/package.json"
git -C "$TEST_RNEX_BLOCK_WS" init -q

"$TEST_RNEX_BLOCK_WS/rnex" init -y "$TEST_RNEX_BLOCK_WS" >/dev/null

cat <<'BLOCK_YAML' > "$TEST_RNEX_BLOCK_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    post-merge: []
rnex_hooks:
  before_sync:
    - "exit 37"
repos:
plugins:
BLOCK_YAML

_block_rc=0
(cd "$TEST_RNEX_BLOCK_WS" && ./rnex sync --quiet >/dev/null 2>&1) || _block_rc=$?
[ "$_block_rc" -eq 37 ] || { fail "before_sync hook did not block with exit code 37 (got: $_block_rc)"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Re-entrant loop guard in rnex_hooks prevents infinite recursion"
TEST_RNEX_RECURSE_WS="$TEST_TMP/rnex-hooks-recurse-ws"
mkdir -p "$TEST_RNEX_RECURSE_WS"
cp "$CLI" "$TEST_RNEX_RECURSE_WS/rnex"
chmod +x "$TEST_RNEX_RECURSE_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_RNEX_RECURSE_WS/toolkit"
cp "$DIR/package.json" "$TEST_RNEX_RECURSE_WS/package.json"
git -C "$TEST_RNEX_RECURSE_WS" init -q

"$TEST_RNEX_RECURSE_WS/rnex" init -y "$TEST_RNEX_RECURSE_WS" >/dev/null

cat <<'RECURSE_YAML' > "$TEST_RNEX_RECURSE_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    post-merge: []
rnex_hooks:
  after_sync:
    - "echo 'REENTRANT_RUN' >> reentrant_log"
    - "./rnex sync --quiet"
repos:
plugins:
RECURSE_YAML

rm -f "$TEST_RNEX_RECURSE_WS/reentrant_log"
(cd "$TEST_RNEX_RECURSE_WS" && ./rnex sync --quiet)
[ -f "$TEST_RNEX_RECURSE_WS/reentrant_log" ] || { fail "reentrant_log was not created"; exit 1; }
_run_count="$(wc -l < "$TEST_RNEX_RECURSE_WS/reentrant_log" | tr -d ' ')"
[ "$_run_count" -eq 1 ] || { fail "reentrant hook executed $_run_count times instead of exactly 1"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Missing wrappers warning in rnex status resolved deterministically by rnex sync"
TEST_SYNC_HOOKS_WS="$TEST_TMP/sync-hooks-resolution-ws"
mkdir -p "$TEST_SYNC_HOOKS_WS"
cp "$CLI" "$TEST_SYNC_HOOKS_WS/rnex"
chmod +x "$TEST_SYNC_HOOKS_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_SYNC_HOOKS_WS/toolkit"
cp "$DIR/package.json" "$TEST_SYNC_HOOKS_WS/package.json"
git -C "$TEST_SYNC_HOOKS_WS" init -q

"$TEST_SYNC_HOOKS_WS/rnex" init -y "$TEST_SYNC_HOOKS_WS" >/dev/null

cat <<'SYNC_YAML' > "$TEST_SYNC_HOOKS_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    pre-commit:
      - "echo 'sync-check' > /dev/null"
    post-merge: []
repos:
plugins:
SYNC_YAML

# Remove all installed wrappers to trigger missing wrappers condition
rm -rf "$TEST_SYNC_HOOKS_WS/.git/hooks"/*

# rnex status must detect missing wrappers and output explicit warning
_status_out="$(cd "$TEST_SYNC_HOOKS_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q "Git Hooks:[ ]*configured in git.hooks, but wrappers missing" || {
  fail "rnex status did not report missing wrappers warning when .git/hooks was cleared"; exit 1;
}

# Run rnex sync to reconcile and restore wrappers
(cd "$TEST_SYNC_HOOKS_WS" && ./rnex sync --quiet)

# Verify wrappers are restored and executable
[ -x "$TEST_SYNC_HOOKS_WS/.git/hooks/pre-commit" ] || { fail "pre-commit wrapper missing after rnex sync"; exit 1; }
[ -x "$TEST_SYNC_HOOKS_WS/.git/hooks/post-merge" ] || { fail "post-merge wrapper missing after rnex sync"; exit 1; }

# rnex status must now report active wrappers without warning
_status_clean="$(cd "$TEST_SYNC_HOOKS_WS" && ./rnex status 2>&1)"
echo "$_status_clean" | grep -q "Git Hooks:[ ]*active" || {
  fail "rnex status did not report active hooks after rnex sync"; exit 1;
}
! echo "$_status_clean" | grep -q "wrappers missing" || {
  fail "rnex status still reports wrappers missing after rnex sync"; exit 1;
}
pass

# --------------------------------------------------------------------------
run_test "YAML format coverage: block sequence, inline array, and .local.rnex.yaml disabling"
TEST_YAML_HOOKS_WS="$TEST_TMP/yaml-formats-hooks-ws"
mkdir -p "$TEST_YAML_HOOKS_WS"
cp "$CLI" "$TEST_YAML_HOOKS_WS/rnex"
chmod +x "$TEST_YAML_HOOKS_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_YAML_HOOKS_WS/toolkit"
cp "$DIR/package.json" "$TEST_YAML_HOOKS_WS/package.json"
git -C "$TEST_YAML_HOOKS_WS" init -q

"$TEST_YAML_HOOKS_WS/rnex" init -y "$TEST_YAML_HOOKS_WS" >/dev/null

# 1. Test block sequence (- pre-commit)
cat <<'SEQ_YAML' > "$TEST_YAML_HOOKS_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    - pre-commit
    - pre-push
repos:
plugins:
SEQ_YAML

rm -rf "$TEST_YAML_HOOKS_WS/.git/hooks"/*
(cd "$TEST_YAML_HOOKS_WS" && ./rnex sync --quiet)
[ -x "$TEST_YAML_HOOKS_WS/.git/hooks/pre-commit" ] || { fail "pre-commit wrapper missing from block sequence config"; exit 1; }
[ -x "$TEST_YAML_HOOKS_WS/.git/hooks/pre-push" ] || { fail "pre-push wrapper missing from block sequence config"; exit 1; }
_seq_status="$(cd "$TEST_YAML_HOOKS_WS" && ./rnex status 2>&1)"
echo "$_seq_status" | grep -q "Git Hooks:[ ]*active" || { fail "status did not report active for block sequence"; exit 1; }

# 2. Test inline array (hooks: [pre-commit, post-checkout])
cat <<'INLINE_YAML' > "$TEST_YAML_HOOKS_WS/rnex.yaml"
version: 1.0.0
git:
  hooks: [pre-commit, post-checkout]
repos:
plugins:
INLINE_YAML

(cd "$TEST_YAML_HOOKS_WS" && ./rnex sync --quiet)
[ -x "$TEST_YAML_HOOKS_WS/.git/hooks/pre-commit" ] || { fail "pre-commit wrapper missing from inline array config"; exit 1; }
[ -x "$TEST_YAML_HOOKS_WS/.git/hooks/post-checkout" ] || { fail "post-checkout wrapper missing from inline array config"; exit 1; }
_inline_status="$(cd "$TEST_YAML_HOOKS_WS" && ./rnex status 2>&1)"
echo "$_inline_status" | grep -q "Git Hooks:[ ]*active" || { fail "status did not report active for inline array"; exit 1; }

# 3. Test .local.rnex.yaml explicitly disabling a hook (pre-commit: false)
cat <<'LOCAL_DISABLE_YAML' > "$TEST_YAML_HOOKS_WS/.local.rnex.yaml"
git:
  hooks:
    pre-commit: false
LOCAL_DISABLE_YAML

(cd "$TEST_YAML_HOOKS_WS" && ./rnex sync --quiet)
_disable_status="$(cd "$TEST_YAML_HOOKS_WS" && ./rnex status 2>&1)"
echo "$_disable_status" | grep -q "Git Hooks:[ ]*active" || { fail "status did not report active after local disable"; exit 1; }
! echo "$_disable_status" | grep -q "wrappers missing" || { fail "status reported missing wrapper for locally disabled hook"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Custom user hook preservation (.user), chaining, and cleanup on unconfigure"
TEST_USER_HOOKS_WS="$TEST_TMP/user-hook-ws"
mkdir -p "$TEST_USER_HOOKS_WS"
cp "$CLI" "$TEST_USER_HOOKS_WS/rnex"
chmod +x "$TEST_USER_HOOKS_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_USER_HOOKS_WS/toolkit"
cp "$DIR/package.json" "$TEST_USER_HOOKS_WS/package.json"
git -C "$TEST_USER_HOOKS_WS" init -q

"$TEST_USER_HOOKS_WS/rnex" init -y "$TEST_USER_HOOKS_WS" >/dev/null

# Create a pre-existing custom user pre-commit hook before configuring rnex
cat <<'USER_HOOK_EOF' > "$TEST_USER_HOOKS_WS/.git/hooks/pre-commit"
#!/bin/sh
echo "USER_HOOK_EXECUTED" >> hook_execution.log
USER_HOOK_EOF
chmod +x "$TEST_USER_HOOKS_WS/.git/hooks/pre-commit"

# Configure pre-commit in rnex.yaml
cat <<'CONFIG_YAML' > "$TEST_USER_HOOKS_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    pre-commit:
      - "echo 'RNEX_HOOK_EXECUTED' >> hook_execution.log"
repos:
plugins:
CONFIG_YAML

# Sync workspace: rnex sync should preserve custom hook as pre-commit.user
(cd "$TEST_USER_HOOKS_WS" && ./rnex sync --quiet)

[ -f "$TEST_USER_HOOKS_WS/.git/hooks/pre-commit.user" ] || {
  fail "custom user hook was not preserved as .git/hooks/pre-commit.user"; exit 1;
}
grep -q "USER_HOOK_EXECUTED" "$TEST_USER_HOOKS_WS/.git/hooks/pre-commit.user" || {
  fail "pre-commit.user did not contain user hook content"; exit 1;
}
grep -q "REPO-NEXUS-HOOK-WRAPPER" "$TEST_USER_HOOKS_WS/.git/hooks/pre-commit" || {
  fail ".git/hooks/pre-commit was not replaced with Repo Nexus wrapper"; exit 1;
}

# Execute hook wrapper and verify both rnex commands and user hook run
rm -f "$TEST_USER_HOOKS_WS/hook_execution.log"
(cd "$TEST_USER_HOOKS_WS" && .git/hooks/pre-commit)

[ -f "$TEST_USER_HOOKS_WS/hook_execution.log" ] || { fail "hook execution log was not created"; exit 1; }
grep -q "RNEX_HOOK_EXECUTED" "$TEST_USER_HOOKS_WS/hook_execution.log" || {
  fail "rnex hook command did not execute"; exit 1;
}
grep -q "USER_HOOK_EXECUTED" "$TEST_USER_HOOKS_WS/hook_execution.log" || {
  fail "preserved user hook was not chained/executed"; exit 1;
}

# Unconfigure pre-commit from rnex.yaml
cat <<'CLEAN_YAML' > "$TEST_USER_HOOKS_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    post-merge: []
repos:
plugins:
CLEAN_YAML

# Run rnex sync: stale pre-commit wrapper should be removed and pre-commit.user restored!
(cd "$TEST_USER_HOOKS_WS" && ./rnex sync --quiet)

[ ! -f "$TEST_USER_HOOKS_WS/.git/hooks/pre-commit.user" ] || {
  fail "pre-commit.user was not removed/restored after unconfiguring"; exit 1;
}
[ -x "$TEST_USER_HOOKS_WS/.git/hooks/pre-commit" ] || {
  fail ".git/hooks/pre-commit was not restored as executable"; exit 1;
}
grep -q "USER_HOOK_EXECUTED" "$TEST_USER_HOOKS_WS/.git/hooks/pre-commit" || {
  fail ".git/hooks/pre-commit does not contain original user hook content after restore"; exit 1;
}
! grep -q "REPO-NEXUS-HOOK-WRAPPER" "$TEST_USER_HOOKS_WS/.git/hooks/pre-commit" || {
  fail ".git/hooks/pre-commit still has wrapper marker after restore"; exit 1;
}
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
