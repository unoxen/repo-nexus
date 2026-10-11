#!/bin/sh
# ============================================================================
# tests/test_cli.sh — Automated Test Suite for rnex 2.0 (v0.4.0)
# ============================================================================
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$DIR/rnex"
export RNEX_LIB_DIR="$DIR/lib"
export PATH="$DIR:$PATH"

# Configure git identity for test repository commits
export GIT_AUTHOR_NAME="Test Runner"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test Runner"
export GIT_COMMITTER_EMAIL="test@example.com"

# Setup temporary sandbox for testing
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

TEST_WORKSPACE="$TEST_TMP/nexus-workspace"
TEST_REPO="$TEST_TMP/dummy-repo"
TEST_OUTSIDE="$TEST_TMP/outside-dir"

mkdir -p "$TEST_WORKSPACE" "$TEST_REPO/src" "$TEST_OUTSIDE"

# Initialize dummy target repo
echo 'console.log("hello world");' > "$TEST_REPO/src/app.js"
git -C "$TEST_REPO" init -q
git -C "$TEST_REPO" add .
git -C "$TEST_REPO" commit -m "init" -q

# Copy CLI to isolated test workspace
cp "$CLI" "$TEST_WORKSPACE/rnex"
chmod +x "$TEST_WORKSPACE/rnex"
if [ -f "$DIR/package.json" ]; then
  cp "$DIR/package.json" "$TEST_WORKSPACE/package.json"
fi
# Copy docs, toolkit, and lib for templates and built-in plugins
if [ -d "$DIR/lib" ]; then
  cp -r "$DIR/lib" "$TEST_WORKSPACE/lib"
fi
if [ -d "$DIR/docs" ]; then
  cp -r "$DIR/docs" "$TEST_WORKSPACE/docs"
fi
if [ -d "$DIR/toolkit" ]; then
  cp -r "$DIR/toolkit" "$TEST_WORKSPACE/toolkit"
fi

cd "$TEST_WORKSPACE"

PASS=0
FAIL=0
TOTAL=0

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
run_test "Re-init warns and suggests fix"
_reinit_output="$("$TEST_WORKSPACE/rnex" init -y "$TEST_WORKSPACE" 2>&1)"
echo "$_reinit_output" | grep -qi "already" || { fail "No already-initialized warning"; exit 1; }
echo "$_reinit_output" | grep -qi "fix" || { fail "No fix suggestion"; exit 1; }
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
run_test "Idempotent Fix (and sync alias)"
"$TEST_WORKSPACE/rnex" fix >/dev/null
[ -d "$TEST_WORKSPACE/repos/test-app/.rnex" ] || { fail ".rnex missing after fix"; exit 1; }
"$TEST_WORKSPACE/rnex" sync >/dev/null
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

# --------------------------------------------------------------------------
run_test "Plugin list command"
# Re-add test-app for plugin tests
"$TEST_WORKSPACE/rnex" add test-app "$TEST_REPO" >/dev/null
_plist_out="$("$TEST_WORKSPACE/rnex" plugin list 2>&1)"
echo "$_plist_out" | grep -q "karpathy-llm" || { fail "karpathy-llm not found in plugin list"; exit 1; }
echo "$_plist_out" | grep -q "available" || { fail "karpathy-llm not marked available"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Plugin info shows scoped directory"
_pinfo_out="$("$TEST_WORKSPACE/rnex" plugin info karpathy-llm 2>&1)"
echo "$_pinfo_out" | grep -q "karpathy-llm" || { fail "Plugin name missing from info"; exit 1; }
echo "$_pinfo_out" | grep -q "Scoped Directory" || { fail "Scoped Directory missing from info"; exit 1; }
echo "$_pinfo_out" | grep -q ".rnex/plugins/karpathy-llm" || { fail ".rnex/plugins/karpathy-llm missing from info"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Plugin enable command scopes assets to .rnex/plugins/karpathy-llm/"
"$TEST_WORKSPACE/rnex" plugin enable karpathy-llm >/dev/null
grep -q "karpathy-llm" "$TEST_WORKSPACE/rnex.yaml" || { fail "karpathy-llm not in rnex.yaml"; exit 1; }
[ -d "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm" ] || { fail "Scoped plugin dir missing in workspace"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm/rules/rnex-behavioral.md" ] || { fail "rnex-behavioral.md missing in scoped plugin dir"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm/instructions/rnex-wiki-architecture.md" ] || { fail "rnex-wiki-architecture.md missing in scoped plugin dir"; exit 1; }
[ -d "$TEST_WORKSPACE/repos/test-app/.rnex/plugins/karpathy-llm" ] || { fail "Scoped plugin dir missing in member repo"; exit 1; }
[ -f "$TEST_WORKSPACE/wiki/index.md" ] || { fail "wiki/index.md not initialized in workspace"; exit 1; }
grep -q "title: Wiki Index" "$TEST_WORKSPACE/wiki/index.md" || { fail "wiki/index.md missing title: Wiki Index"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Plugin disable command cleans up scoped plugin assets while preserving wiki"
"$TEST_WORKSPACE/rnex" plugin disable karpathy-llm >/dev/null
grep -q "karpathy-llm" "$TEST_WORKSPACE/rnex.yaml" && { fail "karpathy-llm still in rnex.yaml"; exit 1; }
[ ! -d "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm" ] || { fail "Scoped plugin dir still present in workspace"; exit 1; }
[ ! -d "$TEST_WORKSPACE/repos/test-app/.rnex/plugins/karpathy-llm" ] || { fail "Scoped plugin dir still present in member repo"; exit 1; }
[ -f "$TEST_WORKSPACE/wiki/index.md" ] || { fail "User wiki data was incorrectly deleted"; exit 1; }
pass

# --------------------------------------------------------------------------
# --------------------------------------------------------------------------
run_test "Routing-Only Instructions in AGENTS.md"
_agents_content="$(cat "$TEST_WORKSPACE/AGENTS.md")"
echo "$_agents_content" | grep -q "Read Configuration First" || { fail "AGENTS.md missing Read Configuration First"; exit 1; }
echo "$_agents_content" | grep -q ".local.rnex.yaml" || { fail "AGENTS.md missing .local.rnex.yaml"; exit 1; }
echo "$_agents_content" | grep -q "Highest Priority" || { fail "AGENTS.md missing Highest Priority notice"; exit 1; }
echo "$_agents_content" | grep -q ".rnex/plugins/<plugin-name>/" || { fail "AGENTS.md missing plugin routing"; exit 1; }
echo "$_agents_content" | grep -q "Routing Protocol for AI Assistants" || { fail "AGENTS.md missing Routing Protocol heading"; exit 1; }
! echo "$_agents_content" | grep -qi "symlink" || { fail "AGENTS.md should not contain symlink mentions"; exit 1; }
! echo "$_agents_content" | grep -q "Think Before Coding" || { fail "AGENTS.md should not contain inlined plugin rules"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Gitignore reconciliation removes legacy lint_trigger_counter and strips .rnex/"
printf '\n.rnex/.lint_trigger_counter\nwiki/.lint_trigger_counter\n.lint_trigger_counter\n.rnex/\n' >> "$TEST_WORKSPACE/.gitignore"
"$TEST_WORKSPACE/rnex" fix >/dev/null
grep -q "lint_trigger_counter" "$TEST_WORKSPACE/.gitignore" && { fail "Legacy lint_trigger_counter still present in .gitignore"; exit 1; }
! grep -q '^\.rnex/' "$TEST_WORKSPACE/.gitignore" || { fail ".rnex/ still present in .gitignore after fix"; exit 1; }
grep -q 'repos/\*' "$TEST_WORKSPACE/.gitignore" || { fail "repos/* missing from .gitignore after fix"; exit 1; }
grep -q '.local.rnex.yaml' "$TEST_WORKSPACE/.gitignore" || { fail ".local.rnex.yaml missing from .gitignore after fix"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Legacy un-delimited AGENTS.md with symlinks upgraded cleanly to routing protocol"
cat <<'LEGACY_EOF' > "$TEST_WORKSPACE/AGENTS.md"
# Multi-Repo AI Workspace Context

This workspace operates as a **Repo Nexus** linking multiple independent repositories via symlinks.

## Rules for AI Coding Assistants

1. **Workspace Structure & Settings**: AI coding assistants MUST inspect and read `rnex.yaml`.
2. **Symlink Write-Through**: Files edited under `repos/<name>/` directly modify the target repository.
3. **Plugin Instructions**: If plugins are enabled in `rnex.yaml` (under `plugins:`), AI coding assistants MUST read instructions.
LEGACY_EOF

"$TEST_WORKSPACE/rnex" fix >/dev/null
_upgraded_agents="$(cat "$TEST_WORKSPACE/AGENTS.md")"
echo "$_upgraded_agents" | grep -q "<!-- REPO-NEXUS:START -->" || { fail "Missing start delimiter after upgrade"; exit 1; }
echo "$_upgraded_agents" | grep -q "<!-- REPO-NEXUS:END -->" || { fail "Missing end delimiter after upgrade"; exit 1; }
echo "$_upgraded_agents" | grep -q "Routing Protocol for AI Assistants" || { fail "Missing Routing Protocol after upgrade"; exit 1; }
! echo "$_upgraded_agents" | grep -qi "symlink" || { fail "Upgraded AGENTS.md still contains symlink mentions"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Two-level config: add --local writes to .local.rnex.yaml"
_local_repo_dir="$TEST_TMP/local-repo"
mkdir -p "$_local_repo_dir/src"
git -C "$_local_repo_dir" init -q
git -C "$_local_repo_dir" add .
git -C "$_local_repo_dir" commit -m "init" -q --allow-empty

"$TEST_WORKSPACE/rnex" add --local local-app "$_local_repo_dir" >/dev/null
[ -f "$TEST_WORKSPACE/.local.rnex.yaml" ] || { fail ".local.rnex.yaml not created"; exit 1; }
grep -q "local-app" "$TEST_WORKSPACE/.local.rnex.yaml" || { fail "local-app not found in .local.rnex.yaml"; exit 1; }
! grep -q "local-app" "$TEST_WORKSPACE/rnex.yaml" || { fail "local-app should not be written to rnex.yaml"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Two-level config: disable --local overrides rnex.yaml"
"$TEST_WORKSPACE/rnex" disable --local test-app >/dev/null
grep -q "test-app:" "$TEST_WORKSPACE/.local.rnex.yaml" || { fail "test-app not in .local.rnex.yaml"; exit 1; }
grep -q "enabled:[ ]*false" "$TEST_WORKSPACE/.local.rnex.yaml" || { fail "enabled: false not set in .local.rnex.yaml"; exit 1; }
! grep -q "enabled:[ ]*false" "$TEST_WORKSPACE/rnex.yaml" || { fail "rnex.yaml was mutated by --local"; exit 1; }

# Verify list shows disabled
_list_chk="$("$TEST_WORKSPACE/rnex" list 2>&1)"
echo "$_list_chk" | grep "test-app" | grep -q "disabled" || { fail "test-app not recognized as disabled from local config"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Status highlights Git Ignore and Workspace AI Context"
_status_out="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_out" | grep -q "Git Ignore:" || { fail "Status did not show Git Ignore"; exit 1; }
echo "$_status_out" | grep -q "Workspace AI Context" || { fail "Status did not show AI Context"; exit 1; }
pass

# --------------------------------------------------------------------------
# --------------------------------------------------------------------------
run_test "Enabling provider plugin creates provider instructions instead of AGENTS.md"
# Enable gemini plugin in workspace
"$TEST_WORKSPACE/rnex" plugin enable gemini >/dev/null
[ -f "$TEST_WORKSPACE/GEMINI.md" ] || { fail "GEMINI.md was not created when gemini plugin enabled"; exit 1; }
grep -q "Multi-Repo AI Workspace Context" "$TEST_WORKSPACE/GEMINI.md" || { fail "GEMINI.md missing routing instructions"; exit 1; }
[ -d "$TEST_WORKSPACE/.gemini/prompts" ] || { fail ".gemini/prompts not created"; exit 1; }
# Remove AGENTS.md to simulate user wanting GEMINI.md instead of AGENTS.md
rm -f "$TEST_WORKSPACE/AGENTS.md"
"$TEST_WORKSPACE/rnex" fix >/dev/null
[ ! -f "$TEST_WORKSPACE/AGENTS.md" ] || { fail "rnex fix recreated AGENTS.md when gemini plugin is active"; exit 1; }
_status_fixed="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_fixed" | grep "GEMINI.md" | grep -q "Gemini instructions" || { fail "Status did not show GEMINI.md as Gemini instructions"; exit 1; }
# Disable gemini plugin; AGENTS.md should be restored as default
"$TEST_WORKSPACE/rnex" plugin disable gemini >/dev/null
[ ! -f "$TEST_WORKSPACE/GEMINI.md" ] || { fail "GEMINI.md was not removed after disabling plugin"; exit 1; }
[ -f "$TEST_WORKSPACE/AGENTS.md" ] || { fail "AGENTS.md was not restored after disabling provider plugin"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Init with --claude flag sets up Claude plugin and CLAUDE.md instead of AGENTS.md"
TEST_AI_WS="$TEST_TMP/ai-workspace"
mkdir -p "$TEST_AI_WS"
cp "$CLI" "$TEST_AI_WS/rnex"
chmod +x "$TEST_AI_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_AI_WS/toolkit"
"$TEST_AI_WS/rnex" init -y --claude "$TEST_AI_WS" >/dev/null
[ -f "$TEST_AI_WS/CLAUDE.md" ] || { fail "CLAUDE.md was not created by init --claude"; exit 1; }
[ ! -f "$TEST_AI_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created when --claude is used"; exit 1; }
grep -q "claude:" "$TEST_AI_WS/rnex.yaml" || { fail "claude plugin not enabled in rnex.yaml"; exit 1; }
! grep -q "ai_instructions:" "$TEST_AI_WS/rnex.yaml" || { fail "ai_instructions should not be present in rnex.yaml"; exit 1; }
grep -q "Multi-Repo AI Workspace Context" "$TEST_AI_WS/CLAUDE.md" || { fail "CLAUDE.md missing routing rules"; exit 1; }
[ -d "$TEST_AI_WS/.claude/commands" ] || { fail ".claude/commands not created"; exit 1; }
[ -f "$TEST_AI_WS/.claude/commands/rnex-cross-repo-feature.md" ] || { fail "rnex-cross-repo-feature.md missing in .claude/commands"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Configurable code_workspace generates and updates .code-workspace file"
echo "code_workspace: true" >> "$TEST_WORKSPACE/rnex.yaml"
_status_ws="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_ws" | grep -q "nexus-workspace.code-workspace" || { fail "Status did not detect configured code_workspace file"; exit 1; }
echo "$_status_ws" | grep -q "MISSING" || { fail "Status did not highlight missing code-workspace"; exit 1; }
"$TEST_WORKSPACE/rnex" fix >/dev/null
[ -f "$TEST_WORKSPACE/nexus-workspace.code-workspace" ] || { fail "code-workspace file was not created by fix"; exit 1; }
grep -q '"folders"' "$TEST_WORKSPACE/nexus-workspace.code-workspace" || { fail "folders array missing in workspace file"; exit 1; }
grep -q 'nexus-workspace (Workspace Root)' "$TEST_WORKSPACE/nexus-workspace.code-workspace" || { fail "Root folder missing in workspace file"; exit 1; }
grep -q 'local-app' "$TEST_WORKSPACE/nexus-workspace.code-workspace" || { fail "local-app missing in workspace file"; exit 1; }
# Re-enable test-app and verify code-workspace updates automatically
"$TEST_WORKSPACE/rnex" enable --local test-app >/dev/null
grep -q 'test-app' "$TEST_WORKSPACE/nexus-workspace.code-workspace" || { fail "test-app not added to workspace file upon enable"; exit 1; }
_status_ws_ok="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_ws_ok" | grep "nexus-workspace.code-workspace" | grep -q "VS Code / Cursor workspace" || { fail "Status did not mark workspace file valid"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Init with --code-workspace flag configures and creates workspace file"
TEST_VS_WS="$TEST_TMP/vscode-workspace"
mkdir -p "$TEST_VS_WS"
cp "$CLI" "$TEST_VS_WS/rnex"
chmod +x "$TEST_VS_WS/rnex"
"$TEST_VS_WS/rnex" init -y --code-workspace "$TEST_VS_WS" >/dev/null
[ -f "$TEST_VS_WS/vscode-workspace.code-workspace" ] || { fail ".code-workspace was not created by init --code-workspace"; exit 1; }
grep -q "code_workspace:[ ]*true" "$TEST_VS_WS/rnex.yaml" || { fail "code_workspace not enabled in rnex.yaml"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Version-aware upgrade in rnex fix and update/upgrade commands"
TEST_UPGRADE_WS="$TEST_TMP/upgrade-workspace"
mkdir -p "$TEST_UPGRADE_WS"
cp "$CLI" "$TEST_UPGRADE_WS/rnex"
chmod +x "$TEST_UPGRADE_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_UPGRADE_WS/toolkit"
cp "$DIR/package.json" "$TEST_UPGRADE_WS/package.json"

# Write older pre-v0.5.0 configuration (missing version & code_workspace)
cat <<'OLD_YAML' > "$TEST_UPGRADE_WS/rnex.yaml"
# Pre-versioned workspace configuration
repos_dir: ./repos
ai_instructions: AGENTS.md
plugins:
repos:
OLD_YAML

cat <<'OLD_AGENTS' > "$TEST_UPGRADE_WS/AGENTS.md"
<!-- REPO-NEXUS:START -->
# Multi-Repo AI Workspace Context
Legacy instructions without mandatory startup
<!-- REPO-NEXUS:END -->
OLD_AGENTS

# Fix with -y should detect missing/older version, upgrade config, and reconcile instructions
(cd "$TEST_UPGRADE_WS" && ./rnex fix -y >/dev/null)
_ws_cli_ver="$("$TEST_UPGRADE_WS/rnex" version 2>&1 | awk '{print $NF}')"
grep -q "version:[ ]*$_ws_cli_ver" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex fix -y did not add version $_ws_cli_ver to rnex.yaml"; exit 1; }
! grep -q "ai_instructions:" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "ai_instructions should be stripped during upgrade"; exit 1; }
grep -q "code_workspace:[ ]*false" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex fix -y did not populate missing code_workspace key"; exit 1; }
grep -q "git_hooks:[ ]*false" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex fix -y did not populate missing git_hooks key"; exit 1; }
grep -q "Mandatory Session Startup" "$TEST_UPGRADE_WS/AGENTS.md" || { fail "AGENTS.md not updated with Mandatory Session Startup"; exit 1; }
grep -q "\.rnex/prompts/index\.md" "$TEST_UPGRADE_WS/AGENTS.md" || { fail "AGENTS.md missing prompts catalog reference"; exit 1; }

# Running update when already at current version should report up to date
_up_out="$(cd "$TEST_UPGRADE_WS" && ./rnex update 2>&1)"
echo "$_up_out" | grep -q "already up to date" || { fail "rnex update did not report already up to date"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Standardized prompts synced to .rnex/prompts/ and indexed"
[ -d "$TEST_WORKSPACE/.rnex/prompts" ] || { fail ".rnex/prompts directory was not created"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/prompts/index.md" ] || { fail "prompts/index.md missing"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/prompts/rnex-cross-repo-feature.md" ] || { fail "rnex-cross-repo-feature.md missing"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/prompts/rnex-workspace-audit.md" ] || { fail "rnex-workspace-audit.md missing"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/prompts/rnex-wiki-ingest.md" ] || { fail "rnex-wiki-ingest.md missing"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/prompts/rnex-wiki-lint.md" ] || { fail "rnex-wiki-lint.md missing"; exit 1; }
# Verify member repos do not contain workspace prompts
[ ! -d "$TEST_WORKSPACE/repos/test-app/.rnex/prompts" ] || { fail "Workspace prompts leaked into member repo .rnex"; exit 1; }
# Verify status highlights prompts catalog
_status_prompts="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_prompts" | grep -q "prompts catalog" || { fail "Status does not highlight prompts catalog"; exit 1; }
pass

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

# Simulate someone manually configuring core.hooksPath, then rnex fix should uninstall it based on local override
git -C "$TEST_LOCAL_HOOKS" config core.hooksPath .rnex/hooks
mkdir -p "$TEST_LOCAL_HOOKS/.rnex/hooks"
(cd "$TEST_LOCAL_HOOKS" && ./rnex fix --quiet >/dev/null)
_reconciled_hp="$(git -C "$TEST_LOCAL_HOOKS" config --get core.hooksPath 2>/dev/null || true)"
[ -z "$_reconciled_hp" ] || { fail "rnex fix did not uninstall hooks when overridden by .local.rnex.yaml git_hooks: false"; exit 1; }

# Re-enable hooks locally (--local)
(cd "$TEST_LOCAL_HOOKS" && ./rnex hooks install --local >/dev/null)
grep -q "^git_hooks: true" "$TEST_LOCAL_HOOKS/.local.rnex.yaml" || { fail ".local.rnex.yaml missing git_hooks: true"; exit 1; }
_loc_hp2="$(git -C "$TEST_LOCAL_HOOKS" config --get core.hooksPath 2>/dev/null || true)"
[ "$_loc_hp2" = ".rnex/hooks" ] || { fail "hooks install --local did not set core.hooksPath"; exit 1; }

# Simulate someone manually unsetting core.hooksPath, then rnex fix should reinstall it based on config
git -C "$TEST_LOCAL_HOOKS" config --unset core.hooksPath
(cd "$TEST_LOCAL_HOOKS" && ./rnex fix --quiet >/dev/null)
_reconciled_hp2="$(git -C "$TEST_LOCAL_HOOKS" config --get core.hooksPath 2>/dev/null || true)"
pass

# --------------------------------------------------------------------------
run_test "Git hooks: custom wrapper preservation, self-rewrite avoidance, and .githooks chaining"
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

# Run fix to ensure custom wrapper is preserved
(cd "$TEST_WRAPPER_WS" && ./rnex fix --quiet >/dev/null)
grep -q "CUSTOM_WRAPPER_ACTIVE" "$TEST_WRAPPER_WS/.rnex/hooks/post-commit" || { fail "rnex fix overwrote custom wrapper in .rnex/hooks/post-commit"; exit 1; }

# 2. Existing .githooks chaining
mkdir -p "$TEST_WRAPPER_WS/.githooks"
cat <<GITHOOKS_EOF > "$TEST_WRAPPER_WS/.githooks/pre-commit"
#!/bin/sh
echo "CHAINED_GITHOOKS_PRE_COMMIT" > "$TEST_WRAPPER_WS/githooks_marker"
GITHOOKS_EOF
chmod +x "$TEST_WRAPPER_WS/.githooks/pre-commit"

(cd "$TEST_WRAPPER_WS" && ./rnex hooks run pre-commit >/dev/null)
[ -f "$TEST_WRAPPER_WS/githooks_marker" ] || { fail "rnex hooks run pre-commit did not chain to .githooks/pre-commit"; exit 1; }
grep -q "CHAINED_GITHOOKS_PRE_COMMIT" "$TEST_WRAPPER_WS/githooks_marker" || { fail "Chained .githooks/pre-commit did not execute properly"; exit 1; }

# 3. Avoidance of self-rewrite during hooks run post-merge
# shellcheck disable=SC2012
_inode_before="$(ls -i "$TEST_WRAPPER_WS/.rnex/hooks/post-merge" | awk '{print $1}')"
(cd "$TEST_WRAPPER_WS" && ./rnex hooks run post-merge >/dev/null)
# shellcheck disable=SC2012
_inode_after="$(ls -i "$TEST_WRAPPER_WS/.rnex/hooks/post-merge" | awk '{print $1}')"
[ "$_inode_before" = "$_inode_after" ] || { fail "post-merge hook was rewritten/replaced during hook execution (self-rewrite bug)"; exit 1; }
pass

# --------------------------------------------------------------------------
# --------------------------------------------------------------------------
run_test "Configurable GitHub Copilot plugin prompts and skills sync"
TEST_COPILOT_WS="$TEST_TMP/copilot-ws"
mkdir -p "$TEST_COPILOT_WS"
cp "$CLI" "$TEST_COPILOT_WS/rnex"
chmod +x "$TEST_COPILOT_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_COPILOT_WS/toolkit"
cp "$DIR/package.json" "$TEST_COPILOT_WS/package.json"
git -C "$TEST_COPILOT_WS" init -q

"$TEST_COPILOT_WS/rnex" init -y --copilot "$TEST_COPILOT_WS" >/dev/null
grep -q "copilot:" "$TEST_COPILOT_WS/rnex.yaml" || { fail "init --copilot did not write copilot plugin to rnex.yaml"; exit 1; }

# Verify .github/prompts/*.prompt.md files created with frontmatter
[ -d "$TEST_COPILOT_WS/.github/prompts" ] || { fail ".github/prompts directory missing"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "rnex-cross-repo-feature.prompt.md missing"; exit 1; }
grep -q "name: rnex-cross-repo-feature" "$TEST_COPILOT_WS/.github/prompts/rnex-cross-repo-feature.prompt.md" || { fail "Missing frontmatter in .prompt.md"; exit 1; }

# Verify .github/skills/rnex-*/SKILL.md created
[ -d "$TEST_COPILOT_WS/.github/skills/rnex-cross-repo-feature" ] || { fail "rnex-cross-repo-feature skill folder missing"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "rnex-cross-repo-feature SKILL.md missing"; exit 1; }
grep -q "name: rnex-cross-repo-feature" "$TEST_COPILOT_WS/.github/skills/rnex-cross-repo-feature/SKILL.md" || { fail "Missing frontmatter in SKILL.md"; exit 1; }

# Verify .github/copilot-instructions.md created
[ -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || { fail ".github/copilot-instructions.md missing"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || { fail "Missing REPO-NEXUS:START marker in copilot-instructions.md"; exit 1; }

# Verify plugin list and plugin info
_cop_list="$(cd "$TEST_COPILOT_WS" && ./rnex plugin list 2>&1)"
echo "$_cop_list" | grep -q "copilot" || { fail "plugin list did not list copilot plugin"; exit 1; }
_cop_info="$(cd "$TEST_COPILOT_WS" && ./rnex plugin info copilot 2>&1)"
echo "$_cop_info" | grep -q "prompts: true|false" || { fail "plugin info did not show prompts option"; exit 1; }
echo "$_cop_info" | grep -q "instructions: true|false" || { fail "plugin info did not show instructions option"; exit 1; }
echo "$_cop_info" | grep -q "agents: true|false" || { fail "plugin info did not show agents option"; exit 1; }

# Verify status highlights copilot plugin, options, and routing
_cop_status="$(cd "$TEST_COPILOT_WS" && ./rnex status 2>&1)"
echo "$_cop_status" | grep -q "copilot" || { fail "Status did not report copilot plugin"; exit 1; }
echo "$_cop_status" | grep -q ".github/prompts/" || { fail "Status did not report .github/prompts/"; exit 1; }
echo "$_cop_status" | grep -q ".github/copilot-instructions.md" || { fail "Status did not report .github/copilot-instructions.md"; exit 1; }
echo "$_cop_status" | grep -q "instructions=true" || { fail "Status did not report copilot instructions option"; exit 1; }

# Enable karpathy-llm alongside copilot to test decoupled cross-plugin mirroring
(cd "$TEST_COPILOT_WS" && ./rnex plugin enable karpathy-llm >/dev/null)
(cd "$TEST_COPILOT_WS" && ./rnex fix -y --quiet >/dev/null)

# Verify Karpathy prompts mirrored to .github/prompts/
[ -f "$TEST_COPILOT_WS/.github/prompts/rnex-wiki-ingest.prompt.md" ] || { fail "rnex-wiki-ingest prompt not mirrored to .github/prompts/"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/prompts/rnex-wiki-lint.prompt.md" ] || { fail "rnex-wiki-lint prompt not mirrored to .github/prompts/"; exit 1; }
grep -q "name: rnex-wiki-ingest" "$TEST_COPILOT_WS/.github/prompts/rnex-wiki-ingest.prompt.md" || { fail "rnex-wiki-ingest prompt missing frontmatter"; exit 1; }

# Verify Karpathy skills mirrored to .github/skills/
[ -f "$TEST_COPILOT_WS/.github/skills/rnex-wiki-ingest/SKILL.md" ] || { fail "rnex-wiki-ingest skill not mirrored to .github/skills/"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/skills/rnex-wiki-lint/SKILL.md" ] || { fail "rnex-wiki-lint skill not mirrored to .github/skills/"; exit 1; }

# Verify Karpathy agents mirrored to .github/agents/ and skills
[ -f "$TEST_COPILOT_WS/.github/agents/rnex-wiki-curator.agent.md" ] || { fail "rnex-wiki-curator agent not mirrored to .github/agents/"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/skills/rnex-wiki-curator/SKILL.md" ] || { fail "rnex-wiki-curator skill not mirrored to .github/skills/"; exit 1; }

# Verify Karpathy rules and instructions merged into .github/copilot-instructions.md
grep -q "Plugin: karpathy-llm" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || { fail "Karpathy guidelines missing from copilot-instructions.md"; exit 1; }

# Test preserving user custom content outside REPO-NEXUS delimiters in copilot-instructions.md
printf '# Custom Developer Section\n\n' | cat - "$TEST_COPILOT_WS/.github/copilot-instructions.md" > "$TEST_COPILOT_WS/.github/copilot-instructions.md.tmp"
mv "$TEST_COPILOT_WS/.github/copilot-instructions.md.tmp" "$TEST_COPILOT_WS/.github/copilot-instructions.md"
(cd "$TEST_COPILOT_WS" && ./rnex fix -y --quiet >/dev/null)
grep -q "Custom Developer Section" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || { fail "User custom content lost during copilot-instructions sync"; exit 1; }
grep -q "Plugin: karpathy-llm" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || { fail "Plugin instructions lost during copilot-instructions sync"; exit 1; }

# Granular option test: disable instructions only (prompts, skills, agents remain)
cat <<EOF > "$TEST_COPILOT_WS/rnex.yaml"
version: 0.5.6
repos_dir: ./repos
code_workspace: false
git_hooks: false
plugins:
  copilot:
    prompts: true
    skills: true
    instructions: false
    agents: true
  karpathy-llm: {}
repos:
EOF
(cd "$TEST_COPILOT_WS" && ./rnex fix -y --quiet >/dev/null)
grep -q "Custom Developer Section" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || { fail "Custom developer instructions lost when instructions: false"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_COPILOT_WS/.github/copilot-instructions.md" && { fail "REPO-NEXUS block not removed when instructions: false"; exit 1; }

# Granular option test: disable agents only
cat <<EOF > "$TEST_COPILOT_WS/rnex.yaml"
version: 0.5.6
repos_dir: ./repos
code_workspace: false
git_hooks: false
plugins:
  copilot:
    prompts: true
    skills: true
    instructions: false
    agents: false
  karpathy-llm: {}
repos:
EOF
(cd "$TEST_COPILOT_WS" && ./rnex fix -y --quiet >/dev/null)
[ ! -d "$TEST_COPILOT_WS/.github/agents" ] || { fail "Agents directory not cleaned up when agents: false"; exit 1; }

# Granular option test: disable prompts only (skills remain)
cat <<EOF > "$TEST_COPILOT_WS/rnex.yaml"
version: 0.5.6
repos_dir: ./repos
code_workspace: false
git_hooks: false
plugins:
  copilot:
    prompts: false
    skills: true
    instructions: false
    agents: false
  karpathy-llm: {}
repos:
EOF
(cd "$TEST_COPILOT_WS" && ./rnex fix -y --quiet >/dev/null)
[ ! -f "$TEST_COPILOT_WS/.github/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "Base prompts not cleaned up when prompts: false"; exit 1; }
[ ! -f "$TEST_COPILOT_WS/.github/prompts/rnex-wiki-ingest.prompt.md" ] || { fail "Plugin prompts not cleaned up when prompts: false"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "Skills removed when skills: true"; exit 1; }

# Add custom user skill, agent, and prompt to verify preservation
mkdir -p "$TEST_COPILOT_WS/.github/skills/user-custom-skill"
echo "# User Skill" > "$TEST_COPILOT_WS/.github/skills/user-custom-skill/SKILL.md"
mkdir -p "$TEST_COPILOT_WS/.github/agents"
echo "# User Agent" > "$TEST_COPILOT_WS/.github/agents/user-custom.agent.md"
mkdir -p "$TEST_COPILOT_WS/.github/prompts"
echo "# User Prompt" > "$TEST_COPILOT_WS/.github/prompts/user-custom.prompt.md"

# Disable copilot via local override and run fix
(cd "$TEST_COPILOT_WS" && ./rnex plugin disable --local copilot >/dev/null)
(cd "$TEST_COPILOT_WS" && ./rnex fix -y --quiet >/dev/null)
[ ! -f "$TEST_COPILOT_WS/.github/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "Prompts not cleaned up when copilot disabled locally"; exit 1; }
[ ! -d "$TEST_COPILOT_WS/.github/skills/rnex-cross-repo-feature" ] || { fail "Skills not cleaned up when copilot disabled locally"; exit 1; }
[ ! -f "$TEST_COPILOT_WS/.github/agents/rnex-wiki-curator.agent.md" ] || { fail "Plugin agents not cleaned up when copilot disabled locally"; exit 1; }

# Verify custom user skills, agents, and prompts are preserved
[ -f "$TEST_COPILOT_WS/.github/skills/user-custom-skill/SKILL.md" ] || { fail "User custom skill deleted when copilot disabled"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/agents/user-custom.agent.md" ] || { fail "User custom agent deleted when copilot disabled"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/prompts/user-custom.prompt.md" ] || { fail "User custom prompt deleted when copilot disabled"; exit 1; }

# Verify status reflects local disable
_cop_status_disabled="$(cd "$TEST_COPILOT_WS" && ./rnex status 2>&1)"
echo "$_cop_status_disabled" | grep -q "disabled locally" || { fail "Status did not report plugin disabled locally"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "AI provider plugins: Claude, Gemini, Cursor, Windsurf sync and cleanup"
TEST_PROVIDERS_WS="$TEST_TMP/providers-ws"
mkdir -p "$TEST_PROVIDERS_WS"
cp "$CLI" "$TEST_PROVIDERS_WS/rnex"
chmod +x "$TEST_PROVIDERS_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_PROVIDERS_WS/toolkit"
cp "$DIR/package.json" "$TEST_PROVIDERS_WS/package.json"
git -C "$TEST_PROVIDERS_WS" init -q

# Init workspace with claude flag
"$TEST_PROVIDERS_WS/rnex" init -y --claude "$TEST_PROVIDERS_WS" >/dev/null
[ -f "$TEST_PROVIDERS_WS/CLAUDE.md" ] || { fail "CLAUDE.md missing after init --claude"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created when claude plugin is enabled"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.claude/commands/rnex-cross-repo-feature.md" ] || { fail "Claude commands missing"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.claude/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "Claude skills missing"; exit 1; }

# Enable gemini plugin
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable gemini >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex fix -y --quiet >/dev/null)
[ -f "$TEST_PROVIDERS_WS/GEMINI.md" ] || { fail "GEMINI.md missing after enabling gemini"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.gemini/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "Gemini prompts missing"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.gemini/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "Gemini skills missing"; exit 1; }

# Enable cursor and windsurf plugins
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable cursor >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable windsurf >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex fix -y --quiet >/dev/null)
[ -f "$TEST_PROVIDERS_WS/.cursorrules" ] || { fail ".cursorrules missing after enabling cursor"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursor/rules/rnex-context.mdc" ] || { fail ".cursor/rules/rnex-context.mdc missing"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursor/prompts/rnex-cross-repo-feature.md" ] || { fail "Cursor prompts missing"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursor/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "Cursor skills missing"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.windsurfrules" ] || { fail ".windsurfrules missing after enabling windsurf"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.windsurf/prompts/rnex-cross-repo-feature.md" ] || { fail "Windsurf prompts missing"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.windsurf/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "Windsurf skills missing"; exit 1; }

# Status command reports all enabled AI providers
_prov_status="$(cd "$TEST_PROVIDERS_WS" && ./rnex status 2>&1)"
echo "$_prov_status" | grep -q "CLAUDE.md" || { fail "Status did not report CLAUDE.md"; exit 1; }
echo "$_prov_status" | grep -q "GEMINI.md" || { fail "Status did not report GEMINI.md"; exit 1; }
echo "$_prov_status" | grep -q "\.cursorrules" || { fail "Status did not report .cursorrules"; exit 1; }
echo "$_prov_status" | grep -q "\.windsurfrules" || { fail "Status did not report .windsurfrules"; exit 1; }

# Test user custom content preservation across provider instructions
printf "# Custom Section\n" >> "$TEST_PROVIDERS_WS/CLAUDE.md"
printf "# Gemini Custom\n" >> "$TEST_PROVIDERS_WS/GEMINI.md"
printf "# Cursor Custom\n" >> "$TEST_PROVIDERS_WS/.cursorrules"
printf "# Windsurf Custom\n" >> "$TEST_PROVIDERS_WS/.windsurfrules"
(cd "$TEST_PROVIDERS_WS" && ./rnex fix -y --quiet >/dev/null)
grep -q "# Custom Section" "$TEST_PROVIDERS_WS/CLAUDE.md" || { fail "Custom section lost in CLAUDE.md"; exit 1; }
grep -q "# Gemini Custom" "$TEST_PROVIDERS_WS/GEMINI.md" || { fail "Custom section lost in GEMINI.md"; exit 1; }
grep -q "# Cursor Custom" "$TEST_PROVIDERS_WS/.cursorrules" || { fail "Custom section lost in .cursorrules"; exit 1; }
grep -q "# Windsurf Custom" "$TEST_PROVIDERS_WS/.windsurfrules" || { fail "Custom section lost in .windsurfrules"; exit 1; }

# Add custom user skills, prompts, agents, and extra files across all providers
mkdir -p "$TEST_PROVIDERS_WS/.claude/skills/my-claude-skill"
echo "custom" > "$TEST_PROVIDERS_WS/.claude/skills/my-claude-skill/SKILL.md"
mkdir -p "$TEST_PROVIDERS_WS/.claude/skills/rnex-cross-repo-feature"
echo "extra user file" > "$TEST_PROVIDERS_WS/.claude/skills/rnex-cross-repo-feature/extra.txt"
mkdir -p "$TEST_PROVIDERS_WS/.claude/commands"
echo "custom" > "$TEST_PROVIDERS_WS/.claude/commands/my-cmd.md"
mkdir -p "$TEST_PROVIDERS_WS/.claude/agents"
echo "custom" > "$TEST_PROVIDERS_WS/.claude/agents/my-agent.md"

mkdir -p "$TEST_PROVIDERS_WS/.gemini/skills/my-gemini-skill"
echo "custom" > "$TEST_PROVIDERS_WS/.gemini/skills/my-gemini-skill/SKILL.md"
mkdir -p "$TEST_PROVIDERS_WS/.gemini/prompts"
echo "custom" > "$TEST_PROVIDERS_WS/.gemini/prompts/my-prompt.prompt.md"
mkdir -p "$TEST_PROVIDERS_WS/.gemini/agents"
echo "custom" > "$TEST_PROVIDERS_WS/.gemini/agents/my-agent.md"

mkdir -p "$TEST_PROVIDERS_WS/.cursor/skills/my-cursor-skill"
echo "custom" > "$TEST_PROVIDERS_WS/.cursor/skills/my-cursor-skill/SKILL.md"
mkdir -p "$TEST_PROVIDERS_WS/.cursor/prompts"
echo "custom" > "$TEST_PROVIDERS_WS/.cursor/prompts/my-prompt.md"
mkdir -p "$TEST_PROVIDERS_WS/.cursor/agents"
echo "custom" > "$TEST_PROVIDERS_WS/.cursor/agents/my-agent.md"
mkdir -p "$TEST_PROVIDERS_WS/.cursor/rules"
echo "custom" > "$TEST_PROVIDERS_WS/.cursor/rules/my-user-rule.mdc"

mkdir -p "$TEST_PROVIDERS_WS/.windsurf/skills/my-windsurf-skill"
echo "custom" > "$TEST_PROVIDERS_WS/.windsurf/skills/my-windsurf-skill/SKILL.md"
mkdir -p "$TEST_PROVIDERS_WS/.windsurf/prompts"
echo "custom" > "$TEST_PROVIDERS_WS/.windsurf/prompts/my-prompt.md"
mkdir -p "$TEST_PROVIDERS_WS/.windsurf/agents"
echo "custom" > "$TEST_PROVIDERS_WS/.windsurf/agents/my-agent.md"

# Disable all provider plugins and verify AGENTS.md restored as fallback default
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable claude >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable gemini >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable cursor >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable windsurf >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex fix -y --quiet >/dev/null)

[ -f "$TEST_PROVIDERS_WS/AGENTS.md" ] || { fail "AGENTS.md not restored when all AI provider plugins disabled"; exit 1; }

# Verify Repo Nexus generated assets were cleaned up
[ ! -f "$TEST_PROVIDERS_WS/.claude/commands/rnex-cross-repo-feature.md" ] || { fail "rnex prompt not cleaned from claude"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.claude/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "rnex skill not cleaned from claude"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.gemini/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "rnex prompt not cleaned from gemini"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.gemini/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "rnex skill not cleaned from gemini"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.cursor/rules/rnex-context.mdc" ] || { fail "rnex-context.mdc not cleaned from cursor"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.cursor/prompts/rnex-cross-repo-feature.md" ] || { fail "rnex prompt not cleaned from cursor"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.cursor/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "rnex skill not cleaned from cursor"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.windsurf/prompts/rnex-cross-repo-feature.md" ] || { fail "rnex prompt not cleaned from windsurf"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.windsurf/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "rnex skill not cleaned from windsurf"; exit 1; }

# Verify ALL user custom files were preserved
[ -f "$TEST_PROVIDERS_WS/.claude/skills/my-claude-skill/SKILL.md" ] || { fail "User skill deleted from .claude"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.claude/skills/rnex-cross-repo-feature/extra.txt" ] || { fail "User extra file in skill dir deleted from .claude"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.claude/commands/my-cmd.md" ] || { fail "User command deleted from .claude"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.claude/agents/my-agent.md" ] || { fail "User agent deleted from .claude"; exit 1; }

[ -f "$TEST_PROVIDERS_WS/.gemini/skills/my-gemini-skill/SKILL.md" ] || { fail "User skill deleted from .gemini"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.gemini/prompts/my-prompt.prompt.md" ] || { fail "User prompt deleted from .gemini"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.gemini/agents/my-agent.md" ] || { fail "User agent deleted from .gemini"; exit 1; }

[ -f "$TEST_PROVIDERS_WS/.cursor/rules/my-user-rule.mdc" ] || { fail "User rule deleted from .cursor"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursor/skills/my-cursor-skill/SKILL.md" ] || { fail "User skill deleted from .cursor"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursor/prompts/my-prompt.md" ] || { fail "User prompt deleted from .cursor"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursor/agents/my-agent.md" ] || { fail "User agent deleted from .cursor"; exit 1; }

[ -f "$TEST_PROVIDERS_WS/.windsurf/skills/my-windsurf-skill/SKILL.md" ] || { fail "User skill deleted from .windsurf"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.windsurf/prompts/my-prompt.md" ] || { fail "User prompt deleted from .windsurf"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.windsurf/agents/my-agent.md" ] || { fail "User agent deleted from .windsurf"; exit 1; }

# Instruction files retained custom user content but stripped REPO-NEXUS block
for _f in CLAUDE.md GEMINI.md .cursorrules .windsurfrules; do
  [ -f "$TEST_PROVIDERS_WS/$_f" ] || { fail "$_f with custom content was deleted"; exit 1; }
  ! grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/$_f" || { fail "REPO-NEXUS block not stripped from $_f"; exit 1; }
done
grep -q "# Custom Section" "$TEST_PROVIDERS_WS/CLAUDE.md" || { fail "Custom content lost from CLAUDE.md"; exit 1; }
grep -q "# Gemini Custom" "$TEST_PROVIDERS_WS/GEMINI.md" || { fail "Custom content lost from GEMINI.md"; exit 1; }
grep -q "# Cursor Custom" "$TEST_PROVIDERS_WS/.cursorrules" || { fail "Custom content lost from .cursorrules"; exit 1; }
grep -q "# Windsurf Custom" "$TEST_PROVIDERS_WS/.windsurfrules" || { fail "Custom content lost from .windsurfrules"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Deterministic plugin installation, verification, and updates"
TEST_DET_WS="$TEST_TMP/deterministic-plugin-ws"
mkdir -p "$TEST_DET_WS"
cp "$CLI" "$TEST_DET_WS/rnex"
chmod +x "$TEST_DET_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_DET_WS/toolkit"
cp "$DIR/package.json" "$TEST_DET_WS/package.json"
git -C "$TEST_DET_WS" init -q

"$TEST_DET_WS/rnex" init -y "$TEST_DET_WS" >/dev/null

# 1. Verify all 6 plugins are available with consistent v0.5.1
_list_out="$(cd "$TEST_DET_WS" && ./rnex plugin list 2>&1)"
for _p in claude copilot cursor gemini karpathy-llm windsurf; do
  echo "$_list_out" | grep -q "$_p" || { fail "Plugin $_p not in plugin list"; exit 1; }
  echo "$_list_out" | grep "$_p" | grep -q "(v0.5.1)" || { fail "Plugin $_p is not v0.5.1"; exit 1; }
done

# 2. Test 'rnex plugin install <name>' alias for enable
(cd "$TEST_DET_WS" && ./rnex plugin install copilot >/dev/null)
[ -d "$TEST_DET_WS/.rnex/plugins/copilot" ] || { fail "Plugin install did not create .rnex/plugins/copilot"; exit 1; }
[ -f "$TEST_DET_WS/.rnex/plugins/copilot/instructions/rnex-copilot-integration.md" ] || { fail "rnex-copilot-integration.md missing"; exit 1; }

# 3. Test deterministic update: inject a stale file into the installed plugin
touch "$TEST_DET_WS/.rnex/plugins/copilot/instructions/stale-artifact.md"
[ -f "$TEST_DET_WS/.rnex/plugins/copilot/instructions/stale-artifact.md" ] || { fail "Failed to create test stale file"; exit 1; }

# 4. Run 'rnex plugin update copilot' and verify stale artifact was deterministically purged
(cd "$TEST_DET_WS" && ./rnex plugin update copilot >/dev/null)
[ ! -f "$TEST_DET_WS/.rnex/plugins/copilot/instructions/stale-artifact.md" ] || { fail "Stale artifact was not purged during deterministic plugin update"; exit 1; }
[ -f "$TEST_DET_WS/.rnex/plugins/copilot/instructions/rnex-copilot-integration.md" ] || { fail "rnex-copilot-integration.md missing after update"; exit 1; }

# 5. Run global 'rnex plugin update'
(cd "$TEST_DET_WS" && ./rnex plugin update >/dev/null)
[ -f "$TEST_DET_WS/.rnex/plugins/copilot/plugin.yaml" ] || { fail "plugin.yaml missing after global plugin update"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy LLM Wiki plugin with configurable raw_dir and wiki_dir in rnex config"
TEST_KWIKI_WS="$TEST_TMP/karpathy-custom-wiki-ws"
mkdir -p "$TEST_KWIKI_WS"
cp "$CLI" "$TEST_KWIKI_WS/rnex"
chmod +x "$TEST_KWIKI_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_KWIKI_WS/toolkit"
cp "$DIR/package.json" "$TEST_KWIKI_WS/package.json"
git -C "$TEST_KWIKI_WS" init -q

"$TEST_KWIKI_WS/rnex" init -y "$TEST_KWIKI_WS" >/dev/null

# Configure custom wiki_dir and raw_dir in rnex.yaml
cat <<'EOF_CFG' >> "$TEST_KWIKI_WS/rnex.yaml"
plugins:
  karpathy-llm:
    wiki_dir: docs/wiki
    raw_dir: intake/raw
    lint_trigger: git-post-commit
    notify_on_changes: true
EOF_CFG

# Reconcile via rnex fix to initialize plugin templates with custom paths
(cd "$TEST_KWIKI_WS" && ./rnex fix >/dev/null)

# Verify custom directories are created instead of default raw/ and wiki/
[ -d "$TEST_KWIKI_WS/docs/wiki" ] || { fail "Custom docs/wiki directory was not created"; exit 1; }
[ -d "$TEST_KWIKI_WS/intake/raw" ] || { fail "Custom intake/raw directory was not created"; exit 1; }
[ ! -d "$TEST_KWIKI_WS/wiki" ] || { fail "Default wiki/ was created despite custom wiki_dir"; exit 1; }
[ ! -d "$TEST_KWIKI_WS/raw" ] || { fail "Default raw/ was created despite custom raw_dir"; exit 1; }

# Verify control files exist in custom directories
[ -f "$TEST_KWIKI_WS/docs/wiki/index.md" ] || { fail "docs/wiki/index.md missing"; exit 1; }
[ -f "$TEST_KWIKI_WS/docs/wiki/hot.md" ] || { fail "docs/wiki/hot.md missing"; exit 1; }
[ -f "$TEST_KWIKI_WS/docs/wiki/_log.md" ] || { fail "docs/wiki/_log.md missing"; exit 1; }
[ -f "$TEST_KWIKI_WS/intake/raw/.gitkeep" ] || { fail "intake/raw/.gitkeep missing"; exit 1; }

# Verify template substitutions reflect custom paths
grep -q "/intake/raw/" "$TEST_KWIKI_WS/docs/wiki/index.md" || { fail "docs/wiki/index.md does not reference custom intake/raw/"; exit 1; }
grep -q "/intake/raw/" "$TEST_KWIKI_WS/docs/wiki/hot.md" || { fail "docs/wiki/hot.md does not reference custom intake/raw/"; exit 1; }
grep -q "/docs/wiki/" "$TEST_KWIKI_WS/docs/wiki/hot.md" || { fail "docs/wiki/hot.md does not reference custom docs/wiki/"; exit 1; }

# Verify AGENTS.md routing reflects custom wiki_dir
_kw_agents="$(cat "$TEST_KWIKI_WS/AGENTS.md")"
echo "$_kw_agents" | grep -q "docs/wiki/" || { fail "AGENTS.md routing does not reference custom docs/wiki/"; exit 1; }
echo "$_kw_agents" | grep -q "docs/wiki/hot.md" || { fail "AGENTS.md routing does not reference custom docs/wiki/hot.md"; exit 1; }

# Verify plugin info reports custom options and template mappings
_kw_info="$(cd "$TEST_KWIKI_WS" && ./rnex plugin info karpathy-llm 2>&1)"
echo "$_kw_info" | grep -q "current: docs/wiki" || { fail "plugin info did not report custom wiki_dir"; exit 1; }
echo "$_kw_info" | grep -q "current: intake/raw" || { fail "plugin info did not report custom raw_dir"; exit 1; }
echo "$_kw_info" | grep -q "docs/wiki/index.md" || { fail "plugin info did not report template mapped to docs/wiki/index.md"; exit 1; }
echo "$_kw_info" | grep -q "intake/raw/.gitkeep" || { fail "plugin info did not report template mapped to intake/raw/.gitkeep"; exit 1; }

# Verify Git hooks trigger detects custom paths
git -C "$TEST_KWIKI_WS" config user.email "test@example.com"
git -C "$TEST_KWIKI_WS" config user.name "Test User"
git -C "$TEST_KWIKI_WS" add .
git -C "$TEST_KWIKI_WS" commit -qm "Initial commit"
echo "sample research" > "$TEST_KWIKI_WS/intake/raw/paper.md"
git -C "$TEST_KWIKI_WS" add intake/raw/paper.md
git -C "$TEST_KWIKI_WS" commit -qm "Add intake document"
_hook_output="$(cd "$TEST_KWIKI_WS" && ./rnex hooks run post-commit 2>&1)"
echo "$_hook_output" | grep -q "intake/raw/ or docs/wiki/" || { fail "Git hook post-commit did not detect commit to intake/raw/: $_hook_output"; exit 1; }
pass

# ==========================================================================

echo ""
echo "===================================="
if [ "$FAIL" -eq 0 ]; then
  echo "  All $TOTAL Automated Tests Passed! ✓"
else
  echo "  $PASS/$TOTAL passed, $FAIL FAILED"
fi
echo "===================================="

[ "$FAIL" -eq 0 ] || exit 1
