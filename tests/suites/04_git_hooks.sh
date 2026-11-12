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
link_dir_contents "$DIR/plugins" "$TEST_HOOKS_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_HOOKS_WS/skills"
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
link_dir_contents "$DIR/plugins" "$TEST_INIT_HOOKS/plugins"
link_dir_contents "$DIR/skills" "$TEST_INIT_HOOKS/skills"
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
link_dir_contents "$DIR/plugins" "$TEST_LOCAL_HOOKS/plugins"
link_dir_contents "$DIR/skills" "$TEST_LOCAL_HOOKS/skills"
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
link_dir_contents "$DIR/plugins" "$TEST_WRAPPER_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_WRAPPER_WS/skills"
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
link_dir_contents "$DIR/plugins" "$TEST_RNEX_HOOKS_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_RNEX_HOOKS_WS/skills"
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
mkdir -p "$TEST_RNEX_HOOKS_WS/plugins/dummy-plugin"
cat <<'EOF_DUMMY_PL' > "$TEST_RNEX_HOOKS_WS/plugins/dummy-plugin/plugin.yaml"
name: dummy-plugin
version: 1.0.0
description: Synthetic plugin for hook testing
EOF_DUMMY_PL
(cd "$TEST_RNEX_HOOKS_WS" && ./rnex plugin enable dummy-plugin >/dev/null)
grep -q "BEFORE_PLUGIN_ENABLE" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "before_plugin_enable hook did not execute"; exit 1; }
grep -q "AFTER_PLUGIN_ENABLE" "$TEST_RNEX_HOOKS_WS/hook_log" || { fail "after_plugin_enable hook did not execute"; exit 1; }

# 7. Plugin disable
(cd "$TEST_RNEX_HOOKS_WS" && ./rnex plugin disable dummy-plugin >/dev/null)
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
link_dir_contents "$DIR/plugins" "$TEST_RNEX_LOCAL_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_RNEX_LOCAL_WS/skills"
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
link_dir_contents "$DIR/plugins" "$TEST_RNEX_BLOCK_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_RNEX_BLOCK_WS/skills"
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
link_dir_contents "$DIR/plugins" "$TEST_RNEX_RECURSE_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_RNEX_RECURSE_WS/skills"
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
link_dir_contents "$DIR/plugins" "$TEST_SYNC_HOOKS_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_SYNC_HOOKS_WS/skills"
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
link_dir_contents "$DIR/plugins" "$TEST_YAML_HOOKS_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_YAML_HOOKS_WS/skills"
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
link_dir_contents "$DIR/plugins" "$TEST_USER_HOOKS_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_USER_HOOKS_WS/skills"
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

# --------------------------------------------------------------------------
run_test "Lifecycle hooks: after_clone with bare 'rnex plugin llm-wiki ingest' and top-level / hooks: blocks"
TEST_AFTER_CLONE_WS="$TEST_TMP/after-clone-hook-ws"
mkdir -p "$TEST_AFTER_CLONE_WS"
cp "$CLI" "$TEST_AFTER_CLONE_WS/rnex"
chmod +x "$TEST_AFTER_CLONE_WS/rnex"
link_dir_contents "$DIR/plugins" "$TEST_AFTER_CLONE_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_AFTER_CLONE_WS/skills"
cp "$DIR/package.json" "$TEST_AFTER_CLONE_WS/package.json"
git -C "$TEST_AFTER_CLONE_WS" init -q

"$TEST_AFTER_CLONE_WS/rnex" init -y --llm-wiki "$TEST_AFTER_CLONE_WS" >/dev/null

# Top-level after_clone configuration (even when rnex_hooks: after_clone: [] also exists)
cat <<AFTER_CLONE_YAML > "$TEST_AFTER_CLONE_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    post-merge: []
rnex_hooks:
  after_clone: []
after_clone:
  - "rnex plugin llm-wiki ingest --quiet"
  - "echo 'AFTER_CLONE_INGEST_RAN' >> clone_hook_marker"
plugins:
  llm-wiki:
repos:
  dummy-svc:
    url: $TEST_DUMMY_REMOTE
    branch: master
AFTER_CLONE_YAML

# 1. Test rnex clone triggers after_clone with bare 'rnex' command
(cd "$TEST_AFTER_CLONE_WS" && ./rnex clone >/dev/null)
[ -f "$TEST_AFTER_CLONE_WS/clone_hook_marker" ] || { fail "after_clone did not run on rnex clone"; exit 1; }
[ -f "$TEST_AFTER_CLONE_WS/.rnex/wiki/repos-dummy-svc.md" ] || { fail "rnex plugin llm-wiki ingest did not run on after_clone"; exit 1; }
[ -f "$TEST_AFTER_CLONE_WS/.rnex/wiki/index.md" ] || { fail "wiki/index.md missing on after_clone"; exit 1; }
[ -f "$TEST_AFTER_CLONE_WS/.rnex/wiki/log.md" ] || { fail "wiki/log.md missing on after_clone"; exit 1; }
[ ! -d "$TEST_AFTER_CLONE_WS/.rnex/wiki/_graph" ] || { fail "wiki/_graph present on after_clone"; exit 1; }
[ ! -d "$TEST_AFTER_CLONE_WS/.rnex/wiki/_index" ] || { fail "wiki/_index present on after_clone"; exit 1; }
[ ! -e "$TEST_AFTER_CLONE_WS/.rnex/wiki/hot.md" ] || { fail "hot.md was created in after_clone test"; exit 1; }
[ ! -d "$TEST_AFTER_CLONE_WS/wiki" ] || { fail "legacy ./wiki was created in after_clone test"; exit 1; }

# 2. Test rnex repo add also triggers after_clone when cloning a new repository
rm -f "$TEST_AFTER_CLONE_WS/clone_hook_marker"
(cd "$TEST_AFTER_CLONE_WS" && ./rnex repo add "$TEST_DUMMY_REMOTE" --name added-svc --branch master >/dev/null)
[ -f "$TEST_AFTER_CLONE_WS/clone_hook_marker" ] || { fail "after_clone did not run on rnex repo add"; exit 1; }
[ -f "$TEST_AFTER_CLONE_WS/.rnex/wiki/repos-added-svc.md" ] || { fail "rnex plugin llm-wiki ingest did not ingest added-svc on after_clone"; exit 1; }
[ ! -e "$TEST_AFTER_CLONE_WS/.rnex/wiki/hot.md" ] || { fail "hot.md was created after repo add in after_clone test"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Hook recursion prevention: --ignore-hooks (-H) flag and transitive hook suppression"
TEST_IGNORE_HOOKS_WS="$TEST_TMP/ignore-hooks-ws"
mkdir -p "$TEST_IGNORE_HOOKS_WS"
cp "$CLI" "$TEST_IGNORE_HOOKS_WS/rnex"
chmod +x "$TEST_IGNORE_HOOKS_WS/rnex"
link_dir_contents "$DIR/plugins" "$TEST_IGNORE_HOOKS_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_IGNORE_HOOKS_WS/skills"
cp "$DIR/package.json" "$TEST_IGNORE_HOOKS_WS/package.json"
git -C "$TEST_IGNORE_HOOKS_WS" init -q

"$TEST_IGNORE_HOOKS_WS/rnex" init -y --llm-wiki "$TEST_IGNORE_HOOKS_WS" >/dev/null

cat <<'IGNORE_HOOKS_YAML' > "$TEST_IGNORE_HOOKS_WS/rnex.yaml"
version: 1.0.0
git:
  hooks:
    post-merge: []
rnex_hooks:
  before_sync:
    - "echo 'BEFORE_SYNC_FIRED' >> ignore_hook_log"
  after_sync:
    - "echo 'AFTER_SYNC_FIRED' >> ignore_hook_log"
    - "rnex plugin llm-wiki ingest --quiet"
  before_plugin_command:
    - "echo 'BEFORE_PLUGIN_CMD_FIRED' >> ignore_hook_log"
    - "rnex sync --quiet"
  after_plugin_command:
    - "echo 'AFTER_PLUGIN_CMD_FIRED' >> ignore_hook_log"
plugins:
  llm-wiki:
repos:
IGNORE_HOOKS_YAML

# 1. Explicit --ignore-hooks and -H must skip all user hooks
rm -f "$TEST_IGNORE_HOOKS_WS/ignore_hook_log"
(cd "$TEST_IGNORE_HOOKS_WS" && ./rnex sync --ignore-hooks --quiet)
[ ! -f "$TEST_IGNORE_HOOKS_WS/ignore_hook_log" ] || { fail "--ignore-hooks did not suppress hooks"; exit 1; }

(cd "$TEST_IGNORE_HOOKS_WS" && ./rnex -H sync --quiet)
[ ! -f "$TEST_IGNORE_HOOKS_WS/ignore_hook_log" ] || { fail "-H did not suppress hooks"; exit 1; }

# 2. Normal sync runs before_sync and after_sync, which calls 'rnex plugin llm-wiki ingest',
#    which must receive --ignore-hooks / RNEX_IGNORE_HOOKS=1 and NOT fire before_plugin_command or recurse into rnex sync!
(cd "$TEST_IGNORE_HOOKS_WS" && ./rnex sync --quiet)
[ -f "$TEST_IGNORE_HOOKS_WS/ignore_hook_log" ] || { fail "Normal sync did not fire hooks"; exit 1; }
grep -q "BEFORE_SYNC_FIRED" "$TEST_IGNORE_HOOKS_WS/ignore_hook_log" || { fail "before_sync missing from log"; exit 1; }
grep -q "AFTER_SYNC_FIRED" "$TEST_IGNORE_HOOKS_WS/ignore_hook_log" || { fail "after_sync missing from log"; exit 1; }
! grep -q "BEFORE_PLUGIN_CMD_FIRED" "$TEST_IGNORE_HOOKS_WS/ignore_hook_log" || {
  fail "Consequential command triggered by after_sync fired before_plugin_command (hook recursion!)"; exit 1;
}
_sync_cnt="$(grep -c "AFTER_SYNC_FIRED" "$TEST_IGNORE_HOOKS_WS/ignore_hook_log" || true)"
[ "$_sync_cnt" -eq 1 ] || { fail "after_sync fired $_sync_cnt times instead of 1"; exit 1; }
[ ! -d "$TEST_IGNORE_HOOKS_WS/wiki" ] || { fail "legacy ./wiki was created in ignore_hooks test"; exit 1; }
[ -f "$TEST_IGNORE_HOOKS_WS/.rnex/wiki/index.md" ] || { fail ".rnex/wiki/index.md was not created by ingest hook"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "rnex-hooks: strict opt-in parsing, after_sync stage dispatch, and zero execution when unconfigured"
# shellcheck source=lib/core.sh
. "$DIR/lib/core.sh"
# shellcheck source=lib/workspace.sh
. "$DIR/lib/workspace.sh"
# shellcheck source=lib/yaml.sh
. "$DIR/lib/yaml.sh"
# shellcheck source=lib/hooks.sh
. "$DIR/lib/hooks.sh"

TEST_STRICT_HOOKS_WS="$TEST_TMP/strict-opt-in-hooks-ws"
mkdir -p "$TEST_STRICT_HOOKS_WS"
cp "$CLI" "$TEST_STRICT_HOOKS_WS/rnex"
chmod +x "$TEST_STRICT_HOOKS_WS/rnex"
link_dir_contents "$DIR/plugins" "$TEST_STRICT_HOOKS_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_STRICT_HOOKS_WS/skills"
cp "$DIR/package.json" "$TEST_STRICT_HOOKS_WS/package.json"
git -C "$TEST_STRICT_HOOKS_WS" init -q

# 1. Workspace with rnex-hooks.after_sync and git.hooks.pre-commit
cat <<'STRICT_YAML' > "$TEST_STRICT_HOOKS_WS/rnex.yaml"
version: 1.0.0
rnex-hooks:
  pre_sync:
    - "echo 'PRE_SYNC_FIRED' >> strict_hook_log"
  after_sync:
    - "echo 'AFTER_SYNC_FIRED' >> strict_hook_log"
git:
  hooks:
    pre-commit:
      - "echo 'PRE_COMMIT'"
repos:
plugins:
STRICT_YAML

(cd "$TEST_STRICT_HOOKS_WS" && ./rnex sync --quiet)
[ -f "$TEST_STRICT_HOOKS_WS/strict_hook_log" ] || { fail "rnex-hooks log missing after sync"; exit 1; }
grep -q "PRE_SYNC_FIRED" "$TEST_STRICT_HOOKS_WS/strict_hook_log" || { fail "pre_sync did not fire"; exit 1; }
grep -q "AFTER_SYNC_FIRED" "$TEST_STRICT_HOOKS_WS/strict_hook_log" || { fail "after_sync did not fire"; exit 1; }
[ -x "$TEST_STRICT_HOOKS_WS/.git/hooks/pre-commit" ] || { fail "pre-commit git wrapper not installed"; exit 1; }
[ ! -f "$TEST_STRICT_HOOKS_WS/.git/hooks/post-merge" ] || { fail "post-merge git wrapper installed when omitted from config"; exit 1; }

# 2. Workspace with NO rnex-hooks and NO git.hooks must execute zero commands and install zero git wrappers
TEST_ZERO_HOOKS_WS="$TEST_TMP/zero-hooks-ws"
mkdir -p "$TEST_ZERO_HOOKS_WS"
cp "$CLI" "$TEST_ZERO_HOOKS_WS/rnex"
chmod +x "$TEST_ZERO_HOOKS_WS/rnex"
link_dir_contents "$DIR/plugins" "$TEST_ZERO_HOOKS_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_ZERO_HOOKS_WS/skills"
cp "$DIR/package.json" "$TEST_ZERO_HOOKS_WS/package.json"
git -C "$TEST_ZERO_HOOKS_WS" init -q

cat <<'ZERO_YAML' > "$TEST_ZERO_HOOKS_WS/rnex.yaml"
version: 1.0.0
repos:
plugins:
ZERO_YAML

(cd "$TEST_ZERO_HOOKS_WS" && ./rnex sync --quiet)
for _zh_h in pre-commit post-merge post-checkout post-commit pre-push; do
  [ ! -f "$TEST_ZERO_HOOKS_WS/.git/hooks/$_zh_h" ] || { fail "Git wrapper $_zh_h was installed in zero-hooks workspace"; exit 1; }
done
[ ! -f "$TEST_ZERO_HOOKS_WS/strict_hook_log" ] || { fail "Lifecycle command ran in zero-hooks workspace"; exit 1; }

# 3. Verify rnex_yaml_get_plugin_hook_events and rnex_yaml_get_plugin_hook_commands zero manifest fallback
_pevents="$(rnex_yaml_get_plugin_hook_events "$TEST_ZERO_HOOKS_WS" "claude" 2>/dev/null || true)"
[ -z "$_pevents" ] || { fail "rnex_yaml_get_plugin_hook_events returned manifest default hooks: $_pevents"; exit 1; }

_pcmds="$(rnex_yaml_get_plugin_hook_commands "$TEST_ZERO_HOOKS_WS" "claude" "SessionStart" 2>/dev/null || true)"
[ -z "$_pcmds" ] || { fail "rnex_yaml_get_plugin_hook_commands returned manifest default commands: $_pcmds"; exit 1; }

# 4. Verify explicit plugin hooks in rnex.yaml are correctly retrieved
cat <<'PLUGIN_HOOKS_YAML' > "$TEST_ZERO_HOOKS_WS/rnex.yaml"
version: 1.0.0
plugins:
  claude:
    hooks:
      SessionStart:
        - "rnex sync --quiet"
repos:
PLUGIN_HOOKS_YAML

_pevents_exp="$(rnex_yaml_get_plugin_hook_events "$TEST_ZERO_HOOKS_WS" "claude" 2>/dev/null || true)"
[ "$_pevents_exp" = "SessionStart" ] || { fail "Expected SessionStart, got: $_pevents_exp"; exit 1; }

_pcmds_exp="$(rnex_yaml_get_plugin_hook_commands "$TEST_ZERO_HOOKS_WS" "claude" "SessionStart" 2>/dev/null || true)"
[ "$_pcmds_exp" = "rnex sync --quiet" ] || { fail "Expected 'rnex sync --quiet', got: $_pcmds_exp"; exit 1; }

# Case-insensitive event query support
_pcmds_ci="$(rnex_yaml_get_plugin_hook_commands "$TEST_ZERO_HOOKS_WS" "claude" "sessionStart" 2>/dev/null || true)"
[ "$_pcmds_ci" = "rnex sync --quiet" ] || { fail "Expected 'rnex sync --quiet' via case-insensitive query, got: $_pcmds_ci"; exit 1; }

# 5. Local override in .local.rnex.yaml takes precedence
cat <<'LOCAL_OVERRIDE_YAML' > "$TEST_ZERO_HOOKS_WS/.local.rnex.yaml"
plugins:
  claude:
    hooks:
      SessionStart:
        - "echo 'LOCAL_CLAUDE_HOOK'"
rnex-hooks:
  after_sync:
    - "echo 'LOCAL_AFTER_SYNC' > local_after_sync_marker"
LOCAL_OVERRIDE_YAML

_pcmds_loc="$(rnex_yaml_get_plugin_hook_commands "$TEST_ZERO_HOOKS_WS" "claude" "SessionStart" 2>/dev/null || true)"
[ "$_pcmds_loc" = "echo 'LOCAL_CLAUDE_HOOK'" ] || { fail "Expected local override, got: $_pcmds_loc"; exit 1; }

(cd "$TEST_ZERO_HOOKS_WS" && ./rnex sync --quiet)
[ -f "$TEST_ZERO_HOOKS_WS/local_after_sync_marker" ] || { fail "Local after_sync hook did not execute"; exit 1; }
grep -q "LOCAL_AFTER_SYNC" "$TEST_ZERO_HOOKS_WS/local_after_sync_marker" || { fail "Marker missing LOCAL_AFTER_SYNC content"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 15: Zero default or hidden hooks invariant across all built-in plugins
# --------------------------------------------------------------------------
run_test "Lifecycle hooks: zero default or hidden hooks invariant across all built-in plugins"
TEST_ALL_ZERO_WS="$TEST_TMP/all-plugins-zero-hooks-ws"
mkdir -p "$TEST_ALL_ZERO_WS"
cp "$CLI" "$TEST_ALL_ZERO_WS/rnex"
chmod +x "$TEST_ALL_ZERO_WS/rnex"
link_dir_contents "$DIR/plugins" "$TEST_ALL_ZERO_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_ALL_ZERO_WS/skills"
cp "$DIR/package.json" "$TEST_ALL_ZERO_WS/package.json"
git -C "$TEST_ALL_ZERO_WS" init -q

# Initialize workspace with all plugins enabled, but ZERO hooks declared
mkdir -p "$TEST_ALL_ZERO_WS/docs"
printf '# Un-ingested Doc\nThis document must not be auto-ingested.\n' > "$TEST_ALL_ZERO_WS/docs/sample.md"

cat <<'ALL_ZERO_YAML' > "$TEST_ALL_ZERO_WS/rnex.yaml"
version: 1.0.0
plugins:
  claude:
    enabled: true
    skills: true
  codex:
    enabled: true
    skills: true
  cursor:
    enabled: true
    skills: true
  gemini:
    enabled: true
    skills: true
  copilot:
    enabled: true
    skills: true
  windsurf:
    enabled: true
    skills: true
  llm-wiki:
    enabled: true
    sources:
      - docs
repos:
ALL_ZERO_YAML

(cd "$TEST_ALL_ZERO_WS" && ./rnex sync --quiet)

# 1. Assert that ZERO provider hook files exist
[ ! -f "$TEST_ALL_ZERO_WS/.claude/settings.json" ] || { fail ".claude/settings.json created when zero hooks configured"; exit 1; }
[ ! -f "$TEST_ALL_ZERO_WS/.codex/hooks.json" ] || { fail ".codex/hooks.json created when zero hooks configured"; exit 1; }
[ ! -f "$TEST_ALL_ZERO_WS/.cursor/hooks.json" ] || { fail ".cursor/hooks.json created when zero hooks configured"; exit 1; }
[ ! -f "$TEST_ALL_ZERO_WS/.gemini/settings.json" ] || { fail ".gemini/settings.json created when zero hooks configured"; exit 1; }
[ ! -f "$TEST_ALL_ZERO_WS/.github/hooks/rnex.json" ] || { fail ".github/hooks/rnex.json created when zero hooks configured"; exit 1; }
[ ! -f "$TEST_ALL_ZERO_WS/.windsurf/hooks.json" ] || { fail ".windsurf/hooks.json created when zero hooks configured"; exit 1; }

# 2. Assert that llm-wiki ingest did NOT execute
[ ! -f "$TEST_ALL_ZERO_WS/.rnex/wiki/repo-nexus-docs.md" ] || { fail "llm-wiki auto-ingested docs without explicit hook"; exit 1; }
if [ -d "$TEST_ALL_ZERO_WS/.rnex/wiki" ]; then
  ! grep -q "Un-ingested Doc" "$TEST_ALL_ZERO_WS/.rnex/wiki"/*.md 2>/dev/null || {
    fail "Sample doc content found in wiki without explicit hook"; exit 1;
  }
fi

# 3. Assert that ZERO git hook wrappers were installed
for _zh_h in pre-commit post-merge post-checkout post-commit pre-push; do
  [ ! -f "$TEST_ALL_ZERO_WS/.git/hooks/$_zh_h" ] || { fail "Git wrapper $_zh_h installed without configuration"; exit 1; }
done
pass

# --------------------------------------------------------------------------
# Test 16: rnex-hooks: after_sync execution of llm-wiki ingest runs exactly once
# --------------------------------------------------------------------------
run_test "Lifecycle hooks: after_sync execution of llm-wiki ingest runs exactly once without recursion"
TEST_AFTER_SYNC_WS="$TEST_TMP/after-sync-ingest-ws"
mkdir -p "$TEST_AFTER_SYNC_WS"
cp "$CLI" "$TEST_AFTER_SYNC_WS/rnex"
chmod +x "$TEST_AFTER_SYNC_WS/rnex"
link_dir_contents "$DIR/plugins" "$TEST_AFTER_SYNC_WS/plugins"
link_dir_contents "$DIR/skills" "$TEST_AFTER_SYNC_WS/skills"
cp "$DIR/package.json" "$TEST_AFTER_SYNC_WS/package.json"
git -C "$TEST_AFTER_SYNC_WS" init -q

mkdir -p "$TEST_AFTER_SYNC_WS/docs"
printf '# Architecture Overview\nSystem architecture details.\n' > "$TEST_AFTER_SYNC_WS/docs/overview.md"

cat <<'AFTER_SYNC_YAML' > "$TEST_AFTER_SYNC_WS/rnex.yaml"
version: 1.0.0
rnex-hooks:
  after_sync:
    - "echo 'AFTER_SYNC_INVOCATION' >> after_sync_run.log"
    - "rnex plugin llm-wiki ingest"
plugins:
  llm-wiki:
    enabled: true
    sources:
      - docs
repos:
AFTER_SYNC_YAML

(cd "$TEST_AFTER_SYNC_WS" && ./rnex sync --quiet)

# Assert after_sync executed exactly once
[ -f "$TEST_AFTER_SYNC_WS/after_sync_run.log" ] || { fail "after_sync_run.log missing after sync"; exit 1; }
_invocations="$(wc -l < "$TEST_AFTER_SYNC_WS/after_sync_run.log" | tr -d ' ')"
[ "$_invocations" -eq 1 ] || { fail "Expected exactly 1 after_sync invocation, got: $_invocations"; exit 1; }

# Assert llm-wiki ingest executed deterministically
[ -f "$TEST_AFTER_SYNC_WS/.rnex/wiki/repo-nexus-docs.md" ] || { fail "repo-nexus-docs.md not created by after_sync ingest"; exit 1; }
grep -q "Architecture Overview" "$TEST_AFTER_SYNC_WS/.rnex/wiki/repo-nexus-docs.md" || {
  fail "Architecture Overview missing in repo-nexus-docs.md"; exit 1;
}

# Run sync a second time and assert exactly 2 invocations (one per sync, zero recursion)
(cd "$TEST_AFTER_SYNC_WS" && ./rnex sync --quiet)
_invocations2="$(wc -l < "$TEST_AFTER_SYNC_WS/after_sync_run.log" | tr -d ' ')"
[ "$_invocations2" -eq 2 ] || { fail "Expected exactly 2 after_sync invocations after second sync, got: $_invocations2"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Maintainer git hooks: merge and amend operations prevent double version bumps and tag updates"
TEST_MAINT_WS="$TEST_TMP/maintainer-hooks-ws"
mkdir -p "$TEST_MAINT_WS/scripts/githooks"
cp "$DIR/scripts/githooks"/* "$TEST_MAINT_WS/scripts/githooks/"
chmod +x "$TEST_MAINT_WS/scripts/githooks"/*
git -C "$TEST_MAINT_WS" init -q
git -C "$TEST_MAINT_WS" config core.hooksPath scripts/githooks

cat << 'EOF_PKG' > "$TEST_MAINT_WS/package.json"
{
  "name": "test-repo",
  "version": "1.0.0"
}
EOF_PKG
git -C "$TEST_MAINT_WS" add package.json
git -C "$TEST_MAINT_WS" commit -m "initial commit" >/dev/null

# 1. Normal commit must auto-bump patch version and create git tag
sleep 1
echo "feat 1" > "$TEST_MAINT_WS/f1.txt"
git -C "$TEST_MAINT_WS" add f1.txt
git -C "$TEST_MAINT_WS" commit -m "feat: file 1" >/dev/null
_v1="$(awk '/^[ ]*"version"[ ]*:[ ]*"[0-9]/ { sub(/.*"version"[ ]*:[ ]*"/, ""); sub(/".*/, ""); print; exit }' "$TEST_MAINT_WS/package.json")"
[ "$_v1" = "1.0.1" ] || { fail "Expected version 1.0.1 after normal commit, got: $_v1"; exit 1; }
git -C "$TEST_MAINT_WS" rev-parse -q --verify "refs/tags/v1.0.1" >/dev/null || { fail "Git tag v1.0.1 missing after normal commit"; exit 1; }

# 2. Amend commit must NOT bump version again and must update tag to point to amended commit
echo "feat 1 amended" > "$TEST_MAINT_WS/f1.txt"
git -C "$TEST_MAINT_WS" add f1.txt
git -C "$TEST_MAINT_WS" commit --amend -m "feat: file 1 amended" >/dev/null
_v_amend="$(awk '/^[ ]*"version"[ ]*:[ ]*"[0-9]/ { sub(/.*"version"[ ]*:[ ]*"/, ""); sub(/".*/, ""); print; exit }' "$TEST_MAINT_WS/package.json")"
[ "$_v_amend" = "1.0.1" ] || { fail "Amend incorrectly bumped version to: $_v_amend"; exit 1; }
_head_sha="$(git -C "$TEST_MAINT_WS" rev-parse HEAD)"
_tag_sha="$(git -C "$TEST_MAINT_WS" rev-parse -q --verify "refs/tags/v1.0.1^{commit}")"
[ "$_head_sha" = "$_tag_sha" ] || { fail "Tag v1.0.1 was not updated to amended HEAD commit"; exit 1; }

# 3. Merge commit must NEVER auto-bump version or create spurious release tags
git -C "$TEST_MAINT_WS" branch feature-branch
sleep 1
echo "master update" > "$TEST_MAINT_WS/master.txt"
git -C "$TEST_MAINT_WS" add master.txt
git -C "$TEST_MAINT_WS" commit -m "feat: master update" >/dev/null
_v_master="$(awk '/^[ ]*"version"[ ]*:[ ]*"[0-9]/ { sub(/.*"version"[ ]*:[ ]*"/, ""); sub(/".*/, ""); print; exit }' "$TEST_MAINT_WS/package.json")"
[ "$_v_master" = "1.0.2" ] || { fail "Expected version 1.0.2 on master commit, got: $_v_master"; exit 1; }

git -C "$TEST_MAINT_WS" checkout feature-branch >/dev/null 2>&1
sleep 1
echo "feature update" > "$TEST_MAINT_WS/feat.txt"
git -C "$TEST_MAINT_WS" add feat.txt
git -C "$TEST_MAINT_WS" commit -m "feat: feature update" >/dev/null
git -C "$TEST_MAINT_WS" checkout master >/dev/null 2>&1

git -C "$TEST_MAINT_WS" merge feature-branch -m "Merge feature branch" >/dev/null
_v_merge="$(awk '/^[ ]*"version"[ ]*:[ ]*"[0-9]/ { sub(/.*"version"[ ]*:[ ]*"/, ""); sub(/".*/, ""); print; exit }' "$TEST_MAINT_WS/package.json")"
[ "$_v_merge" = "1.0.2" ] || { fail "Merge incorrectly bumped version to: $_v_merge"; exit 1; }
! git -C "$TEST_MAINT_WS" rev-parse -q --verify "refs/tags/v1.0.3" >/dev/null 2>&1 || { fail "Merge created spurious tag v1.0.3"; exit 1; }
git -C "$TEST_MAINT_WS" diff --quiet package.json || { fail "package.json left dirty after merge commit"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
