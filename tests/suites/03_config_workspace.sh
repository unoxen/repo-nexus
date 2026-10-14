#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/03_config_workspace.sh — Configuration & Workspace Rules (Tests 17-27)
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/tests/test_helper.sh"
setup_test_workspace
cd "$TEST_WORKSPACE"

# Ensure test-app and workspace initialized if run standalone
if [ ! -f "$TEST_WORKSPACE/rnex.yaml" ]; then
  "$TEST_WORKSPACE/rnex" init -y "$TEST_WORKSPACE" >/dev/null
fi
if ! grep -q "test-app:" "$TEST_WORKSPACE/rnex.yaml" 2>/dev/null; then
  "$TEST_WORKSPACE/rnex" add test-app "$TEST_REPO" >/dev/null
fi

# --------------------------------------------------------------------------
run_test "Gitignore reconciliation removes legacy lint_trigger_counter and strips .rnex/"
printf '\n.rnex/.lint_trigger_counter\nwiki/.lint_trigger_counter\n.lint_trigger_counter\n.rnex/\n' >> "$TEST_WORKSPACE/.gitignore"
"$TEST_WORKSPACE/rnex" fix >/dev/null
grep -q "lint_trigger_counter" "$TEST_WORKSPACE/.gitignore" && { fail "Legacy lint_trigger_counter still present in .gitignore"; exit 1; }
! grep -q '^\.rnex/' "$TEST_WORKSPACE/.gitignore" || { fail ".rnex/ still present in .gitignore after fix"; exit 1; }
grep -q 'repos/\*' "$TEST_WORKSPACE/.gitignore" || { fail "repos/* missing from .gitignore after fix"; exit 1; }
grep -q '.local.rnex.yaml' "$TEST_WORKSPACE/.gitignore" || { fail ".local.rnex.yaml missing from .gitignore after fix"; exit 1; }
[ -f "$TEST_WORKSPACE/.ignore" ] || { fail ".ignore missing after fix"; exit 1; }
grep -q '!repos/\*' "$TEST_WORKSPACE/.ignore" || { fail "!repos/* missing from .ignore after fix"; exit 1; }
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
run_test "Enabling provider plugin creates instruction file, preserves AGENTS.md, and mirrors prompts only"
# Enable gemini plugin in workspace
"$TEST_WORKSPACE/rnex" plugin enable gemini >/dev/null
[ -f "$TEST_WORKSPACE/AGENTS.md" ] || { fail "AGENTS.md missing when gemini enabled"; exit 1; }
[ -f "$TEST_WORKSPACE/GEMINI.md" ] || { fail "GEMINI.md missing when gemini enabled"; exit 1; }
[ ! -d "$TEST_WORKSPACE/.gemini/skills" ] || { fail ".gemini/skills should not be created"; exit 1; }
[ -d "$TEST_WORKSPACE/.gemini/prompts" ] || { fail ".gemini/prompts not created"; exit 1; }
[ -f "$TEST_WORKSPACE/.gemini/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "rnex-cross-repo-feature missing in .gemini/prompts"; exit 1; }
_status_fixed="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_fixed" | grep -q "AGENTS.md" || { fail "Status did not show AGENTS.md"; exit 1; }
echo "$_status_fixed" | grep -q "GEMINI.md" || { fail "Status did not show GEMINI.md"; exit 1; }
echo "$_status_fixed" | grep -q ".gemini/prompts/" || { fail "Status did not show .gemini/prompts/"; exit 1; }
# Disable gemini plugin; AGENTS.md should remain intact, GEMINI.md cleaned, and prompts cleaned up
"$TEST_WORKSPACE/rnex" plugin disable gemini >/dev/null
[ ! -f "$TEST_WORKSPACE/GEMINI.md" ] || { fail "GEMINI.md was not cleaned up"; exit 1; }
[ -f "$TEST_WORKSPACE/AGENTS.md" ] || { fail "AGENTS.md was removed after disabling provider plugin"; exit 1; }
[ ! -f "$TEST_WORKSPACE/.gemini/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "Prompts not cleaned up after disabling gemini"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Init with --claude flag sets up Claude plugin, universal AGENTS.md, CLAUDE.md, and mirrors prompts only"
TEST_AI_WS="$TEST_TMP/ai-workspace"
mkdir -p "$TEST_AI_WS"
cp "$CLI" "$TEST_AI_WS/rnex"
chmod +x "$TEST_AI_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_AI_WS/toolkit"
"$TEST_AI_WS/rnex" init -y --claude "$TEST_AI_WS" >/dev/null
[ -f "$TEST_AI_WS/AGENTS.md" ] || { fail "AGENTS.md missing after init --claude"; exit 1; }
[ -f "$TEST_AI_WS/CLAUDE.md" ] || { fail "CLAUDE.md missing after init --claude"; exit 1; }
[ ! -d "$TEST_AI_WS/.claude/skills" ] || { fail ".claude/skills should not be created"; exit 1; }
grep -q "claude:" "$TEST_AI_WS/rnex.yaml" || { fail "claude plugin not enabled in rnex.yaml"; exit 1; }
! grep -q "ai_instructions:" "$TEST_AI_WS/rnex.yaml" || { fail "ai_instructions should not be present in rnex.yaml"; exit 1; }
grep -q "Multi-Repo AI Workspace Context" "$TEST_AI_WS/AGENTS.md" || { fail "AGENTS.md missing routing rules"; exit 1; }
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
run_test "Version-aware upgrade in rnex sync --fix and update/upgrade commands"
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

# rnex sync without --fix should detect version inconsistency without mutating
_sync_audit="$(cd "$TEST_UPGRADE_WS" && ./rnex sync 2>&1 || true)"
echo "$_sync_audit" | grep -q "older than CLI" || { fail "rnex sync did not audit version mismatch"; exit 1; }
grep -q "ai_instructions:" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex sync without --fix mutated rnex.yaml"; exit 1; }

# Fix with -y should detect missing/older version, upgrade config, and reconcile instructions
(cd "$TEST_UPGRADE_WS" && ./rnex sync --fix -y >/dev/null)
_ws_cli_ver="$("$TEST_UPGRADE_WS/rnex" version 2>&1 | awk '{print $NF}')"
grep -q "version:[ ]*$_ws_cli_ver" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex sync --fix -y did not add version $_ws_cli_ver to rnex.yaml"; exit 1; }
! grep -q "ai_instructions:" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "ai_instructions should be stripped during upgrade"; exit 1; }
grep -q "code_workspace:[ ]*false" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex sync --fix -y did not populate missing code_workspace key"; exit 1; }
grep -q "git_hooks:[ ]*false" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex sync --fix -y did not populate missing git_hooks key"; exit 1; }
grep -q "Mandatory Session Startup" "$TEST_UPGRADE_WS/AGENTS.md" || { fail "AGENTS.md not updated with Mandatory Session Startup"; exit 1; }
grep -q "\.rnex/skills/" "$TEST_UPGRADE_WS/AGENTS.md" || { fail "AGENTS.md missing skills reference"; exit 1; }
grep -q "Subagents" "$TEST_UPGRADE_WS/AGENTS.md" || { fail "AGENTS.md missing subagents reference"; exit 1; }

# Running update when already at current version should report up to date
_up_out="$(cd "$TEST_UPGRADE_WS" && ./rnex update 2>&1)"
echo "$_up_out" | grep -q "already up to date" || { fail "rnex update did not report already up to date"; exit 1; }

# Test deprecated rnex fix alias also works
(cd "$TEST_UPGRADE_WS" && ./rnex fix -y >/dev/null)
pass

# --------------------------------------------------------------------------
run_test "Standardized skills and workflows synced to .rnex/skills/ and .rnex/workflows/, prompts purged from .rnex/"
[ ! -d "$TEST_WORKSPACE/.rnex/prompts" ] || { fail ".rnex/prompts directory should not exist"; exit 1; }
[ -d "$TEST_WORKSPACE/.rnex/skills" ] || { fail ".rnex/skills directory was not created"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/skills/rnex-cross-repo-feature/SKILL.md" ] || { fail "rnex-cross-repo-feature skill missing"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/skills/rnex-workspace-audit/SKILL.md" ] || { fail "rnex-workspace-audit skill missing"; exit 1; }
[ -d "$TEST_WORKSPACE/.rnex/workflows" ] || { fail ".rnex/workflows directory was not created"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/workflows/rnex-cross-repo-feature.md" ] || { fail "rnex-cross-repo-feature workflow missing"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/workflows/rnex-workspace-audit.md" ] || { fail "rnex-workspace-audit workflow missing"; exit 1; }
# Verify member repos do not contain workspace prompts
[ ! -d "$TEST_WORKSPACE/repos/test-app/.rnex/prompts" ] || { fail "Workspace prompts leaked into member repo .rnex"; exit 1; }
# Verify status highlights workspace skills and workflows
_status_prompts="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_prompts" | grep -q "workspace skills" || { fail "Status does not highlight workspace skills"; exit 1; }
echo "$_status_prompts" | grep -q "workspace workflows" || { fail "Status does not highlight workspace workflows"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
