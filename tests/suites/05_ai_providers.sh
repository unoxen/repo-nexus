#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/05_ai_providers.sh — AI Provider Plugins Sync & Cleanup (Tests 32-33)
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/tests/test_helper.sh"

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

# Universal AGENTS.md created
[ -f "$TEST_COPILOT_WS/AGENTS.md" ] || { fail "AGENTS.md missing after init --copilot"; exit 1; }

# Verify .github/prompts/*.prompt.md files created with frontmatter
[ -d "$TEST_COPILOT_WS/.github/prompts" ] || { fail ".github/prompts directory missing"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "rnex-cross-repo-feature.prompt.md missing"; exit 1; }
grep -q "name: rnex-cross-repo-feature" "$TEST_COPILOT_WS/.github/prompts/rnex-cross-repo-feature.prompt.md" || { fail "Missing frontmatter in .prompt.md"; exit 1; }

# Verify .github/skills/, .github/agents/, and .github/copilot-instructions.md are NOT created
[ ! -d "$TEST_COPILOT_WS/.github/skills" ] || { fail ".github/skills folder should not be created"; exit 1; }
[ ! -d "$TEST_COPILOT_WS/.github/agents" ] || { fail ".github/agents folder should not be created"; exit 1; }
[ ! -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || { fail ".github/copilot-instructions.md should not be created"; exit 1; }

# Verify plugin list and plugin info
_cop_list="$(cd "$TEST_COPILOT_WS" && ./rnex plugin list 2>&1)"
echo "$_cop_list" | grep -q "copilot" || { fail "plugin list did not list copilot plugin"; exit 1; }
_cop_info="$(cd "$TEST_COPILOT_WS" && ./rnex plugin info copilot 2>&1)"
echo "$_cop_info" | grep -q "prompts: true|false" || { fail "plugin info did not show prompts option"; exit 1; }
echo "$_cop_info" | grep -q "workflows: true|false" || { fail "plugin info did not show workflows option"; exit 1; }

# Verify status highlights copilot plugin, options, and prompts directory
_cop_status="$(cd "$TEST_COPILOT_WS" && ./rnex status 2>&1)"
echo "$_cop_status" | grep -q "copilot" || { fail "Status did not report copilot plugin"; exit 1; }
echo "$_cop_status" | grep -q ".github/prompts/" || { fail "Status did not report .github/prompts/"; exit 1; }
echo "$_cop_status" | grep -q "prompts=true" || { fail "Status did not report copilot prompts option"; exit 1; }

# Enable karpathy-llm alongside copilot: workflows mirrored as prompts only
(cd "$TEST_COPILOT_WS" && ./rnex plugin enable karpathy-llm >/dev/null)
(cd "$TEST_COPILOT_WS" && ./rnex sync -y --quiet >/dev/null)

# Verify Karpathy workflows mirrored to .github/prompts/
[ -f "$TEST_COPILOT_WS/.github/prompts/rnex-wiki-ingest.prompt.md" ] || { fail "rnex-wiki-ingest prompt not mirrored to .github/prompts/"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/prompts/rnex-wiki-lint.prompt.md" ] || { fail "rnex-wiki-lint prompt not mirrored to .github/prompts/"; exit 1; }
grep -q "name: rnex-wiki-ingest" "$TEST_COPILOT_WS/.github/prompts/rnex-wiki-ingest.prompt.md" || { fail "rnex-wiki-ingest prompt missing frontmatter"; exit 1; }

# Verify skills and agents are NOT mirrored
[ ! -d "$TEST_COPILOT_WS/.github/skills" ] || { fail "Skills mirrored to .github/skills"; exit 1; }
[ ! -d "$TEST_COPILOT_WS/.github/agents" ] || { fail "Agents mirrored to .github/agents"; exit 1; }

# Add custom user skill, agent, prompt, and custom developer copilot-instructions.md
mkdir -p "$TEST_COPILOT_WS/.github/skills/user-custom-skill"
echo "# User Skill" > "$TEST_COPILOT_WS/.github/skills/user-custom-skill/SKILL.md"
mkdir -p "$TEST_COPILOT_WS/.github/agents"
echo "# User Agent" > "$TEST_COPILOT_WS/.github/agents/user-custom.agent.md"
mkdir -p "$TEST_COPILOT_WS/.github/prompts"
echo "# User Prompt" > "$TEST_COPILOT_WS/.github/prompts/user-custom.prompt.md"
echo "# Custom Developer Section" > "$TEST_COPILOT_WS/.github/copilot-instructions.md"

# Simulate legacy mirrored skill and verify rnex sync purges it while keeping user files
mkdir -p "$TEST_COPILOT_WS/.github/skills/rnex-cross-repo-feature"
echo "# Legacy Mirrored" > "$TEST_COPILOT_WS/.github/skills/rnex-cross-repo-feature/SKILL.md"
mkdir -p "$TEST_COPILOT_WS/.github/agents"
echo "# Legacy Agent" > "$TEST_COPILOT_WS/.github/agents/rnex-wiki-curator.agent.md"

(cd "$TEST_COPILOT_WS" && ./rnex sync -y --quiet >/dev/null)
[ ! -d "$TEST_COPILOT_WS/.github/skills/rnex-cross-repo-feature" ] || { fail "Legacy mirrored skill not cleaned up by sync"; exit 1; }
[ ! -f "$TEST_COPILOT_WS/.github/agents/rnex-wiki-curator.agent.md" ] || { fail "Legacy mirrored agent not cleaned up by sync"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/skills/user-custom-skill/SKILL.md" ] || { fail "User custom skill deleted"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/agents/user-custom.agent.md" ] || { fail "User custom agent deleted"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/prompts/user-custom.prompt.md" ] || { fail "User custom prompt deleted"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || { fail "User copilot-instructions.md deleted"; exit 1; }
grep -q "Custom Developer Section" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || { fail "User content lost in copilot-instructions.md"; exit 1; }

# Disable prompts option in rnex.yaml
cat <<EOF > "$TEST_COPILOT_WS/rnex.yaml"
version: 0.5.15
repos_dir: ./repos
code_workspace: false
git_hooks: false
plugins:
  copilot:
    prompts: false
    workflows: false
  karpathy-llm: {}
repos:
EOF
(cd "$TEST_COPILOT_WS" && ./rnex sync -y --quiet >/dev/null)
[ ! -f "$TEST_COPILOT_WS/.github/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "Base prompts not cleaned up when prompts: false"; exit 1; }
[ ! -f "$TEST_COPILOT_WS/.github/prompts/rnex-wiki-ingest.prompt.md" ] || { fail "Plugin prompts not cleaned up when prompts: false"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/prompts/user-custom.prompt.md" ] || { fail "User prompt deleted when prompts: false"; exit 1; }

# Disable copilot via local override and run sync
(cd "$TEST_COPILOT_WS" && ./rnex plugin disable --local copilot >/dev/null)
(cd "$TEST_COPILOT_WS" && ./rnex sync -y --quiet >/dev/null)
[ ! -f "$TEST_COPILOT_WS/.github/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "Prompts not cleaned up when copilot disabled locally"; exit 1; }

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
[ -f "$TEST_PROVIDERS_WS/AGENTS.md" ] || { fail "AGENTS.md missing after init --claude"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/CLAUDE.md" ] || { fail "CLAUDE.md missing after init --claude"; exit 1; }
[ ! -d "$TEST_PROVIDERS_WS/.claude/skills" ] || { fail ".claude/skills should not be created"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.claude/commands/rnex-cross-repo-feature.md" ] || { fail "Claude commands missing"; exit 1; }

# Enable gemini plugin
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable gemini >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex sync -y --quiet >/dev/null)
[ -f "$TEST_PROVIDERS_WS/GEMINI.md" ] || { fail "GEMINI.md missing after enabling gemini"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.geminiignore" ] || { fail ".geminiignore missing after enabling gemini"; exit 1; }
grep -q '!repos/\*' "$TEST_PROVIDERS_WS/.geminiignore" || { fail "!repos/* missing from .geminiignore"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.gemini/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "Gemini prompts missing"; exit 1; }
[ ! -d "$TEST_PROVIDERS_WS/.gemini/skills" ] || { fail "Gemini skills should not be created"; exit 1; }

# Enable cursor and windsurf plugins
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable cursor >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin enable windsurf >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex sync -y --quiet >/dev/null)
[ -f "$TEST_PROVIDERS_WS/.cursorrules" ] || { fail ".cursorrules missing after enabling cursor"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursorignore" ] || { fail ".cursorignore missing after enabling cursor"; exit 1; }
grep -q '!repos/\*' "$TEST_PROVIDERS_WS/.cursorignore" || { fail "!repos/* missing from .cursorignore"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursor/rules/rnex-context.mdc" ] || { fail ".cursor/rules/rnex-context.mdc missing"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.cursor/prompts/rnex-cross-repo-feature.md" ] || { fail "Cursor prompts missing"; exit 1; }
[ ! -d "$TEST_PROVIDERS_WS/.cursor/skills" ] || { fail "Cursor skills should not be created"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.windsurfrules" ] || { fail ".windsurfrules missing after enabling windsurf"; exit 1; }
[ -f "$TEST_PROVIDERS_WS/.windsurf/prompts/rnex-cross-repo-feature.md" ] || { fail "Windsurf prompts missing"; exit 1; }
[ ! -d "$TEST_PROVIDERS_WS/.windsurf/skills" ] || { fail "Windsurf skills should not be created"; exit 1; }

# Status command reports all enabled AI providers
_prov_status="$(cd "$TEST_PROVIDERS_WS" && ./rnex status 2>&1)"
echo "$_prov_status" | grep -q "AGENTS.md" || { fail "Status did not report AGENTS.md"; exit 1; }
echo "$_prov_status" | grep -q "CLAUDE.md" || { fail "Status did not report CLAUDE.md"; exit 1; }
echo "$_prov_status" | grep -q "GEMINI.md" || { fail "Status did not report GEMINI.md"; exit 1; }
echo "$_prov_status" | grep -q "\.cursorrules" || { fail "Status did not report .cursorrules"; exit 1; }
echo "$_prov_status" | grep -q "\.windsurfrules" || { fail "Status did not report .windsurfrules"; exit 1; }
echo "$_prov_status" | grep -q ".claude/commands/" || { fail "Status did not report .claude/commands/"; exit 1; }
echo "$_prov_status" | grep -q ".gemini/prompts/" || { fail "Status did not report .gemini/prompts/"; exit 1; }
echo "$_prov_status" | grep -q ".cursor/prompts/" || { fail "Status did not report .cursor/prompts/"; exit 1; }
echo "$_prov_status" | grep -q ".windsurf/prompts/" || { fail "Status did not report .windsurf/prompts/"; exit 1; }

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

# Disable all provider plugins and verify AGENTS.md remains intact
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable claude >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable gemini >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable cursor >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex plugin disable windsurf >/dev/null)
(cd "$TEST_PROVIDERS_WS" && ./rnex sync -y --quiet >/dev/null)

[ -f "$TEST_PROVIDERS_WS/AGENTS.md" ] || { fail "AGENTS.md not preserved when all AI provider plugins disabled"; exit 1; }

# Verify Repo Nexus generated assets were cleaned up
[ ! -f "$TEST_PROVIDERS_WS/.claude/commands/rnex-cross-repo-feature.md" ] || { fail "rnex prompt not cleaned from claude"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.gemini/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "rnex prompt not cleaned from gemini"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.cursor/prompts/rnex-cross-repo-feature.md" ] || { fail "rnex prompt not cleaned from cursor"; exit 1; }
[ ! -f "$TEST_PROVIDERS_WS/.windsurf/prompts/rnex-cross-repo-feature.md" ] || { fail "rnex prompt not cleaned from windsurf"; exit 1; }

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
[ ! -f "$TEST_PROVIDERS_WS/.geminiignore" ] || { fail ".geminiignore without custom content was not removed"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
