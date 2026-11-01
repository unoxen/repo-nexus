#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/cursor/tests/test_plugin.sh — Cursor Plugin Lifecycle & Rules
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
. "$DIR/tests/test_helper.sh"

TEST_CURSOR_WS="$TEST_TMP/cursor-plugin-ws"
mkdir -p "$TEST_CURSOR_WS"
setup_plugin_test_workspace cursor "$TEST_CURSOR_WS"
cd "$TEST_CURSOR_WS"

# --------------------------------------------------------------------------
run_test "Cursor plugin: init --cursor provisions .cursorrules, .cursorignore, and rules without AGENTS.md"
"$TEST_CURSOR_WS/rnex" init -y --cursor "$TEST_CURSOR_WS" >/dev/null
[ -f "$TEST_CURSOR_WS/.cursorrules" ] || { fail ".cursorrules missing after init --cursor"; exit 1; }
[ -f "$TEST_CURSOR_WS/.cursorignore" ] || { fail ".cursorignore missing after init --cursor"; exit 1; }
grep -q '!repos/\*' "$TEST_CURSOR_WS/.cursorignore" || { fail "!repos/* missing in .cursorignore"; exit 1; }
[ ! -f "$TEST_CURSOR_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created when cursor provides .cursorrules"; exit 1; }

_expected_3line_block="$(printf '%s\n%s\n%s' \
  "<!-- REPO-NEXUS:START -->" \
  "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace." \
  "<!-- REPO-NEXUS:END -->")"
_cursor_block="$(awk '/<!-- REPO-NEXUS:START -->/,/<!-- REPO-NEXUS:END -->/' "$TEST_CURSOR_WS/.cursorrules")"
[ "$_cursor_block" = "$_expected_3line_block" ] || { fail ".cursorrules block did not match expected 3-line block: $_cursor_block"; exit 1; }

_cursor_mdc_block="$(awk '/<!-- REPO-NEXUS:START -->/,/<!-- REPO-NEXUS:END -->/' "$TEST_CURSOR_WS/.cursor/rules/rnex-context.mdc")"
[ "$_cursor_mdc_block" = "$_expected_3line_block" ] || { fail "rnex-context.mdc block did not match expected 3-line block: $_cursor_mdc_block"; exit 1; }

# Verify flat User Skills generated in .cursor/rules/
[ -f "$TEST_CURSOR_WS/.cursor/rules/rnex-clone-sync.md" ] || { fail "rnex-clone-sync.md missing in .cursor/rules/"; exit 1; }
[ -f "$TEST_CURSOR_WS/.cursor/rules/rnex-batch-exec.md" ] || { fail "rnex-batch-exec.md missing in .cursor/rules/"; exit 1; }
[ -f "$TEST_CURSOR_WS/.cursor/rules/rnex-workspace-status.md" ] || { fail "rnex-workspace-status.md missing in .cursor/rules/"; exit 1; }

# Verify integration instructions excluded from compiled .rnex/ai-instructions.md
[ -f "$TEST_CURSOR_WS/.rnex/ai-instructions.md" ] || { fail ".rnex/ai-instructions.md missing"; exit 1; }
! grep -q "Cursor IDE Integration for Repo Nexus" "$TEST_CURSOR_WS/.rnex/ai-instructions.md" || {
  fail "Cursor integration instructions should not be compiled into .rnex/ai-instructions.md"; exit 1;
}

_status_out="$(cd "$TEST_CURSOR_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q "\.cursorrules" || { fail "Status did not report .cursorrules: $_status_out"; exit 1; }
echo "$_status_out" | grep -q "\.cursor/rules/" || { fail "Status did not report .cursor/rules/: $_status_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Cursor plugin: manifest metadata, version parity, and plugin info"
_cli_ver="$("$TEST_CURSOR_WS/rnex" --version | awk '{print $2}')"
_m_ver="$(awk '/^version:[ ]*/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); print; exit }' "$TEST_CURSOR_WS/toolkit/plugins/cursor/plugin.yaml")"
[ "$_m_ver" = "$_cli_ver" ] || { fail "Cursor plugin version ($_m_ver) does not match CLI version ($_cli_ver)"; exit 1; }

_pinfo_out="$(cd "$TEST_CURSOR_WS" && ./rnex plugin info cursor 2>&1)"
echo "$_pinfo_out" | grep -q "cursor" || { fail "Cursor missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "\.cursor/rules/" || { fail "skill_dir .cursor/rules missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "skills" || { fail "skills option missing from plugin info: $_pinfo_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Cursor plugin: custom content preservation and clean disable with fallback AGENTS.md"
printf "\n# Custom Cursor Rules\nAlways check bounds.\n" >> "$TEST_CURSOR_WS/.cursorrules"
printf "custom-cursor.log\n" >> "$TEST_CURSOR_WS/.cursorignore"
echo "custom" > "$TEST_CURSOR_WS/.cursor/rules/my-user-rule.mdc"

(cd "$TEST_CURSOR_WS" && ./rnex sync -y >/dev/null)
grep -q "# Custom Cursor Rules" "$TEST_CURSOR_WS/.cursorrules" || { fail "Custom rules lost on sync"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_CURSOR_WS/.cursorrules" || { fail "REPO-NEXUS block missing on sync"; exit 1; }
grep -q "custom-cursor.log" "$TEST_CURSOR_WS/.cursorignore" || { fail "custom ignore lost on sync"; exit 1; }
[ -f "$TEST_CURSOR_WS/.cursor/rules/my-user-rule.mdc" ] || { fail "Custom user rule lost on sync"; exit 1; }

# Disable cursor plugin
(cd "$TEST_CURSOR_WS" && ./rnex plugin disable cursor >/dev/null)
[ -f "$TEST_CURSOR_WS/.cursorrules" ] || { fail ".cursorrules with custom content was deleted on disable"; exit 1; }
! grep -q "REPO-NEXUS:START" "$TEST_CURSOR_WS/.cursorrules" || { fail "REPO-NEXUS block was not removed from disabled .cursorrules"; exit 1; }
grep -q "# Custom Cursor Rules" "$TEST_CURSOR_WS/.cursorrules" || { fail "Custom rules lost after disable"; exit 1; }

[ -f "$TEST_CURSOR_WS/.cursorignore" ] || { fail ".cursorignore with custom rules was deleted on disable"; exit 1; }
! grep -q '!repos/\*' "$TEST_CURSOR_WS/.cursorignore" || { fail "!repos/* not stripped from disabled .cursorignore"; exit 1; }
grep -q "custom-cursor.log" "$TEST_CURSOR_WS/.cursorignore" || { fail "custom ignore lost after disable"; exit 1; }

# Fallback AGENTS.md restored
[ -f "$TEST_CURSOR_WS/AGENTS.md" ] || { fail "Fallback AGENTS.md not restored after disabling cursor"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_CURSOR_WS/AGENTS.md" || { fail "REPO-NEXUS block missing from fallback AGENTS.md"; exit 1; }
[ ! -f "$TEST_CURSOR_WS/.cursor/rules/rnex-clone-sync.md" ] || { fail "rnex User Skills not cleaned on disable"; exit 1; }
[ -f "$TEST_CURSOR_WS/.cursor/rules/my-user-rule.mdc" ] || { fail "Custom user rule was deleted on disable"; exit 1; }

# Clean removal when .cursorrules and .cursorignore have no custom content
rm -f "$TEST_CURSOR_WS/.cursorrules" "$TEST_CURSOR_WS/.cursorignore"
(cd "$TEST_CURSOR_WS" && ./rnex plugin enable cursor >/dev/null)
[ -f "$TEST_CURSOR_WS/.cursorrules" ] || { fail ".cursorrules not recreated"; exit 1; }
[ -f "$TEST_CURSOR_WS/.cursorignore" ] || { fail ".cursorignore not recreated"; exit 1; }
(cd "$TEST_CURSOR_WS" && ./rnex plugin disable cursor >/dev/null)
[ ! -f "$TEST_CURSOR_WS/.cursorrules" ] || { fail ".cursorrules without custom content was not deleted on disable"; exit 1; }
[ ! -f "$TEST_CURSOR_WS/.cursorignore" ] || { fail ".cursorignore without custom content was not deleted on disable"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
