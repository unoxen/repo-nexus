#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/06_plugins_advanced.sh — Advanced Plugin Lifecycle & Ecosystem Tests (Tests 34-36)
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/tests/test_helper.sh"

# --------------------------------------------------------------------------
run_test "Deterministic plugin installation, verification, and updates"
TEST_DET_WS="$TEST_TMP/deterministic-plugin-ws"
mkdir -p "$TEST_DET_WS"
cp "$CLI" "$TEST_DET_WS/rnex"
chmod +x "$TEST_DET_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_DET_WS/toolkit"
cp "$DIR/package.json" "$TEST_DET_WS/package.json"
git -C "$TEST_DET_WS" init -q

"$TEST_DET_WS/rnex" init -y "$TEST_DET_WS" >/dev/null

# 1. Verify all 6 plugins are available with consistent v0.5.1
_list_out="$(cd "$TEST_DET_WS" && ./rnex plugin list 2>&1)"
for _p in claude copilot cursor gemini karpathy-llm windsurf; do
  echo "$_list_out" | grep -q "$_p" || { fail "Plugin $_p not in plugin list"; exit 1; }
  echo "$_list_out" | grep "$_p" | grep -q "(v0.5.1)" || { fail "Plugin $_p is not v0.5.1"; exit 1; }
done

# 2. Test 'rnex plugin install <name>' alias for enable
(cd "$TEST_DET_WS" && ./rnex plugin install copilot >/dev/null)
[ -d "$TEST_DET_WS/.rnex/plugins/copilot" ] || { fail "Plugin install did not create .rnex/plugins/copilot"; exit 1; }
[ -f "$TEST_DET_WS/.rnex/plugins/copilot/instructions/rnex-copilot-integration.md" ] || { fail "rnex-copilot-integration.md missing"; exit 1; }

# 3. Test deterministic update: inject a stale file into the installed plugin
touch "$TEST_DET_WS/.rnex/plugins/copilot/instructions/stale-artifact.md"
[ -f "$TEST_DET_WS/.rnex/plugins/copilot/instructions/stale-artifact.md" ] || { fail "Failed to create test stale file"; exit 1; }

# 4. Run 'rnex plugin update copilot' and verify stale artifact was deterministically purged
(cd "$TEST_DET_WS" && ./rnex plugin update copilot >/dev/null)
[ ! -f "$TEST_DET_WS/.rnex/plugins/copilot/instructions/stale-artifact.md" ] || { fail "Stale artifact was not purged during deterministic plugin update"; exit 1; }
[ -f "$TEST_DET_WS/.rnex/plugins/copilot/instructions/rnex-copilot-integration.md" ] || { fail "rnex-copilot-integration.md missing after update"; exit 1; }

# 5. Run global 'rnex plugin update'
(cd "$TEST_DET_WS" && ./rnex plugin update >/dev/null)
[ -f "$TEST_DET_WS/.rnex/plugins/copilot/plugin.yaml" ] || { fail "plugin.yaml missing after global plugin update"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy LLM Wiki plugin with configurable raw_dir and wiki_dir in rnex config"
TEST_KWIKI_WS="$TEST_TMP/karpathy-custom-wiki-ws"
mkdir -p "$TEST_KWIKI_WS"
cp "$CLI" "$TEST_KWIKI_WS/rnex"
chmod +x "$TEST_KWIKI_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_KWIKI_WS/toolkit"
cp "$DIR/package.json" "$TEST_KWIKI_WS/package.json"
git -C "$TEST_KWIKI_WS" init -q

"$TEST_KWIKI_WS/rnex" init -y "$TEST_KWIKI_WS" >/dev/null

# Configure custom wiki_dir and raw_dir in rnex.yaml
cat <<'EOF_CFG' >> "$TEST_KWIKI_WS/rnex.yaml"
plugins:
  karpathy-llm:
    wiki_dir: docs/wiki
    raw_dir: intake/raw
    lint_trigger: git-post-commit
    notify_on_changes: true
EOF_CFG

# Reconcile via rnex sync to initialize plugin templates with custom paths
(cd "$TEST_KWIKI_WS" && ./rnex sync -y >/dev/null)

# Verify custom directories are created instead of default raw/ and wiki/
[ -d "$TEST_KWIKI_WS/docs/wiki" ] || { fail "Custom docs/wiki directory was not created"; exit 1; }
[ -d "$TEST_KWIKI_WS/intake/raw" ] || { fail "Custom intake/raw directory was not created"; exit 1; }
[ ! -d "$TEST_KWIKI_WS/wiki" ] || { fail "Default wiki/ was created despite custom wiki_dir"; exit 1; }
[ ! -d "$TEST_KWIKI_WS/raw" ] || { fail "Default raw/ was created despite custom raw_dir"; exit 1; }

# Verify control files exist in custom directories
[ -f "$TEST_KWIKI_WS/docs/wiki/index.md" ] || { fail "docs/wiki/index.md missing"; exit 1; }
[ -f "$TEST_KWIKI_WS/docs/wiki/hot.md" ] || { fail "docs/wiki/hot.md missing"; exit 1; }
[ -f "$TEST_KWIKI_WS/docs/wiki/_log.md" ] || { fail "docs/wiki/_log.md missing"; exit 1; }
[ -f "$TEST_KWIKI_WS/intake/raw/.gitkeep" ] || { fail "intake/raw/.gitkeep missing"; exit 1; }

# Verify template substitutions reflect custom paths
grep -q "/intake/raw/" "$TEST_KWIKI_WS/docs/wiki/index.md" || { fail "docs/wiki/index.md does not reference custom intake/raw/"; exit 1; }
grep -q "/intake/raw/" "$TEST_KWIKI_WS/docs/wiki/hot.md" || { fail "docs/wiki/hot.md does not reference custom intake/raw/"; exit 1; }
grep -q "/docs/wiki/" "$TEST_KWIKI_WS/docs/wiki/hot.md" || { fail "docs/wiki/hot.md does not reference custom docs/wiki/"; exit 1; }

# Verify AGENTS.md maintains strict directive and .rnex/ai-instructions.md contains plugin instructions
_kw_agents="$(cat "$TEST_KWIKI_WS/AGENTS.md")"
echo "$_kw_agents" | grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" || { fail "AGENTS.md missing strict directive"; exit 1; }
_kw_ai_instructions="$(cat "$TEST_KWIKI_WS/.rnex/ai-instructions.md")"
echo "$_kw_ai_instructions" | grep -q "Karpathy LLM Wiki Knowledge Architecture" || { fail "ai-instructions.md missing Karpathy instructions"; exit 1; }
echo "$_kw_ai_instructions" | grep -q "wiki_dir" || { fail "ai-instructions.md missing wiki_dir guidance"; exit 1; }

# Verify plugin info reports custom options and template mappings
_kw_info="$(cd "$TEST_KWIKI_WS" && ./rnex plugin info karpathy-llm 2>&1)"
echo "$_kw_info" | grep -q "current: docs/wiki" || { fail "plugin info did not report custom wiki_dir"; exit 1; }
echo "$_kw_info" | grep -q "current: intake/raw" || { fail "plugin info did not report custom raw_dir"; exit 1; }
echo "$_kw_info" | grep -q "docs/wiki/index.md" || { fail "plugin info did not report template mapped to docs/wiki/index.md"; exit 1; }
echo "$_kw_info" | grep -q "intake/raw/.gitkeep" || { fail "plugin info did not report template mapped to intake/raw/.gitkeep"; exit 1; }

# Verify Git hooks trigger detects custom paths
git -C "$TEST_KWIKI_WS" config user.email "test@example.com"
git -C "$TEST_KWIKI_WS" config user.name "Test User"
git -C "$TEST_KWIKI_WS" add .
git -C "$TEST_KWIKI_WS" commit -qm "Initial commit"
echo "sample research" > "$TEST_KWIKI_WS/intake/raw/paper.md"
git -C "$TEST_KWIKI_WS" add intake/raw/paper.md
git -C "$TEST_KWIKI_WS" commit -qm "Add intake document"
_hook_output="$(cd "$TEST_KWIKI_WS" && ./rnex hooks run post-commit 2>&1)"
echo "$_hook_output" | grep -q "intake/raw/ or docs/wiki/" || { fail "Git hook post-commit did not detect commit to intake/raw/: $_hook_output"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Disabling plugin in rnex.yaml followed by rnex sync cleanly removes instructions, assets, and prompts"
# 1. Enable copilot with prompts: true so we can verify provider prompts cleanup
cat <<'EOF_CFG2' > "$TEST_KWIKI_WS/rnex.yaml"
plugins:
  copilot:
    prompts: true
    workflows: true
  karpathy-llm:
    wiki_dir: docs/wiki
    raw_dir: intake/raw
EOF_CFG2

(cd "$TEST_KWIKI_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_KWIKI_WS/.github/prompts/rnex-wiki-ingest.prompt.md" ] || { fail "Plugin prompt rnex-wiki-ingest was not mirrored to Copilot"; exit 1; }
[ -f "$TEST_KWIKI_WS/.github/prompts/rnex-wiki-lint.prompt.md" ] || { fail "Plugin prompt rnex-wiki-lint was not mirrored to Copilot"; exit 1; }
[ -d "$TEST_KWIKI_WS/.rnex/plugins/karpathy-llm" ] || { fail ".rnex/plugins/karpathy-llm missing while enabled"; exit 1; }
_kw_active_ai="$(cat "$TEST_KWIKI_WS/.rnex/ai-instructions.md")"
echo "$_kw_active_ai" | grep -q "Karpathy LLM Wiki Knowledge Architecture" || { fail "Active ai-instructions.md missing Karpathy instructions"; exit 1; }

# 2. Disable karpathy-llm via enabled: false in rnex.yaml
cat <<'EOF_CFG3' > "$TEST_KWIKI_WS/rnex.yaml"
plugins:
  copilot:
    prompts: true
    workflows: true
  karpathy-llm:
    enabled: false
    wiki_dir: docs/wiki
    raw_dir: intake/raw
EOF_CFG3

# 3. Run rnex sync
(cd "$TEST_KWIKI_WS" && ./rnex sync -y >/dev/null)

# 4. Verify .rnex/ai-instructions.md no longer contains wiki instructions and AGENTS.md retains single directive
_kw_disabled_ai="$(cat "$TEST_KWIKI_WS/.rnex/ai-instructions.md")"
! echo "$_kw_disabled_ai" | grep -q "Karpathy LLM Wiki Knowledge Architecture" || { fail "ai-instructions.md still contains wiki instructions after disabling plugin"; exit 1; }
echo "$_kw_disabled_ai" | grep -q "Read Configuration First" || { fail "ai-instructions.md missing Read Configuration First"; exit 1; }

_kw_disabled_agents="$(cat "$TEST_KWIKI_WS/AGENTS.md")"
echo "$_kw_disabled_agents" | grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" || { fail "AGENTS.md missing strict directive"; exit 1; }

# 5. Verify provider prompts from disabled plugin were removed, but base prompts kept
[ ! -f "$TEST_KWIKI_WS/.github/prompts/rnex-wiki-ingest.prompt.md" ] || { fail "rnex-wiki-ingest.prompt.md still present after disabling plugin"; exit 1; }
[ ! -f "$TEST_KWIKI_WS/.github/prompts/rnex-wiki-lint.prompt.md" ] || { fail "rnex-wiki-lint.prompt.md still present after disabling plugin"; exit 1; }
[ -f "$TEST_KWIKI_WS/.github/prompts/rnex-cross-repo-feature.prompt.md" ] || { fail "Base prompt rnex-cross-repo-feature was incorrectly removed"; exit 1; }

# 6. Verify .rnex/plugins/karpathy-llm scope was removed
[ ! -d "$TEST_KWIKI_WS/.rnex/plugins/karpathy-llm" ] || { fail ".rnex/plugins/karpathy-llm still exists after sync"; exit 1; }

# 7. Verify user wiki files remain intact
[ -f "$TEST_KWIKI_WS/docs/wiki/index.md" ] || { fail "docs/wiki/index.md was deleted when plugin was disabled"; exit 1; }
[ -f "$TEST_KWIKI_WS/docs/wiki/hot.md" ] || { fail "docs/wiki/hot.md was deleted when plugin was disabled"; exit 1; }
[ -f "$TEST_KWIKI_WS/intake/raw/paper.md" ] || { fail "intake/raw/paper.md was deleted when plugin was disabled"; exit 1; }

# 8. Verify plugin list and info report disabled
_list_out="$(cd "$TEST_KWIKI_WS" && ./rnex plugin list 2>&1)"
echo "$_list_out" | grep "karpathy-llm" | grep -q "disabled" || { fail "plugin list did not report karpathy-llm as disabled: $_list_out"; exit 1; }

pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
