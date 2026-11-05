#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# plugins/codex/tests/test_plugin.sh — Codex Plugin Lifecycle & User Skills
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
[ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
. "$DIR/tests/test_helper.sh"

TEST_CODEX_WS="$TEST_TMP/codex-plugin-ws"
mkdir -p "$TEST_CODEX_WS"
setup_plugin_test_workspace codex "$TEST_CODEX_WS"
cd "$TEST_CODEX_WS"

# --------------------------------------------------------------------------
run_test "Codex plugin: init --codex provisions CODEX.md and User Skills without AGENTS.md"
"$TEST_CODEX_WS/rnex" init -y --codex "$TEST_CODEX_WS" >/dev/null
[ -f "$TEST_CODEX_WS/CODEX.md" ] || { fail "CODEX.md missing after init --codex"; exit 1; }
[ ! -f "$TEST_CODEX_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created when codex provides CODEX.md"; exit 1; }

_expected_3line_block="$(printf '%s\n%s\n%s' \
  "<!-- REPO-NEXUS:START -->" \
  "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace." \
  "<!-- REPO-NEXUS:END -->")"
_codex_block="$(awk '/<!-- REPO-NEXUS:START -->/,/<!-- REPO-NEXUS:END -->/' "$TEST_CODEX_WS/CODEX.md")"
[ "$_codex_block" = "$_expected_3line_block" ] || { fail "CODEX.md block did not match expected 3-line block: $_codex_block"; exit 1; }

# Verify User Skills in .codex/skills/
[ -d "$TEST_CODEX_WS/.codex/skills" ] || { fail ".codex/skills/ directory missing"; exit 1; }
[ -f "$TEST_CODEX_WS/.codex/skills/rnex-clone-sync/SKILL.md" ] || { fail "rnex-clone-sync/SKILL.md missing in .codex/skills"; exit 1; }
[ -f "$TEST_CODEX_WS/.codex/skills/rnex-batch-exec/SKILL.md" ] || { fail "rnex-batch-exec/SKILL.md missing in .codex/skills"; exit 1; }
[ -f "$TEST_CODEX_WS/.codex/skills/rnex-workspace-status/SKILL.md" ] || { fail "rnex-workspace-status/SKILL.md missing in .codex/skills"; exit 1; }

# Verify integration instructions excluded from compiled .rnex/ai-instructions.md
[ -f "$TEST_CODEX_WS/.rnex/ai-instructions.md" ] || { fail ".rnex/ai-instructions.md missing"; exit 1; }
! grep -q "OpenAI Codex Integration for Repo Nexus" "$TEST_CODEX_WS/.rnex/ai-instructions.md" || {
  fail "Codex integration instructions should not be compiled into .rnex/ai-instructions.md"; exit 1;
}

_status_out="$(cd "$TEST_CODEX_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q "CODEX.md" || { fail "Status did not report CODEX.md: $_status_out"; exit 1; }
echo "$_status_out" | grep -q "\.codex/skills/" || { fail "Status did not report .codex/skills/: $_status_out"; exit 1; }
echo "$_status_out" | grep "codex" -A 2 | grep -q "Options: skills=" || { fail "Status did not report codex plugin options: $_status_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Codex plugin: manifest metadata, version parity, and plugin info"
_cli_ver="$("$TEST_CODEX_WS/rnex" --version | awk '{print $2}')"
_codex_manifest="$TEST_CODEX_WS/plugins/codex/plugin.yaml"
_m_ver="$(awk '/^version:[ ]*/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); print; exit }' "$_codex_manifest")"
[ "$_m_ver" = "$_cli_ver" ] || { fail "Codex plugin version ($_m_ver) does not match CLI version ($_cli_ver)"; exit 1; }

_pinfo_out="$(cd "$TEST_CODEX_WS" && ./rnex plugin info codex 2>&1)"
echo "$_pinfo_out" | grep -q "codex" || { fail "Codex missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "\.codex/skills/" || { fail "skill_dir .codex/skills missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "skills" || { fail "skills option missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "hooks" || { fail "hooks option missing from plugin info: $_pinfo_out"; exit 1; }
[ -x "$TEST_CODEX_WS/.codex/hooks/rnex-hook-session-start.sh" ] || { fail ".codex/hooks/rnex-hook-session-start.sh missing"; exit 1; }
[ -f "$TEST_CODEX_WS/.codex/hooks/rnex-hooks.json" ] || { fail ".codex/hooks/rnex-hooks.json missing"; exit 1; }
grep -q "\.rnex/plugins/codex/hooks/rnex-hook-session-start\.sh" "$TEST_CODEX_WS/.codex/hooks/rnex-hook-session-start.sh" || {
  fail ".codex/hooks/rnex-hook-session-start.sh does not reference .rnex working script"; exit 1;
}
pass

# --------------------------------------------------------------------------
run_test "Codex plugin: custom content preservation and clean disable with fallback AGENTS.md"
printf "\n# Custom Codex Rules\nWrite concise code.\n" >> "$TEST_CODEX_WS/CODEX.md"
mkdir -p "$TEST_CODEX_WS/.codex/skills/custom-skill"
echo "custom" > "$TEST_CODEX_WS/.codex/skills/custom-skill/SKILL.md"

(cd "$TEST_CODEX_WS" && ./rnex sync -y >/dev/null)
grep -q "# Custom Codex Rules" "$TEST_CODEX_WS/CODEX.md" || { fail "Custom rules lost on sync"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_CODEX_WS/CODEX.md" || { fail "REPO-NEXUS block missing on sync"; exit 1; }
[ -f "$TEST_CODEX_WS/.codex/skills/custom-skill/SKILL.md" ] || { fail "Custom user skill lost on sync"; exit 1; }

# Disable codex plugin
(cd "$TEST_CODEX_WS" && ./rnex plugin disable codex >/dev/null)
[ -f "$TEST_CODEX_WS/CODEX.md" ] || { fail "CODEX.md with custom content was deleted on disable"; exit 1; }
! grep -q "REPO-NEXUS:START" "$TEST_CODEX_WS/CODEX.md" || { fail "REPO-NEXUS block was not removed from disabled CODEX.md"; exit 1; }
grep -q "# Custom Codex Rules" "$TEST_CODEX_WS/CODEX.md" || { fail "Custom rules lost after disable"; exit 1; }

# Fallback AGENTS.md restored
[ -f "$TEST_CODEX_WS/AGENTS.md" ] || { fail "Fallback AGENTS.md not restored after disabling codex"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_CODEX_WS/AGENTS.md" || { fail "REPO-NEXUS block missing from fallback AGENTS.md"; exit 1; }
[ ! -d "$TEST_CODEX_WS/.codex/skills/rnex-clone-sync" ] || { fail "rnex User Skills not cleaned on disable"; exit 1; }
[ -f "$TEST_CODEX_WS/.codex/skills/custom-skill/SKILL.md" ] || { fail "Custom user skill was deleted on disable"; exit 1; }

# Clean removal when CODEX.md has no custom content
rm -f "$TEST_CODEX_WS/CODEX.md"
(cd "$TEST_CODEX_WS" && ./rnex plugin enable codex >/dev/null)
[ -f "$TEST_CODEX_WS/CODEX.md" ] || { fail "CODEX.md not recreated"; exit 1; }
(cd "$TEST_CODEX_WS" && ./rnex plugin disable codex >/dev/null)
[ ! -f "$TEST_CODEX_WS/CODEX.md" ] || { fail "CODEX.md without custom content was not deleted on disable"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
