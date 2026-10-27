#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# tests/suites/07_goal_fixes.sh — Regression tests for audited CLI bugs
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$DIR/tests/test_helper.sh"

TEST_GOAL_WS="$TEST_TMP/goal-fixes-workspace"
mkdir -p "$TEST_GOAL_WS"
setup_dummy_repo

cp "$CLI" "$TEST_GOAL_WS/rnex"
chmod +x "$TEST_GOAL_WS/rnex"
cp "$DIR/package.json" "$TEST_GOAL_WS/package.json"
cp -r "$DIR/lib" "$TEST_GOAL_WS/lib"
cp -r "$DIR/toolkit" "$TEST_GOAL_WS/toolkit"
cp -r "$DIR/templates" "$TEST_GOAL_WS/templates"

# Initialize workspace with copilot and karpathy plugins
(cd "$TEST_GOAL_WS" && ./rnex init -y --copilot --karpathy >/dev/null)

# --------------------------------------------------------------------------
run_test "Fix 1: cmd_plugin_update logs Plugin 'name' updated instead of empty name"
_update_out="$(cd "$TEST_GOAL_WS" && ./rnex plugin update copilot 2>&1)"
echo "$_update_out" | grep -q "Plugin 'copilot' updated" || { fail "Expected 'Plugin '\''copilot'\'' updated', got: $_update_out"; exit 1; }
! echo "$_update_out" | grep -q "Plugin '' updated" || { fail "Found buggy 'Plugin '\'''\'' updated': $_update_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 2a: Lifecycle hooks before_sync and after_sync fire exactly once on rnex sync"
mkdir -p "$TEST_GOAL_WS/toolkit/plugins/karpathy-llm/hooks"
cat <<'EOF_BS' > "$TEST_GOAL_WS/toolkit/plugins/karpathy-llm/hooks/before_sync.sh"
#!/bin/sh
printf 'x\n' >> "$RNEX_ROOT/before_sync_counts"
EOF_BS
chmod +x "$TEST_GOAL_WS/toolkit/plugins/karpathy-llm/hooks/before_sync.sh"

# Pre-populate before_sync in .rnex so it exists for the before_sync hook run before sync_plugins
mkdir -p "$TEST_GOAL_WS/.rnex/plugins/karpathy-llm/hooks"
cp "$TEST_GOAL_WS/toolkit/plugins/karpathy-llm/hooks/before_sync.sh" "$TEST_GOAL_WS/.rnex/plugins/karpathy-llm/hooks/before_sync.sh"

# Append counter output to existing after_sync.sh in toolkit
cat <<'EOF_AS' >> "$TEST_GOAL_WS/toolkit/plugins/karpathy-llm/hooks/after_sync.sh"
printf 'y\n' >> "$RNEX_ROOT/after_sync_counts"
EOF_AS

rm -f "$TEST_GOAL_WS/before_sync_counts" "$TEST_GOAL_WS/after_sync_counts"

(cd "$TEST_GOAL_WS" && ./rnex sync -y >/dev/null)

[ -f "$TEST_GOAL_WS/before_sync_counts" ] || { fail "before_sync hook did not fire"; exit 1; }
[ -f "$TEST_GOAL_WS/after_sync_counts" ] || { fail "after_sync hook did not fire"; exit 1; }
_bs_count="$(wc -l < "$TEST_GOAL_WS/before_sync_counts" | tr -d ' ')"
_as_count="$(wc -l < "$TEST_GOAL_WS/after_sync_counts" | tr -d ' ')"
[ "$_bs_count" -eq 1 ] || { fail "before_sync fired $_bs_count times (expected 1)"; exit 1; }
[ "$_as_count" -eq 1 ] || { fail "after_sync fired $_as_count times (expected 1)"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 2b: Lifecycle hook after_init fires exactly once on rnex init"
TEST_INIT_HOOK_WS="$TEST_TMP/init-hook-ws"
mkdir -p "$TEST_INIT_HOOK_WS"
cp "$CLI" "$TEST_INIT_HOOK_WS/rnex"
chmod +x "$TEST_INIT_HOOK_WS/rnex"
cp "$DIR/package.json" "$TEST_INIT_HOOK_WS/package.json"
cp -r "$DIR/lib" "$TEST_INIT_HOOK_WS/lib"
cp -r "$DIR/toolkit" "$TEST_INIT_HOOK_WS/toolkit"
cp -r "$DIR/templates" "$TEST_INIT_HOOK_WS/templates"

# Create a custom after_init.sh in toolkit/plugins/copilot/hooks/
mkdir -p "$TEST_INIT_HOOK_WS/toolkit/plugins/copilot/hooks"
cat <<'EOF_AI' > "$TEST_INIT_HOOK_WS/toolkit/plugins/copilot/hooks/after_init.sh"
#!/bin/sh
printf 'init_fired\n' >> "$RNEX_ROOT/after_init_counts"
EOF_AI
chmod +x "$TEST_INIT_HOOK_WS/toolkit/plugins/copilot/hooks/after_init.sh"

(cd "$TEST_INIT_HOOK_WS" && ./rnex init -y --copilot >/dev/null)
[ -f "$TEST_INIT_HOOK_WS/after_init_counts" ] || { fail "after_init hook did not fire"; exit 1; }
_ai_count="$(wc -l < "$TEST_INIT_HOOK_WS/after_init_counts" | tr -d ' ')"
[ "$_ai_count" -eq 1 ] || { fail "after_init fired $_ai_count times (expected 1)"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 3: Swallowed exit codes in cmd_exec properly propagated"
(cd "$TEST_GOAL_WS" && ./rnex repo add "$TEST_REPO" --name repo-exec >/dev/null)
set +e
(cd "$TEST_GOAL_WS" && ./rnex exec "false" >/dev/null 2>&1)
_exec_rc=$?
set -e
[ "$_exec_rc" -ne 0 ] || { fail "rnex exec false returned 0 instead of non-zero exit code"; exit 1; }

set +e
(cd "$TEST_GOAL_WS" && ./rnex exec "exit 42" >/dev/null 2>&1)
_exec_rc42=$?
set -e
[ "$_exec_rc42" -eq 42 ] || { fail "rnex exec exit 42 returned $_exec_rc42 (expected 42)"; exit 1; }

set +e
(cd "$TEST_GOAL_WS" && ./rnex repo exec repo-exec "exit 42" >/dev/null 2>&1)
_repo_exec_rc42=$?
set -e
[ "$_repo_exec_rc42" -eq 42 ] || { fail "rnex repo exec exit 42 returned $_repo_exec_rc42 (expected 42)"; exit 1; }

# Successful exec returns 0
(cd "$TEST_GOAL_WS" && ./rnex exec "true" >/dev/null)
pass

# --------------------------------------------------------------------------
run_test "Fix 4: set -e prevents after_<cmd> hooks on failure in dispatch_action"
cat <<'EOF_AE' > "$TEST_GOAL_WS/.rnex/plugins/karpathy-llm/hooks/after_exec.sh"
#!/bin/sh
printf 'AFTER_EXEC_RAN\n' > "$RNEX_ROOT/after_exec_marker"
EOF_AE
chmod +x "$TEST_GOAL_WS/.rnex/plugins/karpathy-llm/hooks/after_exec.sh"
rm -f "$TEST_GOAL_WS/after_exec_marker"

set +e
(cd "$TEST_GOAL_WS" && ./rnex exec "false" >/dev/null 2>&1)
_fail_rc=$?
set -e

[ "$_fail_rc" -ne 0 ] || { fail "rnex exec failed command should have non-zero exit code"; exit 1; }
[ -f "$TEST_GOAL_WS/after_exec_marker" ] || { fail "after_exec hook was not executed when command failed under set -e"; exit 1; }
grep -q "AFTER_EXEC_RAN" "$TEST_GOAL_WS/after_exec_marker" || { fail "after_exec marker content mismatch"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 5: Re-enabling a disabled plugin in rnex.yaml updates enabled: true"
# Manually disable copilot in rnex.yaml
sed -e '/copilot:/,/skills:/ s/skills: true/enabled: false/' "$TEST_GOAL_WS/rnex.yaml" > "$TEST_GOAL_WS/rnex.yaml.tmp"
mv "$TEST_GOAL_WS/rnex.yaml.tmp" "$TEST_GOAL_WS/rnex.yaml"
# Ensure enabled: false is in rnex.yaml
if ! grep -q "enabled: false" "$TEST_GOAL_WS/rnex.yaml"; then
  # Replace copilot block with enabled: false
  awk '
    /^  copilot:/ { print; print "    enabled: false"; next }
    { print }
  ' "$TEST_GOAL_WS/rnex.yaml" > "$TEST_GOAL_WS/rnex.yaml.tmp" && mv "$TEST_GOAL_WS/rnex.yaml.tmp" "$TEST_GOAL_WS/rnex.yaml"
fi
(cd "$TEST_GOAL_WS" && ./rnex sync -y >/dev/null)
# Now re-enable without --local
(cd "$TEST_GOAL_WS" && ./rnex plugin enable copilot >/dev/null)
grep -q "enabled: true" "$TEST_GOAL_WS/rnex.yaml" || { fail "rnex.yaml was not updated to enabled: true for copilot"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 6: Commented repo keys removed by _yaml_remove_repo_from_file"
(cd "$TEST_GOAL_WS" && ./rnex repo add "$TEST_REPO" --name commented-repo >/dev/null)
# Add inline comment to repo header line in rnex.yaml
sed -e 's/^  commented-repo:[ ]*$/  commented-repo: # inline comment for test/' "$TEST_GOAL_WS/rnex.yaml" > "$TEST_GOAL_WS/rnex.yaml.tmp"
mv "$TEST_GOAL_WS/rnex.yaml.tmp" "$TEST_GOAL_WS/rnex.yaml"
grep -q "commented-repo: # inline comment" "$TEST_GOAL_WS/rnex.yaml" || { fail "Failed to prepare inline comment in rnex.yaml"; exit 1; }

(cd "$TEST_GOAL_WS" && ./rnex repo remove commented-repo --purge -y >/dev/null)
! grep -q "commented-repo" "$TEST_GOAL_WS/rnex.yaml" || { fail "commented-repo was not removed from rnex.yaml when having inline comment"; exit 1; }
[ ! -d "$TEST_GOAL_WS/repos/commented-repo" ] || { fail "repos/commented-repo directory was not deleted"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 7: cmd_plugin_disable does not print duplicate log message"
_disable_out="$(cd "$TEST_GOAL_WS" && ./rnex plugin disable copilot 2>&1)"
_disable_count="$(echo "$_disable_out" | grep -c "disabled from workspace" || true)"
[ "$_disable_count" -eq 1 ] || { fail "Expected 1 'disabled from workspace' log, got $_disable_count:\n$_disable_out"; exit 1; }
# Re-enable copilot for subsequent tests
(cd "$TEST_GOAL_WS" && ./rnex plugin enable copilot >/dev/null)
pass

# --------------------------------------------------------------------------
run_test "Fix 8: Path resolution & flag inconsistencies in repo commands"
# 8a: cmd_repo_remove parses flags properly (-y and --purge before or after name)
(cd "$TEST_GOAL_WS" && ./rnex repo add "$TEST_REPO" --name remove-flag-repo >/dev/null)
(cd "$TEST_GOAL_WS" && ./rnex repo remove -y --purge remove-flag-repo >/dev/null)
[ ! -d "$TEST_GOAL_WS/repos/remove-flag-repo" ] || { fail "remove -y <name> failed to delete repo directory"; exit 1; }
! grep -q "remove-flag-repo" "$TEST_GOAL_WS/rnex.yaml" || { fail "remove -y <name> failed to unregister repo from rnex.yaml"; exit 1; }

# 8b: cmd_repo_set supports --local
(cd "$TEST_GOAL_WS" && ./rnex repo add "$TEST_REPO" --name readonly-test >/dev/null)
(cd "$TEST_GOAL_WS" && ./rnex repo set readonly-test --readonly --local >/dev/null)
[ -f "$TEST_GOAL_WS/.local.rnex.yaml" ] || { fail ".local.rnex.yaml not created by repo set --readonly --local"; exit 1; }
grep -q "readonly: true" "$TEST_GOAL_WS/.local.rnex.yaml" || { fail "readonly: true not set in .local.rnex.yaml"; exit 1; }

# 8c: cmd_clone uses resolve_repo_path (custom path resolution)
mkdir -p "$TEST_GOAL_WS/custom-repos"
cat <<'EOF_CR' >> "$TEST_GOAL_WS/rnex.yaml"
  custom-path-repo:
    path: custom-repos/my-custom-repo
    url: ./dummy-url
EOF_CR
# Set valid url pointing to TEST_REPO
sed -e "s|\./dummy-url|$TEST_REPO|" "$TEST_GOAL_WS/rnex.yaml" > "$TEST_GOAL_WS/rnex.yaml.tmp"
mv "$TEST_GOAL_WS/rnex.yaml.tmp" "$TEST_GOAL_WS/rnex.yaml"
(cd "$TEST_GOAL_WS" && ./rnex clone >/dev/null)
[ -d "$TEST_GOAL_WS/custom-repos/my-custom-repo/.git" ] || { fail "cmd_clone did not use resolve_repo_path to clone into custom path"; exit 1; }

# 8d: completion.sh includes readonly in zsh and fish
_zsh_out="$("$TEST_GOAL_WS/rnex" completion zsh)"
echo "$_zsh_out" | grep -q "readonly" || { fail "zsh completion missing readonly"; exit 1; }
_fish_out="$("$TEST_GOAL_WS/rnex" completion fish)"
echo "$_fish_out" | grep -q "readonly" || { fail "fish completion missing readonly"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 9: Incomplete copilot plugin CLI integration"
# 9a: status displays copilot instructions and options
_status_out="$(cd "$TEST_GOAL_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q ".github/copilot-instructions.md" || { fail "status did not check .github/copilot-instructions.md: $_status_out"; exit 1; }
echo "$_status_out" | grep "copilot" -A 2 | grep -q "Options: skills=" || { fail "status did not display copilot options: $_status_out"; exit 1; }

# 9b: plugin info copilot shows configurable options with .github/skills/
_pinfo_copilot="$(cd "$TEST_GOAL_WS" && ./rnex plugin info copilot 2>&1)"
echo "$_pinfo_copilot" | grep -q "Configurable Options" || { fail "copilot plugin info missing Configurable Options: $_pinfo_copilot"; exit 1; }
echo "$_pinfo_copilot" | grep -q "\.github/skills/" || { fail "copilot plugin info missing .github/skills/: $_pinfo_copilot"; exit 1; }

# 9c: help lists --copilot and --karpathy in init syntax
_help_out="$("$TEST_GOAL_WS/rnex" help 2>&1)"
echo "$_help_out" | grep "init " | grep -q -- "--copilot" || { fail "help init missing --copilot: $_help_out"; exit 1; }
echo "$_help_out" | grep "init " | grep -q -- "--karpathy" || { fail "help init missing --karpathy: $_help_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 10: --config / -c pre-flight check_auto_sync detects changes from outside directory"
TEST_CFG_EXT_WS="$TEST_TMP/cfg-ext-ws"
mkdir -p "$TEST_CFG_EXT_WS"
cp "$CLI" "$TEST_CFG_EXT_WS/rnex"
chmod +x "$TEST_CFG_EXT_WS/rnex"
cp "$DIR/package.json" "$TEST_CFG_EXT_WS/package.json"
cp -r "$DIR/lib" "$TEST_CFG_EXT_WS/lib"
cp -r "$DIR/toolkit" "$TEST_CFG_EXT_WS/toolkit"
cp -r "$DIR/templates" "$TEST_CFG_EXT_WS/templates"
(cd "$TEST_CFG_EXT_WS" && ./rnex init -y >/dev/null)

# Verify sync stamp exists
[ -f "$TEST_CFG_EXT_WS/.rnex/sync_stamp" ] || { fail "sync stamp missing after init"; exit 1; }
[ ! -f "$TEST_CFG_EXT_WS/.rnex/.sync_stamp" ] || { fail "legacy .sync_stamp still exists after init"; exit 1; }

# Modify rnex.yaml in TEST_CFG_EXT_WS
printf "\n# modified config\n" >> "$TEST_CFG_EXT_WS/rnex.yaml"

# Run rnex with -c from outside directory (TEST_OUTSIDE)
mkdir -p "$TEST_OUTSIDE"
cd "$TEST_OUTSIDE"
_outside_out="$("$TEST_CFG_EXT_WS/rnex" -c "$TEST_CFG_EXT_WS/rnex.yaml" list 2>&1)"
cd "$DIR"

# Verify the stamp in TEST_CFG_EXT_WS was updated to match the new config sum
_new_sum="$(cd "$TEST_CFG_EXT_WS" && cksum rnex.yaml .local.rnex.yaml 2>/dev/null | cksum | awk '{print $1, $2}')"
_stamp_val="$(cat "$TEST_CFG_EXT_WS/.rnex/sync_stamp" 2>/dev/null)"
[ "$_new_sum" = "$_stamp_val" ] || { fail "Auto-sync was not triggered for custom config from external directory (sum: $_new_sum, stamp: $_stamp_val)"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 11: Clean template instantiation without sequential sed path corruption"
TEST_TPL_WS="$TEST_TMP/tpl-path-ws"
mkdir -p "$TEST_TPL_WS"
cp "$CLI" "$TEST_TPL_WS/rnex"
chmod +x "$TEST_TPL_WS/rnex"
cp "$DIR/package.json" "$TEST_TPL_WS/package.json"
cp -r "$DIR/lib" "$TEST_TPL_WS/lib"
cp -r "$DIR/toolkit" "$TEST_TPL_WS/toolkit"
cp -r "$DIR/templates" "$TEST_TPL_WS/templates"
git -C "$TEST_TPL_WS" init -q

"$TEST_TPL_WS/rnex" init -y "$TEST_TPL_WS" >/dev/null

cat <<'EOF_TPL' >> "$TEST_TPL_WS/rnex.yaml"
plugins:
  karpathy-llm:
    wiki_dir: docs/wiki
    raw_dir: intake/raw
EOF_TPL

(cd "$TEST_TPL_WS" && ./rnex sync -y >/dev/null)

[ -f "$TEST_TPL_WS/docs/wiki/hot.md" ] || { fail "docs/wiki/hot.md missing"; exit 1; }
[ -f "$TEST_TPL_WS/docs/wiki/index.md" ] || { fail "docs/wiki/index.md missing"; exit 1; }
[ -f "$TEST_TPL_WS/docs/wiki/_log.md" ] || { fail "docs/wiki/_log.md missing"; exit 1; }

# Assert clean paths in hot.md
! grep -q "docs/docs/wiki" "$TEST_TPL_WS/docs/wiki/hot.md" || { fail "Found corrupted duplicated path docs/docs/wiki in hot.md"; exit 1; }
! grep -q "intake/intake/raw" "$TEST_TPL_WS/docs/wiki/hot.md" || { fail "Found corrupted duplicated path intake/intake/raw in hot.md"; exit 1; }
! grep -q "\.rnex/\.rnex" "$TEST_TPL_WS/docs/wiki/hot.md" || { fail "Found corrupted duplicated path .rnex/.rnex in hot.md"; exit 1; }
grep -q "docs/wiki/" "$TEST_TPL_WS/docs/wiki/hot.md" || { fail "docs/wiki/ missing from hot.md"; exit 1; }
grep -q "intake/raw/" "$TEST_TPL_WS/docs/wiki/hot.md" || { fail "intake/raw/ missing from hot.md"; exit 1; }

# Assert clean paths in index.md and _log.md
! grep -q "docs/docs/wiki" "$TEST_TPL_WS/docs/wiki/index.md" || { fail "Found corrupted docs/docs/wiki in index.md"; exit 1; }
! grep -q "intake/intake/raw" "$TEST_TPL_WS/docs/wiki/index.md" || { fail "Found corrupted intake/intake/raw in index.md"; exit 1; }
! grep -q "docs/docs/wiki" "$TEST_TPL_WS/docs/wiki/_log.md" || { fail "Found corrupted docs/docs/wiki in _log.md"; exit 1; }

# Assert <wiki_dir>/ literal placeholder preserved in sample/template
[ -f "$TEST_TPL_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" ] || { fail "rnex-wiki-page.template.md missing"; exit 1; }
grep -q "<wiki_dir>/" "$TEST_TPL_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" || { fail "<wiki_dir>/ placeholder missing in template"; exit 1; }
! grep -q "<docs/wiki>/" "$TEST_TPL_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" || { fail "<docs/wiki>/ corrupted placeholder found in template"; exit 1; }
! grep -q "<\.rnex/wiki>/" "$TEST_TPL_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" || { fail "<.rnex/wiki>/ corrupted placeholder found in template"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 12: Idempotent hot.md condensation across repeated syncs and custom repos_dir"
TEST_CONDENSE_WS="$TEST_TMP/condense-hot-ws"
mkdir -p "$TEST_CONDENSE_WS"
cp "$CLI" "$TEST_CONDENSE_WS/rnex"
chmod +x "$TEST_CONDENSE_WS/rnex"
cp "$DIR/package.json" "$TEST_CONDENSE_WS/package.json"
cp -r "$DIR/lib" "$TEST_CONDENSE_WS/lib"
cp -r "$DIR/toolkit" "$TEST_CONDENSE_WS/toolkit"
cp -r "$DIR/templates" "$TEST_CONDENSE_WS/templates"
git -C "$TEST_CONDENSE_WS" init -q

"$TEST_CONDENSE_WS/rnex" init -y "$TEST_CONDENSE_WS" >/dev/null

cat <<'EOF_COND' > "$TEST_CONDENSE_WS/rnex.yaml"
repos_dir: custom-repos
plugins:
  karpathy-llm: {}
repos:
EOF_COND

# Initial sync to scaffold wiki files
(cd "$TEST_CONDENSE_WS" && ./rnex sync -y >/dev/null)

# Append realistic domain context notes (~290 words) so initial + 15 repos (~110 + 290 + 120 = 520) exceeds 480 words, triggering condensation while keeping final condensed count <= 500 words.
cat <<'EOF_HOT_INIT' >> "$TEST_CONDENSE_WS/wiki/hot.md"

## Core System Directives
The unified workspace integrates distributed autonomous services collaborating across strictly verified contracts. Each member repository encapsulates domain microservices, isolating storage, ingestion pipelines, messaging buses, and analytics telemetry. When routing cross-repository requests, AI assistants must prioritize atomic markdown pages and typed relationships defined in the primary catalog. Distributed consensus protocols require state machine replication across regional clusters with bounded clock skew. Network partitions must be handled with eventual consistency for non-critical audit records while retaining strict serializability for financial ledger entries. Background reconcilers execute periodic health audits to detect stale cache entries, orphan pointers, and dangling foreign keys across schemas. Every service implements idempotent processing semantics to prevent duplicate transaction execution during retry storms. High availability clusters maintain warm standby nodes across redundant failure zones. Audit trails record every administrative event with cryptographic integrity verification.
The unified workspace integrates distributed autonomous services collaborating across strictly verified contracts. Each member repository encapsulates domain microservices, isolating storage, ingestion pipelines, messaging buses, and analytics telemetry. When routing cross-repository requests, AI assistants must prioritize atomic markdown pages and typed relationships defined in the primary catalog. Distributed consensus protocols require state machine replication across regional clusters with bounded clock skew. Network partitions must be handled with eventual consistency for non-critical audit records while retaining strict serializability for financial ledger entries. Background reconcilers execute periodic health audits to detect stale cache entries, orphan pointers, and dangling foreign keys across schemas. Every service implements idempotent processing semantics to prevent duplicate transaction execution during retry storms. High availability clusters maintain warm standby nodes across redundant failure zones. Audit trails record every administrative event with cryptographic integrity verification.
EOF_HOT_INIT

# Create 15 repositories under custom-repos/
for _idx in $(seq 1 15); do
  mkdir -p "$TEST_CONDENSE_WS/custom-repos/repo-$_idx"
  printf '# Member Repo %s\nHigh performance microservice module %s for distributed transactional workflows.\n' "$_idx" "$_idx" > "$TEST_CONDENSE_WS/custom-repos/repo-$_idx/README.md"
  printf '  repo-%s:\n' "$_idx" >> "$TEST_CONDENSE_WS/rnex.yaml"
done

# Sync 1: Triggers Step 3 condensation (>480 words)
(cd "$TEST_CONDENSE_WS" && ./rnex sync -y >/dev/null)
_wc1="$(wc -w < "$TEST_CONDENSE_WS/wiki/hot.md")"
[ "$_wc1" -le 500 ] || { fail "hot.md word count ($_wc1) exceeded 500 words on sync 1"; exit 1; }
_sum_cnt1="$(grep -c "Member Repositories" "$TEST_CONDENSE_WS/wiki/hot.md" || true)"
[ "$_sum_cnt1" -eq 1 ] || { fail "Expected 1 summary line on sync 1, found $_sum_cnt1"; exit 1; }
grep -q "Member Repositories (15 repos):" "$TEST_CONDENSE_WS/wiki/hot.md" || { fail "Missing condensed summary line on sync 1"; exit 1; }
! grep -q "\* \*\*repo-1 (" "$TEST_CONDENSE_WS/wiki/hot.md" || { fail "Individual repo entry not condensed on sync 1"; exit 1; }

# Sync 2: Verify idempotency - no re-insertion of individual lines or duplicate summary lines
(cd "$TEST_CONDENSE_WS" && ./rnex sync -y >/dev/null)
_wc2="$(wc -w < "$TEST_CONDENSE_WS/wiki/hot.md")"
[ "$_wc2" -le 500 ] || { fail "hot.md word count ($_wc2) exceeded 500 words on sync 2"; exit 1; }
_sum_cnt2="$(grep -c "Member Repositories" "$TEST_CONDENSE_WS/wiki/hot.md" || true)"
[ "$_sum_cnt2" -eq 1 ] || { fail "Duplicate summary lines generated on sync 2: count $_sum_cnt2"; exit 1; }

# Sync 3: Additional sync check
(cd "$TEST_CONDENSE_WS" && ./rnex sync -y >/dev/null)
_sum_cnt3="$(grep -c "Member Repositories" "$TEST_CONDENSE_WS/wiki/hot.md" || true)"
[ "$_sum_cnt3" -eq 1 ] || { fail "Duplicate summary lines generated on sync 3: count $_sum_cnt3"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 13: Non-destructive preservation of curated repo-<name>.md pages and deduplicated _log.md"
TEST_CURATED_WS="$TEST_TMP/curated-page-ws"
mkdir -p "$TEST_CURATED_WS"
cp "$CLI" "$TEST_CURATED_WS/rnex"
chmod +x "$TEST_CURATED_WS/rnex"
cp "$DIR/package.json" "$TEST_CURATED_WS/package.json"
cp -r "$DIR/lib" "$TEST_CURATED_WS/lib"
cp -r "$DIR/toolkit" "$TEST_CURATED_WS/toolkit"
cp -r "$DIR/templates" "$TEST_CURATED_WS/templates"
git -C "$TEST_CURATED_WS" init -q

"$TEST_CURATED_WS/rnex" init -y "$TEST_CURATED_WS" >/dev/null

mkdir -p "$TEST_CURATED_WS/repos/auth-svc"
printf '# Auth Service\nAuthentication and authorization microservice.\n' > "$TEST_CURATED_WS/repos/auth-svc/README.md"
cat <<'EOF_CUR' > "$TEST_CURATED_WS/rnex.yaml"
version: 0.6.16
repos_dir: ./repos
plugins:
  karpathy-llm: {}
repos:
  auth-svc: {}
EOF_CUR

(cd "$TEST_CURATED_WS" && ./rnex sync -y >/dev/null)

[ -f "$TEST_CURATED_WS/wiki/repo-auth-svc.md" ] || { fail "repo-auth-svc.md not generated"; exit 1; }

# User / Agent curates repo-auth-svc.md
cat <<'EOF_PAGE' > "$TEST_CURATED_WS/wiki/repo-auth-svc.md"
---
title: "Member Repo: auth-svc (Curated)"
tags: [member-repo, auth-svc, security]
sources: ["repos/auth-svc/README.md"]
related: ["repo-billing.md"]
extends: ["specs/oauth2.md"]
contradicts: []
mentioned_in: ["architecture-overview.md"]
---

# Auth Service

Authentication and authorization microservice.

## Curated Invariant
- Tokens must validate JWKS with exponential caching.
EOF_PAGE

# Modify source README.md to simulate an update that makes src strictly newer than page
sleep 1
printf '# Auth Service (Upgraded)\nUpdated authentication logic.\n' > "$TEST_CURATED_WS/repos/auth-svc/README.md"

# Run rnex sync again
(cd "$TEST_CURATED_WS" && ./rnex sync -y >/dev/null)

# Verify curated fields and custom notes are strictly preserved
grep -q 'title: "Member Repo: auth-svc (Curated)"' "$TEST_CURATED_WS/wiki/repo-auth-svc.md" || { fail "Curated title was overwritten"; exit 1; }
grep -q 'related: \["repo-billing\.md"\]' "$TEST_CURATED_WS/wiki/repo-auth-svc.md" || { fail "Curated related links were overwritten"; exit 1; }
grep -q 'extends: \["specs/oauth2\.md"\]' "$TEST_CURATED_WS/wiki/repo-auth-svc.md" || { fail "Curated extends links were overwritten"; exit 1; }
grep -q 'mentioned_in: \["architecture-overview\.md"\]' "$TEST_CURATED_WS/wiki/repo-auth-svc.md" || { fail "Curated mentioned_in links were overwritten"; exit 1; }
grep -q "Curated Invariant" "$TEST_CURATED_WS/wiki/repo-auth-svc.md" || { fail "Curated notes body was overwritten"; exit 1; }

# Verify _log.md has only 1 entry for auth-svc ingest (no duplicate audit entries)
_log_cnt="$(grep -c "Member Repo Ingest: auth-svc" "$TEST_CURATED_WS/wiki/_log.md" || true)"
[ "$_log_cnt" -eq 1 ] || { fail "Expected 1 log entry for auth-svc, got $_log_cnt"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 14: Hook config isolation, robust repos_dir parsing, untracked folder filtering, and git diff --root"
TEST_CFG_ISOLATION_WS="$TEST_TMP/cfg-isolation-ws"
mkdir -p "$TEST_CFG_ISOLATION_WS"
cp "$CLI" "$TEST_CFG_ISOLATION_WS/rnex"
chmod +x "$TEST_CFG_ISOLATION_WS/rnex"
cp "$DIR/package.json" "$TEST_CFG_ISOLATION_WS/package.json"
cp -r "$DIR/lib" "$TEST_CFG_ISOLATION_WS/lib"
cp -r "$DIR/toolkit" "$TEST_CFG_ISOLATION_WS/toolkit"
cp -r "$DIR/templates" "$TEST_CFG_ISOLATION_WS/templates"
git -C "$TEST_CFG_ISOLATION_WS" init -q

"$TEST_CFG_ISOLATION_WS/rnex" init -y "$TEST_CFG_ISOLATION_WS" >/dev/null

# 14a & 14b: Sibling plugin isolation & repos_dir parsing with quotes and inline comments with colons
cat <<'EOF_ISO' > "$TEST_CFG_ISOLATION_WS/rnex.yaml"
version: 0.6.16
repos_dir: "my-repos" # note: inline comment: with colons and spaces
plugins:
  claude:
    wiki_dir: leaked/claude/wiki
    raw_dir: leaked/claude/raw
    lint_trigger: git-pre-push
  karpathy-llm: {}
repos:
  declared-repo: {}
  custom-path-repo:
    path: nested/custom-repo-dir
EOF_ISO

# Create member repositories
mkdir -p "$TEST_CFG_ISOLATION_WS/my-repos/declared-repo"
printf '# Declared Repo\nTracked in rnex.yaml\n' > "$TEST_CFG_ISOLATION_WS/my-repos/declared-repo/README.md"

mkdir -p "$TEST_CFG_ISOLATION_WS/my-repos/untracked-stray"
printf '# Untracked Stray\nNot in rnex.yaml\n' > "$TEST_CFG_ISOLATION_WS/my-repos/untracked-stray/README.md"

mkdir -p "$TEST_CFG_ISOLATION_WS/nested/custom-repo-dir"
printf '# Custom Path Repo\nCustom path repo\n' > "$TEST_CFG_ISOLATION_WS/nested/custom-repo-dir/README.md"

(cd "$TEST_CFG_ISOLATION_WS" && ./rnex sync -y >/dev/null)

# Verify default wiki_dir wiki used, NOT leaked/claude/wiki
[ -d "$TEST_CFG_ISOLATION_WS/wiki" ] || { fail "Default wiki not created"; exit 1; }
[ ! -d "$TEST_CFG_ISOLATION_WS/leaked" ] || { fail "Sibling plugin claude keys leaked into karpathy-llm"; exit 1; }

# Verify declared repo ingested
[ -f "$TEST_CFG_ISOLATION_WS/wiki/repo-declared-repo.md" ] || { fail "repo-declared-repo.md not ingested"; exit 1; }

# Verify custom path repo ingested with correct sources path
[ -f "$TEST_CFG_ISOLATION_WS/wiki/repo-custom-path-repo.md" ] || { fail "repo-custom-path-repo.md not ingested"; exit 1; }
grep -q 'sources: \["nested/custom-repo-dir/README.md"\]' "$TEST_CFG_ISOLATION_WS/wiki/repo-custom-path-repo.md" || { fail "sources path incorrect for custom path repo"; exit 1; }

# Verify untracked stray directory ignored
[ ! -f "$TEST_CFG_ISOLATION_WS/wiki/repo-untracked-stray.md" ] || { fail "Untracked stray folder was ingested into wiki"; exit 1; }

# 14c: Karpathy-llm plugin manifest config cleanup (removal of lint_trigger and notify_on_changes)
_k_yaml="$DIR/toolkit/plugins/karpathy-llm/plugin.yaml"
! grep -q "lint_trigger" "$_k_yaml" || { fail "lint_trigger still present in plugin.yaml"; exit 1; }
! grep -q "notify_on_changes" "$_k_yaml" || { fail "notify_on_changes still present in plugin.yaml"; exit 1; }
grep -q 'wiki_dir:[ ]*"wiki"' "$_k_yaml" || grep -q 'wiki_dir:[ ]*wiki' "$_k_yaml" || { fail "default wiki_dir in plugin.yaml is not wiki"; exit 1; }
grep -q "ingest:" "$_k_yaml" || { fail "ingest command missing in plugin.yaml"; exit 1; }
grep -q "lint:" "$_k_yaml" || { fail "lint command missing in plugin.yaml"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 15: README.md documentation accuracy, removal of ingest_member_readmes, and raw_dir to sources migration"
# 15a: README & plugin.yaml documentation check
_readme_file="$DIR/toolkit/plugins/karpathy-llm/README.md"
[ -f "$_readme_file" ] || { fail "README.md missing"; exit 1; }
grep -q "sources" "$_readme_file" || { fail "README.md does not document sources"; exit 1; }
! grep -q "ingest_member_readmes" "$_readme_file" || { fail "README.md still mentions obsolete ingest_member_readmes"; exit 1; }
! grep -q "ingest_member_readmes" "$DIR/toolkit/plugins/karpathy-llm/plugin.yaml" || { fail "plugin.yaml still mentions obsolete ingest_member_readmes"; exit 1; }
! grep -q "auto_index" "$_readme_file" || { fail "README.md still mentions auto_index"; exit 1; }
! grep -q "run_deterministic_checks" "$_readme_file" || { fail "README.md still mentions run_deterministic_checks"; exit 1; }
! grep -q "ai_cmd" "$_readme_file" || { fail "README.md still mentions ai_cmd"; exit 1; }

# 15b: Legacy raw_dir rewritten to sources on sync, and member README skipped when sources only lists docs
TEST_TOGGLE_WS="$TEST_TMP/toggle-ingest-ws"
mkdir -p "$TEST_TOGGLE_WS"
cp "$CLI" "$TEST_TOGGLE_WS/rnex"
chmod +x "$TEST_TOGGLE_WS/rnex"
cp "$DIR/package.json" "$TEST_TOGGLE_WS/package.json"
cp -r "$DIR/lib" "$TEST_TOGGLE_WS/lib"
cp -r "$DIR/toolkit" "$TEST_TOGGLE_WS/toolkit"
cp -r "$DIR/templates" "$TEST_TOGGLE_WS/templates"
git -C "$TEST_TOGGLE_WS" init -q

"$TEST_TOGGLE_WS/rnex" init -y "$TEST_TOGGLE_WS" >/dev/null

mkdir -p "$TEST_TOGGLE_WS/repos/skipped-repo"
printf '# Skipped Repo\nShould not be ingested\n' > "$TEST_TOGGLE_WS/repos/skipped-repo/README.md"

cat <<'EOF_TOG' > "$TEST_TOGGLE_WS/rnex.yaml"
version: 0.6.16
plugins:
  karpathy-llm:
    raw_dir: docs
    ingest_member_readmes: false
repos:
  skipped-repo: {}
EOF_TOG

(cd "$TEST_TOGGLE_WS" && ./rnex sync -y >/dev/null)
! grep -q "raw_dir:" "$TEST_TOGGLE_WS/rnex.yaml" || { fail "raw_dir was not rewritten to sources in rnex.yaml"; exit 1; }
! grep -q "ingest_member_readmes" "$TEST_TOGGLE_WS/rnex.yaml" || { fail "ingest_member_readmes was not stripped from rnex.yaml"; exit 1; }
grep -q "^    sources:$" "$TEST_TOGGLE_WS/rnex.yaml" || { fail "sources key missing in rnex.yaml after migration"; exit 1; }
grep -q "^      - docs$" "$TEST_TOGGLE_WS/rnex.yaml" || { fail "'- docs' item missing in rnex.yaml after migration"; exit 1; }
[ ! -f "$TEST_TOGGLE_WS/wiki/repo-skipped-repo.md" ] || { fail "repo-skipped-repo.md was generated despite sources only containing docs"; exit 1; }
[ ! -f "$TEST_TOGGLE_WS/.rnex/wiki/repo-skipped-repo.md" ] || { fail "repo-skipped-repo.md was generated despite sources only containing docs"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 16: Copilot before_plugin_disable hook preserves unrelated prompts and non-empty directories"
TEST_COP_DIS_WS="$TEST_TMP/cop-disable-preserve-ws"
mkdir -p "$TEST_COP_DIS_WS"
cp "$CLI" "$TEST_COP_DIS_WS/rnex"
chmod +x "$TEST_COP_DIS_WS/rnex"
cp "$DIR/package.json" "$TEST_COP_DIS_WS/package.json"
cp -r "$DIR/lib" "$TEST_COP_DIS_WS/lib"
cp -r "$DIR/toolkit" "$TEST_COP_DIS_WS/toolkit"
cp -r "$DIR/templates" "$TEST_COP_DIS_WS/templates"
git -C "$TEST_COP_DIS_WS" init -q

"$TEST_COP_DIS_WS/rnex" init -y --copilot "$TEST_COP_DIS_WS" >/dev/null

# Add user-authored prompts in .github/prompts/ and a plugin-owned prompt
mkdir -p "$TEST_COP_DIS_WS/.github/prompts"
printf '# User custom prompt\n' > "$TEST_COP_DIS_WS/.github/prompts/user-authored.prompt.md"
printf '# Third-party prompt\n' > "$TEST_COP_DIS_WS/.github/prompts/vendor.prompt.md"
printf '# Plugin-owned prompt\n' > "$TEST_COP_DIS_WS/.github/prompts/rnex-sample.prompt.md"

# Disable copilot plugin
(cd "$TEST_COP_DIS_WS" && ./rnex plugin disable copilot >/dev/null)

# Verify plugin-owned prompt is removed but user/third-party prompts remain
[ ! -f "$TEST_COP_DIS_WS/.github/prompts/rnex-sample.prompt.md" ] || { fail "Plugin-owned prompt was not removed"; exit 1; }
[ -f "$TEST_COP_DIS_WS/.github/prompts/user-authored.prompt.md" ] || { fail "User-authored prompt was deleted as collateral"; exit 1; }
[ -f "$TEST_COP_DIS_WS/.github/prompts/vendor.prompt.md" ] || { fail "Vendor prompt was deleted as collateral"; exit 1; }
[ -d "$TEST_COP_DIS_WS/.github/prompts" ] || { fail ".github/prompts directory was removed despite containing user files"; exit 1; }

# Remove remaining user prompts and run disable hook again; verify empty directory is cleaned
rm -f "$TEST_COP_DIS_WS/.github/prompts"/*
(RNEX_ROOT="$TEST_COP_DIS_WS" "$TEST_COP_DIS_WS/toolkit/plugins/copilot/hooks/before_plugin_disable.sh" >/dev/null 2>&1 || true)
[ ! -d "$TEST_COP_DIS_WS/.github/prompts" ] || { fail "Empty .github/prompts directory was not removed"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 17: Karpathy-llm plugin.yaml quoted template placeholders parse cleanly as valid YAML and resolve without quotes"
_yaml_file="$DIR/toolkit/plugins/karpathy-llm/plugin.yaml"
[ -f "$_yaml_file" ] || { fail "karpathy-llm plugin.yaml missing"; exit 1; }

# Assert placeholders are quoted in plugin.yaml
grep -q 'templates/index\.md:[ ]*"{wiki_dir}/index\.md"' "$_yaml_file" || { fail "index.md placeholder not quoted in plugin.yaml"; exit 1; }
grep -q 'templates/hot\.md:[ ]*"{wiki_dir}/hot\.md"' "$_yaml_file" || { fail "hot.md placeholder not quoted in plugin.yaml"; exit 1; }

# Verify valid YAML parsing if ruby is available
if command -v ruby >/dev/null 2>&1; then
  ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$_yaml_file" || { fail "karpathy-llm plugin.yaml is not valid YAML"; exit 1; }
fi

# Verify placeholder resolution strips quotes cleanly
TEST_QUOTE_WS="$TEST_TMP/quote-resolve-ws"
mkdir -p "$TEST_QUOTE_WS"
cp "$CLI" "$TEST_QUOTE_WS/rnex"
chmod +x "$TEST_QUOTE_WS/rnex"
cp "$DIR/package.json" "$TEST_QUOTE_WS/package.json"
cp -r "$DIR/lib" "$TEST_QUOTE_WS/lib"
cp -r "$DIR/toolkit" "$TEST_QUOTE_WS/toolkit"
cp -r "$DIR/templates" "$TEST_QUOTE_WS/templates"
git -C "$TEST_QUOTE_WS" init -q

"$TEST_QUOTE_WS/rnex" init -y --karpathy "$TEST_QUOTE_WS" >/dev/null
[ -f "$TEST_QUOTE_WS/wiki/index.md" ] || { fail "index.md not created at resolved path"; exit 1; }
[ ! -d "$TEST_QUOTE_WS/\"" ] || { fail "Literal quotes leaked into directory names"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 18: Copilot after_sync hook functions reliably in standalone/unpreloaded hook runners"
TEST_STANDALONE_SYNC_WS="$TEST_TMP/cop-sync-standalone-ws"
mkdir -p "$TEST_STANDALONE_SYNC_WS"
cp "$CLI" "$TEST_STANDALONE_SYNC_WS/rnex"
chmod +x "$TEST_STANDALONE_SYNC_WS/rnex"
cp "$DIR/package.json" "$TEST_STANDALONE_SYNC_WS/package.json"
cp -r "$DIR/lib" "$TEST_STANDALONE_SYNC_WS/lib"
cp -r "$DIR/toolkit" "$TEST_STANDALONE_SYNC_WS/toolkit"
cp -r "$DIR/templates" "$TEST_STANDALONE_SYNC_WS/templates"
git -C "$TEST_STANDALONE_SYNC_WS" init -q
"$TEST_STANDALONE_SYNC_WS/rnex" init -y --copilot "$TEST_STANDALONE_SYNC_WS" >/dev/null
rm -f "$TEST_STANDALONE_SYNC_WS/.github/copilot-instructions.md"

# Run copilot after_sync.sh in a clean subshell with NO preloaded core functions
_sync_out="$(env -i PATH="$PATH" HOME="$HOME" RNEX_ROOT="$TEST_STANDALONE_SYNC_WS" sh "$TEST_STANDALONE_SYNC_WS/toolkit/plugins/copilot/hooks/after_sync.sh" 2>&1)" || { fail "after_sync.sh failed in unpreloaded subshell: $_sync_out"; exit 1; }
[ -f "$TEST_STANDALONE_SYNC_WS/.github/copilot-instructions.md" ] || { fail "copilot-instructions.md not created by standalone after_sync hook"; exit 1; }
grep -q "CRITICAL: You MUST read and strictly follow all instructions" "$TEST_STANDALONE_SYNC_WS/.github/copilot-instructions.md" || { fail "Instructions content missing in standalone after_sync run"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 19: Copilot before_plugin_disable hook functions reliably in standalone/unpreloaded hook runners"
TEST_STANDALONE_DIS_WS="$TEST_TMP/cop-dis-standalone-ws"
mkdir -p "$TEST_STANDALONE_DIS_WS"
cp "$CLI" "$TEST_STANDALONE_DIS_WS/rnex"
chmod +x "$TEST_STANDALONE_DIS_WS/rnex"
cp "$DIR/package.json" "$TEST_STANDALONE_DIS_WS/package.json"
cp -r "$DIR/lib" "$TEST_STANDALONE_DIS_WS/lib"
cp -r "$DIR/toolkit" "$TEST_STANDALONE_DIS_WS/toolkit"
cp -r "$DIR/templates" "$TEST_STANDALONE_DIS_WS/templates"
git -C "$TEST_STANDALONE_DIS_WS" init -q
"$TEST_STANDALONE_DIS_WS/rnex" init -y --copilot "$TEST_STANDALONE_DIS_WS" >/dev/null
[ -f "$TEST_STANDALONE_DIS_WS/.github/copilot-instructions.md" ] || { fail "copilot-instructions.md missing before disable"; exit 1; }

# Run copilot before_plugin_disable.sh in a clean subshell with NO preloaded core functions
_dis_out="$(env -i PATH="$PATH" HOME="$HOME" RNEX_ROOT="$TEST_STANDALONE_DIS_WS" sh "$TEST_STANDALONE_DIS_WS/toolkit/plugins/copilot/hooks/before_plugin_disable.sh" 2>&1)" || { fail "before_plugin_disable.sh failed in unpreloaded subshell: $_dis_out"; exit 1; }
[ ! -f "$TEST_STANDALONE_DIS_WS/.github/copilot-instructions.md" ] || { fail "copilot-instructions.md without user content should be removed by standalone before_plugin_disable hook"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 20: Karpathy-llm plugin commands ingest and lint execute with options and strict validation"
TEST_PUSH_WS="$TEST_TMP/git-prepush-ws"
mkdir -p "$TEST_PUSH_WS"
cp "$CLI" "$TEST_PUSH_WS/rnex"
chmod +x "$TEST_PUSH_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_PUSH_WS/toolkit"
cp "$DIR/package.json" "$TEST_PUSH_WS/package.json"
git -C "$TEST_PUSH_WS" init -q

"$TEST_PUSH_WS/rnex" init -y --karpathy "$TEST_PUSH_WS" >/dev/null

# Verify default wiki directory is ./wiki at workspace root
[ -d "$TEST_PUSH_WS/wiki" ] || { fail "Default wiki directory not created at workspace root ./wiki"; exit 1; }
[ -f "$TEST_PUSH_WS/wiki/index.md" ] || { fail "Default wiki/index.md missing"; exit 1; }
[ -f "$TEST_PUSH_WS/wiki/hot.md" ] || { fail "Default wiki/hot.md missing"; exit 1; }
[ -f "$TEST_PUSH_WS/wiki/_log.md" ] || { fail "Default wiki/_log.md missing"; exit 1; }

# Test ingest --source
mkdir -p "$TEST_PUSH_WS/docs"
printf '# Project Roadmap\nFuture roadmap notes.\n' > "$TEST_PUSH_WS/docs/roadmap.md"
(cd "$TEST_PUSH_WS" && ./rnex plugin karpathy-llm ingest --source docs/roadmap.md >/dev/null)
[ -f "$TEST_PUSH_WS/wiki/roadmap.md" ] || { fail "wiki/roadmap.md not created by ingest --source"; exit 1; }

# Test lint passing
_lint_ok="$(cd "$TEST_PUSH_WS" && ./rnex plugin karpathy-llm lint 2>&1)" || { fail "lint failed: $_lint_ok"; exit 1; }
echo "$_lint_ok" | grep -q "Wiki lint passed" || { fail "Lint output mismatch: $_lint_ok"; exit 1; }

# Test lint --strict failing on broken source link
cat > "$TEST_PUSH_WS/wiki/broken-doc.md" <<'EOF_BROKEN'
---
title: Broken Doc
last_updated: 2026-10-24
sources: ["nonexistent/missing-source.md"]
related: []
extends: []
---

# Broken Doc
Summary.
EOF_BROKEN

_lint_strict_err=0
(cd "$TEST_PUSH_WS" && ./rnex plugin karpathy-llm lint --strict >/dev/null 2>&1) || _lint_strict_err=1
[ "$_lint_strict_err" -eq 1 ] || { fail "lint --strict did not exit non-zero on broken source link"; exit 1; }

# Clean up broken doc
rm -f "$TEST_PUSH_WS/wiki/broken-doc.md"
pass

# --------------------------------------------------------------------------
run_test "Fix 21: Karpathy-llm rnex-scaffolding-meta-prompt.md relation and source examples match configured wiki/ and ./docs/ paths"
_prompt_file="$DIR/toolkit/plugins/karpathy-llm/instructions/rnex-scaffolding-meta-prompt.md"
[ -f "$_prompt_file" ] || { fail "rnex-scaffolding-meta-prompt.md missing"; exit 1; }

grep -q "sources: \[\][ ]*#[ ]*\./docs/ files this page was derived from" "$_prompt_file" || { fail "sources example does not reference ./docs/: $(grep -n 'sources:' "$_prompt_file")"; exit 1; }
grep -q "# Typed relation fields — paths relative to wiki/" "$_prompt_file" || { fail "relations example does not reference wiki/: $(grep -n 'Typed relation fields' "$_prompt_file")"; exit 1; }
grep -q "\`wiki/index\.md\` uses its own frontmatter schema" "$_prompt_file" || { fail "index file example does not reference wiki/index.md"; exit 1; }
! grep -q "# /raw/ files this page was derived from" "$_prompt_file" || { fail "Still references legacy /raw/ in sources comment"; exit 1; }
! grep -q "# Typed relation fields — paths relative to /wiki/" "$_prompt_file" || { fail "Still references legacy /wiki/ in relations comment"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 22: rnex sync resolves template placeholders without creating literal \"{wiki_dir} or \"{raw_dir} directories and purges leaked dirs"
TEST_SYNC_PLACEHOLDER_WS="$TEST_TMP/sync-placeholder-ws"
mkdir -p "$TEST_SYNC_PLACEHOLDER_WS"
cp "$CLI" "$TEST_SYNC_PLACEHOLDER_WS/rnex"
chmod +x "$TEST_SYNC_PLACEHOLDER_WS/rnex"
cp "$DIR/package.json" "$TEST_SYNC_PLACEHOLDER_WS/package.json"
cp -r "$DIR/lib" "$TEST_SYNC_PLACEHOLDER_WS/lib"
cp -r "$DIR/toolkit" "$TEST_SYNC_PLACEHOLDER_WS/toolkit"
cp -r "$DIR/templates" "$TEST_SYNC_PLACEHOLDER_WS/templates"
git -C "$TEST_SYNC_PLACEHOLDER_WS" init -q

# Initialize workspace without plugins first
"$TEST_SYNC_PLACEHOLDER_WS/rnex" init -y "$TEST_SYNC_PLACEHOLDER_WS" >/dev/null

# Simulate pre-existing leaked bogus directories in workspace root
mkdir -p "$TEST_SYNC_PLACEHOLDER_WS/\"{wiki_dir}" "$TEST_SYNC_PLACEHOLDER_WS/\"{raw_dir}" "$TEST_SYNC_PLACEHOLDER_WS/{wiki_dir}" "$TEST_SYNC_PLACEHOLDER_WS/{raw_dir}"
[ -d "$TEST_SYNC_PLACEHOLDER_WS/\"{wiki_dir}" ] || { fail "Failed to set up test directory \"{wiki_dir}"; exit 1; }
[ -d "$TEST_SYNC_PLACEHOLDER_WS/\"{raw_dir}" ] || { fail "Failed to set up test directory \"{raw_dir}"; exit 1; }

# Enable karpathy-llm plugin
cat <<'EOF_CFG' >> "$TEST_SYNC_PLACEHOLDER_WS/rnex.yaml"
plugins:
  karpathy-llm: true
EOF_CFG

# Run rnex sync
_sync_out="$(cd "$TEST_SYNC_PLACEHOLDER_WS" && ./rnex sync 2>&1)" || { fail "rnex sync failed: $_sync_out"; exit 1; }

# Verify bogus directories were purged
[ ! -d "$TEST_SYNC_PLACEHOLDER_WS/\"{wiki_dir}" ] || { fail "Bogus directory \"{wiki_dir} still exists after sync"; exit 1; }
[ ! -d "$TEST_SYNC_PLACEHOLDER_WS/\"{raw_dir}" ] || { fail "Bogus directory \"{raw_dir} still exists after sync"; exit 1; }
[ ! -d "$TEST_SYNC_PLACEHOLDER_WS/{wiki_dir}" ] || { fail "Bogus directory {wiki_dir} still exists after sync"; exit 1; }
[ ! -d "$TEST_SYNC_PLACEHOLDER_WS/{raw_dir}" ] || { fail "Bogus directory {raw_dir} still exists after sync"; exit 1; }
[ ! -d "$TEST_SYNC_PLACEHOLDER_WS/\"" ] || { fail "Literal quote directory leaked into workspace root"; exit 1; }

# Verify templates were correctly initialized in resolved paths
[ -f "$TEST_SYNC_PLACEHOLDER_WS/wiki/index.md" ] || { fail "wiki/index.md missing after sync"; exit 1; }
[ -f "$TEST_SYNC_PLACEHOLDER_WS/docs/.gitkeep" ] || { fail "docs/.gitkeep missing after sync"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Fix 23: rnex sync reordered steps and karpathy-llm wiki_dir / raw_dir configuration without leaking ./raw or ./wiki"
TEST_SYNC_GOAL_WS="$TEST_TMP/sync-goal-ws"
mkdir -p "$TEST_SYNC_GOAL_WS"
cp "$CLI" "$TEST_SYNC_GOAL_WS/rnex"
chmod +x "$TEST_SYNC_GOAL_WS/rnex"
cp "$DIR/package.json" "$TEST_SYNC_GOAL_WS/package.json"
cp -r "$DIR/lib" "$TEST_SYNC_GOAL_WS/lib"
cp -r "$DIR/toolkit" "$TEST_SYNC_GOAL_WS/toolkit"
cp -r "$DIR/templates" "$TEST_SYNC_GOAL_WS/templates"
git -C "$TEST_SYNC_GOAL_WS" init -q

# Initialize workspace
"$TEST_SYNC_GOAL_WS/rnex" init -y "$TEST_SYNC_GOAL_WS" >/dev/null

# Configure exact user rnex.yaml
cat <<'EOF_CFG' > "$TEST_SYNC_GOAL_WS/rnex.yaml"
name: user-test-project
plugins:
  karpathy-llm:
    wiki_dir: .rnex/wiki
    raw_dir: docs
EOF_CFG

# Simulate pre-existing leaked root raw/ and wiki/ directories (e.g. from previous runs)
mkdir -p "$TEST_SYNC_GOAL_WS/raw" "$TEST_SYNC_GOAL_WS/wiki"
touch "$TEST_SYNC_GOAL_WS/raw/.gitkeep"
touch "$TEST_SYNC_GOAL_WS/wiki/index.md"
[ -d "$TEST_SYNC_GOAL_WS/raw" ] || { fail "Failed to set up test directory raw"; exit 1; }
[ -d "$TEST_SYNC_GOAL_WS/wiki" ] || { fail "Failed to set up test directory wiki"; exit 1; }

# Remove Step 2 artifacts to verify that rnex sync generates them before Step 3 completes
rm -f "$TEST_SYNC_GOAL_WS/.rnex/sync_stamp" "$TEST_SYNC_GOAL_WS/.rnex/.sync_stamp" "$TEST_SYNC_GOAL_WS/.rnex/ai-instructions.md"
[ ! -f "$TEST_SYNC_GOAL_WS/.rnex/sync_stamp" ] || { fail "sync_stamp was not removed"; exit 1; }
[ ! -f "$TEST_SYNC_GOAL_WS/.rnex/ai-instructions.md" ] || { fail "ai-instructions.md was not removed"; exit 1; }

# Add after_sync hook to verify that during Step 3, Step 2 artifacts (.rnex/sync_stamp & .rnex/ai-instructions.md) already exist
mkdir -p "$TEST_SYNC_GOAL_WS/toolkit/plugins/karpathy-llm/hooks"
cat <<'HOOK_CHECK' > "$TEST_SYNC_GOAL_WS/toolkit/plugins/karpathy-llm/hooks/after_sync.sh"
#!/bin/sh
if [ ! -f "$RNEX_ROOT/.rnex/sync_stamp" ]; then
  echo "STEP_ORDER_ERROR: sync_stamp does not exist before Step 3 completes" >&2
  exit 1
fi
if [ ! -f "$RNEX_ROOT/.rnex/ai-instructions.md" ]; then
  echo "STEP_ORDER_ERROR: ai-instructions.md does not exist before Step 3 completes" >&2
  exit 1
fi
echo "STEP_ORDER_VERIFIED: Step 2 ran before Step 3"
HOOK_CHECK
chmod +x "$TEST_SYNC_GOAL_WS/toolkit/plugins/karpathy-llm/hooks/after_sync.sh"

# Run rnex sync and capture output
_sync_goal_out="$(cd "$TEST_SYNC_GOAL_WS" && ./rnex sync 2>&1)" || { fail "rnex sync failed: $_sync_goal_out"; exit 1; }

# Verify step order assertion passed
echo "$_sync_goal_out" | grep -q "STEP_ORDER_VERIFIED: Step 2 ran before Step 3" || { fail "Step order verification failed: $_sync_goal_out"; exit 1; }

# Verify .rnex/sync_stamp and .rnex/ai-instructions.md exist
[ -f "$TEST_SYNC_GOAL_WS/.rnex/sync_stamp" ] || { fail ".rnex/sync_stamp missing after sync"; exit 1; }
[ ! -f "$TEST_SYNC_GOAL_WS/.rnex/.sync_stamp" ] || { fail "legacy .rnex/.sync_stamp still exists after sync"; exit 1; }
[ -f "$TEST_SYNC_GOAL_WS/.rnex/ai-instructions.md" ] || { fail ".rnex/ai-instructions.md missing after sync"; exit 1; }

# Verify root raw/ and wiki/ were purged / do not exist
[ ! -d "$TEST_SYNC_GOAL_WS/raw" ] || { fail "Root ./raw directory still exists after sync"; exit 1; }
[ ! -d "$TEST_SYNC_GOAL_WS/wiki" ] || { fail "Root ./wiki directory still exists after sync"; exit 1; }

# Verify configured directories exist and have templates
[ -d "$TEST_SYNC_GOAL_WS/docs" ] || { fail "Configured raw_dir 'docs' missing after sync"; exit 1; }
[ -f "$TEST_SYNC_GOAL_WS/docs/.gitkeep" ] || { fail "docs/.gitkeep missing after sync"; exit 1; }
[ -d "$TEST_SYNC_GOAL_WS/.rnex/wiki" ] || { fail "Configured wiki_dir '.rnex/wiki' missing after sync"; exit 1; }
[ -f "$TEST_SYNC_GOAL_WS/.rnex/wiki/index.md" ] || { fail ".rnex/wiki/index.md missing after sync"; exit 1; }
[ -f "$TEST_SYNC_GOAL_WS/.rnex/wiki/hot.md" ] || { fail ".rnex/wiki/hot.md missing after sync"; exit 1; }
[ -f "$TEST_SYNC_GOAL_WS/.rnex/wiki/_log.md" ] || { fail ".rnex/wiki/_log.md missing after sync"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Fix 24: rnex sync (with gemini plugin enabled) builds .agents/skills/ instead of .gemini/skills/"
TEST_GEMINI_WS="$TEST_TMP/gemini-fix-ws"
mkdir -p "$TEST_GEMINI_WS"
cp "$CLI" "$TEST_GEMINI_WS/rnex"
chmod +x "$TEST_GEMINI_WS/rnex"
cp "$DIR/package.json" "$TEST_GEMINI_WS/package.json"
cp -r "$DIR/lib" "$TEST_GEMINI_WS/lib"
cp -r "$DIR/toolkit" "$TEST_GEMINI_WS/toolkit"
cp -r "$DIR/templates" "$TEST_GEMINI_WS/templates"

# Create a legacy .gemini/skills directory to verify migration/cleanup
mkdir -p "$TEST_GEMINI_WS/.gemini/skills/rnex-legacy-skill"
echo "legacy" > "$TEST_GEMINI_WS/.gemini/skills/rnex-legacy.md"

(cd "$TEST_GEMINI_WS" && ./rnex init -y --gemini >/dev/null)

# Verify .agents/skills/ is created and .gemini/skills/ is cleaned up
[ -d "$TEST_GEMINI_WS/.agents/skills" ] || { fail ".agents/skills missing after init --gemini"; exit 1; }
[ -f "$TEST_GEMINI_WS/.agents/skills/rnex-clone-sync/SKILL.md" ] || { fail ".agents/skills/rnex-clone-sync/SKILL.md missing"; exit 1; }
[ ! -d "$TEST_GEMINI_WS/.gemini/skills" ] || { fail "legacy .gemini/skills was not purged on sync"; exit 1; }

# Verify GEMINI.md exists with instructions directive
[ -f "$TEST_GEMINI_WS/GEMINI.md" ] || { fail "GEMINI.md missing after init --gemini"; exit 1; }
grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$TEST_GEMINI_WS/GEMINI.md" || { fail "GEMINI.md missing directive"; exit 1; }

# Verify AGENTS.md is NOT created when gemini provider is active
[ ! -f "$TEST_GEMINI_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created when gemini provider is active"; exit 1; }

# Status reports .agents/skills/ and GEMINI.md, and does not report AGENTS.md
_gem_status="$(cd "$TEST_GEMINI_WS" && ./rnex status 2>&1)"
echo "$_gem_status" | grep -q "GEMINI.md" || { fail "status did not report GEMINI.md: $_gem_status"; exit 1; }
! echo "$_gem_status" | grep -q "AGENTS.md" || { fail "status reported AGENTS.md when inactive: $_gem_status"; exit 1; }
echo "$_gem_status" | grep -q "\.agents/skills/" || { fail "status did not report .agents/skills/: $_gem_status"; exit 1; }
! echo "$_gem_status" | grep -q "\.gemini/skills/" || { fail "status reported obsolete .gemini/skills/: $_gem_status"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Fix 25: rnex sync (with copilot enabled) maintains permanent AGENTS.md and copilot-instructions.md across init, sync, and disable"
TEST_COPILOT_WS="$TEST_TMP/copilot-redundancy-ws"
mkdir -p "$TEST_COPILOT_WS"
cp "$CLI" "$TEST_COPILOT_WS/rnex"
chmod +x "$TEST_COPILOT_WS/rnex"
cp "$DIR/package.json" "$TEST_COPILOT_WS/package.json"
cp -r "$DIR/lib" "$TEST_COPILOT_WS/lib"
cp -r "$DIR/toolkit" "$TEST_COPILOT_WS/toolkit"
cp -r "$DIR/templates" "$TEST_COPILOT_WS/templates"

# 1. Initialize workspace with copilot plugin enabled
(cd "$TEST_COPILOT_WS" && ./rnex init -y --copilot >/dev/null)

# Verify .github/copilot-instructions.md was created with routing instructions
[ -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || { fail ".github/copilot-instructions.md missing after init --copilot"; exit 1; }
grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$TEST_COPILOT_WS/.github/copilot-instructions.md" || { fail ".github/copilot-instructions.md missing directive"; exit 1; }

# Verify AGENTS.md was NOT created (active provider copilot owns routing)
[ ! -f "$TEST_COPILOT_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created after init --copilot"; exit 1; }

# Status reports copilot instructions and not AGENTS.md
_copilot_status="$(cd "$TEST_COPILOT_WS" && ./rnex status 2>&1)"
echo "$_copilot_status" | grep -q "\.github/copilot-instructions.md" || { fail "status did not report .github/copilot-instructions.md: $_copilot_status"; exit 1; }
! echo "$_copilot_status" | grep -q "AGENTS.md" || { fail "status reported AGENTS.md when copilot enabled: $_copilot_status"; exit 1; }

# 2. Test AGENTS.md remains absent on sync when copilot is enabled
(cd "$TEST_COPILOT_WS" && ./rnex sync -y >/dev/null)
[ ! -f "$TEST_COPILOT_WS/AGENTS.md" ] || { fail "AGENTS.md should remain absent after rnex sync with copilot enabled"; exit 1; }

# 3. Test existing custom AGENTS.md preserves user content alongside rnex block
cat <<'EOF_CUSTOM_AGENTS' > "$TEST_COPILOT_WS/AGENTS.md"
# Custom Workspace Guidelines
These are custom developer instructions.
<!-- REPO-NEXUS:START -->
CRITICAL: You MUST read and strictly follow all instructions in `.rnex/ai-instructions.md` before executing any task or answering any query in this workspace.
<!-- REPO-NEXUS:END -->
EOF_CUSTOM_AGENTS

(cd "$TEST_COPILOT_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_COPILOT_WS/AGENTS.md" ] || { fail "Custom AGENTS.md was incorrectly deleted"; exit 1; }
grep -q "These are custom developer instructions" "$TEST_COPILOT_WS/AGENTS.md" || { fail "Custom developer instructions were deleted from AGENTS.md"; exit 1; }

# 4. Disable copilot plugin: copilot-instructions.md (empty of user content) is removed, while custom AGENTS.md is preserved
(cd "$TEST_COPILOT_WS" && ./rnex plugin disable copilot >/dev/null)
[ ! -f "$TEST_COPILOT_WS/.github/copilot-instructions.md" ] || { fail ".github/copilot-instructions.md without user content should be removed after disabling copilot"; exit 1; }
[ -f "$TEST_COPILOT_WS/AGENTS.md" ] || { fail "Custom AGENTS.md missing after disabling copilot"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_COPILOT_WS/AGENTS.md" || { fail "REPO-NEXUS instructions not found in AGENTS.md after disabling copilot"; exit 1; }
grep -q "These are custom developer instructions" "$TEST_COPILOT_WS/AGENTS.md" || { fail "Custom developer instructions lost in AGENTS.md"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Fix 26: Claude and Gemini auto_sync_on lifecycle hooks (.claude/settings.json & .agents/hooks.json) and rnex-env.sh .gemini deduplication"
TEST_HOOKS_WS="$TEST_TMP/hooks-test-ws"
mkdir -p "$TEST_HOOKS_WS"
cp "$CLI" "$TEST_HOOKS_WS/rnex"
chmod +x "$TEST_HOOKS_WS/rnex"
cp "$DIR/package.json" "$TEST_HOOKS_WS/package.json"
cp -r "$DIR/lib" "$TEST_HOOKS_WS/lib"
cp -r "$DIR/toolkit" "$TEST_HOOKS_WS/toolkit"
cp -r "$DIR/templates" "$TEST_HOOKS_WS/templates"

# 1. Verify sdk.sh does not contain .gemini check
# shellcheck disable=SC2016
! grep -q '\[ -d "\$RNEX_ROOT/\.gemini" \]' "$DIR/lib/sdk.sh" || { fail "lib/sdk.sh still contains .gemini check"; exit 1; }

# 2. Initialize workspace with claude and gemini plugins
(cd "$TEST_HOOKS_WS" && ./rnex init -y --claude --gemini >/dev/null)

# Verify generated .rnex/bin/rnex-env.sh does not contain .gemini check
# shellcheck disable=SC2016
! grep -q '\[ -d "\$RNEX_ROOT/\.gemini" \]' "$TEST_HOOKS_WS/.rnex/bin/rnex-env.sh" || { fail ".rnex/bin/rnex-env.sh still contains .gemini check"; exit 1; }

# Verify instruction files created automatically without instructions: setting
[ -f "$TEST_HOOKS_WS/CLAUDE.md" ] || { fail "CLAUDE.md not created by default"; exit 1; }
[ -f "$TEST_HOOKS_WS/GEMINI.md" ] || { fail "GEMINI.md not created by default"; exit 1; }
grep -q "CRITICAL: You MUST read and strictly follow" "$TEST_HOOKS_WS/CLAUDE.md" || { fail "CLAUDE.md missing directive"; exit 1; }
grep -q "CRITICAL: You MUST read and strictly follow" "$TEST_HOOKS_WS/GEMINI.md" || { fail "GEMINI.md missing directive"; exit 1; }

# Verify .claude/settings.json created with SessionStart auto-sync hook
[ -f "$TEST_HOOKS_WS/.claude/settings.json" ] || { fail ".claude/settings.json not created"; exit 1; }
grep -q '"SessionStart"' "$TEST_HOOKS_WS/.claude/settings.json" || { fail ".claude/settings.json missing SessionStart"; exit 1; }
grep -q '"command"[ ]*:[ ]*"\.rnex/bin/auto-sync\.sh"' "$TEST_HOOKS_WS/.claude/settings.json" || { fail ".claude/settings.json missing auto-sync command"; exit 1; }

# Verify .agents/hooks.json created with rnex-auto-sync SessionStart hook
[ -f "$TEST_HOOKS_WS/.agents/hooks.json" ] || { fail ".agents/hooks.json not created"; exit 1; }
grep -q '"rnex-auto-sync"' "$TEST_HOOKS_WS/.agents/hooks.json" || { fail ".agents/hooks.json missing rnex-auto-sync"; exit 1; }
grep -q '"SessionStart"' "$TEST_HOOKS_WS/.agents/hooks.json" || { fail ".agents/hooks.json missing SessionStart"; exit 1; }
grep -q '"command"[ ]*:[ ]*"\.rnex/bin/auto-sync\.sh"' "$TEST_HOOKS_WS/.agents/hooks.json" || { fail ".agents/hooks.json missing auto-sync command"; exit 1; }

# 3. Status command displays auto_sync_on option
_hooks_status="$(cd "$TEST_HOOKS_WS" && ./rnex status 2>&1)"
echo "$_hooks_status" | grep "claude" -A 2 | grep -q "auto_sync_on=SessionStart" || { fail "status missing claude auto_sync_on: $_hooks_status"; exit 1; }
echo "$_hooks_status" | grep "gemini" -A 2 | grep -q "auto_sync_on=SessionStart" || { fail "status missing gemini auto_sync_on: $_hooks_status"; exit 1; }

# 4. Test disabling auto_sync_on: false in rnex.yaml
cat <<'EOF_CFG_NO_HOOKS' > "$TEST_HOOKS_WS/rnex.yaml"
version: 0.7.22
repos_dir: ./repos
code_workspace: false
git_hooks: false
plugins:
  claude:
    skills: true
    auto_sync_on: false
  gemini:
    skills: true
    autoSyncOn: false
repos:
EOF_CFG_NO_HOOKS

(cd "$TEST_HOOKS_WS" && ./rnex sync -y >/dev/null)

# Verify hooks removed from settings.json and hooks.json
[ ! -f "$TEST_HOOKS_WS/.claude/settings.json" ] || { fail ".claude/settings.json should be removed when empty"; exit 1; }
[ ! -f "$TEST_HOOKS_WS/.agents/hooks.json" ] || { fail ".agents/hooks.json should be removed when empty"; exit 1; }

# 5. Test re-enabling with camelCase autoSyncOn: SessionStart
cat <<'EOF_CFG_CAMEL' > "$TEST_HOOKS_WS/rnex.yaml"
version: 0.7.22
repos_dir: ./repos
code_workspace: false
git_hooks: false
plugins:
  claude:
    skills: true
    autoSyncOn: SessionStart
  gemini:
    skills: true
    auto_sync_on: SessionStart
repos:
EOF_CFG_CAMEL

(cd "$TEST_HOOKS_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_HOOKS_WS/.claude/settings.json" ] || { fail ".claude/settings.json not restored with autoSyncOn"; exit 1; }
[ -f "$TEST_HOOKS_WS/.agents/hooks.json" ] || { fail ".agents/hooks.json not restored with auto_sync_on"; exit 1; }

# 6. Test disabling plugins cleans up hooks
(cd "$TEST_HOOKS_WS" && ./rnex plugin disable claude >/dev/null)
(cd "$TEST_HOOKS_WS" && ./rnex plugin disable gemini >/dev/null)

[ ! -f "$TEST_HOOKS_WS/.claude/settings.json" ] || { fail ".claude/settings.json not cleaned after disabling claude"; exit 1; }
[ ! -f "$TEST_HOOKS_WS/.agents/hooks.json" ] || { fail ".agents/hooks.json not cleaned after disabling gemini"; exit 1; }
[ ! -f "$TEST_HOOKS_WS/CLAUDE.md" ] || { fail "CLAUDE.md without user content was not removed after disabling claude"; exit 1; }
[ ! -f "$TEST_HOOKS_WS/GEMINI.md" ] || { fail "GEMINI.md without user content was not removed after disabling gemini"; exit 1; }
[ -f "$TEST_HOOKS_WS/AGENTS.md" ] || { fail "AGENTS.md not restored after disabling provider plugins"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_HOOKS_WS/AGENTS.md" || { fail "REPO-NEXUS block missing from AGENTS.md"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Fix 27: Exclude docs/ from installations, npm packaging, and remove remaining .gitkeep files"
# 1. Verify package.json files array excludes docs/
grep -q '"docs/"' "$DIR/package.json" && { fail "package.json files array still includes docs/"; exit 1; }
grep -q '"rnex"' "$DIR/package.json" || { fail "package.json missing rnex in files"; exit 1; }
grep -q '"lib/"' "$DIR/package.json" || { fail "package.json missing lib/ in files"; exit 1; }
grep -q '"templates/"' "$DIR/package.json" || { fail "package.json missing templates/ in files"; exit 1; }
grep -q '"toolkit/"' "$DIR/package.json" || { fail "package.json missing toolkit/ in files"; exit 1; }

# 2. Verify .npmignore contains /docs/
grep -q '/docs/' "$DIR/.npmignore" || { fail ".npmignore missing /docs/"; exit 1; }

# 3. Verify no tracked .gitkeep files remain in repository
_gitkeep_count="$(git -C "$DIR" ls-files "*.gitkeep" 2>/dev/null | wc -l | tr -d ' ')"
[ "$_gitkeep_count" -eq 0 ] || { fail "Found $_gitkeep_count tracked .gitkeep files"; exit 1; }

# 4. Verify rnex install copies runtime assets and excludes docs/
TEST_CLI_INST_BIN="$TEST_TMP/test-cli-inst-bin"
TEST_CLI_INST_SHARE="$TEST_TMP/test-cli-inst-share"
mkdir -p "$TEST_CLI_INST_BIN" "$TEST_CLI_INST_SHARE"
RNEX_INSTALL_DIR="$TEST_CLI_INST_SHARE" "$DIR/rnex" install "$TEST_CLI_INST_BIN" >/dev/null
[ -x "$TEST_CLI_INST_BIN/rnex" ] || { fail "rnex install did not create executable in bin dir"; exit 1; }
[ -d "$TEST_CLI_INST_SHARE/lib" ] || { fail "rnex install did not copy lib/ to install dir"; exit 1; }
[ -d "$TEST_CLI_INST_SHARE/templates" ] || { fail "rnex install did not copy templates/ to install dir"; exit 1; }
[ -d "$TEST_CLI_INST_SHARE/toolkit" ] || { fail "rnex install did not copy toolkit/ to install dir"; exit 1; }
[ ! -d "$TEST_CLI_INST_SHARE/docs" ] || { fail "rnex install leaked docs/ into install dir"; exit 1; }
[ ! -d "$TEST_CLI_INST_BIN/docs" ] || { fail "rnex install leaked docs/ into bin dir"; exit 1; }

# 5. Verify scripts/install.sh copies runtime assets and excludes docs/
TEST_SCRIPT_INST_BIN="$TEST_TMP/test-script-inst-bin"
TEST_SCRIPT_INST_SHARE="$TEST_TMP/test-script-inst-share"
mkdir -p "$TEST_SCRIPT_INST_BIN" "$TEST_SCRIPT_INST_SHARE"
RNEX_REPO_URL="$DIR" RNEX_INSTALL_DIR="$TEST_SCRIPT_INST_SHARE" RNEX_BIN_DIR="$TEST_SCRIPT_INST_BIN" sh "$DIR/scripts/install.sh" >/dev/null
[ -x "$TEST_SCRIPT_INST_BIN/rnex" ] || { fail "scripts/install.sh did not create executable in bin dir"; exit 1; }
[ -d "$TEST_SCRIPT_INST_SHARE/lib" ] || { fail "scripts/install.sh did not copy lib/ to install dir"; exit 1; }
[ -d "$TEST_SCRIPT_INST_SHARE/templates" ] || { fail "scripts/install.sh did not copy templates/ to install dir"; exit 1; }
[ -d "$TEST_SCRIPT_INST_SHARE/toolkit" ] || { fail "scripts/install.sh did not copy toolkit/ to install dir"; exit 1; }
[ ! -d "$TEST_SCRIPT_INST_SHARE/docs" ] || { fail "scripts/install.sh leaked docs/ into install dir"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Fix 28: rnex repo add infers repository name from URL or path when name argument is omitted"
TEST_INFER_WS="$TEST_TMP/infer-name-workspace"
mkdir -p "$TEST_INFER_WS"
"$DIR/rnex" init -y "$TEST_INFER_WS" >/dev/null

# 1. rnex repo add with local repo path clones and infers name from directory
(cd "$TEST_INFER_WS" && "$CLI" repo add "$TEST_REPO" >/dev/null)
[ -d "$TEST_INFER_WS/repos/dummy-repo/.git" ] || { fail "dummy-repo not cloned when name omitted"; exit 1; }
grep -q "dummy-repo:" "$TEST_INFER_WS/rnex.yaml" || { fail "dummy-repo not registered in rnex.yaml"; exit 1; }

# 2. rnex repo add with HTTPS URL ending in .git infers name
(cd "$TEST_INFER_WS" && "$CLI" repo add https://github.com/example-org/inferred-service.git --disabled >/dev/null)
grep -q "inferred-service:" "$TEST_INFER_WS/rnex.yaml" || { fail "inferred-service not registered from .git URL"; exit 1; }

# 3. rnex repo add with URL with trailing slash and --local infers name
(cd "$TEST_INFER_WS" && "$CLI" repo add --local https://github.com/example-org/inferred-local/ --disabled >/dev/null)
grep -q "inferred-local:" "$TEST_INFER_WS/.local.rnex.yaml" || { fail "inferred-local not registered in local config"; exit 1; }

# 4. rnex repo add with SSH scp-like URL infers name
(cd "$TEST_INFER_WS" && "$CLI" repo add git@github.com:example-org/ssh-service.git --disabled >/dev/null)
grep -q "ssh-service:" "$TEST_INFER_WS/rnex.yaml" || { fail "ssh-service not registered from SSH URL"; exit 1; }

# 5. Explicit --name form works as expected
(cd "$TEST_INFER_WS" && "$CLI" repo add https://github.com/example-org/other.git --name custom-alias --disabled >/dev/null)
grep -q "custom-alias:" "$TEST_INFER_WS/rnex.yaml" || { fail "custom-alias not registered from --name form"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Fix 29: Codex plugin lifecycle (enable, CODEX.md, .codex/skills, status, and disable cleanup)"
TEST_CODEX_WS="$TEST_TMP/codex-lifecycle-ws"
mkdir -p "$TEST_CODEX_WS"
cp "$CLI" "$TEST_CODEX_WS/rnex"
chmod +x "$TEST_CODEX_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_CODEX_WS/toolkit"
cp "$DIR/package.json" "$TEST_CODEX_WS/package.json"
git -C "$TEST_CODEX_WS" init -q

# 1. Initialize workspace with --codex
"$TEST_CODEX_WS/rnex" init -y --codex "$TEST_CODEX_WS" >/dev/null
[ ! -f "$TEST_CODEX_WS/AGENTS.md" ] || { fail "AGENTS.md should not be created after init --codex"; exit 1; }
[ -f "$TEST_CODEX_WS/CODEX.md" ] || { fail "CODEX.md missing after init --codex"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_CODEX_WS/CODEX.md" || { fail "REPO-NEXUS routing block missing in CODEX.md"; exit 1; }

# 2. Verify User Skills generated in .codex/skills/
[ -d "$TEST_CODEX_WS/.codex/skills" ] || { fail ".codex/skills directory missing after init --codex"; exit 1; }
[ -f "$TEST_CODEX_WS/.codex/skills/rnex-clone-sync/SKILL.md" ] || { fail "rnex-clone-sync/SKILL.md missing in .codex/skills/"; exit 1; }
[ -f "$TEST_CODEX_WS/.codex/skills/rnex-batch-exec/SKILL.md" ] || { fail "rnex-batch-exec/SKILL.md missing in .codex/skills/"; exit 1; }
grep -q "name: rnex-clone-sync" "$TEST_CODEX_WS/.codex/skills/rnex-clone-sync/SKILL.md" || { fail "Codex user skill missing YAML frontmatter"; exit 1; }
grep -q "\.rnex/skills/clone-sync\.md" "$TEST_CODEX_WS/.codex/skills/rnex-clone-sync/SKILL.md" || { fail "Codex user skill missing target skill path"; exit 1; }

# 3. Verify compiled instructions in .rnex/ai-instructions.md
[ -f "$TEST_CODEX_WS/.rnex/ai-instructions.md" ] || { fail ".rnex/ai-instructions.md missing"; exit 1; }
! grep -q "OpenAI Codex Integration for Repo Nexus" "$TEST_CODEX_WS/.rnex/ai-instructions.md" || { fail "Codex instructions must not be compiled into .rnex/ai-instructions.md"; exit 1; }

# 4. Status inspection
_codex_status="$(cd "$TEST_CODEX_WS" && ./rnex status 2>&1)"
echo "$_codex_status" | grep -q "CODEX.md" || { fail "Status did not report CODEX.md: $_codex_status"; exit 1; }
echo "$_codex_status" | grep -q "\.codex/skills/" || { fail "Status did not report .codex/skills/: $_codex_status"; exit 1; }
echo "$_codex_status" | grep "codex" -A 2 | grep -q "Options: skills=" || { fail "Status did not report codex plugin options: $_codex_status"; exit 1; }

# 5. Plugin info inspection
_codex_pinfo="$(cd "$TEST_CODEX_WS" && ./rnex plugin info codex 2>&1)"
echo "$_codex_pinfo" | grep -q "OpenAI Codex" || { fail "Plugin info missing title/summary: $_codex_pinfo"; exit 1; }
echo "$_codex_pinfo" | grep -q "Configurable Options" || { fail "Plugin info missing configurable options: $_codex_pinfo"; exit 1; }
echo "$_codex_pinfo" | grep -q "\.codex/skills/" || { fail "Plugin info missing .codex/skills/ reference: $_codex_pinfo"; exit 1; }

# 6. Preserve custom developer rules & skills across sync
printf "\n# Custom Codex Rules\n" >> "$TEST_CODEX_WS/CODEX.md"
mkdir -p "$TEST_CODEX_WS/.codex/skills/custom-skill"
echo "custom" > "$TEST_CODEX_WS/.codex/skills/custom-skill/SKILL.md"
(cd "$TEST_CODEX_WS" && ./rnex sync -y --quiet >/dev/null)
grep -q "# Custom Codex Rules" "$TEST_CODEX_WS/CODEX.md" || { fail "Custom section lost in CODEX.md after sync"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_CODEX_WS/CODEX.md" || { fail "REPO-NEXUS block missing after sync"; exit 1; }
[ -f "$TEST_CODEX_WS/.codex/skills/custom-skill/SKILL.md" ] || { fail "Custom user skill lost after sync"; exit 1; }

# 7. Disable codex plugin, verify cleanup & AGENTS.md restoration
(cd "$TEST_CODEX_WS" && ./rnex plugin disable codex >/dev/null)
(cd "$TEST_CODEX_WS" && ./rnex sync -y --quiet >/dev/null)
[ -f "$TEST_CODEX_WS/AGENTS.md" ] || { fail "AGENTS.md not restored when codex disabled"; exit 1; }
grep -q "REPO-NEXUS:START" "$TEST_CODEX_WS/AGENTS.md" || { fail "AGENTS.md missing REPO-NEXUS block when codex disabled"; exit 1; }
[ -f "$TEST_CODEX_WS/CODEX.md" ] || { fail "CODEX.md was deleted when codex disabled"; exit 1; }
! grep -q "REPO-NEXUS:START" "$TEST_CODEX_WS/CODEX.md" || { fail "REPO-NEXUS block not removed from CODEX.md after disable"; exit 1; }
grep -q "# Custom Codex Rules" "$TEST_CODEX_WS/CODEX.md" || { fail "Custom rules lost from CODEX.md after disable"; exit 1; }
[ ! -d "$TEST_CODEX_WS/.codex/skills/rnex-clone-sync" ] || { fail "rnex User Skills not cleaned from .codex/skills"; exit 1; }
[ -f "$TEST_CODEX_WS/.codex/skills/custom-skill/SKILL.md" ] || { fail "Custom skill deleted when codex disabled"; exit 1; }
! grep -q "OpenAI Codex Integration for Repo Nexus" "$TEST_CODEX_WS/.rnex/ai-instructions.md" || { fail "Codex instructions not stripped from .rnex/ai-instructions.md after disable"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Fix 30: Member repository lazy/on-demand .rnex model and readonly: <boolean> setting"
TEST_RO_WS="$TEST_TMP/ro-lazy-ws"
mkdir -p "$TEST_RO_WS"
cp "$CLI" "$TEST_RO_WS/rnex"
chmod +x "$TEST_RO_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_RO_WS/toolkit"
cp "$DIR/package.json" "$TEST_RO_WS/package.json"
git -C "$TEST_RO_WS" init -q

"$TEST_RO_WS/rnex" init -y "$TEST_RO_WS" >/dev/null

# 1. rnex repo add clones repo cleanly without creating member .rnex/
(cd "$TEST_RO_WS" && ./rnex repo add "$TEST_REPO" --name standard-repo >/dev/null)
[ -d "$TEST_RO_WS/repos/standard-repo/.git" ] || { fail "standard-repo not cloned"; exit 1; }
[ ! -d "$TEST_RO_WS/repos/standard-repo/.rnex" ] || { fail "standard-repo has unexpected .rnex/ folder"; exit 1; }
! grep -q "rnex_dir" "$TEST_RO_WS/rnex.yaml" || { fail "rnex_dir setting unexpectedly written to rnex.yaml"; exit 1; }

# 2. rnex list shows READONLY column defaulting to false
_list_out="$(cd "$TEST_RO_WS" && ./rnex list 2>&1)"
echo "$_list_out" | grep -q "READONLY" || { fail "rnex list missing READONLY column: $_list_out"; exit 1; }
echo "$_list_out" | grep "standard-repo" | grep -q "false" || { fail "standard-repo readonly not false in list: $_list_out"; exit 1; }

# 3. rnex repo add --readonly marks repository readonly
(cd "$TEST_RO_WS" && ./rnex repo add "$TEST_REPO" --name reference-repo --readonly >/dev/null)
grep -q "readonly: true" "$TEST_RO_WS/rnex.yaml" || { fail "readonly: true not found in rnex.yaml"; exit 1; }
[ ! -d "$TEST_RO_WS/repos/reference-repo/.rnex" ] || { fail "reference-repo has unexpected .rnex/"; exit 1; }

# 4. Status and list reflect readonly status
_list_out="$(cd "$TEST_RO_WS" && ./rnex list 2>&1)"
echo "$_list_out" | grep "reference-repo" | grep -q "true" || { fail "reference-repo readonly not true in list: $_list_out"; exit 1; }
_status_out="$(cd "$TEST_RO_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep "reference-repo" | grep -q "\[readonly\]" || { fail "reference-repo missing [readonly] in status: $_status_out"; exit 1; }

# 5. rnex repo set readonly toggle commands (global and local)
(cd "$TEST_RO_WS" && ./rnex repo set reference-repo --readwrite --global >/dev/null)
grep -q "readonly: false" "$TEST_RO_WS/rnex.yaml" || { fail "readonly: false not updated in rnex.yaml"; exit 1; }

(cd "$TEST_RO_WS" && ./rnex repo set standard-repo --readonly --local >/dev/null)
[ -f "$TEST_RO_WS/.local.rnex.yaml" ] || { fail ".local.rnex.yaml missing"; exit 1; }
grep -q "readonly: true" "$TEST_RO_WS/.local.rnex.yaml" || { fail "readonly: true not in .local.rnex.yaml"; exit 1; }

# 6. Verify AI instructions mention readonly rules
[ -f "$TEST_RO_WS/.rnex/ai-instructions.md" ] || { fail ".rnex/ai-instructions.md missing"; exit 1; }
grep -q "READ-ONLY" "$TEST_RO_WS/.rnex/ai-instructions.md" || { fail "readonly directive missing from compiled AI instructions"; exit 1; }

# 7. Lazy on-demand .rnex behavior:
# - If user or plugin creates a custom file in member .rnex/, it is preserved
mkdir -p "$TEST_RO_WS/repos/standard-repo/.rnex"
echo "custom member context" > "$TEST_RO_WS/repos/standard-repo/.rnex/custom.txt"
(cd "$TEST_RO_WS" && ./rnex sync -y --quiet >/dev/null)
[ -f "$TEST_RO_WS/repos/standard-repo/.rnex/custom.txt" ] || { fail "custom member .rnex file deleted during sync"; exit 1; }

# - If member repo only has boilerplate README, rnex sync prunes it
mkdir -p "$TEST_RO_WS/repos/reference-repo/.rnex"
cat <<'EOF_BOILERPLATE' > "$TEST_RO_WS/repos/reference-repo/.rnex/README.md"
# .rnex — Repo Nexus Workspace Integration
Repo Nexus Workspace Integration boilerplate
EOF_BOILERPLATE
(cd "$TEST_RO_WS" && ./rnex sync -y --quiet >/dev/null)
[ ! -d "$TEST_RO_WS/repos/reference-repo/.rnex" ] || { fail "boilerplate .rnex was not pruned by sync"; exit 1; }

pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
