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

if [ ! -d "$TEST_WORKSPACE/.git" ]; then
  git -C "$TEST_WORKSPACE" init -q
fi

# Ensure test-app and workspace initialized if run standalone
if [ ! -f "$TEST_WORKSPACE/rnex.yaml" ]; then
  "$TEST_WORKSPACE/rnex" init -y "$TEST_WORKSPACE" >/dev/null
fi
if ! grep -q "test-app:" "$TEST_WORKSPACE/rnex.yaml" 2>/dev/null; then
  "$TEST_WORKSPACE/rnex" repo add "$TEST_REPO" --name test-app >/dev/null
fi

# --------------------------------------------------------------------------
run_test "Gitignore reconciliation removes legacy lint_trigger_counter and ensures safe recursive .rnex directories"
printf '\n.rnex/.lint_trigger_counter\nwiki/.lint_trigger_counter\n.lint_trigger_counter\n' >> "$TEST_WORKSPACE/.gitignore"
"$TEST_WORKSPACE/rnex" sync >/dev/null
grep -q "lint_trigger_counter" "$TEST_WORKSPACE/.gitignore" && { fail "Legacy lint_trigger_counter still present in .gitignore"; exit 1; }
grep -q '\*\*/\.rnex\*/' "$TEST_WORKSPACE/.gitignore" || { fail "**/.rnex*/ missing from .gitignore after sync"; exit 1; }
grep -q '\*\*/rnex\*/' "$TEST_WORKSPACE/.gitignore" || { fail "**/rnex*/ missing from .gitignore after sync"; exit 1; }
grep -q 'repos/\*' "$TEST_WORKSPACE/.gitignore" || { fail "repos/* missing from .gitignore after sync"; exit 1; }
grep -q '.local.rnex.yaml' "$TEST_WORKSPACE/.gitignore" || { fail ".local.rnex.yaml missing from .gitignore after sync"; exit 1; }
[ -f "$TEST_WORKSPACE/.ignore" ] || { fail ".ignore missing after sync"; exit 1; }
grep -q '!repos/\*' "$TEST_WORKSPACE/.ignore" || { fail "!repos/* missing from .ignore after sync"; exit 1; }
# Risk mitigation check: rnex CLI binary and rnex.yaml remain untracked by gitignore, but directories are ignored
! git -C "$TEST_WORKSPACE" check-ignore -q rnex || { fail "rnex file is ignored by git"; exit 1; }
! git -C "$TEST_WORKSPACE" check-ignore -q rnex.yaml || { fail "rnex.yaml file is ignored by git"; exit 1; }
mkdir -p "$TEST_WORKSPACE/.rnex" "$TEST_WORKSPACE/.claude/skills/rnex-core"
touch "$TEST_WORKSPACE/.rnex/test.txt" "$TEST_WORKSPACE/.claude/skills/rnex-core/test.txt"
git -C "$TEST_WORKSPACE" check-ignore -q "$TEST_WORKSPACE/.rnex/" || { fail ".rnex/ directory is not ignored by git"; exit 1; }
git -C "$TEST_WORKSPACE" check-ignore -q "$TEST_WORKSPACE/.claude/skills/rnex-core/" || { fail ".claude/skills/rnex-core/ directory is not ignored by git"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "git.ignore configuration synced into delimited # REPO-NEXUS:START/END section in .gitignore (add, remove, preserve user rules)"
TEST_GI_WS="$TEST_TMP/git-ignore-ws"
mkdir -p "$TEST_GI_WS"
cp "$CLI" "$TEST_GI_WS/rnex"
chmod +x "$TEST_GI_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_GI_WS/toolkit"
cp "$DIR/package.json" "$TEST_GI_WS/package.json"
git -C "$TEST_GI_WS" init -q

# Pre-populate user-owned .gitignore rules and a file matching *.log to test glob-expansion safety
cat <<'USER_GI' > "$TEST_GI_WS/.gitignore"
# User custom rules
.DS_Store
node_modules/
USER_GI
touch "$TEST_GI_WS/app-debug.log"

"$TEST_GI_WS/rnex" init -y "$TEST_GI_WS" >/dev/null

grep -qFx "# REPO-NEXUS:START" "$TEST_GI_WS/.gitignore" || { fail "Missing # REPO-NEXUS:START delimiter after init"; exit 1; }
grep -qFx "# REPO-NEXUS:END" "$TEST_GI_WS/.gitignore" || { fail "Missing # REPO-NEXUS:END delimiter after init"; exit 1; }
grep -qFx ".DS_Store" "$TEST_GI_WS/.gitignore" || { fail "User rule .DS_Store lost during init"; exit 1; }
grep -qFx "node_modules/" "$TEST_GI_WS/.gitignore" || { fail "User rule node_modules/ lost during init"; exit 1; }

cat <<'GITIGNORE_YAML' > "$TEST_GI_WS/rnex.yaml"
version: 1.0.0
git:
  ignore:
    - "*.log"
    - "build-output/"
  hooks:
    post-merge: []
repos:
plugins:
GITIGNORE_YAML

cat <<'GITIGNORE_LOCAL' > "$TEST_GI_WS/.local.rnex.yaml"
git:
  ignore:
    - ".env.local"
GITIGNORE_LOCAL

(cd "$TEST_GI_WS" && ./rnex sync --quiet)
grep -q "^\*\.log$" "$TEST_GI_WS/.gitignore" || { fail "*.log missing from .gitignore after sync (or glob-expanded)"; exit 1; }
! grep -q "^app-debug\.log$" "$TEST_GI_WS/.gitignore" || { fail "*.log was expanded by shell to app-debug.log"; exit 1; }
grep -q "^build-output/$" "$TEST_GI_WS/.gitignore" || { fail "build-output/ missing from .gitignore after sync"; exit 1; }
grep -q "^\.env\.local$" "$TEST_GI_WS/.gitignore" || { fail ".env.local missing from .gitignore after sync"; exit 1; }
grep -qFx ".DS_Store" "$TEST_GI_WS/.gitignore" || { fail "User rule .DS_Store lost after sync"; exit 1; }
! git -C "$TEST_GI_WS" check-ignore -q rnex || { fail "rnex binary is ignored by git"; exit 1; }
! git -C "$TEST_GI_WS" check-ignore -q rnex.yaml || { fail "rnex.yaml is ignored by git"; exit 1; }

# Remove *.log from rnex.yaml and replace build-output/ with dist/, then sync and verify removal
cat <<'GITIGNORE_YAML_2' > "$TEST_GI_WS/rnex.yaml"
version: 1.0.0
git:
  ignore:
    - "dist/"
  hooks:
    post-merge: []
repos:
plugins:
GITIGNORE_YAML_2
rm -f "$TEST_GI_WS/.local.rnex.yaml"

(cd "$TEST_GI_WS" && ./rnex sync --quiet)
! grep -q "^\*\.log$" "$TEST_GI_WS/.gitignore" || { fail "Removed entry *.log still present in .gitignore after sync"; exit 1; }
! grep -q "^build-output/$" "$TEST_GI_WS/.gitignore" || { fail "Removed entry build-output/ still present in .gitignore after sync"; exit 1; }
! grep -q "^\.env\.local$" "$TEST_GI_WS/.gitignore" || { fail "Removed local entry .env.local still present in .gitignore after sync"; exit 1; }
grep -q "^dist/$" "$TEST_GI_WS/.gitignore" || { fail "Updated entry dist/ missing from .gitignore after sync"; exit 1; }
grep -qFx ".DS_Store" "$TEST_GI_WS/.gitignore" || { fail "User rule .DS_Store lost after removal sync"; exit 1; }
grep -qFx "node_modules/" "$TEST_GI_WS/.gitignore" || { fail "User rule node_modules/ lost after removal sync"; exit 1; }
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

"$TEST_WORKSPACE/rnex" sync >/dev/null
_upgraded_agents="$(cat "$TEST_WORKSPACE/AGENTS.md")"
echo "$_upgraded_agents" | grep -q "<!-- REPO-NEXUS:START -->" || { fail "Missing start delimiter after upgrade"; exit 1; }
echo "$_upgraded_agents" | grep -q "<!-- REPO-NEXUS:END -->" || { fail "Missing end delimiter after upgrade"; exit 1; }
echo "$_upgraded_agents" | grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" || { fail "Missing critical directive after upgrade"; exit 1; }
grep -q "Strict Operating Constraints" "$TEST_WORKSPACE/.rnex/ai-instructions.md" || { fail "Missing Routing Protocol in .rnex/ai-instructions.md"; exit 1; }
! echo "$_upgraded_agents" | grep -qi "symlink" || { fail "Upgraded AGENTS.md still contains symlink mentions"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Two-level config: add --local writes to .local.rnex.yaml"
_local_repo_dir="$TEST_TMP/local-repo"
mkdir -p "$_local_repo_dir/src"
git -C "$_local_repo_dir" init -q
git -C "$_local_repo_dir" add .
git -C "$_local_repo_dir" commit -m "init" -q --allow-empty

"$TEST_WORKSPACE/rnex" repo add "$_local_repo_dir" --name local-app --local >/dev/null
[ -f "$TEST_WORKSPACE/.local.rnex.yaml" ] || { fail ".local.rnex.yaml not created"; exit 1; }
grep -q "local-app" "$TEST_WORKSPACE/.local.rnex.yaml" || { fail "local-app not found in .local.rnex.yaml"; exit 1; }
! grep -q "local-app" "$TEST_WORKSPACE/rnex.yaml" || { fail "local-app should not be written to rnex.yaml"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Two-level config: rnex repo set --disable --local overrides rnex.yaml"
"$TEST_WORKSPACE/rnex" repo set test-app --disable --local >/dev/null
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
run_test "Enabling provider plugin creates provider instruction file, cleans inactive AGENTS.md, and creates User Skills"
# Enable gemini plugin in workspace
"$TEST_WORKSPACE/rnex" plugin enable gemini >/dev/null
[ -f "$TEST_WORKSPACE/GEMINI.md" ] || { fail "GEMINI.md missing when gemini enabled"; exit 1; }
[ -f "$TEST_WORKSPACE/.geminiignore" ] || { fail ".geminiignore missing when gemini enabled"; exit 1; }
grep -qFx "# REPO-NEXUS:START" "$TEST_WORKSPACE/.geminiignore" || { fail ".geminiignore missing # REPO-NEXUS:START delimiter"; exit 1; }
grep -qFx "# REPO-NEXUS:END" "$TEST_WORKSPACE/.geminiignore" || { fail ".geminiignore missing # REPO-NEXUS:END delimiter"; exit 1; }
# AGENTS.md (which only had default rnex instructions and is not gemini's instruction file) is cleaned
[ ! -f "$TEST_WORKSPACE/AGENTS.md" ] || { fail "AGENTS.md should not be retained when gemini provides GEMINI.md"; exit 1; }
[ -d "$TEST_WORKSPACE/.agents/skills" ] || { fail ".agents/skills not created"; exit 1; }
[ ! -d "$TEST_WORKSPACE/.gemini/skills" ] || { fail "incorrect .gemini/skills was created"; exit 1; }
[ -f "$TEST_WORKSPACE/.agents/skills/rnex-clone-sync/SKILL.md" ] || { fail "rnex-clone-sync missing in .agents/skills"; exit 1; }
_status_fixed="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_fixed" | grep -q "GEMINI.md" || { fail "Status did not show GEMINI.md"; exit 1; }
echo "$_status_fixed" | grep -q ".agents/skills/" || { fail "Status did not show .agents/skills/"; exit 1; }
# Disable gemini plugin; GEMINI.md (empty of user content) is deleted, .geminiignore is deleted, and AGENTS.md restored as fallback
"$TEST_WORKSPACE/rnex" plugin disable gemini >/dev/null
[ ! -f "$TEST_WORKSPACE/GEMINI.md" ] || { fail "GEMINI.md was not removed after disabling gemini (had no user content)"; exit 1; }
[ ! -f "$TEST_WORKSPACE/.geminiignore" ] || { fail ".geminiignore was not removed after disabling gemini (had no user rules)"; exit 1; }
[ -f "$TEST_WORKSPACE/AGENTS.md" ] || { fail "AGENTS.md missing after disabling provider plugin (should restore as fallback)"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_WORKSPACE/AGENTS.md" || { fail "AGENTS.md missing REPO-NEXUS instructions after disabling gemini"; exit 1; }
[ ! -d "$TEST_WORKSPACE/.agents/skills/rnex-clone-sync" ] || { fail "User skills not cleaned up after disabling gemini"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Init with --claude flag sets up Claude plugin, CLAUDE.md, and User Skills without redundant AGENTS.md"
TEST_AI_WS="$TEST_TMP/ai-workspace"
mkdir -p "$TEST_AI_WS"
cp "$CLI" "$TEST_AI_WS/rnex"
chmod +x "$TEST_AI_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_AI_WS/toolkit"
"$TEST_AI_WS/rnex" init -y --claude "$TEST_AI_WS" >/dev/null
[ ! -f "$TEST_AI_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created when claude provides CLAUDE.md"; exit 1; }
[ -f "$TEST_AI_WS/CLAUDE.md" ] || { fail "CLAUDE.md missing after init --claude"; exit 1; }
[ -d "$TEST_AI_WS/.claude/skills" ] || { fail ".claude/skills missing after init --claude"; exit 1; }
[ -f "$TEST_AI_WS/.claude/skills/rnex-clone-sync/SKILL.md" ] || { fail "rnex-clone-sync/SKILL.md missing in .claude/skills"; exit 1; }
grep -q "claude:" "$TEST_AI_WS/rnex.yaml" || { fail "claude plugin not enabled in rnex.yaml"; exit 1; }
grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$TEST_AI_WS/CLAUDE.md" || { fail "CLAUDE.md missing critical directive"; exit 1; }
grep -q "Repo Nexus Workspace Instructions" "$TEST_AI_WS/.rnex/ai-instructions.md" || { fail ".rnex/ai-instructions.md missing Repo Nexus Workspace Instructions"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Configurable code_workspace generates and updates .code-workspace file"
echo "code_workspace: true" >> "$TEST_WORKSPACE/rnex.yaml"
_status_ws="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_ws" | grep -q "nexus-workspace.code-workspace" || { fail "Status did not detect configured code_workspace file"; exit 1; }
echo "$_status_ws" | grep -q "MISSING" || { fail "Status did not highlight missing code-workspace"; exit 1; }
"$TEST_WORKSPACE/rnex" sync >/dev/null
[ -f "$TEST_WORKSPACE/nexus-workspace.code-workspace" ] || { fail "code-workspace file was not created by fix"; exit 1; }
grep -q '"folders"' "$TEST_WORKSPACE/nexus-workspace.code-workspace" || { fail "folders array missing in workspace file"; exit 1; }
grep -q 'nexus-workspace (Workspace Root)' "$TEST_WORKSPACE/nexus-workspace.code-workspace" || { fail "Root folder missing in workspace file"; exit 1; }
grep -q 'local-app' "$TEST_WORKSPACE/nexus-workspace.code-workspace" || { fail "local-app missing in workspace file"; exit 1; }
# Re-enable test-app and verify code-workspace updates automatically
"$TEST_WORKSPACE/rnex" repo set test-app --enable --local >/dev/null
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
run_test "Version-aware upgrade in rnex sync and update/upgrade commands"
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

# rnex status should detect version inconsistency without mutating
_status_audit="$(cd "$TEST_UPGRADE_WS" && { ./rnex status 2>&1 || true; })"
echo "$_status_audit" | grep -q "older than CLI" || { fail "rnex status did not audit version mismatch"; exit 1; }
grep -q "ai_instructions:" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex status mutated rnex.yaml"; exit 1; }

# Sync with -y should detect missing/older version, upgrade config, and reconcile instructions
(cd "$TEST_UPGRADE_WS" && ./rnex sync -y >/dev/null)
_ws_cli_ver="$("$TEST_UPGRADE_WS/rnex" version 2>&1 | awk '{print $NF}')"
grep -q "version:[ ]*$_ws_cli_ver" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex sync -y did not add version $_ws_cli_ver to rnex.yaml"; exit 1; }
! grep -q "ai_instructions:" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "ai_instructions should be stripped during upgrade"; exit 1; }
grep -q "code_workspace:[ ]*false" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex sync -y did not populate missing code_workspace key"; exit 1; }
grep -q "git:" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex sync -y did not populate missing git: section"; exit 1; }
grep -q "post-merge:" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "rnex sync -y did not populate missing git.hooks"; exit 1; }
! grep -q "git_hooks:" "$TEST_UPGRADE_WS/rnex.yaml" || { fail "legacy git_hooks still present after upgrade"; exit 1; }
grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$TEST_UPGRADE_WS/AGENTS.md" || { fail "AGENTS.md missing critical directive after upgrade"; exit 1; }
grep -q "Mandatory Execution Sequence" "$TEST_UPGRADE_WS/.rnex/ai-instructions.md" || { fail ".rnex/ai-instructions.md not updated with Mandatory Execution Sequence"; exit 1; }
grep -q "Skills" "$TEST_UPGRADE_WS/.rnex/ai-instructions.md" || { fail ".rnex/ai-instructions.md missing subagents reference"; exit 1; }

# Running sync when already at current version should succeed cleanly
(cd "$TEST_UPGRADE_WS" && ./rnex sync -y >/dev/null)

# Verify deleted update and upgrade commands fail with unknown command
for _del_cmd in update upgrade; do
  _del_err="$(cd "$TEST_UPGRADE_WS" && { ./rnex "$_del_cmd" 2>&1 || true; })"
  echo "$_del_err" | grep -qi "Unknown command" || { fail "Deleted command 'rnex $_del_cmd' did not fail with Unknown command"; exit 1; }
done
pass

# --------------------------------------------------------------------------
run_test "rnex repo add with --branch, repo set multi-flags, and repo remove with/without --purge"
TEST_REPO_OPS_WS="$TEST_TMP/repo-ops-workspace"
mkdir -p "$TEST_REPO_OPS_WS"
cp "$CLI" "$TEST_REPO_OPS_WS/rnex"
chmod +x "$TEST_REPO_OPS_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_REPO_OPS_WS/toolkit"
cp "$DIR/package.json" "$TEST_REPO_OPS_WS/package.json"
"$TEST_REPO_OPS_WS/rnex" init -y "$TEST_REPO_OPS_WS" >/dev/null

# Prepare remote repo with a 'develop' branch
_branch_repo_dir="$TEST_TMP/branch-repo"
mkdir -p "$_branch_repo_dir"
git -C "$_branch_repo_dir" init -q
git -C "$_branch_repo_dir" checkout -q -b develop
touch "$_branch_repo_dir/api.txt"
git -C "$_branch_repo_dir" add .
git -C "$_branch_repo_dir" commit -q -m "initial develop commit"

# 1. Add repo with explicit --branch develop
(cd "$TEST_REPO_OPS_WS" && ./rnex repo add "$_branch_repo_dir" --name api --branch develop >/dev/null)
grep -q "api:" "$TEST_REPO_OPS_WS/rnex.yaml" || { fail "api repo not added to rnex.yaml"; exit 1; }
grep -q "branch:[ ]*develop" "$TEST_REPO_OPS_WS/rnex.yaml" || { fail "branch: develop not written to rnex.yaml"; exit 1; }
[ -d "$TEST_REPO_OPS_WS/repos/api/.git" ] || { fail "repos/api not cloned"; exit 1; }
_cloned_b="$(git -C "$TEST_REPO_OPS_WS/repos/api" symbolic-ref --short HEAD 2>/dev/null || true)"
[ "$_cloned_b" = "develop" ] || { fail "Expected cloned branch 'develop', got '$_cloned_b'"; exit 1; }

# 2. Test rnex repo set with both disable and readonly in one invocation
(cd "$TEST_REPO_OPS_WS" && ./rnex repo set api --disable --readonly >/dev/null)
grep -q "enabled:[ ]*false" "$TEST_REPO_OPS_WS/.local.rnex.yaml" || { fail "api enabled: false not set in local config"; exit 1; }
grep -q "readonly:[ ]*true" "$TEST_REPO_OPS_WS/.local.rnex.yaml" || { fail "api readonly: true not set in local config"; exit 1; }

# 3. Test rnex repo set with both enable and readwrite in one invocation
(cd "$TEST_REPO_OPS_WS" && ./rnex repo set api --enable --readwrite >/dev/null)
grep -q "enabled:[ ]*true" "$TEST_REPO_OPS_WS/.local.rnex.yaml" || { fail "api enabled: true not set in local config"; exit 1; }
grep -q "readonly:[ ]*false" "$TEST_REPO_OPS_WS/.local.rnex.yaml" || { fail "api readonly: false not set in local config"; exit 1; }

# 4. Test rnex repo status and exec
_rstatus_out="$(cd "$TEST_REPO_OPS_WS" && ./rnex repo status api 2>&1)"
echo "$_rstatus_out" | grep -q "Repository: api" || { fail "rnex repo status did not output repository name"; exit 1; }
echo "$_rstatus_out" | grep -q "Target Branch: develop" || { fail "rnex repo status did not report Target Branch: develop"; exit 1; }

_rexec_out="$(cd "$TEST_REPO_OPS_WS" && ./rnex repo exec api git status -s 2>&1)"
echo "$_rexec_out" | grep -q "\[api\]" || { fail "rnex repo exec did not run in api repo"; exit 1; }

# 5. Remove repo without --purge (keeps repos/api on disk)
(cd "$TEST_REPO_OPS_WS" && ./rnex repo remove api >/dev/null)
! grep -q "api:" "$TEST_REPO_OPS_WS/rnex.yaml" || { fail "api still present in rnex.yaml after remove"; exit 1; }
[ -d "$TEST_REPO_OPS_WS/repos/api/.git" ] || { fail "repos/api was deleted without --purge"; exit 1; }

# 6. Re-add and remove with --purge (deletes repos/api from disk)
(cd "$TEST_REPO_OPS_WS" && ./rnex repo add "$_branch_repo_dir" --name api >/dev/null)
(cd "$TEST_REPO_OPS_WS" && ./rnex repo remove api --purge -y >/dev/null)
[ ! -d "$TEST_REPO_OPS_WS/repos/api" ] || { fail "repos/api directory was not deleted with --purge"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Core skills synced to .rnex/skills/*.md, prompts and workflows purged from .rnex/"
[ ! -d "$TEST_WORKSPACE/.rnex/prompts" ] || { fail ".rnex/prompts directory should not exist"; exit 1; }
[ ! -d "$TEST_WORKSPACE/.rnex/workflows" ] || { fail ".rnex/workflows directory should not exist"; exit 1; }
[ -d "$TEST_WORKSPACE/.rnex/skills" ] || { fail ".rnex/skills directory was not created"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/skills/clone-sync.md" ] || { fail "clone-sync skill missing"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/skills/batch-exec.md" ] || { fail "batch-exec skill missing"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/skills/workspace-status.md" ] || { fail "workspace-status skill missing"; exit 1; }
# Verify member repos do not contain workspace prompts
[ ! -d "$TEST_WORKSPACE/repos/test-app/.rnex/prompts" ] || { fail "Workspace prompts leaked into member repo .rnex"; exit 1; }
[ ! -d "$TEST_WORKSPACE/repos/test-app/.rnex/workflows" ] || { fail "Workspace workflows leaked into member repo .rnex"; exit 1; }
# Verify status highlights workspace skills
_status_prompts="$("$TEST_WORKSPACE/rnex" status 2>&1)"
echo "$_status_prompts" | grep -q "workspace skills" || { fail "Status does not highlight workspace skills"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Configurable repos_dir lifecycle: init, gitignore, add, clone, status, exec, set, and purge"
TEST_RDIR_WS="$TEST_TMP/custom-repos-dir-ws"
mkdir -p "$TEST_RDIR_WS"
cp "$CLI" "$TEST_RDIR_WS/rnex"
chmod +x "$TEST_RDIR_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_RDIR_WS/toolkit"
cp "$DIR/package.json" "$TEST_RDIR_WS/package.json"
git -C "$TEST_RDIR_WS" init -q

# 1. Initialize workspace with custom --repos-dir services
(cd "$TEST_RDIR_WS" && ./rnex init -y --repos-dir services "$TEST_RDIR_WS" >/dev/null)

[ -d "$TEST_RDIR_WS/services" ] || { fail "Custom services/ directory not created during init"; exit 1; }
[ ! -d "$TEST_RDIR_WS/repos" ] || { fail "Default repos/ directory should not exist"; exit 1; }
grep -q 'repos_dir:[ ]*"services"' "$TEST_RDIR_WS/rnex.yaml" || { fail "repos_dir: \"services\" not written to rnex.yaml"; exit 1; }
git -C "$TEST_RDIR_WS" check-ignore -q services/ || { fail "services/ is not ignored by git"; exit 1; }
grep -q '!services/\*' "$TEST_RDIR_WS/.ignore" || { fail "!services/* not found in .ignore"; exit 1; }

# Prepare remote repo
_svc_remote="$TEST_TMP/svc-remote-auth"
mkdir -p "$_svc_remote"
git -C "$_svc_remote" init -q
echo "# Auth Service" > "$_svc_remote/README.md"
git -C "$_svc_remote" add .
git -C "$_svc_remote" commit -q -m "initial commit"

# 2. Add repo and verify it clones into services/auth
(cd "$TEST_RDIR_WS" && ./rnex repo add "$_svc_remote" --name auth >/dev/null)
[ -d "$TEST_RDIR_WS/services/auth/.git" ] || { fail "Repository not cloned into services/auth"; exit 1; }
[ ! -d "$TEST_RDIR_WS/repos" ] || { fail "repos/ was created when adding repo"; exit 1; }

# 3. Verify .rnex/ai-instructions.md references services/<name> and not repos/<name>
grep -q "services/<name>" "$TEST_RDIR_WS/.rnex/ai-instructions.md" || { fail "ai-instructions.md does not reference services/<name>"; exit 1; }
! grep -q "repos/<name>" "$TEST_RDIR_WS/.rnex/ai-instructions.md" || { fail "ai-instructions.md still references repos/<name>"; exit 1; }

# 4. Verify rnex status checks services/ in gitignore
_status_out="$(cd "$TEST_RDIR_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q "services/" || { fail "rnex status does not report services/ ignore"; exit 1; }

# 5. Verify rnex exec runs inside services/auth
_exec_pwd="$(cd "$TEST_RDIR_WS" && ./rnex exec pwd 2>&1)"
echo "$_exec_pwd" | grep -q "services/auth" || { fail "rnex exec did not execute inside services/auth: $_exec_pwd"; exit 1; }

# 6. Verify rnex repo set --readonly marks services/auth readonly in status and list
(cd "$TEST_RDIR_WS" && ./rnex repo set auth --readonly >/dev/null)
_rlist_out="$(cd "$TEST_RDIR_WS" && ./rnex repo list 2>&1)"
echo "$_rlist_out" | grep "auth" | grep -q "true" || { fail "auth readonly not true in list: $_rlist_out"; exit 1; }
_rstatus_out="$(cd "$TEST_RDIR_WS" && ./rnex repo status auth 2>&1)"
echo "$_rstatus_out" | grep -qi "Readonly:[ ]*true" || { fail "auth missing Readonly: true in repo status: $_rstatus_out"; exit 1; }
_ws_status="$(cd "$TEST_RDIR_WS" && ./rnex status 2>&1)"
echo "$_ws_status" | grep "auth" | grep -q "\[readonly\]" || { fail "auth missing [readonly] in workspace status: $_ws_status"; exit 1; }

# 7. Verify rnex repo remove --purge removes services/auth
(cd "$TEST_RDIR_WS" && ./rnex repo remove auth --purge -y >/dev/null)
[ ! -d "$TEST_RDIR_WS/services/auth" ] || { fail "services/auth was not purged"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "repos_dir two-level config override (.local.rnex.yaml) and path traversal fallback"
TEST_RDIR_OVR="$TEST_TMP/repos-dir-ovr-ws"
mkdir -p "$TEST_RDIR_OVR"
cp "$CLI" "$TEST_RDIR_OVR/rnex"
chmod +x "$TEST_RDIR_OVR/rnex"
cp -r "$DIR/toolkit" "$TEST_RDIR_OVR/toolkit"
cp "$DIR/package.json" "$TEST_RDIR_OVR/package.json"
git -C "$TEST_RDIR_OVR" init -q

"$TEST_RDIR_OVR/rnex" init -y "$TEST_RDIR_OVR" >/dev/null

# Set base config repos_dir: "components"
_sed_cmd='s/^repos_dir:.*/repos_dir: "components"/'
sed "$_sed_cmd" "$TEST_RDIR_OVR/rnex.yaml" > "$TEST_RDIR_OVR/rnex.yaml.tmp" && mv "$TEST_RDIR_OVR/rnex.yaml.tmp" "$TEST_RDIR_OVR/rnex.yaml"

# Override in .local.rnex.yaml
cat <<'LOCAL_EOF' > "$TEST_RDIR_OVR/.local.rnex.yaml"
repos_dir: "local-components"
LOCAL_EOF

(cd "$TEST_RDIR_OVR" && ./rnex sync >/dev/null)
[ -d "$TEST_RDIR_OVR/local-components" ] || { fail "local-components/ not created from .local.rnex.yaml override"; exit 1; }
git -C "$TEST_RDIR_OVR" check-ignore -q local-components/ || { fail "local-components/ not ignored in git"; exit 1; }

# Test path traversal security fallback
cat <<'TRAVERSAL_EOF' > "$TEST_RDIR_OVR/.local.rnex.yaml"
repos_dir: "../escaping"
TRAVERSAL_EOF

_resolved_trav="$(cd "$TEST_RDIR_OVR" && . "$DIR/lib/core.sh" && . "$DIR/lib/workspace.sh" && . "$DIR/lib/yaml.sh" && WORKSPACE_YAML="$TEST_RDIR_OVR/rnex.yaml" WORKSPACE_LOCAL_YAML="$TEST_RDIR_OVR/.local.rnex.yaml" yaml_get_repos_dir)"
[ "$_resolved_trav" = "repos" ] || { fail "Path traversal ../escaping did not fall back to repos, got '$_resolved_trav'"; exit 1; }

cat <<'ABSOLUTE_EOF' > "$TEST_RDIR_OVR/.local.rnex.yaml"
repos_dir: "/root/abs"
ABSOLUTE_EOF

_resolved_abs="$(cd "$TEST_RDIR_OVR" && . "$DIR/lib/core.sh" && . "$DIR/lib/workspace.sh" && . "$DIR/lib/yaml.sh" && WORKSPACE_YAML="$TEST_RDIR_OVR/rnex.yaml" WORKSPACE_LOCAL_YAML="$TEST_RDIR_OVR/.local.rnex.yaml" yaml_get_repos_dir)"
[ "$_resolved_abs" = "repos" ] || { fail "Absolute path /root/abs did not fall back to repos, got '$_resolved_abs'"; exit 1; }

cat <<'DOT_EOF' > "$TEST_RDIR_OVR/.local.rnex.yaml"
repos_dir: "."
DOT_EOF

_resolved_dot="$(cd "$TEST_RDIR_OVR" && . "$DIR/lib/core.sh" && . "$DIR/lib/workspace.sh" && . "$DIR/lib/yaml.sh" && WORKSPACE_YAML="$TEST_RDIR_OVR/rnex.yaml" WORKSPACE_LOCAL_YAML="$TEST_RDIR_OVR/.local.rnex.yaml" yaml_get_repos_dir)"
[ "$_resolved_dot" = "repos" ] || { fail "Dot path . did not fall back to repos, got '$_resolved_dot'"; exit 1; }
pass


# --------------------------------------------------------------------------
run_test "Compiled ai-instructions.md reflects two-level merged config (.local.rnex.yaml wins)"
TEST_MERGE_WS="$TEST_TMP/merge-ai-workspace"
mkdir -p "$TEST_MERGE_WS"
cp "$CLI" "$TEST_MERGE_WS/rnex"
chmod +x "$TEST_MERGE_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_MERGE_WS/toolkit"
"$TEST_MERGE_WS/rnex" init -y "$TEST_MERGE_WS" >/dev/null 2>&1
cat <<'MERGE_EOF' > "$TEST_MERGE_WS/rnex.yaml"
version: "1"
name: merge-ws
repos:
  repo-beta:
    url: "https://example.invalid/beta.git"
    enabled: true
  repo-alpha:
    url: "https://example.invalid/alpha.git"
    readonly: false
    branch: main
MERGE_EOF
cat <<'MERGE_LOCAL_EOF' > "$TEST_MERGE_WS/.local.rnex.yaml"
repos:
  repo-alpha:
    readonly: true
    branch: dev
  repo-beta:
    enabled: false
MERGE_LOCAL_EOF
(cd "$TEST_MERGE_WS" && ./rnex sync -y >/dev/null 2>&1) || true
_merge_ai="$TEST_MERGE_WS/.rnex/ai-instructions.md"
[ -f "$_merge_ai" ] || { fail "ai-instructions.md missing after sync"; exit 1; }
grep -qF "| \`repo-alpha\` | \`repos/repo-alpha/\` | \`dev\` | \`READ-ONLY\` |" "$_merge_ai" || { fail "repo-alpha not rendered with local overrides (dev, READ-ONLY)"; exit 1; }
grep -qF "**Disabled Repositories (Do Not Access)**: \`repo-beta\`" "$_merge_ai" || { fail "repo-beta not listed as disabled"; exit 1; }
! grep -qF "| \`repo-beta\` |" "$_merge_ai" || { fail "Disabled repo-beta present in active table"; exit 1; }
grep -qF 'DO NOT read or search for rnex.yaml or .local.rnex.yaml' "$_merge_ai" || { fail "Missing NO CONFIG READS constraint"; exit 1; }
! grep -qE "Read .*\.local\.rnex\.yaml" "$_merge_ai" || { fail "ai-instructions.md still instructs reading config files"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Compiled ai-instructions.md is byte-for-byte deterministic across runs and repo declaration order"
(cd "$TEST_MERGE_WS" && ./rnex sync -y >/dev/null 2>&1) || true
_det_1="$(cksum < "$_merge_ai")"
(cd "$TEST_MERGE_WS" && ./rnex sync -y >/dev/null 2>&1) || true
_det_2="$(cksum < "$_merge_ai")"
cat <<'MERGE_REV_EOF' > "$TEST_MERGE_WS/rnex.yaml"
version: "1"
name: merge-ws
repos:
  repo-alpha:
    url: "https://example.invalid/alpha.git"
    readonly: false
    branch: main
  repo-beta:
    url: "https://example.invalid/beta.git"
    enabled: true
MERGE_REV_EOF
(cd "$TEST_MERGE_WS" && ./rnex sync -y >/dev/null 2>&1) || true
_det_3="$(cksum < "$_merge_ai")"
[ "$_det_1" = "$_det_2" ] || { fail "ai-instructions.md changed between identical syncs"; exit 1; }
[ "$_det_1" = "$_det_3" ] || { fail "ai-instructions.md depends on repo declaration order"; exit 1; }

# Verify rnex repo set and rnex plugin enable/disable immediately update .rnex/ai-instructions.md
(cd "$TEST_MERGE_WS" && ./rnex repo set repo-alpha --readwrite --local >/dev/null 2>&1)
grep -qF "| \`repo-alpha\` | \`repos/repo-alpha/\` | \`dev\` | \`READ-WRITE\` |" "$_merge_ai" || { fail "rnex repo set --readwrite did not immediately update ai-instructions.md"; exit 1; }
(cd "$TEST_MERGE_WS" && ./rnex repo set repo-alpha --readonly --local >/dev/null 2>&1)
grep -qF "| \`repo-alpha\` | \`repos/repo-alpha/\` | \`dev\` | \`READ-ONLY\` |" "$_merge_ai" || { fail "rnex repo set --readonly did not immediately update ai-instructions.md"; exit 1; }
(cd "$TEST_MERGE_WS" && ./rnex plugin enable copilot >/dev/null 2>&1)
grep -qF "**Enabled Plugins**: \`copilot\`" "$_merge_ai" || { fail "rnex plugin enable did not immediately update ai-instructions.md"; exit 1; }
(cd "$TEST_MERGE_WS" && ./rnex plugin disable copilot >/dev/null 2>&1)
! grep -qF "\`copilot\`" "$_merge_ai" || { fail "rnex plugin disable did not immediately update ai-instructions.md"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
