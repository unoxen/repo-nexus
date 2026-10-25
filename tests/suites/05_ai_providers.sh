#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/05_ai_providers.sh — AI Provider Plugins & User Skills Sync
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/tests/test_helper.sh"

# --------------------------------------------------------------------------
run_test "On-the-fly zero-logic User Skill generator and provider sync"
TEST_SKILLS_WS="$TEST_TMP/skills-ws"
mkdir -p "$TEST_SKILLS_WS"
cp "$CLI" "$TEST_SKILLS_WS/rnex"
chmod +x "$TEST_SKILLS_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_SKILLS_WS/toolkit"
cp "$DIR/package.json" "$TEST_SKILLS_WS/package.json"
git -C "$TEST_SKILLS_WS" init -q

"$TEST_SKILLS_WS/rnex" init -y --claude "$TEST_SKILLS_WS" >/dev/null

# Verify core agentic skills exist in .rnex/skills/
[ -f "$TEST_SKILLS_WS/.rnex/skills/clone-sync.md" ] || { fail "clone-sync.md missing in .rnex/skills/"; exit 1; }
[ -f "$TEST_SKILLS_WS/.rnex/skills/batch-exec.md" ] || { fail "batch-exec.md missing in .rnex/skills/"; exit 1; }
[ -f "$TEST_SKILLS_WS/.rnex/skills/workspace-status.md" ] || { fail "workspace-status.md missing in .rnex/skills/"; exit 1; }

# Verify .claude/skills/ has User Skills generated with rnex- prefix
[ -d "$TEST_SKILLS_WS/.claude/skills" ] || { fail ".claude/skills directory missing"; exit 1; }
[ -f "$TEST_SKILLS_WS/.claude/skills/rnex-clone-sync/SKILL.md" ] || { fail "rnex-clone-sync/SKILL.md missing in .claude/skills/"; exit 1; }
[ -f "$TEST_SKILLS_WS/.claude/skills/rnex-batch-exec/SKILL.md" ] || { fail "rnex-batch-exec/SKILL.md missing in .claude/skills/"; exit 1; }
[ -f "$TEST_SKILLS_WS/.claude/skills/rnex-workspace-status/SKILL.md" ] || { fail "rnex-workspace-status/SKILL.md missing in .claude/skills/"; exit 1; }

# Verify User Skill contains YAML frontmatter and points to .rnex/skills/
grep -q "name: rnex-clone-sync" "$TEST_SKILLS_WS/.claude/skills/rnex-clone-sync/SKILL.md" || { fail "User skill missing YAML frontmatter"; exit 1; }
grep -q "CRITICAL: Do not execute inline heuristics" "$TEST_SKILLS_WS/.claude/skills/rnex-clone-sync/SKILL.md" || { fail "User skill missing strict no-heuristic directive"; exit 1; }
grep -q "\.rnex/skills/clone-sync\.md" "$TEST_SKILLS_WS/.claude/skills/rnex-clone-sync/SKILL.md" || { fail "User skill missing target skill path"; exit 1; }

# Verify status highlights user skills
_skills_status="$(cd "$TEST_SKILLS_WS" && ./rnex status 2>&1)"
echo "$_skills_status" | grep -q "\.claude/skills/" || { fail "Status did not report .claude/skills/"; exit 1; }

# Test disabling skills option for claude
cat <<EOF > "$TEST_SKILLS_WS/rnex.yaml"
version: 0.6.16
repos_dir: ./repos
code_workspace: false
git_hooks: false
plugins:
  claude:
    skills: false
repos:
EOF

# Add a user-authored custom skill to ensure it is not deleted
echo "# Custom skill" > "$TEST_SKILLS_WS/.claude/skills/custom-user-skill.md"

(cd "$TEST_SKILLS_WS" && ./rnex sync -y --quiet >/dev/null)

# Verify rnex-* User Skills were cleaned up, but custom skill remains
[ ! -d "$TEST_SKILLS_WS/.claude/skills/rnex-clone-sync" ] || { fail "rnex User Skills not cleaned when skills: false"; exit 1; }
[ -f "$TEST_SKILLS_WS/.claude/skills/custom-user-skill.md" ] || { fail "User custom skill deleted when skills: false"; exit 1; }
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
[ -f "$TEST_PROVIDERS_WS/AGENTS.md" ] || { fail "Permanent AGENTS.md missing after init --claude"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/AGENTS.md" || { fail "AGENTS.md missing REPO-NEXUS instructions"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/CLAUDE.md" ] || { fail "CLAUDE.md missing after init --claude"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.claude/skills/rnex-clone-sync/SKILL.md" ] || { fail "Claude user skill rnex-clone-sync/SKILL.md missing"; exit 1; }

# Enable gemini plugin
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable gemini >/dev/null)
[ -f "$TEST_PROVIDERS_WS/GEMINI.md" ] || { fail "GEMINI.md missing after enabling gemini"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.geminiignore" ] || { fail ".geminiignore missing after enabling gemini"; exit 1; }
grep -q '!repos/\*' "$TEST_PROVIDERS_WS/.geminiignore" || { fail "!repos/* missing from .geminiignore"; exit 1; }
[ -d "$TEST_PROVIDERS_WS/.agents/skills" ] || { fail ".agents/skills missing after enabling gemini"; exit 1; }
[ ! -d "$TEST_PROVIDERS_WS/.gemini/skills" ] || { fail "incorrect .gemini/skills created"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.agents/skills/rnex-clone-sync/SKILL.md" ] || { fail "Gemini user skill rnex-clone-sync/SKILL.md missing in .agents/skills"; exit 1; }

# Enable cursor and windsurf plugins
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable cursor >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable windsurf >/dev/null)
[ -f "$TEST_PROVIDERS_WS/.cursorrules" ] || { fail ".cursorrules missing after enabling cursor"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursorignore" ] || { fail ".cursorignore missing after enabling cursor"; exit 1; }
grep -q '!repos/\*' "$TEST_PROVIDERS_WS/.cursorignore" || { fail "!repos/* missing from .cursorignore"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursor/rules/rnex-clone-sync.md" ] || { fail "Cursor user skill rnex-clone-sync.md missing"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.windsurfrules" ] || { fail ".windsurfrules missing after enabling windsurf"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.windsurf/rules/rnex-clone-sync.md" ] || { fail "Windsurf user skill rnex-clone-sync.md missing"; exit 1; }

# Status command reports all enabled AI providers
_prov_status="$(cd "$TEST_PROVIDERS_WS" && ./rnex status 2>&1)"
echo "$_prov_status" | grep -q "CLAUDE.md" || { fail "Status did not report CLAUDE.md"; exit 1; }
echo "$_prov_status" | grep -q "GEMINI.md" || { fail "Status did not report GEMINI.md"; exit 1; }
echo "$_prov_status" | grep -q "\.cursorrules" || { fail "Status did not report .cursorrules"; exit 1; }
echo "$_prov_status" | grep -q "\.windsurfrules" || { fail "Status did not report .windsurfrules"; exit 1; }
echo "$_prov_status" | grep -q "\.claude/skills/" || { fail "Status did not report .claude/skills/"; exit 1; }
echo "$_prov_status" | grep -q "\.agents/skills/" || { fail "Status did not report .agents/skills/"; exit 1; }
echo "$_prov_status" | grep -q "\.cursor/rules/" || { fail "Status did not report .cursor/rules/"; exit 1; }
echo "$_prov_status" | grep -q "\.windsurf/rules/" || { fail "Status did not report .windsurf/rules/"; exit 1; }

# Test user custom content preservation across provider instructions
printf "# Custom Section\n" >> "$TEST_PROVIDERS_WS/CLAUDE.md"
printf "# Gemini Custom\n" >> "$TEST_PROVIDERS_WS/GEMINI.md"
printf "custom-gemini.log\n" >> "$TEST_PROVIDERS_WS/.geminiignore"
printf "# Cursor Custom\n" >> "$TEST_PROVIDERS_WS/.cursorrules"
printf "custom-cursor.log\n" >> "$TEST_PROVIDERS_WS/.cursorignore"
printf "# Windsurf Custom\n" >> "$TEST_PROVIDERS_WS/.windsurfrules"
(cd "$TEST_PROVIDERS_WS" && ./rnex sync -y --quiet >/dev/null)
grep -q "# Custom Section" "$TEST_PROVIDERS_WS/CLAUDE.md" || { fail "Custom section lost in CLAUDE.md"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/CLAUDE.md" || { fail "REPO-NEXUS block missing in CLAUDE.md"; exit 1; }
grep -q "# Gemini Custom" "$TEST_PROVIDERS_WS/GEMINI.md" || { fail "Custom section lost in GEMINI.md"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/GEMINI.md" || { fail "REPO-NEXUS block missing in GEMINI.md"; exit 1; }
grep -q "# Cursor Custom" "$TEST_PROVIDERS_WS/.cursorrules" || { fail "Custom section lost in .cursorrules"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/.cursorrules" || { fail "REPO-NEXUS block missing in .cursorrules"; exit 1; }
grep -q "# Windsurf Custom" "$TEST_PROVIDERS_WS/.windsurfrules" || { fail "Custom section lost in .windsurfrules"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/.windsurfrules" || { fail "REPO-NEXUS block missing in .windsurfrules"; exit 1; }

# Add custom user skills and extra files across all providers
echo "custom" > "$TEST_PROVIDERS_WS/.claude/skills/my-claude-skill.md"
echo "custom" > "$TEST_PROVIDERS_WS/.agents/skills/my-gemini-skill.md"
echo "custom" > "$TEST_PROVIDERS_WS/.cursor/rules/my-user-rule.mdc"
echo "custom" > "$TEST_PROVIDERS_WS/.windsurf/rules/my-user-rule.md"

# Disable all provider plugins and verify permanent AGENTS.md is retained
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable claude >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable gemini >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable cursor >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable windsurf >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex sync -y --quiet >/dev/null)

[ -f "$TEST_PROVIDERS_WS/AGENTS.md" ] || { fail "AGENTS.md missing when provider plugins disabled"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/AGENTS.md" || { fail "AGENTS.md missing REPO-NEXUS instructions"; exit 1; }

# Verify Repo Nexus generated User Skills were cleaned up
[ ! -d "$TEST_PROVIDERS_WS/.claude/skills/rnex-clone-sync" ] || { fail "rnex User Skill not cleaned from claude"; exit 1; }
[ ! -d "$TEST_PROVIDERS_WS/.agents/skills/rnex-clone-sync" ] || { fail "rnex User Skill not cleaned from .agents"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.cursor/rules/rnex-clone-sync.md" ] || { fail "rnex User Skill not cleaned from cursor"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.windsurf/rules/rnex-clone-sync.md" ] || { fail "rnex User Skill not cleaned from windsurf"; exit 1; }

# Verify ALL user custom files were preserved
[ -f "$TEST_PROVIDERS_WS/.claude/skills/my-claude-skill.md" ] || { fail "User skill deleted from .claude"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.agents/skills/my-gemini-skill.md" ] || { fail "User skill deleted from .agents"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursor/rules/my-user-rule.mdc" ] || { fail "User rule deleted from .cursor"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.windsurf/rules/my-user-rule.md" ] || { fail "User rule deleted from .windsurf"; exit 1; }

# Instruction files permanently retain routing instructions and custom user content
for _f in CLAUDE.md GEMINI.md .cursorrules .windsurfrules; do
  [ -f "$TEST_PROVIDERS_WS/$_f" ] || { fail "$_f with custom content was deleted"; exit 1; }
  grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/$_f" || { fail "REPO-NEXUS block missing from $_f"; exit 1; }
done
grep -q "# Custom Section" "$TEST_PROVIDERS_WS/CLAUDE.md" || { fail "Custom content lost from CLAUDE.md"; exit 1; }
grep -q "# Gemini Custom" "$TEST_PROVIDERS_WS/GEMINI.md" || { fail "Custom content lost from GEMINI.md"; exit 1; }
grep -q "# Cursor Custom" "$TEST_PROVIDERS_WS/.cursorrules" || { fail "Custom content lost from .cursorrules"; exit 1; }
grep -q "# Windsurf Custom" "$TEST_PROVIDERS_WS/.windsurfrules" || { fail "Custom content lost from .windsurfrules"; exit 1; }

# Verify custom ignore files preserved custom entries with !repos/* stripped
[ -f "$TEST_PROVIDERS_WS/.cursorignore" ] || { fail ".cursorignore deleted despite custom content"; exit 1; }
! grep -q '!repos/\*' "$TEST_PROVIDERS_WS/.cursorignore" || { fail "!repos/* not stripped from .cursorignore"; exit 1; }
grep -q "custom-cursor.log" "$TEST_PROVIDERS_WS/.cursorignore" || { fail "custom content lost in .cursorignore"; exit 1; }

[ -f "$TEST_PROVIDERS_WS/.geminiignore" ] || { fail ".geminiignore deleted despite custom content"; exit 1; }
! grep -q '!repos/\*' "$TEST_PROVIDERS_WS/.geminiignore" || { fail "!repos/* not stripped from .geminiignore"; exit 1; }
grep -q "custom-gemini.log" "$TEST_PROVIDERS_WS/.geminiignore" || { fail "custom content lost in .geminiignore"; exit 1; }

# Verify clean removal when no custom content exists
rm -f "$TEST_PROVIDERS_WS/.cursorignore" "$TEST_PROVIDERS_WS/.geminiignore"
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable cursor >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable gemini >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex sync -y --quiet >/dev/null)
[ -f "$TEST_PROVIDERS_WS/.cursorignore" ] || { fail ".cursorignore not recreated"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.geminiignore" ] || { fail ".geminiignore not recreated"; exit 1; }
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable cursor >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable gemini >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex sync -y --quiet >/dev/null)
[ ! -f "$TEST_PROVIDERS_WS/.cursorignore" ] || { fail ".cursorignore without custom content was not removed"; exit 1; }
# Verify custom Copilot instructions in .github/copilot-instructions.md are strictly preserved
mkdir -p "$TEST_PROVIDERS_WS/.github"
cat <<'EOF_COPILOT' > "$TEST_PROVIDERS_WS/.github/copilot-instructions.md"
<!-- REPO-NEXUS:START -->
# Repo Nexus routing block
<!-- REPO-NEXUS:END -->

# My Custom Copilot Developer Rules
1. Never hallucinate.
2. Maintain clean architecture.
EOF_COPILOT

(cd "$TEST_PROVIDERS_WS" && ./rnex sync -y --quiet >/dev/null)
[ -f "$TEST_PROVIDERS_WS/.github/copilot-instructions.md" ] || { fail ".github/copilot-instructions.md with custom content was deleted"; exit 1; }
grep -q "My Custom Copilot Developer Rules" "$TEST_PROVIDERS_WS/.github/copilot-instructions.md" || { fail "Custom Copilot developer rules lost after rnex sync"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/.github/copilot-instructions.md" || { fail "REPO-NEXUS block missing from .github/copilot-instructions.md"; exit 1; }

# Verify enabling copilot plugin manages .github/copilot-instructions.md and .github/skills/
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable copilot >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex sync -y --quiet >/dev/null)
grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/.github/copilot-instructions.md" || { fail "REPO-NEXUS block not merged when copilot enabled"; exit 1; }
grep -q "My Custom Copilot Developer Rules" "$TEST_PROVIDERS_WS/.github/copilot-instructions.md" || { fail "Custom rules lost when copilot merged"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.github/skills/rnex-batch-exec/SKILL.md" ] || { fail "User skills not generated in .github/skills/ when copilot enabled"; exit 1; }

# Verify disabling copilot preserves permanent routing block and cleans user skills while preserving custom instructions
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable copilot >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex sync -y --quiet >/dev/null)
grep -q "REPO-NEXUS:START" "$TEST_PROVIDERS_WS/.github/copilot-instructions.md" || { fail "REPO-NEXUS block lost after copilot disabled"; exit 1; }
grep -q "My Custom Copilot Developer Rules" "$TEST_PROVIDERS_WS/.github/copilot-instructions.md" || { fail "Custom Copilot rules lost after copilot disabled"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Provider integration instructions compiled into .rnex/ai-instructions.md from plugin.yaml"
TEST_INSTR_WS="$TEST_TMP/instr-compile-ws"
mkdir -p "$TEST_INSTR_WS"
cp "$CLI" "$TEST_INSTR_WS/rnex"
chmod +x "$TEST_INSTR_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_INSTR_WS/toolkit"
cp "$DIR/package.json" "$TEST_INSTR_WS/package.json"
git -C "$TEST_INSTR_WS" init -q

"$TEST_INSTR_WS/rnex" init -y --claude "$TEST_INSTR_WS" >/dev/null
[ -f "$TEST_INSTR_WS/.rnex/ai-instructions.md" ] || { fail ".rnex/ai-instructions.md missing after init --claude"; exit 1; }
grep -q "Anthropic Claude Code Integration for Repo Nexus" "$TEST_INSTR_WS/.rnex/ai-instructions.md" || { fail "Claude instructions not compiled into .rnex/ai-instructions.md"; exit 1; }

(cd "$TEST_INSTR_WS" && ./rnex plugin enable gemini >/dev/null)
grep -q "Google Gemini & Antigravity Integration for Repo Nexus" "$TEST_INSTR_WS/.rnex/ai-instructions.md" || { fail "Gemini instructions not compiled into .rnex/ai-instructions.md after enable"; exit 1; }

(cd "$TEST_INSTR_WS" && ./rnex plugin disable claude >/dev/null)
! grep -q "Anthropic Claude Code Integration for Repo Nexus" "$TEST_INSTR_WS/.rnex/ai-instructions.md" || { fail "Claude instructions not removed after disable"; exit 1; }
grep -q "Google Gemini & Antigravity Integration for Repo Nexus" "$TEST_INSTR_WS/.rnex/ai-instructions.md" || { fail "Gemini instructions lost after disabling claude"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Permanent main context instructions: all 7 files preserved across sync, disable, and clean"
TEST_PERM_WS="$TEST_TMP/perm-context-ws"
mkdir -p "$TEST_PERM_WS"
cp "$CLI" "$TEST_PERM_WS/rnex"
chmod +x "$TEST_PERM_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_PERM_WS/toolkit"
cp -r "$DIR/lib" "$TEST_PERM_WS/lib"
cp "$DIR/package.json" "$TEST_PERM_WS/package.json"
git -C "$TEST_PERM_WS" init -q

"$TEST_PERM_WS/rnex" init -y "$TEST_PERM_WS" >/dev/null

# 1. Populate all 7 permanent context files with custom developer text
mkdir -p "$TEST_PERM_WS/.github"
cat <<'EOF_AGENTS' > "$TEST_PERM_WS/AGENTS.md"
# Universal Agents
Custom universal rules.
EOF_AGENTS

cat <<'EOF_CLAUDE' > "$TEST_PERM_WS/CLAUDE.md"
# Claude Guidelines
Custom claude instructions.
EOF_CLAUDE

cat <<'EOF_GEMINI' > "$TEST_PERM_WS/GEMINI.md"
# Gemini Guidelines
Custom gemini instructions.
EOF_GEMINI

cat <<'EOF_CODEX' > "$TEST_PERM_WS/CODEX.md"
# Codex Guidelines
Custom codex instructions.
EOF_CODEX

cat <<'EOF_CURSOR' > "$TEST_PERM_WS/.cursorrules"
# Cursor Guidelines
Custom cursor instructions.
EOF_CURSOR

cat <<'EOF_WINDSURF' > "$TEST_PERM_WS/.windsurfrules"
# Windsurf Guidelines
Custom windsurf instructions.
EOF_WINDSURF

cat <<'EOF_COPILOT' > "$TEST_PERM_WS/.github/copilot-instructions.md"
# Copilot Guidelines
Custom copilot instructions.
EOF_COPILOT

# 2. Run rnex sync — all 7 should have REPO-NEXUS:START routing instructions merged
(cd "$TEST_PERM_WS" && ./rnex sync -y >/dev/null)

_context_files="AGENTS.md CLAUDE.md GEMINI.md CODEX.md .cursorrules .windsurfrules .github/copilot-instructions.md"
for _cf in $_context_files; do
  [ -f "$TEST_PERM_WS/$_cf" ] || { fail "Permanent file $_cf missing after rnex sync"; exit 1; }
  grep -q "REPO-NEXUS:START" "$TEST_PERM_WS/$_cf" || { fail "REPO-NEXUS:START block missing in $_cf after sync"; exit 1; }
  grep -q "Custom " "$TEST_PERM_WS/$_cf" || { fail "Custom developer instructions deleted from $_cf"; exit 1; }
done

# 3. Explicitly invoke clean_rnex_instructions on all 7 — should be protected NO-OP
for _cf in $_context_files; do
  (
    . "$TEST_PERM_WS/lib/sdk.sh"
    clean_rnex_instructions "$TEST_PERM_WS/$_cf"
  )
  [ -f "$TEST_PERM_WS/$_cf" ] || { fail "Permanent file $_cf was deleted by clean_rnex_instructions"; exit 1; }
  grep -q "REPO-NEXUS:START" "$TEST_PERM_WS/$_cf" || { fail "REPO-NEXUS:START stripped from $_cf by clean_rnex_instructions"; exit 1; }
done

# 4. Enable and then disable all provider plugins
for _p in claude gemini codex cursor windsurf copilot; do
  (cd "$TEST_PERM_WS" && ./rnex plugin enable "$_p" >/dev/null)
  (cd "$TEST_PERM_WS" && ./rnex plugin disable "$_p" >/dev/null)
done

# 5. Run sync again with plugins disabled
(cd "$TEST_PERM_WS" && ./rnex sync -y >/dev/null)

for _cf in $_context_files; do
  [ -f "$TEST_PERM_WS/$_cf" ] || { fail "Permanent file $_cf missing after plugin disable and sync"; exit 1; }
  grep -q "REPO-NEXUS:START" "$TEST_PERM_WS/$_cf" || { fail "REPO-NEXUS:START block missing in $_cf after plugin disable"; exit 1; }
  grep -q "Custom " "$TEST_PERM_WS/$_cf" || { fail "Custom developer content lost in $_cf after plugin disable"; exit 1; }
done
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
