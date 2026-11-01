#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/02_plugins_basic.sh — Plugin Engine Lifecycle & Architecture
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
if ! grep -q "test-app:" "$TEST_WORKSPACE/rnex.yaml" 2>/dev/null; then
  "$TEST_WORKSPACE/rnex" repo add "$TEST_REPO" --name test-app >/dev/null
fi

# --------------------------------------------------------------------------
run_test "Plugin engine: list command discovers plugins across plugins"
_plist_out="$("$TEST_WORKSPACE/rnex" plugin list 2>&1)"
echo "$_plist_out" | grep -q "Repo Nexus Plugins" || { fail "Plugin list missing header: $_plist_out"; exit 1; }
echo "$_plist_out" | grep -q "available" || { fail "Plugin list missing available marker: $_plist_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Plugin engine: extensible commands, options forwarding, shorthand, and lifecycle hooks"
_cmd_plugin_dir="$TEST_WORKSPACE/plugins/cmd-test"
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
cat <<'EOF_CUSTOM_INSTR' > "$_cmd_plugin_dir/instructions.md"
# Custom Workflow Plugin Guidelines
- Follow custom workflow verification before committing.
EOF_CUSTOM_INSTR
chmod +x "$_cmd_plugin_dir/commands"/*

# 1. Enable plugin and verify custom workflow plugin instructions are included in .rnex/ai-instructions.md
"$TEST_WORKSPACE/rnex" plugin enable cmd-test >/dev/null
grep -qF "### Plugin Directives (\`cmd-test\`)" "$TEST_WORKSPACE/.rnex/ai-instructions.md" || { fail "Custom workflow plugin header missing from ai-instructions.md"; exit 1; }
grep -qF 'Follow custom workflow verification before committing.' "$TEST_WORKSPACE/.rnex/ai-instructions.md" || { fail "Custom workflow plugin instructions missing from ai-instructions.md"; exit 1; }

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
grep -q "BEFORE_CMD: cmd-test hello --flag foo bar extra" "$TEST_WORKSPACE/hook_cmd.log" || { fail "before_plugin_command hook did not record args"; exit 1; }
grep -q "AFTER_CMD: cmd-test hello --flag foo bar extra" "$TEST_WORKSPACE/hook_cmd.log" || { fail "after_plugin_command hook did not record args"; exit 1; }

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

# 7. Disable plugin and verify invocation rejection and removal from ai-instructions.md
"$TEST_WORKSPACE/rnex" plugin disable cmd-test >/dev/null
! grep -qF 'cmd-test' "$TEST_WORKSPACE/.rnex/ai-instructions.md" || { fail "Custom workflow plugin instructions not removed after disable"; exit 1; }
_dis_out="$("$TEST_WORKSPACE/rnex" plugin cmd-test hello 2>&1 || true)"
echo "$_dis_out" | grep -q "Plugin 'cmd-test' is not enabled in workspace" || { fail "Expected disabled plugin error: $_dis_out"; exit 1; }

_short_dis_out="$("$TEST_WORKSPACE/rnex" plugin hello 2>&1 || true)"
echo "$_short_dis_out" | grep -q "currently disabled" || { fail "Expected shorthand disabled message: $_short_dis_out"; exit 1; }

# Clean up temporary test plugin
rm -rf "$_cmd_plugin_dir" "$TEST_WORKSPACE/.rnex/plugins/cmd-test" "$TEST_WORKSPACE/.local.rnex.yaml" "$TEST_WORKSPACE/hook_cmd.log"
pass

# --------------------------------------------------------------------------
run_test "Plugin engine: scoped isolation, update with stale artifact purge, and clean disable"
_sample_plugin_dir="$TEST_WORKSPACE/plugins/sample-pkg"
mkdir -p "$_sample_plugin_dir/rules" "$_sample_plugin_dir/skills" "$_sample_plugin_dir/instructions"
cat <<'EOF_SAMPLE' > "$_sample_plugin_dir/plugin.yaml"
name: sample-pkg
version: 1.0.0
description: Sample testing plugin for engine mechanics
rules:
  - rules/sample.md: .rnex/plugins/sample-pkg/rules/sample.md
skills:
  - skills/sample-skill.md: .rnex/plugins/sample-pkg/skills/sample-skill.md
instructions:
  - instructions/sample.md: .rnex/plugins/sample-pkg/instructions/sample.md
EOF_SAMPLE

echo "# Sample Rule" > "$_sample_plugin_dir/rules/sample.md"
echo "# Sample Skill" > "$_sample_plugin_dir/skills/sample-skill.md"
echo "# Sample Instructions" > "$_sample_plugin_dir/instructions/sample.md"

# Enable plugin and verify scoped assets
"$TEST_WORKSPACE/rnex" plugin enable sample-pkg >/dev/null
[ -d "$TEST_WORKSPACE/.rnex/plugins/sample-pkg" ] || { fail "Scoped plugin dir missing"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/plugins/sample-pkg/rules/sample.md" ] || { fail "rules/sample.md missing in scope"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/plugins/sample-pkg/skills/sample-skill.md" ] || { fail "skills/sample-skill.md missing in scope"; exit 1; }
[ -f "$TEST_WORKSPACE/.rnex/plugins/sample-pkg/instructions/sample.md" ] || { fail "instructions/sample.md missing in scope"; exit 1; }
[ ! -d "$TEST_WORKSPACE/repos/test-app/.rnex" ] || { fail "Member repo must remain untouched with no .rnex/"; exit 1; }

# Stale artifact injection and plugin update
touch "$TEST_WORKSPACE/.rnex/plugins/sample-pkg/instructions/stale.md"
[ -f "$TEST_WORKSPACE/.rnex/plugins/sample-pkg/instructions/stale.md" ] || { fail "Failed to inject stale artifact"; exit 1; }

_update_out="$("$TEST_WORKSPACE/rnex" plugin update sample-pkg 2>&1)"
echo "$_update_out" | grep -q "Plugin 'sample-pkg' updated" || { fail "Update log missing 'Plugin '\'sample-pkg\'' updated': $_update_out"; exit 1; }
! echo "$_update_out" | grep -q "Plugin '' updated" || { fail "Update log contained empty name: $_update_out"; exit 1; }
[ ! -f "$TEST_WORKSPACE/.rnex/plugins/sample-pkg/instructions/stale.md" ] || { fail "Stale artifact was not purged on update"; exit 1; }

# Global update
_g_update="$("$TEST_WORKSPACE/rnex" plugin update 2>&1)"
echo "$_g_update" | grep -q "All plugins updated" || { fail "Global update log mismatch: $_g_update"; exit 1; }

# Disable plugin and verify single log message
_disable_out="$("$TEST_WORKSPACE/rnex" plugin disable sample-pkg 2>&1)"
_disable_cnt="$(echo "$_disable_out" | grep -c "disabled from workspace" || true)"
[ "$_disable_cnt" -eq 1 ] || { fail "Expected exactly 1 disable log message, got $_disable_cnt: $_disable_out"; exit 1; }
[ ! -d "$TEST_WORKSPACE/.rnex/plugins/sample-pkg" ] || { fail "Scoped dir still present after disable"; exit 1; }

# Re-enabling a disabled plugin in rnex.yaml updates enabled: true
awk '
  /^plugins:/ { print; print "  sample-pkg:"; print "    enabled: false"; next }
  { print }
' "$TEST_WORKSPACE/rnex.yaml" > "$TEST_WORKSPACE/rnex.yaml.tmp" && mv "$TEST_WORKSPACE/rnex.yaml.tmp" "$TEST_WORKSPACE/rnex.yaml"
"$TEST_WORKSPACE/rnex" sync -y >/dev/null
"$TEST_WORKSPACE/rnex" plugin enable sample-pkg >/dev/null
grep -q "enabled: true" "$TEST_WORKSPACE/rnex.yaml" || { fail "rnex.yaml was not updated to enabled: true"; exit 1; }

# Clean up
"$TEST_WORKSPACE/rnex" plugin disable sample-pkg >/dev/null
rm -rf "$_sample_plugin_dir" "$TEST_WORKSPACE/.rnex/plugins/sample-pkg"
pass

# --------------------------------------------------------------------------
run_test "Plugin engine: lifecycle hooks before_sync, after_sync, after_init, and after_exec"
TEST_PHOOK_WS="$TEST_TMP/plugin-hooks-engine-ws"
mkdir -p "$TEST_PHOOK_WS"
cp "$CLI" "$TEST_PHOOK_WS/rnex"
chmod +x "$TEST_PHOOK_WS/rnex"
cp "$DIR/package.json" "$TEST_PHOOK_WS/package.json"
cp -r "$DIR/lib" "$TEST_PHOOK_WS/lib"
cp -r "$DIR/templates" "$TEST_PHOOK_WS/templates"
mkdir -p "$TEST_PHOOK_WS/plugins/hook-tester/hooks"

cat <<'EOF_HT_YAML' > "$TEST_PHOOK_WS/plugins/hook-tester/plugin.yaml"
name: hook-tester
version: 1.0.0
description: Plugin testing lifecycle hooks
EOF_HT_YAML

cat <<'EOF_HT_BS' > "$TEST_PHOOK_WS/plugins/hook-tester/hooks/before_sync.sh"
#!/bin/sh
printf 'bs\n' >> "$RNEX_ROOT/bs_counts"
EOF_HT_BS

cat <<'EOF_HT_AS' > "$TEST_PHOOK_WS/plugins/hook-tester/hooks/after_sync.sh"
#!/bin/sh
if [ ! -f "$RNEX_ROOT/.rnex/sync_stamp" ]; then
  echo "STEP_ORDER_ERROR: sync_stamp missing before Step 3 completes" >&2
  exit 1
fi
if [ ! -f "$RNEX_ROOT/.rnex/ai-instructions.md" ]; then
  echo "STEP_ORDER_ERROR: ai-instructions.md missing before Step 3 completes" >&2
  exit 1
fi
printf 'as\n' >> "$RNEX_ROOT/as_counts"
EOF_HT_AS

cat <<'EOF_HT_AI' > "$TEST_PHOOK_WS/plugins/hook-tester/hooks/after_init.sh"
#!/bin/sh
printf 'ai\n' >> "$RNEX_ROOT/ai_counts"
EOF_HT_AI

cat <<'EOF_HT_AE' > "$TEST_PHOOK_WS/plugins/hook-tester/hooks/after_exec.sh"
#!/bin/sh
printf 'ae\n' >> "$RNEX_ROOT/ae_marker"
EOF_HT_AE

chmod +x "$TEST_PHOOK_WS/plugins/hook-tester/hooks"/*

# 1. after_init hook fires on init
(cd "$TEST_PHOOK_WS" && ./rnex init -y >/dev/null)
cat <<'EOF_CFG_HOOKS' >> "$TEST_PHOOK_WS/rnex.yaml"
plugins:
  hook-tester: {}
repos:
EOF_CFG_HOOKS

# 2. before_sync and after_sync fire exactly once on rnex sync
(cd "$TEST_PHOOK_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_PHOOK_WS/bs_counts" ] || { fail "before_sync hook did not fire"; exit 1; }
[ -f "$TEST_PHOOK_WS/as_counts" ] || { fail "after_sync hook did not fire"; exit 1; }
_bs_c="$(wc -l < "$TEST_PHOOK_WS/bs_counts" | tr -d ' ')"
_as_c="$(wc -l < "$TEST_PHOOK_WS/as_counts" | tr -d ' ')"
[ "$_bs_c" -eq 1 ] || { fail "before_sync fired $_bs_c times (expected 1)"; exit 1; }
[ "$_as_c" -eq 1 ] || { fail "after_sync fired $_as_c times (expected 1)"; exit 1; }

# 3. set -e in caller does not prevent after_exec hook when exec fails
(cd "$TEST_PHOOK_WS" && ./rnex repo add "$TEST_REPO" --name dummy-app >/dev/null)
rm -f "$TEST_PHOOK_WS/ae_marker"
set +e
(cd "$TEST_PHOOK_WS" && ./rnex exec "false" >/dev/null 2>&1)
_f_rc=$?
set -e
[ "$_f_rc" -ne 0 ] || { fail "Expected non-zero exit code from failing exec"; exit 1; }
[ -f "$TEST_PHOOK_WS/ae_marker" ] || { fail "after_exec hook was not executed when command failed"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Plugin engine: two-tier skills architecture and zero-logic User Skill generator contract"
TEST_SKILLS_ARCH_WS="$TEST_TMP/skills-arch-ws"
mkdir -p "$TEST_SKILLS_ARCH_WS"
cp "$CLI" "$TEST_SKILLS_ARCH_WS/rnex"
chmod +x "$TEST_SKILLS_ARCH_WS/rnex"
cp "$DIR/package.json" "$TEST_SKILLS_ARCH_WS/package.json"
cp -r "$DIR/lib" "$TEST_SKILLS_ARCH_WS/lib"
cp -r "$DIR/templates" "$TEST_SKILLS_ARCH_WS/templates"
cp -r "$DIR/skills" "$TEST_SKILLS_ARCH_WS/skills"

# Create a synthetic provider plugin and a synthetic domain plugin
mkdir -p "$TEST_SKILLS_ARCH_WS/plugins/sample-prov"
cat <<'EOF_PROV_YAML' > "$TEST_SKILLS_ARCH_WS/plugins/sample-prov/plugin.yaml"
name: sample-prov
version: 1.0.0
description: Synthetic provider plugin
skill_dir: .sample-prov/skills
config_defaults:
  skills: true
EOF_PROV_YAML

mkdir -p "$TEST_SKILLS_ARCH_WS/plugins/sample-domain/skills"
mkdir -p "$TEST_SKILLS_ARCH_WS/plugins/sample-domain/hooks"
cat <<'EOF_DOM_YAML' > "$TEST_SKILLS_ARCH_WS/plugins/sample-domain/plugin.yaml"
name: sample-domain
version: 1.0.0
description: Synthetic domain plugin
skills:
  - skills/domain-work.md: .rnex/plugins/sample-domain/skills/domain-work.md
EOF_DOM_YAML
echo "# Domain Work Skill" > "$TEST_SKILLS_ARCH_WS/plugins/sample-domain/skills/domain-work.md"

cat <<'EOF_DOM_AS' > "$TEST_SKILLS_ARCH_WS/plugins/sample-domain/hooks/after_sync.sh"
#!/bin/sh
if [ -f "$RNEX_ROOT/.rnex/bin/rnex-env.sh" ]; then
  . "$RNEX_ROOT/.rnex/bin/rnex-env.sh"
fi
rnex_generate_user_skill "domain-work" ".rnex/plugins/sample-domain/skills/domain-work.md" "sample-domain"
EOF_DOM_AS

cat <<'EOF_DOM_BPD' > "$TEST_SKILLS_ARCH_WS/plugins/sample-domain/hooks/before_plugin_disable.sh"
#!/bin/sh
if [ -f "$RNEX_ROOT/.rnex/bin/rnex-env.sh" ]; then
  . "$RNEX_ROOT/.rnex/bin/rnex-env.sh"
fi
rnex_unregister_user_skill "domain-work" "sample-domain"
EOF_DOM_BPD
chmod +x "$TEST_SKILLS_ARCH_WS/plugins/sample-domain/hooks"/*

(cd "$TEST_SKILLS_ARCH_WS" && ./rnex init -y >/dev/null)
cat <<'EOF_WS_SKILLS' >> "$TEST_SKILLS_ARCH_WS/rnex.yaml"
plugins:
  sample-prov: {}
  sample-domain: {}
repos:
EOF_WS_SKILLS

(cd "$TEST_SKILLS_ARCH_WS" && ./rnex sync -y >/dev/null)

# Verify core skills in .rnex/skills/
[ -f "$TEST_SKILLS_ARCH_WS/.rnex/skills/clone-sync.md" ] || { fail "clone-sync.md missing in .rnex/skills/"; exit 1; }
[ -f "$TEST_SKILLS_ARCH_WS/.rnex/skills/batch-exec.md" ] || { fail "batch-exec.md missing in .rnex/skills/"; exit 1; }
[ ! -f "$TEST_SKILLS_ARCH_WS/.rnex/skills/domain-work.md" ] || { fail "Domain skill leaked into core skills/"; exit 1; }

# Verify plugin skill in .rnex/plugins/sample-domain/skills/
[ -f "$TEST_SKILLS_ARCH_WS/.rnex/plugins/sample-domain/skills/domain-work.md" ] || { fail "domain-work.md missing in plugin skills/"; exit 1; }

# Verify User Skills in .sample-prov/skills/
[ -f "$TEST_SKILLS_ARCH_WS/.sample-prov/skills/rnex-clone-sync/SKILL.md" ] || { fail "rnex-clone-sync User Skill missing"; exit 1; }
[ -f "$TEST_SKILLS_ARCH_WS/.sample-prov/skills/rnex-sample-domain-domain-work/SKILL.md" ] || { fail "rnex-sample-domain-domain-work User Skill missing"; exit 1; }

# Verify target pointers
grep -q "\.rnex/skills/clone-sync\.md" "$TEST_SKILLS_ARCH_WS/.sample-prov/skills/rnex-clone-sync/SKILL.md" || { fail "Target path wrong in core user skill"; exit 1; }
grep -q "\.rnex/plugins/sample-domain/skills/domain-work\.md" "$TEST_SKILLS_ARCH_WS/.sample-prov/skills/rnex-sample-domain-domain-work/SKILL.md" || { fail "Target path wrong in domain user skill"; exit 1; }

# Disable domain plugin and verify its user skill is cleaned while core user skills remain
(cd "$TEST_SKILLS_ARCH_WS" && ./rnex plugin disable sample-domain >/dev/null)
[ ! -d "$TEST_SKILLS_ARCH_WS/.sample-prov/skills/rnex-sample-domain-domain-work" ] || { fail "Domain user skill not cleaned on disable"; exit 1; }
[ -f "$TEST_SKILLS_ARCH_WS/.sample-prov/skills/rnex-clone-sync/SKILL.md" ] || { fail "Core user skill was removed when disabling domain plugin"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Plugin engine: external plugin mounting via plugins.<name>.path and resolution priority"
TEST_EXT_WS="$TEST_TMP/ext-plugins-path-ws"
mkdir -p "$TEST_EXT_WS"
cp "$CLI" "$TEST_EXT_WS/rnex"
chmod +x "$TEST_EXT_WS/rnex"
cp "$DIR/package.json" "$TEST_EXT_WS/package.json"
cp -r "$DIR/lib" "$TEST_EXT_WS/lib"
cp -r "$DIR/templates" "$TEST_EXT_WS/templates"
(cd "$TEST_EXT_WS" && ./rnex init -y >/dev/null)

mkdir -p "$TEST_EXT_WS/ext/acme-plugin/commands"
cat <<'EOF_ACME_YAML' > "$TEST_EXT_WS/ext/acme-plugin/plugin.yaml"
name: acme-plugin
version: 2.3.0
description: Acme external engineering workflow plugin
commands:
  - hello: Say hello from external plugin
EOF_ACME_YAML
cat <<'EOF_ACME_HELLO' > "$TEST_EXT_WS/ext/acme-plugin/commands/hello.sh"
#!/bin/sh
printf 'hello-from-acme:%s\n' "${1:-world}"
EOF_ACME_HELLO
chmod +x "$TEST_EXT_WS/ext/acme-plugin/commands/hello.sh"

cat <<'EOF_EXT_CFG' >> "$TEST_EXT_WS/rnex.yaml"
plugins:
  acme-plugin:
    enabled: true
    path: "./ext/acme-plugin"
repos:
EOF_EXT_CFG

_list_out="$(cd "$TEST_EXT_WS" && ./rnex plugin list 2>&1)"
echo "$_list_out" | grep -q "acme-plugin" || { fail "acme-plugin not discovered in list: $_list_out"; exit 1; }
echo "$_list_out" | grep -q "(v2.3.0)" || { fail "acme-plugin version 2.3.0 missing in list: $_list_out"; exit 1; }

_info_out="$(cd "$TEST_EXT_WS" && ./rnex plugin info acme-plugin 2>&1)"
echo "$_info_out" | grep -q "Location:" || { fail "Location header missing in info: $_info_out"; exit 1; }
echo "$_info_out" | grep "Location:" | grep -q "ext/acme-plugin" || { fail "Resolved location wrong in info: $_info_out"; exit 1; }

# Sync and execute
(cd "$TEST_EXT_WS" && ./rnex sync >/dev/null)
[ -d "$TEST_EXT_WS/.rnex/plugins/acme-plugin" ] || { fail ".rnex/plugins/acme-plugin not synced"; exit 1; }
_cmd_out="$(cd "$TEST_EXT_WS" && ./rnex plugin acme-plugin hello enterprise 2>&1)"
echo "$_cmd_out" | grep -q "hello-from-acme:enterprise" || { fail "Command output mismatch: $_cmd_out"; exit 1; }

# Test manifest pointer normalization
sed 's|path: "./ext/acme-plugin"|path: "./ext/acme-plugin/plugin.yaml"|' "$TEST_EXT_WS/rnex.yaml" > "$TEST_EXT_WS/rnex.yaml.tmp"
mv "$TEST_EXT_WS/rnex.yaml.tmp" "$TEST_EXT_WS/rnex.yaml"
_cmd_out2="$(cd "$TEST_EXT_WS" && ./rnex plugin acme-plugin hello manifest-path 2>&1)"
echo "$_cmd_out2" | grep -q "hello-from-acme:manifest-path" || { fail "Manifest-path command mismatch: $_cmd_out2"; exit 1; }

# Resolution priority: .local.rnex.yaml (path) > rnex.yaml (path)
mkdir -p "$TEST_EXT_WS/local-override/acme-plugin"
cat <<'EOF_LOCAL_ACME' > "$TEST_EXT_WS/local-override/acme-plugin/plugin.yaml"
name: acme-plugin
version: 3.0.0-local
description: Local override plugin
EOF_LOCAL_ACME

cat <<'EOF_LOCAL_OVR' > "$TEST_EXT_WS/.local.rnex.yaml"
plugins:
  acme-plugin:
    path: ./local-override/acme-plugin
EOF_LOCAL_OVR

_ver_local="$(cd "$TEST_EXT_WS" && ./rnex plugin info acme-plugin | sed -n 's/.*(v\(.*\))/\1/p')"
[ "$_ver_local" = "3.0.0-local" ] || { fail "Local override failed: expected 3.0.0-local, got $_ver_local"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Plugin engine invariant: zero references to plugins_dir or plugins.<name>.dir"
if grep -rn "plugins_dir" "$DIR/rnex" "$DIR/lib/" "$DIR/docs/" "$DIR/templates/" "$DIR/README.md" "$DIR/CONTRIBUTION.md" 2>/dev/null; then
  fail "Found stale plugins_dir references"; exit 1
fi
if grep -rn "plugins\.<name>\.dir\|plugin\.<name>\.dir" "$DIR/rnex" "$DIR/lib/" "$DIR/docs/" "$DIR/templates/" "$DIR/README.md" "$DIR/CONTRIBUTION.md" 2>/dev/null; then
  fail "Found stale plugins.<name>.dir references"; exit 1
fi
if grep -En 'yaml_(get_plugin_config|plugin_get).*["'"'"']dir["'"'"']' "$DIR/rnex" "$DIR/lib/" 2>/dev/null; then
  fail "Found yaml_get_plugin_config or yaml_plugin_get query for 'dir'"; exit 1
fi
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
