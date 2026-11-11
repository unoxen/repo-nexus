#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# plugins/copilot/tests/test_plugin.sh — Copilot Plugin Lifecycle & Hooks
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
[ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
. "$DIR/tests/test_helper.sh"

TEST_COPILOT_WS="$TEST_TMP/copilot-plugin-ws"
mkdir -p "$TEST_COPILOT_WS"
setup_plugin_test_workspace copilot "$TEST_COPILOT_WS"
cd "$TEST_COPILOT_WS"

_copilot_pdir="$TEST_COPILOT_WS/plugins/copilot"

# --------------------------------------------------------------------------
run_test "Copilot plugin: init --copilot provisions instructions and User Skills without AGENTS.md"
"$TEST_COPILOT_WS/rnex" init -y --copilot "$TEST_COPILOT_WS" >/dev/null
[ -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || { fail ".github/copilot-instructions.md missing after init --copilot"; exit 1; }
[ ! -f "$TEST_COPILOT_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created when copilot provides copilot-instructions.md"; exit 1; }

_expected_3line_block="$(printf '%s\n%s\n%s' \
  "<!-- REPO-NEXUS:START -->" \
  "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace." \
  "<!-- REPO-NEXUS:END -->")"
_copilot_block="$(awk '/<!-- REPO-NEXUS:START -->/,/<!-- REPO-NEXUS:END -->/' "$TEST_COPILOT_WS/.github/copilot-instructions.md")"
[ "$_copilot_block" = "$_expected_3line_block" ] || { fail "copilot-instructions.md block did not match expected 3-line block: $_copilot_block"; exit 1; }

# Verify User Skills in .github/skills/
[ -d "$TEST_COPILOT_WS/.github/skills" ] || { fail ".github/skills/ directory missing"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/skills/rnex-clone-sync/SKILL.md" ] || { fail "rnex-clone-sync/SKILL.md missing in .github/skills"; exit 1; }

# Verify integration instructions excluded from compiled .rnex/ai-instructions.md
[ -f "$TEST_COPILOT_WS/.rnex/ai-instructions.md" ] || { fail ".rnex/ai-instructions.md missing"; exit 1; }
! grep -q "GitHub Copilot Integration for Repo Nexus" "$TEST_COPILOT_WS/.rnex/ai-instructions.md" || {
  fail "Copilot integration instructions should not be compiled into .rnex/ai-instructions.md"; exit 1;
}
grep -q "No plugin AI instructions registered." "$TEST_COPILOT_WS/.rnex/ai-instructions.md" || {
  fail "Section 2 should indicate no plugin AI instructions registered for copilot"; exit 1;
}

# Verify integration instructions reference .github/skills/rnex-*/SKILL.md
grep -q "\.github/skills/rnex-\*/SKILL\.md" "$_copilot_pdir/instructions/rnex-copilot-integration.md" || {
  fail "copilot integration missing .github/skills/rnex-*/SKILL.md reference"; exit 1;
}

_status_out="$(cd "$TEST_COPILOT_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q "\.github/copilot-instructions.md" || { fail "Status did not report copilot-instructions.md: $_status_out"; exit 1; }
echo "$_status_out" | grep "copilot" -A 2 | grep -q "Options: skills=" || { fail "Status did not report copilot options: $_status_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Copilot plugin: manifest metadata, version parity, and plugin info"
_cli_ver="$("$TEST_COPILOT_WS/rnex" --version | awk '{print $2}')"
_m_ver="$(awk '/^version:[ ]*/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); print; exit }' "$_copilot_pdir/plugin.yaml")"
[ "$_m_ver" = "$_cli_ver" ] || { fail "Copilot plugin version ($_m_ver) does not match CLI version ($_cli_ver)"; exit 1; }

_pinfo_out="$(cd "$TEST_COPILOT_WS" && ./rnex plugin info copilot 2>&1)"
echo "$_pinfo_out" | grep -q "copilot" || { fail "Copilot missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "\.github/skills/" || { fail "skill_dir .github/skills missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "skills" || { fail "skills option missing from plugin info: $_pinfo_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Copilot plugin: standalone lifecycle hook execution in unpreloaded subshell"
rm -f "$TEST_COPILOT_WS/.github/copilot-instructions.md"

# Run copilot after_sync.sh in an isolated environment with NO preloaded core functions
_sync_out="$(env -i PATH="$PATH" HOME="$HOME" RNEX_ROOT="$TEST_COPILOT_WS" sh "$_copilot_pdir/hooks/after_sync.sh" 2>&1)" || {
  fail "after_sync.sh failed in unpreloaded subshell: $_sync_out"; exit 1;
}
[ -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || { fail "copilot-instructions.md not created by standalone after_sync hook"; exit 1; }
grep -q "CRITICAL: You MUST read and strictly follow all instructions" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || {
  fail "Instructions content missing in standalone after_sync run"; exit 1;
}

# Run copilot before_plugin_disable.sh in an isolated environment with NO preloaded core functions
_dis_out="$(env -i PATH="$PATH" HOME="$HOME" RNEX_ROOT="$TEST_COPILOT_WS" sh "$_copilot_pdir/hooks/before_plugin_disable.sh" 2>&1)" || {
  fail "before_plugin_disable.sh failed in unpreloaded subshell: $_dis_out"; exit 1;
}
[ ! -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || {
  fail "copilot-instructions.md without user content should be removed by standalone before_plugin_disable hook"; exit 1;
}
pass

# --------------------------------------------------------------------------
run_test "Copilot plugin: prompt preservation and clean disable with fallback AGENTS.md"
# Re-enable copilot
(cd "$TEST_COPILOT_WS" && ./rnex plugin enable copilot >/dev/null)

mkdir -p "$TEST_COPILOT_WS/.github/prompts"
printf '# User custom prompt\n' > "$TEST_COPILOT_WS/.github/prompts/user-authored.prompt.md"
printf '# Vendor prompt\n' > "$TEST_COPILOT_WS/.github/prompts/vendor.prompt.md"
printf '# Plugin-owned prompt\n' > "$TEST_COPILOT_WS/.github/prompts/rnex-sample.prompt.md"
printf "\n# Custom Copilot Rules\n1. Do not hallucinate.\n" >> "$TEST_COPILOT_WS/.github/copilot-instructions.md"

(cd "$TEST_COPILOT_WS" && ./rnex sync -y >/dev/null)
grep -q "# Custom Copilot Rules" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || { fail "Custom rules lost on sync"; exit 1; }

# Disable copilot plugin
(cd "$TEST_COPILOT_WS" && ./rnex plugin disable copilot >/dev/null)

# Verify plugin-owned prompt is removed but user/vendor prompts remain
[ ! -f "$TEST_COPILOT_WS/.github/prompts/rnex-sample.prompt.md" ] || { fail "Plugin-owned prompt was not removed"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/prompts/user-authored.prompt.md" ] || { fail "User-authored prompt was deleted"; exit 1; }
[ -f "$TEST_COPILOT_WS/.github/prompts/vendor.prompt.md" ] || { fail "Vendor prompt was deleted"; exit 1; }
[ -d "$TEST_COPILOT_WS/.github/prompts" ] || { fail ".github/prompts directory was removed despite containing user files"; exit 1; }

# Clean remaining user prompts and run disable hook; verify empty directory is removed
rm -f "$TEST_COPILOT_WS/.github/prompts"/*
(RNEX_ROOT="$TEST_COPILOT_WS" "$_copilot_pdir/hooks/before_plugin_disable.sh" >/dev/null 2>&1 || true)
[ ! -d "$TEST_COPILOT_WS/.github/prompts" ] || { fail "Empty .github/prompts directory was not removed"; exit 1; }

# Verify instructions file preserved custom content while REPO-NEXUS block was stripped
[ -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || { fail "copilot-instructions.md with custom content was deleted"; exit 1; }
! grep -q "REPO-NEXUS:START" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || { fail "REPO-NEXUS block not removed from copilot-instructions.md"; exit 1; }
grep -q "Custom Copilot Rules" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || { fail "Custom Copilot rules lost after disable"; exit 1; }

# Fallback AGENTS.md restored
[ -f "$TEST_COPILOT_WS/AGENTS.md" ] || { fail "Fallback AGENTS.md missing after disabling copilot"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_COPILOT_WS/AGENTS.md" || { fail "AGENTS.md missing REPO-NEXUS block after restoring fallback"; exit 1; }

# Clean removal when copilot-instructions.md has no custom content
rm -f "$TEST_COPILOT_WS/.github/copilot-instructions.md"
(cd "$TEST_COPILOT_WS" && ./rnex plugin enable copilot >/dev/null)
[ -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || { fail "copilot-instructions.md not recreated"; exit 1; }
(cd "$TEST_COPILOT_WS" && ./rnex plugin disable copilot >/dev/null)
[ ! -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || { fail "copilot-instructions.md without custom content was not removed"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
