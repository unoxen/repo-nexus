#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/02_plugins_basic.sh — Plugin Lifecycle & AGENTS.md Routing (Tests 12-16)
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/tests/test_helper.sh"
setup_test_workspace
cd "$TEST_WORKSPACE"

# Ensure test-app and workspace initialized if run standalone
if [ ! -f "$TEST_WORKSPACE/rnex.yaml" ]; then
  "$TEST_WORKSPACE/rnex" init -y "$TEST_WORKSPACE" >/dev/null
fi

# --------------------------------------------------------------------------
run_test "Plugin list command"
# Re-add test-app for plugin tests if missing
if ! grep -q "test-app:" "$TEST_WORKSPACE/rnex.yaml" 2>/dev/null; then
  "$TEST_WORKSPACE/rnex" add test-app "$TEST_REPO" >/dev/null
fi
_plist_out="$("$TEST_WORKSPACE/rnex" plugin list 2>&1)"
echo "$_plist_out" | grep -q "karpathy-llm" || { fail "karpathy-llm not found in plugin list"; exit 1; }
echo "$_plist_out" | grep -q "available" || { fail "karpathy-llm not marked available"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Plugin info shows scoped directory"
_pinfo_out="$("$TEST_WORKSPACE/rnex" plugin info karpathy-llm 2>&1)"
echo "$_pinfo_out" | grep -q "karpathy-llm" || { fail "Plugin name missing from info"; exit 1; }
echo "$_pinfo_out" | grep -q "Scoped Directory" || { fail "Scoped Directory missing from info"; exit 1; }
echo "$_pinfo_out" | grep -q ".rnex/plugins/karpathy-llm" || { fail ".rnex/plugins/karpathy-llm missing from info"; exit 1; }
pass

# --------------------------------------------------------------------------
# --------------------------------------------------------------------------
run_test "Plugin enable command scopes assets to .rnex/plugins/karpathy-llm/"
"$TEST_WORKSPACE/rnex" plugin enable karpathy-llm >/dev/null
grep -q "karpathy-llm" "$TEST_WORKSPACE/rnex.yaml" || { fail "karpathy-llm not in rnex.yaml"; exit 1; }
[ -d "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm" ] || { fail "Scoped plugin dir missing in workspace"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm/rules/behavioral.md" ] || { fail "behavioral.md missing in scoped plugin dir"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm/skills/wiki-ingest.md" ] || { fail "wiki-ingest.md missing in scoped plugin dir"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm/skills/wiki-lint.md" ] || { fail "wiki-lint.md missing in scoped plugin dir"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm/instructions/rnex-wiki-architecture.md" ] || { fail "rnex-wiki-architecture.md missing in scoped plugin dir"; exit 1; }
[ ! -d "$TEST_WORKSPACE/repos/test-app/.rnex" ] || { fail "Member repo should remain clean"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/wiki/index.md" ] || { fail ".rnex/wiki/index.md not initialized in workspace"; exit 1; }
grep -q "title: Wiki Index" "$TEST_WORKSPACE/.rnex/wiki/index.md" || { fail ".rnex/wiki/index.md missing title: Wiki Index"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Plugin disable command cleans up scoped plugin assets while preserving wiki"
"$TEST_WORKSPACE/rnex" plugin disable karpathy-llm >/dev/null
grep -q "karpathy-llm" "$TEST_WORKSPACE/rnex.yaml" && { fail "karpathy-llm still in rnex.yaml"; exit 1; }
[ ! -d "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm" ] || { fail "Scoped plugin dir still present in workspace"; exit 1; }
[ ! -d "$TEST_WORKSPACE/repos/test-app/.rnex" ] || { fail "Member repo .rnex should not exist"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/wiki/index.md" ] || { fail "User wiki data was incorrectly deleted"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Directive in AGENTS.md and compiled instructions in .rnex/ai-instructions.md"
_agents_content="$(cat "$TEST_WORKSPACE/AGENTS.md")"
echo "$_agents_content" | grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" || { fail "AGENTS.md missing critical directive"; exit 1; }

_ai_content="$(cat "$TEST_WORKSPACE/.rnex/ai-instructions.md")"
echo "$_ai_content" | grep -q "Read Configuration First" || { fail ".rnex/ai-instructions.md missing Read Configuration First"; exit 1; }
echo "$_ai_content" | grep -q ".local.rnex.yaml" || { fail ".rnex/ai-instructions.md missing .local.rnex.yaml"; exit 1; }
echo "$_ai_content" | grep -q "Highest Priority" || { fail ".rnex/ai-instructions.md missing Highest Priority notice"; exit 1; }
echo "$_ai_content" | grep -q ".rnex/plugins/<plugin-name>/" || { fail ".rnex/ai-instructions.md missing plugin routing"; exit 1; }
echo "$_ai_content" | grep -q "Routing Protocol for AI Assistants" || { fail ".rnex/ai-instructions.md missing Routing Protocol heading"; exit 1; }
! echo "$_ai_content" | grep -qi "symlink" || { fail ".rnex/ai-instructions.md should not contain symlink mentions"; exit 1; }
! echo "$_ai_content" | grep -q "Think Before Coding" || { fail ".rnex/ai-instructions.md should not contain inlined plugin rules"; exit 1; }
! echo "$_ai_content" | grep -q "MANDATORY GATE: DO NOT INSPECT" || { fail ".rnex/ai-instructions.md should not contain wiki mandatory gate when karpathy-llm is disabled"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
