#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# plugins/gemini/tests/test_plugin.sh — Gemini Plugin Lifecycle & User Skills
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
[ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
. "$DIR/tests/test_helper.sh"

TEST_GEMINI_WS="$TEST_TMP/gemini-plugin-ws"
mkdir -p "$TEST_GEMINI_WS"
setup_plugin_test_workspace gemini "$TEST_GEMINI_WS"
cd "$TEST_GEMINI_WS"

# --------------------------------------------------------------------------
run_test "Gemini plugin: init --gemini provisions GEMINI.md, .geminiignore, and User Skills without AGENTS.md"
# Create a legacy .gemini/skills directory to verify migration/cleanup
mkdir -p "$TEST_GEMINI_WS/.gemini/skills/rnex-legacy-skill"
echo "legacy" > "$TEST_GEMINI_WS/.gemini/skills/rnex-legacy.md"

"$TEST_GEMINI_WS/rnex" init -y --gemini "$TEST_GEMINI_WS" >/dev/null
[ -f "$TEST_GEMINI_WS/GEMINI.md" ] || { fail "GEMINI.md missing after init --gemini"; exit 1; }
[ -f "$TEST_GEMINI_WS/.geminiignore" ] || { fail ".geminiignore missing after init --gemini"; exit 1; }
grep -qFx "# REPO-NEXUS:START" "$TEST_GEMINI_WS/.geminiignore" || { fail ".geminiignore missing # REPO-NEXUS:START"; exit 1; }
grep -qFx "# REPO-NEXUS:END" "$TEST_GEMINI_WS/.geminiignore" || { fail ".geminiignore missing # REPO-NEXUS:END"; exit 1; }
grep -q '!repos/\*' "$TEST_GEMINI_WS/.geminiignore" || { fail "!repos/* missing in .geminiignore"; exit 1; }
[ ! -f "$TEST_GEMINI_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created when gemini provides GEMINI.md"; exit 1; }

_expected_3line_block="$(printf '%s\n%s\n%s' \
  "<!-- REPO-NEXUS:START -->" \
  "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace." \
  "<!-- REPO-NEXUS:END -->")"
_gemini_block="$(awk '/<!-- REPO-NEXUS:START -->/,/<!-- REPO-NEXUS:END -->/' "$TEST_GEMINI_WS/GEMINI.md")"
[ "$_gemini_block" = "$_expected_3line_block" ] || { fail "GEMINI.md block did not match expected 3-line block: $_gemini_block"; exit 1; }

# Verify legacy .gemini/skills was purged and .agents/skills created
[ ! -d "$TEST_GEMINI_WS/.gemini/skills" ] || { fail "legacy .gemini/skills was not purged on sync"; exit 1; }
[ -d "$TEST_GEMINI_WS/.agents/skills" ] || { fail ".agents/skills missing after init --gemini"; exit 1; }
[ -f "$TEST_GEMINI_WS/.agents/skills/rnex-clone-sync/SKILL.md" ] || { fail "rnex-clone-sync/SKILL.md missing in .agents/skills"; exit 1; }

# Verify integration instructions excluded from compiled .rnex/ai-instructions.md
[ -f "$TEST_GEMINI_WS/.rnex/ai-instructions.md" ] || { fail ".rnex/ai-instructions.md missing"; exit 1; }
! grep -q "Google Gemini & Antigravity Integration" "$TEST_GEMINI_WS/.rnex/ai-instructions.md" || {
  fail "Gemini integration instructions should not be compiled into .rnex/ai-instructions.md"; exit 1;
}

_status_out="$(cd "$TEST_GEMINI_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q "GEMINI.md" || { fail "Status did not report GEMINI.md"; exit 1; }
echo "$_status_out" | grep -q "\.agents/skills/" || { fail "Status did not report .agents/skills/"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Gemini plugin: manifest metadata, version parity, and plugin info"
_cli_ver="$("$TEST_GEMINI_WS/rnex" --version | awk '{print $2}')"
_gemini_manifest="$TEST_GEMINI_WS/plugins/gemini/plugin.yaml"
[ -f "$_gemini_manifest" ] || _gemini_manifest="$TEST_GEMINI_WS/toolkit/plugins/gemini/plugin.yaml"
_m_ver="$(awk '/^version:[ ]*/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); print; exit }' "$_gemini_manifest")"
[ "$_m_ver" = "$_cli_ver" ] || { fail "Gemini plugin version ($_m_ver) does not match CLI version ($_cli_ver)"; exit 1; }

_pinfo_out="$(cd "$TEST_GEMINI_WS" && ./rnex plugin info gemini 2>&1)"
echo "$_pinfo_out" | grep -q "gemini" || { fail "Gemini missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "\.agents/skills/" || { fail "skill_dir .agents/skills missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "hooks" || { fail "hooks missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "skills" || { fail "skills option missing from plugin info: $_pinfo_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Gemini plugin: hooks configuration in .agents/hooks/rnex-hook-*.sh, .agents/hooks.json, and rnex-env.sh check"
[ -f "$TEST_GEMINI_WS/.agents/hooks.json" ] || { fail ".agents/hooks.json missing"; exit 1; }
[ -x "$TEST_GEMINI_WS/.agents/hooks/rnex-hook-session-start.sh" ] || { fail ".agents/hooks/rnex-hook-session-start.sh missing or not executable"; exit 1; }
[ -x "$TEST_GEMINI_WS/.rnex/plugins/gemini/hooks/rnex-hook-session-start.sh" ] || { fail ".rnex/plugins/gemini/hooks/rnex-hook-session-start.sh missing or not executable"; exit 1; }
grep -q "\.rnex/plugins/gemini/hooks/rnex-hook-session-start\.sh" "$TEST_GEMINI_WS/.agents/hooks/rnex-hook-session-start.sh" || {
  fail ".agents/hooks/rnex-hook-session-start.sh does not reference .rnex working script"; exit 1;
}
grep -q '"rnex-hook-session-start"' "$TEST_GEMINI_WS/.agents/hooks.json" || { fail "rnex-hook-session-start missing in hooks.json"; exit 1; }
grep -q '"SessionStart"' "$TEST_GEMINI_WS/.agents/hooks.json" || { fail "SessionStart hook missing in hooks.json"; exit 1; }
grep -q '"command"[ ]*:[ ]*"\.agents/hooks/rnex-hook-session-start\.sh"' "$TEST_GEMINI_WS/.agents/hooks.json" || {
  fail "rnex-hook-session-start.sh command missing in hooks.json"; exit 1;
}

# Verify generated .rnex/bin/rnex-env.sh does not contain legacy .gemini check
# shellcheck disable=SC2016
! grep -q '\[ -d "\$RNEX_ROOT/\.gemini" \]' "$TEST_GEMINI_WS/.rnex/bin/rnex-env.sh" || {
  fail ".rnex/bin/rnex-env.sh still contains .gemini check"; exit 1;
}

# Disable hooks: false in rnex.yaml
cat <<'EOF_CFG' > "$TEST_GEMINI_WS/rnex.yaml"
version: 1.0.0
plugins:
  gemini:
    skills: true
    hooks: false
repos:
EOF_CFG
(cd "$TEST_GEMINI_WS" && ./rnex sync -y >/dev/null)
[ ! -f "$TEST_GEMINI_WS/.agents/hooks.json" ] || { fail ".agents/hooks.json should be removed when empty"; exit 1; }
[ ! -f "$TEST_GEMINI_WS/.agents/hooks/rnex-hook-session-start.sh" ] || { fail ".agents/hooks/rnex-hook-session-start.sh should be removed when hooks: false"; exit 1; }

# Re-enable with hooks map
cat <<'EOF_CFG2' > "$TEST_GEMINI_WS/rnex.yaml"
version: 1.0.0
plugins:
  gemini:
    skills: true
    hooks:
      SessionStart:
        - "rnex sync --quiet"
repos:
EOF_CFG2
(cd "$TEST_GEMINI_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_GEMINI_WS/.agents/hooks.json" ] || { fail ".agents/hooks.json not restored with hooks"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Gemini plugin: custom content preservation and clean disable with fallback AGENTS.md"
printf "\n# Custom Gemini Guidelines\nAlways write pure functions.\n" >> "$TEST_GEMINI_WS/GEMINI.md"
printf "custom-gemini.log\n" >> "$TEST_GEMINI_WS/.geminiignore"
mkdir -p "$TEST_GEMINI_WS/.agents/skills/my-gemini-skill"
echo "custom" > "$TEST_GEMINI_WS/.agents/skills/my-gemini-skill/SKILL.md"

(cd "$TEST_GEMINI_WS" && ./rnex sync -y >/dev/null)
grep -q "# Custom Gemini Guidelines" "$TEST_GEMINI_WS/GEMINI.md" || { fail "Custom guidelines lost on sync"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_GEMINI_WS/GEMINI.md" || { fail "REPO-NEXUS block missing on sync"; exit 1; }
grep -q "custom-gemini.log" "$TEST_GEMINI_WS/.geminiignore" || { fail "custom ignore lost on sync"; exit 1; }
[ -f "$TEST_GEMINI_WS/.agents/skills/my-gemini-skill/SKILL.md" ] || { fail "Custom user skill lost on sync"; exit 1; }

# Disable gemini plugin
(cd "$TEST_GEMINI_WS" && ./rnex plugin disable gemini >/dev/null)
[ -f "$TEST_GEMINI_WS/GEMINI.md" ] || { fail "GEMINI.md with custom content was deleted on disable"; exit 1; }
! grep -q "REPO-NEXUS:START" "$TEST_GEMINI_WS/GEMINI.md" || { fail "REPO-NEXUS block was not removed from disabled GEMINI.md"; exit 1; }
grep -q "# Custom Gemini Guidelines" "$TEST_GEMINI_WS/GEMINI.md" || { fail "Custom guidelines lost after disable"; exit 1; }

[ -f "$TEST_GEMINI_WS/.geminiignore" ] || { fail ".geminiignore with custom rules was deleted on disable"; exit 1; }
! grep -q '!repos/\*' "$TEST_GEMINI_WS/.geminiignore" || { fail "!repos/* not stripped from disabled .geminiignore"; exit 1; }
grep -q "custom-gemini.log" "$TEST_GEMINI_WS/.geminiignore" || { fail "custom ignore lost after disable"; exit 1; }

# Fallback AGENTS.md restored
[ -f "$TEST_GEMINI_WS/AGENTS.md" ] || { fail "Fallback AGENTS.md not restored after disabling gemini"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_GEMINI_WS/AGENTS.md" || { fail "REPO-NEXUS block missing from fallback AGENTS.md"; exit 1; }
[ ! -d "$TEST_GEMINI_WS/.agents/skills/rnex-clone-sync" ] || { fail "rnex User Skills not cleaned on disable"; exit 1; }
[ -f "$TEST_GEMINI_WS/.agents/skills/my-gemini-skill/SKILL.md" ] || { fail "Custom user skill was deleted on disable"; exit 1; }

# Clean removal when GEMINI.md and .geminiignore have no custom content
rm -f "$TEST_GEMINI_WS/GEMINI.md" "$TEST_GEMINI_WS/.geminiignore"
(cd "$TEST_GEMINI_WS" && ./rnex plugin enable gemini >/dev/null)
[ -f "$TEST_GEMINI_WS/GEMINI.md" ] || { fail "GEMINI.md not recreated"; exit 1; }
[ -f "$TEST_GEMINI_WS/.geminiignore" ] || { fail ".geminiignore not recreated"; exit 1; }
(cd "$TEST_GEMINI_WS" && ./rnex plugin disable gemini >/dev/null)
[ ! -f "$TEST_GEMINI_WS/GEMINI.md" ] || { fail "GEMINI.md without custom content was not deleted on disable"; exit 1; }
[ ! -f "$TEST_GEMINI_WS/.geminiignore" ] || { fail ".geminiignore without custom content was not deleted on disable"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
