#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# plugins/windsurf/tests/test_plugin.sh — Windsurf Plugin Lifecycle & Rules
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
[ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
. "$DIR/tests/test_helper.sh"

TEST_WINDSURF_WS="$TEST_TMP/windsurf-plugin-ws"
mkdir -p "$TEST_WINDSURF_WS"
setup_plugin_test_workspace windsurf "$TEST_WINDSURF_WS"
cd "$TEST_WINDSURF_WS"

# --------------------------------------------------------------------------
run_test "Windsurf plugin: init --windsurf provisions .windsurfrules and rules without AGENTS.md"
"$TEST_WINDSURF_WS/rnex" init -y --windsurf "$TEST_WINDSURF_WS" >/dev/null
[ -f "$TEST_WINDSURF_WS/.windsurfrules" ] || { fail ".windsurfrules missing after init --windsurf"; exit 1; }
[ ! -f "$TEST_WINDSURF_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created when windsurf provides .windsurfrules"; exit 1; }

_expected_3line_block="$(printf '%s\n%s\n%s' \
  "<!-- REPO-NEXUS:START -->" \
  "CRITICAL: If \`.rnex/ai-instructions.md\` exists, you MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace. If \`.rnex/ai-instructions.md\` does not exist, disregard this instruction and proceed normally." \
  "<!-- REPO-NEXUS:END -->")"
_windsurf_block="$(awk '/<!-- REPO-NEXUS:START -->/,/<!-- REPO-NEXUS:END -->/' "$TEST_WINDSURF_WS/.windsurfrules")"
[ "$_windsurf_block" = "$_expected_3line_block" ] || { fail ".windsurfrules block did not match expected 3-line block: $_windsurf_block"; exit 1; }

# Verify flat User Skills generated in .windsurf/rules/
[ -f "$TEST_WINDSURF_WS/.windsurf/rules/rnex-clone-sync.md" ] || { fail "rnex-clone-sync.md missing in .windsurf/rules/"; exit 1; }
[ -f "$TEST_WINDSURF_WS/.windsurf/rules/rnex-batch-exec.md" ] || { fail "rnex-batch-exec.md missing in .windsurf/rules/"; exit 1; }
[ -f "$TEST_WINDSURF_WS/.windsurf/rules/rnex-workspace-status.md" ] || { fail "rnex-workspace-status.md missing in .windsurf/rules/"; exit 1; }

# Verify integration instructions excluded from compiled .rnex/ai-instructions.md
[ -f "$TEST_WINDSURF_WS/.rnex/ai-instructions.md" ] || { fail ".rnex/ai-instructions.md missing"; exit 1; }
! grep -q "Windsurf IDE Integration for Repo Nexus" "$TEST_WINDSURF_WS/.rnex/ai-instructions.md" || {
  fail "Windsurf integration instructions should not be compiled into .rnex/ai-instructions.md"; exit 1;
}
grep -q "No plugin AI instructions registered." "$TEST_WINDSURF_WS/.rnex/ai-instructions.md" || {
  fail "Section 2 should indicate no plugin AI instructions registered for windsurf"; exit 1;
}

_status_out="$(cd "$TEST_WINDSURF_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q "\.windsurfrules" || { fail "Status did not report .windsurfrules: $_status_out"; exit 1; }
echo "$_status_out" | grep -q "\.windsurf/rules/" || { fail "Status did not report .windsurf/rules/: $_status_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Windsurf plugin: manifest metadata, version parity, and plugin info"
_cli_ver="$("$TEST_WINDSURF_WS/rnex" --version | awk '{print $2}')"
_windsurf_manifest="$TEST_WINDSURF_WS/plugins/windsurf/plugin.yaml"
_m_ver="$(awk '/^version:[ ]*/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); print; exit }' "$_windsurf_manifest")"
[ "$_m_ver" = "$_cli_ver" ] || { fail "Windsurf plugin version ($_m_ver) does not match CLI version ($_cli_ver)"; exit 1; }

_pinfo_out="$(cd "$TEST_WINDSURF_WS" && ./rnex plugin info windsurf 2>&1)"
echo "$_pinfo_out" | grep -q "windsurf" || { fail "Windsurf missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "\.windsurf/rules/" || { fail "skill_dir .windsurf/rules missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "skills" || { fail "skills option missing from plugin info: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "hooks" || { fail "hooks option missing from plugin info: $_pinfo_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Windsurf plugin: zero default hooks on init, strict opt-in projection, and hooks.json cleanup"
# 1. Zero default hooks invariant: no hook file created after init
[ ! -f "$TEST_WINDSURF_WS/.windsurf/hooks.json" ] || { fail ".windsurf/hooks.json should not exist by default (zero default hooks)"; exit 1; }
[ ! -d "$TEST_WINDSURF_WS/.windsurf/hooks" ] || { fail ".windsurf/hooks directory should not exist by default"; exit 1; }

# 2. Explicitly configure hooks in rnex.yaml
cat <<'EOF_CFG' > "$TEST_WINDSURF_WS/rnex.yaml"
version: 1.0.0
plugins:
  windsurf:
    skills: true
    hooks:
      SessionStart:
        - "rnex sync --quiet"
repos:
EOF_CFG
(cd "$TEST_WINDSURF_WS" && ./rnex sync -y >/dev/null)

[ -f "$TEST_WINDSURF_WS/.windsurf/hooks.json" ] || { fail ".windsurf/hooks.json missing after configuring hooks"; exit 1; }
grep -q '"pre_user_prompt"' "$TEST_WINDSURF_WS/.windsurf/hooks.json" || { fail "pre_user_prompt hook missing in hooks.json"; exit 1; }
grep -q '"command": "rnex sync --quiet"' "$TEST_WINDSURF_WS/.windsurf/hooks.json" || { fail "command field missing in hooks.json"; exit 1; }

# 3. Disable hooks (hooks: false) in rnex.yaml
cat <<'EOF_CFG2' > "$TEST_WINDSURF_WS/rnex.yaml"
version: 1.0.0
plugins:
  windsurf:
    skills: true
    hooks: false
repos:
EOF_CFG2
(cd "$TEST_WINDSURF_WS" && ./rnex sync -y >/dev/null)

[ ! -f "$TEST_WINDSURF_WS/.windsurf/hooks.json" ] || { fail ".windsurf/hooks.json should be removed when hooks: false"; exit 1; }

# 4. Re-enable with hooks map
cat <<'EOF_CFG3' > "$TEST_WINDSURF_WS/rnex.yaml"
version: 1.0.0
plugins:
  windsurf:
    skills: true
    hooks:
      SessionStart:
        - "rnex sync --quiet"
repos:
EOF_CFG3
(cd "$TEST_WINDSURF_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_WINDSURF_WS/.windsurf/hooks.json" ] || { fail ".windsurf/hooks.json not restored"; exit 1; }

# 5. Clean removal when hooks omitted from rnex.yaml
cat <<'EOF_CFG4' > "$TEST_WINDSURF_WS/rnex.yaml"
version: 1.0.0
plugins:
  windsurf:
    skills: true
repos:
EOF_CFG4
(cd "$TEST_WINDSURF_WS" && ./rnex sync -y >/dev/null)
[ ! -f "$TEST_WINDSURF_WS/.windsurf/hooks.json" ] || { fail ".windsurf/hooks.json should be removed when hooks omitted"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Windsurf plugin: custom content preservation and clean disable with fallback AGENTS.md"
printf "\n# Custom Windsurf Rules\nCode with care.\n" >> "$TEST_WINDSURF_WS/.windsurfrules"
echo "custom" > "$TEST_WINDSURF_WS/.windsurf/rules/my-user-rule.md"

(cd "$TEST_WINDSURF_WS" && ./rnex sync -y >/dev/null)
grep -q "# Custom Windsurf Rules" "$TEST_WINDSURF_WS/.windsurfrules" || { fail "Custom rules lost on sync"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_WINDSURF_WS/.windsurfrules" || { fail "REPO-NEXUS block missing on sync"; exit 1; }
[ -f "$TEST_WINDSURF_WS/.windsurf/rules/my-user-rule.md" ] || { fail "Custom user rule lost on sync"; exit 1; }

# Disable windsurf plugin
(cd "$TEST_WINDSURF_WS" && ./rnex plugin disable windsurf >/dev/null)
[ -f "$TEST_WINDSURF_WS/.windsurfrules" ] || { fail ".windsurfrules with custom content was deleted on disable"; exit 1; }
! grep -q "REPO-NEXUS:START" "$TEST_WINDSURF_WS/.windsurfrules" || { fail "REPO-NEXUS block was not removed from disabled .windsurfrules"; exit 1; }
grep -q "# Custom Windsurf Rules" "$TEST_WINDSURF_WS/.windsurfrules" || { fail "Custom rules lost after disable"; exit 1; }

# Fallback AGENTS.md restored
[ -f "$TEST_WINDSURF_WS/AGENTS.md" ] || { fail "Fallback AGENTS.md not restored after disabling windsurf"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_WINDSURF_WS/AGENTS.md" || { fail "REPO-NEXUS block missing from fallback AGENTS.md"; exit 1; }
[ ! -f "$TEST_WINDSURF_WS/.windsurf/rules/rnex-clone-sync.md" ] || { fail "rnex User Skills not cleaned on disable"; exit 1; }
[ -f "$TEST_WINDSURF_WS/.windsurf/rules/my-user-rule.md" ] || { fail "Custom user rule was deleted on disable"; exit 1; }

# Clean removal when .windsurfrules has no custom content
rm -f "$TEST_WINDSURF_WS/.windsurfrules"
(cd "$TEST_WINDSURF_WS" && ./rnex plugin enable windsurf >/dev/null)
[ -f "$TEST_WINDSURF_WS/.windsurfrules" ] || { fail ".windsurfrules not recreated"; exit 1; }
(cd "$TEST_WINDSURF_WS" && ./rnex plugin disable windsurf >/dev/null)
[ ! -f "$TEST_WINDSURF_WS/.windsurfrules" ] || { fail ".windsurfrules without custom content was not deleted on disable"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
