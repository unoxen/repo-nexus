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
  "$TEST_WORKSPACE/rnex" repo add "$TEST_REPO" --name test-app >/dev/null
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
[ -f "$TEST_WORKSPACE/wiki/index.md" ] || { fail "wiki/index.md not initialized in workspace"; exit 1; }
grep -q "title: Wiki Index" "$TEST_WORKSPACE/wiki/index.md" || { fail "wiki/index.md missing title: Wiki Index"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Plugin disable command cleans up scoped plugin assets while preserving wiki"
"$TEST_WORKSPACE/rnex" plugin disable karpathy-llm >/dev/null
grep -q "karpathy-llm" "$TEST_WORKSPACE/rnex.yaml" && { fail "karpathy-llm still in rnex.yaml"; exit 1; }
[ ! -d "$TEST_WORKSPACE/.rnex/plugins/karpathy-llm" ] || { fail "Scoped plugin dir still present in workspace"; exit 1; }
[ ! -d "$TEST_WORKSPACE/repos/test-app/.rnex" ] || { fail "Member repo .rnex should not exist"; exit 1; }
[ -f "$TEST_WORKSPACE/wiki/index.md" ] || { fail "User wiki data was incorrectly deleted"; exit 1; }
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

# --------------------------------------------------------------------------
run_test "Extensible plugin command engine: discovery, execution, options forwarding, and shorthand fallback"
_cmd_plugin_dir="$TEST_WORKSPACE/toolkit/plugins/cmd-test"
mkdir -p "$_cmd_plugin_dir/commands"
cat <<'EOF_PLUG' > "$_cmd_plugin_dir/plugin.yaml"
name: cmd-test
version: 1.0.0
description: Test plugin with extensible commands.
commands:
  hello: "Print greetings with options"
  dump-env: "Dump workspace environment variables"
EOF_PLUG

cat <<'EOF_HELLO' > "$_cmd_plugin_dir/commands/hello.sh"
#!/bin/sh
printf 'HELLO: %s\n' "$*"
EOF_HELLO

cat <<'EOF_DUMP' > "$_cmd_plugin_dir/commands/dump-env.sh"
#!/bin/sh
printf 'ROOT=%s\n' "$RNEX_ROOT"
printf 'PLUGIN=%s\n' "$RNEX_PLUGIN_NAME"
printf 'ARGS=%s\n' "$*"
EOF_DUMP
chmod +x "$_cmd_plugin_dir/commands"/*

# 1. Enable plugin
"$TEST_WORKSPACE/rnex" plugin enable cmd-test >/dev/null

# Configure rnex_hooks for before_plugin_command and after_plugin_command via .local.rnex.yaml
cat <<'EOF_HOOKS' > "$TEST_WORKSPACE/.local.rnex.yaml"
rnex_hooks:
  before_plugin_command:
    - "echo BEFORE_CMD: $RNEX_ARGS >> hook_cmd.log"
  after_plugin_command:
    - "echo AFTER_CMD: $RNEX_ARGS >> hook_cmd.log"
EOF_HOOKS

# 2. Check plugin list and info list commands
_list_out="$("$TEST_WORKSPACE/rnex" plugin list 2>&1)"
echo "$_list_out" | grep -q "rnex plugin cmd-test hello" || { fail "Plugin list missing hello command: $_list_out"; exit 1; }

_info_out="$("$TEST_WORKSPACE/rnex" plugin info cmd-test 2>&1)"
echo "$_info_out" | grep -q "Commands:" || { fail "Plugin info missing Commands section: $_info_out"; exit 1; }
echo "$_info_out" | grep -q "rnex plugin cmd-test hello" || { fail "Plugin info missing hello command"; exit 1; }
echo "$_info_out" | grep -q "Print greetings with options" || { fail "Plugin info missing hello description"; exit 1; }

# 3. Explicit command execution: rnex plugin cmd-test hello --flag value pos1
rm -f "$TEST_WORKSPACE/hook_cmd.log"
_hello_out="$("$TEST_WORKSPACE/rnex" plugin cmd-test hello --flag "foo bar" extra 2>&1)"
echo "$_hello_out" | grep -q 'HELLO: --flag foo bar extra' || { fail "Arguments not forwarded correctly: $_hello_out"; exit 1; }
[ -f "$TEST_WORKSPACE/hook_cmd.log" ] || { fail "hook_cmd.log missing; lifecycle hooks did not fire"; exit 1; }
grep -q "BEFORE_CMD: cmd-test hello --flag foo bar extra" "$TEST_WORKSPACE/hook_cmd.log" || { fail "before_plugin_command hook did not record args: $(cat "$TEST_WORKSPACE/hook_cmd.log")"; exit 1; }
grep -q "AFTER_CMD: cmd-test hello --flag foo bar extra" "$TEST_WORKSPACE/hook_cmd.log" || { fail "after_plugin_command hook did not record args: $(cat "$TEST_WORKSPACE/hook_cmd.log")"; exit 1; }

# 4. Environment variable validation
_dump_out="$("$TEST_WORKSPACE/rnex" plugin cmd-test dump-env --opt 123 2>&1)"
echo "$_dump_out" | grep "ROOT=" | grep -q "nexus-workspace" || { fail "RNEX_ROOT not set in plugin command: $_dump_out"; exit 1; }
echo "$_dump_out" | grep -q "PLUGIN=cmd-test" || { fail "RNEX_PLUGIN_NAME not set: $_dump_out"; exit 1; }
echo "$_dump_out" | grep -q "ARGS=--opt 123" || { fail "ARGS not forwarded: $_dump_out"; exit 1; }

# 5. Shorthand fallback: rnex plugin hello [options...]
_short_out="$("$TEST_WORKSPACE/rnex" plugin hello --shorthand active 2>&1)"
echo "$_short_out" | grep -q 'HELLO: --shorthand active' || { fail "Shorthand fallback execution failed: $_short_out"; exit 1; }

# 6. Unknown command on enabled plugin errors cleanly
_err_out="$("$TEST_WORKSPACE/rnex" plugin cmd-test non-existent-command 2>&1 || true)"
echo "$_err_out" | grep -q "Unknown command 'non-existent-command' for plugin 'cmd-test'" || { fail "Expected unknown command error: $_err_out"; exit 1; }

# 7. Disable plugin and verify invocation rejection
"$TEST_WORKSPACE/rnex" plugin disable cmd-test >/dev/null
_dis_out="$("$TEST_WORKSPACE/rnex" plugin cmd-test hello 2>&1 || true)"
echo "$_dis_out" | grep -q "Plugin 'cmd-test' is not enabled in workspace" || { fail "Expected disabled plugin error: $_dis_out"; exit 1; }

_short_dis_out="$("$TEST_WORKSPACE/rnex" plugin hello 2>&1 || true)"
echo "$_short_dis_out" | grep -q "currently disabled" || { fail "Expected shorthand disabled message: $_short_dis_out"; exit 1; }

# Clean up temporary test plugin
rm -rf "$_cmd_plugin_dir" "$TEST_WORKSPACE/.rnex/plugins/cmd-test" "$TEST_WORKSPACE/.local.rnex.yaml" "$TEST_WORKSPACE/hook_cmd.log"
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
