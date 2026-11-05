#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# plugins/claude/tests/test_plugin.sh — Claude Plugin Lifecycle & User Skills
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
[ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
. "$DIR/tests/test_helper.sh"

TEST_CLAUDE_WS="$TEST_TMP/claude-plugin-ws"
mkdir -p "$TEST_CLAUDE_WS"
setup_plugin_test_workspace claude "$TEST_CLAUDE_WS"
cd "$TEST_CLAUDE_WS"

# --------------------------------------------------------------------------
run_test "Claude plugin: init --claude provisions CLAUDE.md and User Skills without AGENTS.md"
"$TEST_CLAUDE_WS/rnex" init -y --claude "$TEST_CLAUDE_WS" >/dev/null
[ -f "$TEST_CLAUDE_WS/CLAUDE.md" ] || { fail "CLAUDE.md missing after init --claude"; exit 1; }
[ ! -f "$TEST_CLAUDE_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created when claude provides CLAUDE.md"; exit 1; }

_expected_3line_block="$(printf '%s\n%s\n%s' \
  "<!-- REPO-NEXUS:START -->" \
  "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace." \
  "<!-- REPO-NEXUS:END -->")"
_claude_block="$(awk '/<!-- REPO-NEXUS:START -->/,/<!-- REPO-NEXUS:END -->/' "$TEST_CLAUDE_WS/CLAUDE.md")"
[ "$_claude_block" = "$_expected_3line_block" ] || { fail "CLAUDE.md block did not match expected 3-line block: $_claude_block"; exit 1; }

# Verify integration instructions excluded from compiled .rnex/ai-instructions.md
[ -f "$TEST_CLAUDE_WS/.rnex/ai-instructions.md" ] || { fail ".rnex/ai-instructions.md missing"; exit 1; }
! grep -q "Anthropic Claude Code Integration" "$TEST_CLAUDE_WS/.rnex/ai-instructions.md" || {
  fail "Claude integration instructions should not be compiled into .rnex/ai-instructions.md"; exit 1;
}

# Verify User Skills in .claude/skills/
for _s in clone-sync batch-exec workspace-status; do
  _usk="$TEST_CLAUDE_WS/.claude/skills/rnex-${_s}/SKILL.md"
  [ -f "$_usk" ] || { fail "User skill rnex-${_s}/SKILL.md missing in .claude/skills/"; exit 1; }
  grep -q "name: rnex-${_s}" "$_usk" || { fail "User skill rnex-${_s} missing YAML frontmatter"; exit 1; }
  grep -q "\.rnex/skills/${_s}\.md" "$_usk" || { fail "User skill rnex-${_s} missing target pointer"; exit 1; }
done

_status_out="$(cd "$TEST_CLAUDE_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q "CLAUDE.md" || { fail "Status did not report CLAUDE.md"; exit 1; }
echo "$_status_out" | grep -q "\.claude/skills/" || { fail "Status did not report .claude/skills/"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Claude plugin: manifest metadata, version parity, and plugin info"
_cli_ver="$("$TEST_CLAUDE_WS/rnex" --version | awk '{print $2}')"
_claude_manifest="$TEST_CLAUDE_WS/plugins/claude/plugin.yaml"
_m_ver="$(awk '/^version:[ ]*/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); print; exit }' "$_claude_manifest")"
[ "$_m_ver" = "$_cli_ver" ] || { fail "Claude plugin version ($_m_ver) does not match CLI version ($_cli_ver)"; exit 1; }

_pinfo_out="$(cd "$TEST_CLAUDE_WS" && ./rnex plugin info claude 2>&1)"
echo "$_pinfo_out" | grep -q "claude" || { fail "Claude missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "\.claude/skills/" || { fail "skill_dir .claude/skills missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "hooks" || { fail "hooks missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "skills" || { fail "skills option missing from plugin info: $_pinfo_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Claude plugin: hooks configuration in .claude/hooks/rnex-hook-*.sh, .rnex/plugins/claude/hooks/, and .claude/settings.json"
[ -f "$TEST_CLAUDE_WS/.claude/settings.json" ] || { fail ".claude/settings.json missing"; exit 1; }
[ -x "$TEST_CLAUDE_WS/.claude/hooks/rnex-hook-session-start.sh" ] || { fail ".claude/hooks/rnex-hook-session-start.sh missing or not executable"; exit 1; }
[ -x "$TEST_CLAUDE_WS/.rnex/plugins/claude/hooks/rnex-hook-session-start.sh" ] || { fail ".rnex/plugins/claude/hooks/rnex-hook-session-start.sh missing or not executable"; exit 1; }
grep -q "\.rnex/plugins/claude/hooks/rnex-hook-session-start\.sh" "$TEST_CLAUDE_WS/.claude/hooks/rnex-hook-session-start.sh" || {
  fail ".claude/hooks/rnex-hook-session-start.sh does not reference .rnex working script"; exit 1;
}
grep -q '"SessionStart"' "$TEST_CLAUDE_WS/.claude/settings.json" || { fail "SessionStart hook missing in settings.json"; exit 1; }
grep -q '"command"[ ]*:[ ]*"\.claude/hooks/rnex-hook-session-start\.sh"' "$TEST_CLAUDE_WS/.claude/settings.json" || {
  fail "rnex-hook-session-start.sh command missing in settings.json"; exit 1;
}

# Disable hooks: false in rnex.yaml
cat <<'EOF_CFG' > "$TEST_CLAUDE_WS/rnex.yaml"
version: 1.0.0
plugins:
  claude:
    skills: true
    hooks: false
repos:
EOF_CFG
(cd "$TEST_CLAUDE_WS" && ./rnex sync -y >/dev/null)
[ ! -f "$TEST_CLAUDE_WS/.claude/settings.json" ] || { fail ".claude/settings.json should be removed when empty"; exit 1; }
[ ! -f "$TEST_CLAUDE_WS/.claude/hooks/rnex-hook-session-start.sh" ] || { fail ".claude/hooks/rnex-hook-session-start.sh should be removed when hooks: false"; exit 1; }

# Re-enable with custom hooks map (SessionStart + Stop)
cat <<'EOF_CFG2' > "$TEST_CLAUDE_WS/rnex.yaml"
version: 1.0.0
plugins:
  claude:
    skills: true
    hooks:
      SessionStart:
        - "rnex sync --quiet"
      Stop:
        - "echo 'CLAUDE_STOP_HOOK' > stop_marker"
repos:
EOF_CFG2
(cd "$TEST_CLAUDE_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_CLAUDE_WS/.claude/settings.json" ] || { fail ".claude/settings.json not restored with hooks map"; exit 1; }
[ -x "$TEST_CLAUDE_WS/.claude/hooks/rnex-hook-stop.sh" ] || { fail "rnex-hook-stop.sh not generated for Stop event"; exit 1; }
grep -q '"Stop"' "$TEST_CLAUDE_WS/.claude/settings.json" || { fail "Stop hook missing in settings.json"; exit 1; }
(cd "$TEST_CLAUDE_WS" && ./.claude/hooks/rnex-hook-stop.sh)
[ -f "$TEST_CLAUDE_WS/stop_marker" ] || { fail "Executing .claude/hooks/rnex-hook-stop.sh did not run working script"; exit 1; }
rm -f "$TEST_CLAUDE_WS/stop_marker"
pass

# --------------------------------------------------------------------------
run_test "Claude plugin: skills: false option cleans User Skills and preserves custom skills"
echo "# Custom user skill" > "$TEST_CLAUDE_WS/.claude/skills/custom-user-skill.md"

cat <<'EOF_CFG3' > "$TEST_CLAUDE_WS/rnex.yaml"
version: 1.0.0
plugins:
  claude:
    skills: false
repos:
EOF_CFG3
(cd "$TEST_CLAUDE_WS" && ./rnex sync -y >/dev/null)

[ ! -d "$TEST_CLAUDE_WS/.claude/skills/rnex-clone-sync" ] || { fail "rnex User Skills not cleaned when skills: false"; exit 1; }
[ -f "$TEST_CLAUDE_WS/.claude/skills/custom-user-skill.md" ] || { fail "Custom user skill was deleted when skills: false"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Claude plugin: custom content preservation and clean disable with fallback AGENTS.md"
# Re-enable claude skills
cat <<'EOF_CFG4' > "$TEST_CLAUDE_WS/rnex.yaml"
version: 1.0.0
plugins:
  claude:
    skills: true
repos:
EOF_CFG4
(cd "$TEST_CLAUDE_WS" && ./rnex sync -y >/dev/null)

printf "\n# Custom Claude Guidelines\nAlways write clean code.\n" >> "$TEST_CLAUDE_WS/CLAUDE.md"
(cd "$TEST_CLAUDE_WS" && ./rnex sync -y >/dev/null)
grep -q "# Custom Claude Guidelines" "$TEST_CLAUDE_WS/CLAUDE.md" || { fail "Custom guidelines lost on sync"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_CLAUDE_WS/CLAUDE.md" || { fail "REPO-NEXUS block missing on sync"; exit 1; }

# Disable claude plugin
(cd "$TEST_CLAUDE_WS" && ./rnex plugin disable claude >/dev/null)
[ -f "$TEST_CLAUDE_WS/CLAUDE.md" ] || { fail "CLAUDE.md with custom content was deleted on disable"; exit 1; }
! grep -q "REPO-NEXUS:START" "$TEST_CLAUDE_WS/CLAUDE.md" || { fail "REPO-NEXUS block was not removed from disabled CLAUDE.md"; exit 1; }
grep -q "# Custom Claude Guidelines" "$TEST_CLAUDE_WS/CLAUDE.md" || { fail "Custom guidelines lost after disable"; exit 1; }

# Fallback AGENTS.md restored
[ -f "$TEST_CLAUDE_WS/AGENTS.md" ] || { fail "Fallback AGENTS.md not restored after disabling claude"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_CLAUDE_WS/AGENTS.md" || { fail "REPO-NEXUS block missing from fallback AGENTS.md"; exit 1; }
[ ! -d "$TEST_CLAUDE_WS/.claude/skills/rnex-clone-sync" ] || { fail "rnex User Skills not cleaned on disable"; exit 1; }
[ -f "$TEST_CLAUDE_WS/.claude/skills/custom-user-skill.md" ] || { fail "Custom user skill was deleted on disable"; exit 1; }

# Clean removal when CLAUDE.md has no custom content
rm -f "$TEST_CLAUDE_WS/CLAUDE.md"
(cd "$TEST_CLAUDE_WS" && ./rnex plugin enable claude >/dev/null)
[ -f "$TEST_CLAUDE_WS/CLAUDE.md" ] || { fail "CLAUDE.md not recreated"; exit 1; }
(cd "$TEST_CLAUDE_WS" && ./rnex plugin disable claude >/dev/null)
[ ! -f "$TEST_CLAUDE_WS/CLAUDE.md" ] || { fail "CLAUDE.md without custom content was not deleted on disable"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
