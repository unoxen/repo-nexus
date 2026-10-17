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
(cd "$TEST_GOAL_WS" && ./rnex add repo-exec "$TEST_REPO" >/dev/null)
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
sed -e '/copilot:/,/skills:/ s/instructions: true/enabled: false/' "$TEST_GOAL_WS/rnex.yaml" > "$TEST_GOAL_WS/rnex.yaml.tmp"
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
(cd "$TEST_GOAL_WS" && ./rnex add commented-repo "$TEST_REPO" >/dev/null)
# Add inline comment to repo header line in rnex.yaml
sed -e 's/^  commented-repo:[ ]*$/  commented-repo: # inline comment for test/' "$TEST_GOAL_WS/rnex.yaml" > "$TEST_GOAL_WS/rnex.yaml.tmp"
mv "$TEST_GOAL_WS/rnex.yaml.tmp" "$TEST_GOAL_WS/rnex.yaml"
grep -q "commented-repo: # inline comment" "$TEST_GOAL_WS/rnex.yaml" || { fail "Failed to prepare inline comment in rnex.yaml"; exit 1; }

(cd "$TEST_GOAL_WS" && ./rnex remove commented-repo -y >/dev/null)
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
# 8a: cmd_remove parses flags properly (-y before or after name)
(cd "$TEST_GOAL_WS" && ./rnex add remove-flag-repo "$TEST_REPO" >/dev/null)
(cd "$TEST_GOAL_WS" && ./rnex remove -y remove-flag-repo >/dev/null)
[ ! -d "$TEST_GOAL_WS/repos/remove-flag-repo" ] || { fail "remove -y <name> failed to delete repo directory"; exit 1; }
! grep -q "remove-flag-repo" "$TEST_GOAL_WS/rnex.yaml" || { fail "remove -y <name> failed to unregister repo from rnex.yaml"; exit 1; }

# 8b: cmd_rnex_dir supports --local
(cd "$TEST_GOAL_WS" && ./rnex add rnexdir-test "$TEST_REPO" >/dev/null)
(cd "$TEST_GOAL_WS" && ./rnex rnex-dir disable rnexdir-test --local >/dev/null)
[ -f "$TEST_GOAL_WS/.local.rnex.yaml" ] || { fail ".local.rnex.yaml not created by rnex-dir --local"; exit 1; }
grep -q "rnex_dir: false" "$TEST_GOAL_WS/.local.rnex.yaml" || { fail "rnex_dir: false not set in .local.rnex.yaml"; exit 1; }

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

# 8d: completion.sh includes rnex-dir in zsh and fish
_zsh_out="$("$TEST_GOAL_WS/rnex" completion zsh)"
echo "$_zsh_out" | grep -q "rnex-dir" || { fail "zsh completion missing rnex-dir"; exit 1; }
_fish_out="$("$TEST_GOAL_WS/rnex" completion fish)"
echo "$_fish_out" | grep -q "rnex-dir" || { fail "fish completion missing rnex-dir"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 9: Incomplete copilot plugin CLI integration"
# 9a: status displays copilot instructions and options
_status_out="$(cd "$TEST_GOAL_WS" && ./rnex status 2>&1)"
echo "$_status_out" | grep -q ".github/copilot-instructions.md" || { fail "status did not check .github/copilot-instructions.md: $_status_out"; exit 1; }
echo "$_status_out" | grep "copilot" -A 2 | grep -q "Options: instructions=" || { fail "status did not display copilot options: $_status_out"; exit 1; }

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
[ -f "$TEST_CFG_EXT_WS/.rnex/.sync_stamp" ] || { fail "sync stamp missing after init"; exit 1; }

# Modify rnex.yaml in TEST_CFG_EXT_WS
printf "\n# modified config\n" >> "$TEST_CFG_EXT_WS/rnex.yaml"

# Run rnex with -c from outside directory (TEST_OUTSIDE)
mkdir -p "$TEST_OUTSIDE"
cd "$TEST_OUTSIDE"
_outside_out="$("$TEST_CFG_EXT_WS/rnex" -c "$TEST_CFG_EXT_WS/rnex.yaml" list 2>&1)"
cd "$DIR"

# Verify the stamp in TEST_CFG_EXT_WS was updated to match the new config sum
_new_sum="$(cd "$TEST_CFG_EXT_WS" && cksum rnex.yaml .local.rnex.yaml 2>/dev/null | cksum | awk '{print $1, $2}')"
_stamp_val="$(cat "$TEST_CFG_EXT_WS/.rnex/.sync_stamp" 2>/dev/null)"
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
cat <<'EOF_HOT_INIT' >> "$TEST_CONDENSE_WS/.rnex/wiki/hot.md"

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
_wc1="$(wc -w < "$TEST_CONDENSE_WS/.rnex/wiki/hot.md")"
[ "$_wc1" -le 500 ] || { fail "hot.md word count ($_wc1) exceeded 500 words on sync 1"; exit 1; }
_sum_cnt1="$(grep -c "Member Repositories" "$TEST_CONDENSE_WS/.rnex/wiki/hot.md" || true)"
[ "$_sum_cnt1" -eq 1 ] || { fail "Expected 1 summary line on sync 1, found $_sum_cnt1"; exit 1; }
grep -q "Member Repositories (15 repos):" "$TEST_CONDENSE_WS/.rnex/wiki/hot.md" || { fail "Missing condensed summary line on sync 1"; exit 1; }
! grep -q "\* \*\*repo-1 (" "$TEST_CONDENSE_WS/.rnex/wiki/hot.md" || { fail "Individual repo entry not condensed on sync 1"; exit 1; }

# Sync 2: Verify idempotency - no re-insertion of individual lines or duplicate summary lines
(cd "$TEST_CONDENSE_WS" && ./rnex sync -y >/dev/null)
_wc2="$(wc -w < "$TEST_CONDENSE_WS/.rnex/wiki/hot.md")"
[ "$_wc2" -le 500 ] || { fail "hot.md word count ($_wc2) exceeded 500 words on sync 2"; exit 1; }
_sum_cnt2="$(grep -c "Member Repositories" "$TEST_CONDENSE_WS/.rnex/wiki/hot.md" || true)"
[ "$_sum_cnt2" -eq 1 ] || { fail "Duplicate summary lines generated on sync 2: count $_sum_cnt2"; exit 1; }

# Sync 3: Additional sync check
(cd "$TEST_CONDENSE_WS" && ./rnex sync -y >/dev/null)
_sum_cnt3="$(grep -c "Member Repositories" "$TEST_CONDENSE_WS/.rnex/wiki/hot.md" || true)"
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

[ -f "$TEST_CURATED_WS/.rnex/wiki/repo-auth-svc.md" ] || { fail "repo-auth-svc.md not generated"; exit 1; }

# User / Agent curates repo-auth-svc.md
cat <<'EOF_PAGE' > "$TEST_CURATED_WS/.rnex/wiki/repo-auth-svc.md"
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
grep -q 'title: "Member Repo: auth-svc (Curated)"' "$TEST_CURATED_WS/.rnex/wiki/repo-auth-svc.md" || { fail "Curated title was overwritten"; exit 1; }
grep -q 'related: \["repo-billing\.md"\]' "$TEST_CURATED_WS/.rnex/wiki/repo-auth-svc.md" || { fail "Curated related links were overwritten"; exit 1; }
grep -q 'extends: \["specs/oauth2\.md"\]' "$TEST_CURATED_WS/.rnex/wiki/repo-auth-svc.md" || { fail "Curated extends links were overwritten"; exit 1; }
grep -q 'mentioned_in: \["architecture-overview\.md"\]' "$TEST_CURATED_WS/.rnex/wiki/repo-auth-svc.md" || { fail "Curated mentioned_in links were overwritten"; exit 1; }
grep -q "Curated Invariant" "$TEST_CURATED_WS/.rnex/wiki/repo-auth-svc.md" || { fail "Curated notes body was overwritten"; exit 1; }

# Verify _log.md has only 1 entry for auth-svc ingest (no duplicate audit entries)
_log_cnt="$(grep -c "Member Repo Ingest: auth-svc" "$TEST_CURATED_WS/.rnex/wiki/_log.md" || true)"
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

# Verify default wiki_dir .rnex/wiki used, NOT leaked/claude/wiki
[ -d "$TEST_CFG_ISOLATION_WS/.rnex/wiki" ] || { fail "Default .rnex/wiki not created"; exit 1; }
[ ! -d "$TEST_CFG_ISOLATION_WS/leaked" ] || { fail "Sibling plugin claude keys leaked into karpathy-llm"; exit 1; }

# Verify declared repo ingested
[ -f "$TEST_CFG_ISOLATION_WS/.rnex/wiki/repo-declared-repo.md" ] || { fail "repo-declared-repo.md not ingested"; exit 1; }

# Verify custom path repo ingested with correct sources path
[ -f "$TEST_CFG_ISOLATION_WS/.rnex/wiki/repo-custom-path-repo.md" ] || { fail "repo-custom-path-repo.md not ingested"; exit 1; }
grep -q 'sources: \["nested/custom-repo-dir/README.md"\]' "$TEST_CFG_ISOLATION_WS/.rnex/wiki/repo-custom-path-repo.md" || { fail "sources path incorrect for custom path repo"; exit 1; }

# Verify untracked stray directory ignored
[ ! -f "$TEST_CFG_ISOLATION_WS/.rnex/wiki/repo-untracked-stray.md" ] || { fail "Untracked stray folder was ingested into wiki"; exit 1; }

# 14c: git_post-commit.sh initial root commit detection with --root
TEST_GIT_ROOT_WS="$TEST_TMP/git-root-ws"
mkdir -p "$TEST_GIT_ROOT_WS/docs"
git -C "$TEST_GIT_ROOT_WS" init -q
git -C "$TEST_GIT_ROOT_WS" config user.email "test@example.com"
git -C "$TEST_GIT_ROOT_WS" config user.name "Test Runner"
printf '# Initial Intake\nNotes for test.\n' > "$TEST_GIT_ROOT_WS/docs/initial.md"
git -C "$TEST_GIT_ROOT_WS" add docs/initial.md
git -C "$TEST_GIT_ROOT_WS" commit -qm "Root initial commit"

cat <<'EOF_LCL' > "$TEST_GIT_ROOT_WS/.local.rnex.yaml"
plugins:
  karpathy-llm:
    lint_trigger: git-post-commit
    notify_on_changes: true
EOF_LCL

_hook_root_out="$(RNEX_ROOT="$TEST_GIT_ROOT_WS" "$DIR/toolkit/plugins/karpathy-llm/hooks/git_post-commit.sh" 2>&1)"
echo "$_hook_root_out" | grep -q "\[WIKI\] Changes committed to docs/ or \.rnex/wiki/\." || { fail "git_post-commit.sh failed to detect changes in root commit: $_hook_root_out"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Fix 15: README.md documentation accuracy and ingest_member_readmes toggle"
# 15a: README documentation check
_readme_file="$DIR/toolkit/plugins/karpathy-llm/README.md"
[ -f "$_readme_file" ] || { fail "README.md missing"; exit 1; }
grep -q "ingest_member_readmes" "$_readme_file" || { fail "README.md does not document ingest_member_readmes"; exit 1; }
! grep -q "auto_index" "$_readme_file" || { fail "README.md still mentions auto_index"; exit 1; }
! grep -q "run_deterministic_checks" "$_readme_file" || { fail "README.md still mentions run_deterministic_checks"; exit 1; }
! grep -q "ai_cmd" "$_readme_file" || { fail "README.md still mentions ai_cmd"; exit 1; }

# 15b: ingest_member_readmes: false toggle
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
    ingest_member_readmes: false
repos:
  skipped-repo: {}
EOF_TOG

(cd "$TEST_TOGGLE_WS" && ./rnex sync -y >/dev/null)
[ ! -f "$TEST_TOGGLE_WS/.rnex/wiki/repo-skipped-repo.md" ] || { fail "repo-skipped-repo.md was generated despite ingest_member_readmes: false"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
