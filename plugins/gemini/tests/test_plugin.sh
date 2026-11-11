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
  "CRITICAL: If \`.rnex/ai-instructions.md\` exists, you MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace. If \`.rnex/ai-instructions.md\` does not exist, disregard this instruction and proceed normally." \
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
grep -q "No plugin AI instructions registered." "$TEST_GEMINI_WS/.rnex/ai-instructions.md" || {
  fail "Section 2 should indicate no plugin AI instructions registered for gemini"; exit 1;
}

_status_out="$(cd "$TEST_GEMINI_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q "GEMINI.md" || { fail "Status did not report GEMINI.md"; exit 1; }
echo "$_status_out" | grep -q "\.agents/skills/" || { fail "Status did not report .agents/skills/"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Gemini plugin: manifest metadata, version parity, and plugin info"
_cli_ver="$("$TEST_GEMINI_WS/rnex" --version | awk '{print $2}')"
_gemini_manifest="$TEST_GEMINI_WS/plugins/gemini/plugin.yaml"
_m_ver="$(awk '/^version:[ ]*/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); print; exit }' "$_gemini_manifest")"
[ "$_m_ver" = "$_cli_ver" ] || { fail "Gemini plugin version ($_m_ver) does not match CLI version ($_cli_ver)"; exit 1; }

_pinfo_out="$(cd "$TEST_GEMINI_WS" && ./rnex plugin info gemini 2>&1)"
echo "$_pinfo_out" | grep -q "gemini" || { fail "Gemini missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "\.agents/skills/" || { fail "skill_dir .agents/skills missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "hooks" || { fail "hooks missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "skills" || { fail "skills option missing from plugin info: $_pinfo_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Gemini plugin: zero default hooks on init, strict opt-in projection, and settings cleanup"
# 1. Zero default hooks invariant: no hook file created after init
[ ! -f "$TEST_GEMINI_WS/.gemini/settings.json" ] || { fail ".gemini/settings.json should not exist by default (zero default hooks)"; exit 1; }
[ ! -f "$TEST_GEMINI_WS/.agents/hooks.json" ] || { fail ".agents/hooks.json should not exist by default"; exit 1; }
[ ! -d "$TEST_GEMINI_WS/.agents/hooks" ] || { fail ".agents/hooks directory should not exist by default"; exit 1; }

# 2. Add non-hook setting to .gemini/settings.json to verify merge preservation
mkdir -p "$TEST_GEMINI_WS/.gemini"
printf '{\n  "model": "gemini-2.0"\n}\n' > "$TEST_GEMINI_WS/.gemini/settings.json"

# 3. Explicitly configure hooks in rnex.yaml
cat <<'EOF_CFG' > "$TEST_GEMINI_WS/rnex.yaml"
version: 1.0.0
plugins:
  gemini:
    skills: true
    hooks:
      SessionStart:
        - "rnex sync --quiet"
repos:
EOF_CFG
(cd "$TEST_GEMINI_WS" && ./rnex sync -y >/dev/null)

[ -f "$TEST_GEMINI_WS/.gemini/settings.json" ] || { fail ".gemini/settings.json missing after configuring hooks"; exit 1; }
grep -q '"model": "gemini-2.0"' "$TEST_GEMINI_WS/.gemini/settings.json" || { fail "Custom model setting lost after syncing hooks"; exit 1; }
grep -q '"SessionStart"' "$TEST_GEMINI_WS/.gemini/settings.json" || { fail "SessionStart hook missing in settings.json"; exit 1; }
grep -q '"type": "command"' "$TEST_GEMINI_WS/.gemini/settings.json" || { fail "type: command missing in settings.json"; exit 1; }
grep -q '"command": "rnex sync --quiet"' "$TEST_GEMINI_WS/.gemini/settings.json" || { fail "SessionStart command missing in settings.json"; exit 1; }

# 4. Disable hooks (hooks: false) in rnex.yaml
cat <<'EOF_CFG2' > "$TEST_GEMINI_WS/rnex.yaml"
version: 1.0.0
plugins:
  gemini:
    skills: true
    hooks: false
repos:
EOF_CFG2
(cd "$TEST_GEMINI_WS" && ./rnex sync -y >/dev/null)

[ -f "$TEST_GEMINI_WS/.gemini/settings.json" ] || { fail ".gemini/settings.json missing (model should be preserved)"; exit 1; }
grep -q '"model": "gemini-2.0"' "$TEST_GEMINI_WS/.gemini/settings.json" || { fail "model setting lost after disabling hooks"; exit 1; }
! grep -q '"hooks"' "$TEST_GEMINI_WS/.gemini/settings.json" || { fail "hooks block still present after hooks: false"; exit 1; }

# 5. Clean removal when settings.json has only hooks
rm -f "$TEST_GEMINI_WS/.gemini/settings.json"
cat <<'EOF_CFG3' > "$TEST_GEMINI_WS/rnex.yaml"
version: 1.0.0
plugins:
  gemini:
    skills: true
    hooks:
      SessionStart:
        - "rnex sync --quiet"
repos:
EOF_CFG3
(cd "$TEST_GEMINI_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_GEMINI_WS/.gemini/settings.json" ] || { fail ".gemini/settings.json not created"; exit 1; }

# Now remove hooks declaration completely
cat <<'EOF_CFG4' > "$TEST_GEMINI_WS/rnex.yaml"
version: 1.0.0
plugins:
  gemini:
    skills: true
repos:
EOF_CFG4
(cd "$TEST_GEMINI_WS" && ./rnex sync -y >/dev/null)
[ ! -f "$TEST_GEMINI_WS/.gemini/settings.json" ] || { fail ".gemini/settings.json should be removed when no other settings remain"; exit 1; }
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
