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

# 1. Verify all 5 plugins are available
_list_out="$(cd "$TEST_DET_WS" && ./rnex plugin list 2>&1)"
for _p in claude cursor gemini karpathy-llm windsurf; do
  echo "$_list_out" | grep -q "$_p" || { fail "Plugin $_p not in plugin list"; exit 1; }
  if [ "$_p" = "karpathy-llm" ]; then
    echo "$_list_out" | grep "$_p" | grep -E -q "\(v(0\.5\.1|1\.0\.0)\)" || { fail "Plugin $_p version unexpected"; exit 1; }
  else
    echo "$_list_out" | grep "$_p" | grep -q "(v0.5.1)" || { fail "Plugin $_p is not v0.5.1"; exit 1; }
  fi
done

# 2. Test 'rnex plugin install <name>' alias for enable
(cd "$TEST_DET_WS" && ./rnex plugin install claude >/dev/null)
[ -d "$TEST_DET_WS/.rnex/plugins/claude" ] || { fail "Plugin install did not create .rnex/plugins/claude"; exit 1; }
[ -f "$TEST_DET_WS/.rnex/plugins/claude/instructions/rnex-claude-integration.md" ] || { fail "rnex-claude-integration.md missing"; exit 1; }

# 3. Test deterministic update: inject a stale file into the installed plugin
touch "$TEST_DET_WS/.rnex/plugins/claude/instructions/stale-artifact.md"
[ -f "$TEST_DET_WS/.rnex/plugins/claude/instructions/stale-artifact.md" ] || { fail "Failed to create test stale file"; exit 1; }

# 4. Run 'rnex plugin update claude' and verify stale artifact was deterministically purged
(cd "$TEST_DET_WS" && ./rnex plugin update claude >/dev/null)
[ ! -f "$TEST_DET_WS/.rnex/plugins/claude/instructions/stale-artifact.md" ] || { fail "Stale artifact was not purged during deterministic plugin update"; exit 1; }
[ -f "$TEST_DET_WS/.rnex/plugins/claude/instructions/rnex-claude-integration.md" ] || { fail "rnex-claude-integration.md missing after update"; exit 1; }

# 5. Run global 'rnex plugin update'
(cd "$TEST_DET_WS" && ./rnex plugin update >/dev/null)
[ -f "$TEST_DET_WS/.rnex/plugins/claude/plugin.yaml" ] || { fail "plugin.yaml missing after global plugin update"; exit 1; }
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

# Verify template substitutions reflect custom paths without corruption
grep -q "intake/raw/" "$TEST_KWIKI_WS/docs/wiki/index.md" || { fail "docs/wiki/index.md does not reference custom intake/raw/"; exit 1; }
grep -q "intake/raw/" "$TEST_KWIKI_WS/docs/wiki/hot.md" || { fail "docs/wiki/hot.md does not reference custom intake/raw/"; exit 1; }
grep -q "docs/wiki/" "$TEST_KWIKI_WS/docs/wiki/hot.md" || { fail "docs/wiki/hot.md does not reference custom docs/wiki/"; exit 1; }
! grep -q "docs/docs/wiki" "$TEST_KWIKI_WS/docs/wiki/hot.md" || { fail "Corrupted duplicated path docs/docs/wiki found"; exit 1; }
! grep -q "intake/intake/raw" "$TEST_KWIKI_WS/docs/wiki/hot.md" || { fail "Corrupted duplicated path intake/intake/raw found"; exit 1; }

# Verify AGENTS.md maintains strict directive and .rnex/ai-instructions.md contains plugin instructions
_kw_agents="$(cat "$TEST_KWIKI_WS/AGENTS.md")"
echo "$_kw_agents" | grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" || { fail "AGENTS.md missing strict directive"; exit 1; }
_kw_ai_instructions="$(cat "$TEST_KWIKI_WS/.rnex/ai-instructions.md")"
echo "$_kw_ai_instructions" | grep -q "Resolved Knowledge Base" || { fail "ai-instructions.md missing Karpathy instructions"; exit 1; }
echo "$_kw_ai_instructions" | grep -q "wiki/hot.md" || { fail "ai-instructions.md missing wiki_dir guidance"; exit 1; }

# Verify plugin info reports custom options and template mappings
_kw_info="$(cd "$TEST_KWIKI_WS" && ./rnex plugin info karpathy-llm 2>&1)"
echo "$_kw_info" | grep -q "current: docs/wiki" || { fail "plugin info did not report custom wiki_dir"; exit 1; }
echo "$_kw_info" | grep -q "current: intake/raw" || { fail "plugin info did not report custom raw_dir"; exit 1; }
echo "$_kw_info" | grep -q "docs/wiki/index.md" || { fail "plugin info did not report template mapped to docs/wiki/index.md"; exit 1; }
echo "$_kw_info" | grep -q "docs/wiki/hot.md" || { fail "plugin info did not report template mapped to docs/wiki/hot.md"; exit 1; }

# Verify CLI ingest and lint work on the custom paths
git -C "$TEST_KWIKI_WS" config user.email "test@example.com"
git -C "$TEST_KWIKI_WS" config user.name "Test User"
git -C "$TEST_KWIKI_WS" add .
git -C "$TEST_KWIKI_WS" commit -qm "Initial commit"
echo "sample research" > "$TEST_KWIKI_WS/intake/raw/paper.md"
(
  cd "$TEST_KWIKI_WS"
  ./rnex plugin karpathy-llm ingest --source intake/raw/paper.md >/dev/null
  [ -f "docs/wiki/paper.md" ] || { fail "paper.md was not ingested into custom docs/wiki/"; exit 1; }
  _lint_out="$(./rnex plugin karpathy-llm lint 2>&1)"
  echo "$_lint_out" | grep -q "Wiki lint passed" || { fail "Wiki lint failed on custom wiki_dir: $_lint_out"; exit 1; }

  # Update wiki_dir to a new path (./custom-wiki) and verify rnex sync creates index.md, hot.md, _log.md
  cat <<'EOF_UPD1' > "$TEST_KWIKI_WS/rnex.yaml"
plugins:
  karpathy-llm:
    wiki_dir: ./custom-wiki
    sources:
      - intake/raw
EOF_UPD1
  ./rnex sync >/dev/null
  [ -d "custom-wiki" ] || { fail "Updated wiki_dir ./custom-wiki was not created by rnex sync"; exit 1; }
  [ -f "custom-wiki/index.md" ] || { fail "custom-wiki/index.md missing after updating wiki_dir"; exit 1; }
  [ -f "custom-wiki/hot.md" ] || { fail "custom-wiki/hot.md missing after updating wiki_dir"; exit 1; }
  [ -f "custom-wiki/_log.md" ] || { fail "custom-wiki/_log.md missing after updating wiki_dir"; exit 1; }

  # Update wiki_dir to ./wiki (with leading ./) and verify rnex sync creates/preserves wiki/index.md, hot.md, _log.md
  cat <<'EOF_UPD2' > "$TEST_KWIKI_WS/rnex.yaml"
plugins:
  karpathy-llm:
    wiki_dir: ./wiki
    sources:
      - intake/raw
EOF_UPD2
  ./rnex sync >/dev/null
  [ -d "wiki" ] || { fail "wiki/ directory missing when wiki_dir is ./wiki"; exit 1; }
  [ -f "wiki/index.md" ] || { fail "wiki/index.md missing when wiki_dir is ./wiki"; exit 1; }
  [ -f "wiki/hot.md" ] || { fail "wiki/hot.md missing when wiki_dir is ./wiki"; exit 1; }
  [ -f "wiki/_log.md" ] || { fail "wiki/_log.md missing when wiki_dir is ./wiki"; exit 1; }
)
pass

# --------------------------------------------------------------------------
run_test "Disabling plugin in rnex.yaml followed by rnex sync cleanly removes instructions, assets, and User Skills"
# 1. Enable claude with skills: true so we can verify provider User Skills cleanup
cat <<'EOF_CFG2' > "$TEST_KWIKI_WS/rnex.yaml"
plugins:
  claude:
    skills: true
  karpathy-llm:
    wiki_dir: docs/wiki
    raw_dir: intake/raw
EOF_CFG2

(cd "$TEST_KWIKI_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_KWIKI_WS/.claude/skills/rnex-karpathy-llm-wiki-ingest/SKILL.md" ] || { fail "Plugin User Skill rnex-karpathy-llm-wiki-ingest was not generated in claude"; exit 1; }
[ -f "$TEST_KWIKI_WS/.claude/skills/rnex-karpathy-llm-wiki-lint/SKILL.md" ] || { fail "Plugin User Skill rnex-karpathy-llm-wiki-lint was not generated in claude"; exit 1; }
[ ! -d "$TEST_KWIKI_WS/.claude/skills/rnex-wiki-ingest" ] || { fail "Stale unprefixed rnex-wiki-ingest was generated in claude"; exit 1; }
[ ! -d "$TEST_KWIKI_WS/.claude/skills/rnex-wiki-lint" ] || { fail "Stale unprefixed rnex-wiki-lint was generated in claude"; exit 1; }
[ -f "$TEST_KWIKI_WS/.claude/skills/rnex-clone-sync/SKILL.md" ] || { fail "Core User Skill rnex-clone-sync missing in claude"; exit 1; }
[ -d "$TEST_KWIKI_WS/.rnex/plugins/karpathy-llm" ] || { fail ".rnex/plugins/karpathy-llm missing while enabled"; exit 1; }
_kw_active_ai="$(cat "$TEST_KWIKI_WS/.rnex/ai-instructions.md")"
echo "$_kw_active_ai" | grep -q "Resolved Knowledge Base" || { fail "Active ai-instructions.md missing Karpathy instructions"; exit 1; }

# 2. Disable karpathy-llm via enabled: false in rnex.yaml
cat <<'EOF_CFG3' > "$TEST_KWIKI_WS/rnex.yaml"
plugins:
  claude:
    skills: true
  karpathy-llm:
    enabled: false
    wiki_dir: docs/wiki
    raw_dir: intake/raw
EOF_CFG3

# 3. Run rnex sync
(cd "$TEST_KWIKI_WS" && ./rnex sync -y >/dev/null)

# 4. Verify .rnex/ai-instructions.md no longer contains wiki instructions and CLAUDE.md retains single directive
_kw_disabled_ai="$(cat "$TEST_KWIKI_WS/.rnex/ai-instructions.md")"
! echo "$_kw_disabled_ai" | grep -q "Resolved Knowledge Base" || { fail "ai-instructions.md still contains wiki instructions after disabling plugin"; exit 1; }
echo "$_kw_disabled_ai" | grep -q "NO CONFIG READS" || { fail "ai-instructions.md missing NO CONFIG READS"; exit 1; }

[ ! -f "$TEST_KWIKI_WS/AGENTS.md" ] || { fail "AGENTS.md should not be present when claude plugin is enabled"; exit 1; }
_kw_disabled_claude="$(cat "$TEST_KWIKI_WS/CLAUDE.md")"
echo "$_kw_disabled_claude" | grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" || { fail "CLAUDE.md missing strict directive"; exit 1; }

# 5. Verify provider User Skills from disabled plugin were removed, but core skills kept
[ ! -d "$TEST_KWIKI_WS/.claude/skills/rnex-karpathy-llm-wiki-ingest" ] || { fail "rnex-karpathy-llm-wiki-ingest still present after disabling plugin"; exit 1; }
[ ! -d "$TEST_KWIKI_WS/.claude/skills/rnex-karpathy-llm-wiki-lint" ] || { fail "rnex-karpathy-llm-wiki-lint still present after disabling plugin"; exit 1; }
[ ! -d "$TEST_KWIKI_WS/.claude/skills/rnex-wiki-ingest" ] || { fail "rnex-wiki-ingest still present after disabling plugin"; exit 1; }
[ ! -d "$TEST_KWIKI_WS/.claude/skills/rnex-wiki-lint" ] || { fail "rnex-wiki-lint still present after disabling plugin"; exit 1; }
[ -f "$TEST_KWIKI_WS/.claude/skills/rnex-clone-sync/SKILL.md" ] || { fail "Core User Skill rnex-clone-sync was incorrectly removed"; exit 1; }

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

# --------------------------------------------------------------------------
run_test "Karpathy LLM plugin config default wiki_dir: wiki and after_sync hook syncing raw_dir and member repository READMEs"
TEST_HOOK_WS="$TEST_TMP/karpathy-hook-sync-ws"
mkdir -p "$TEST_HOOK_WS"
cp "$CLI" "$TEST_HOOK_WS/rnex"
chmod +x "$TEST_HOOK_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_HOOK_WS/toolkit"
cp "$DIR/package.json" "$TEST_HOOK_WS/package.json"
git -C "$TEST_HOOK_WS" init -q

"$TEST_HOOK_WS/rnex" init -y "$TEST_HOOK_WS" >/dev/null

# 1. Enable karpathy-llm and assert wiki_dir defaults to wiki while lint_trigger is absent
(cd "$TEST_HOOK_WS" && ./rnex plugin enable karpathy-llm >/dev/null)
_pinfo="$(cd "$TEST_HOOK_WS" && ./rnex plugin info karpathy-llm 2>&1)"
echo "$_pinfo" | grep "wiki_dir:" | grep -q "current: wiki" || { fail "Plugin info did not report default wiki_dir as wiki: $_pinfo"; exit 1; }
! echo "$_pinfo" | grep -q "lint_trigger:" || { fail "Plugin info still reports removed lint_trigger: $_pinfo"; exit 1; }
! echo "$_pinfo" | grep -q "notify_on_changes:" || { fail "Plugin info still reports removed notify_on_changes: $_pinfo"; exit 1; }
! grep -q "lint_trigger" "$TEST_HOOK_WS/rnex.yaml" || { fail "rnex.yaml contains removed lint_trigger"; exit 1; }
! grep -q "notify_on_changes" "$TEST_HOOK_WS/rnex.yaml" || { fail "rnex.yaml contains removed notify_on_changes"; exit 1; }

# 2. Mock a member repository initialization (./repos/mock-member-repo/README.md)
mkdir -p "$TEST_HOOK_WS/repos/mock-member-repo"
printf '# Mock Member Repo\nThis is a mock repository README.\n' > "$TEST_HOOK_WS/repos/mock-member-repo/README.md"
printf '  mock-member-repo:\n' >> "$TEST_HOOK_WS/rnex.yaml"

# Also place a sample document in custom/default raw_dir (./docs)
mkdir -p "$TEST_HOOK_WS/docs"
printf '# Intake Note\nImportant context notes.\n' > "$TEST_HOOK_WS/docs/intake-note.md"

# 3. Invoke rnex sync to trigger after_sync hook
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)

# 4. Confirm wiki/raw staging directory is NOT created and docs/intake-note.md remains in-place
[ ! -d "$TEST_HOOK_WS/wiki/raw" ] || { fail "wiki/raw staging directory was created; should not exist"; exit 1; }
[ -f "$TEST_HOOK_WS/docs/intake-note.md" ] || { fail "docs/intake-note.md missing"; exit 1; }
grep -q "Intake Note" "$TEST_HOOK_WS/docs/intake-note.md" || { fail "Content mismatch in docs/intake-note.md"; exit 1; }

# 5a. Verify user-created files in wiki/raw are strictly preserved, while duplicate staging is removed
mkdir -p "$TEST_HOOK_WS/wiki/raw"
printf '# Custom User Draft\nDo not delete this uncommitted content!\n' > "$TEST_HOOK_WS/wiki/raw/user-draft.md"
_sync_preserve_out="$(cd "$TEST_HOOK_WS" && ./rnex sync -y 2>&1)"
[ -f "$TEST_HOOK_WS/wiki/raw/user-draft.md" ] || { fail "Custom user file in wiki/raw was deleted by rnex sync"; exit 1; }
echo "$_sync_preserve_out" | grep -q "Warning: wiki/raw contains custom or uncommitted files" || { fail "Missing preservation warning for wiki/raw: $_sync_preserve_out"; exit 1; }

# Replace custom file with duplicate staging file matching docs/intake-note.md
rm -f "$TEST_HOOK_WS/wiki/raw/user-draft.md"
cp "$TEST_HOOK_WS/docs/intake-note.md" "$TEST_HOOK_WS/wiki/raw/intake-note.md"
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)
[ ! -d "$TEST_HOOK_WS/wiki/raw" ] || { fail "Managed duplicate staging wiki/raw was not cleaned up"; exit 1; }

# 5b. Confirm member repository README ingested into atomic wiki page
[ -f "$TEST_HOOK_WS/wiki/repo-mock-member-repo.md" ] || { fail "repo-mock-member-repo.md missing after wiki ingest"; exit 1; }
grep -q 'title: "Member Repo: mock-member-repo"' "$TEST_HOOK_WS/wiki/repo-mock-member-repo.md" || { fail "Frontmatter title missing in repo-mock-member-repo.md"; exit 1; }
grep -q 'tags: \[member-repo, mock-member-repo\]' "$TEST_HOOK_WS/wiki/repo-mock-member-repo.md" || { fail "Frontmatter tags missing in repo-mock-member-repo.md"; exit 1; }
grep -q 'sources: \["repos/mock-member-repo/README.md"\]' "$TEST_HOOK_WS/wiki/repo-mock-member-repo.md" || { fail "Frontmatter sources missing in repo-mock-member-repo.md"; exit 1; }
grep -q "This is a mock repository README." "$TEST_HOOK_WS/wiki/repo-mock-member-repo.md" || { fail "Summary missing in repo-mock-member-repo.md"; exit 1; }
! grep -q "member-repositories.md" "$TEST_HOOK_WS/wiki/repo-mock-member-repo.md" || { fail "Missing navigation page member-repositories.md was referenced"; exit 1; }
grep -q "See \[Wiki Index\](\./index.md)" "$TEST_HOOK_WS/wiki/repo-mock-member-repo.md" || { fail "Did not reference real navigation index.md"; exit 1; }

# 5c. Confirm registration in navigation index (index.md)
[ -f "$TEST_HOOK_WS/wiki/index.md" ] || { fail "wiki/index.md missing"; exit 1; }
grep -q "repo-mock-member-repo\.md" "$TEST_HOOK_WS/wiki/index.md" || { fail "repo-mock-member-repo.md not indexed in index.md"; exit 1; }
grep -q "Member Repo: mock-member-repo" "$TEST_HOOK_WS/wiki/index.md" || { fail "Member repo title not in index.md"; exit 1; }

# 5d. Confirm registration in hot cache (hot.md)
[ -f "$TEST_HOOK_WS/wiki/hot.md" ] || { fail "wiki/hot.md missing"; exit 1; }
grep -q "mock-member-repo" "$TEST_HOOK_WS/wiki/hot.md" || { fail "mock-member-repo missing from hot.md"; exit 1; }
grep -q "repos/mock-member-repo/" "$TEST_HOOK_WS/wiki/hot.md" || { fail "repos/mock-member-repo/ missing from hot.md"; exit 1; }

# 5e. Confirm operation log entry (_log.md)
[ -f "$TEST_HOOK_WS/wiki/_log.md" ] || { fail "wiki/_log.md missing"; exit 1; }
grep -q "Member Repo Ingest: mock-member-repo" "$TEST_HOOK_WS/wiki/_log.md" || { fail "Ingest log missing from _log.md"; exit 1; }

# 6. Verify disabled member repo READMEs are not synced
mkdir -p "$TEST_HOOK_WS/repos/disabled-member-repo"
printf '# Disabled Repo\n' > "$TEST_HOOK_WS/repos/disabled-member-repo/README.md"
cat <<'EOF_DIS' >> "$TEST_HOOK_WS/rnex.yaml"
repos:
  disabled-member-repo:
    enabled: false
EOF_DIS
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)
[ ! -d "$TEST_HOOK_WS/wiki/raw" ] || { fail "wiki/raw staging directory exists"; exit 1; }
[ ! -f "$TEST_HOOK_WS/wiki/repo-disabled-member-repo.md" ] || { fail "Disabled repository should not be ingested into wiki"; exit 1; }

# 7. Verify an adjacent enabled repository is NOT affected by the disabled repository entry
mkdir -p "$TEST_HOOK_WS/repos/adjacent-enabled-repo"
printf '# Adjacent Enabled Repo\n' > "$TEST_HOOK_WS/repos/adjacent-enabled-repo/README.md"
cat <<'EOF_ADJ' >> "$TEST_HOOK_WS/rnex.yaml"
  adjacent-enabled-repo:
    url: ./repos/adjacent-enabled-repo
EOF_ADJ
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_HOOK_WS/wiki/repo-adjacent-enabled-repo.md" ] || { fail "Adjacent enabled repository was not ingested into wiki"; exit 1; }
grep -q "Adjacent Enabled Repo" "$TEST_HOOK_WS/wiki/repo-adjacent-enabled-repo.md" || { fail "Content mismatch in adjacent enabled repo wiki page"; exit 1; }
[ ! -d "$TEST_HOOK_WS/wiki/raw" ] || { fail "wiki/raw staging directory was created during sync"; exit 1; }

# 8. Verify before_sync plugin lifecycle hook execution
mkdir -p "$TEST_HOOK_WS/.rnex/plugins/karpathy-llm/hooks"
cat <<'EOF_BS' > "$TEST_HOOK_WS/.rnex/plugins/karpathy-llm/hooks/before_sync.sh"
#!/bin/sh
printf 'BEFORE_SYNC_FIRED' > "$RNEX_ROOT/before_sync_marker"
EOF_BS
chmod +x "$TEST_HOOK_WS/.rnex/plugins/karpathy-llm/hooks/before_sync.sh"
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_HOOK_WS/before_sync_marker" ] || { fail "before_sync lifecycle hook was not executed by rnex sync"; exit 1; }
grep -q "BEFORE_SYNC_FIRED" "$TEST_HOOK_WS/before_sync_marker" || { fail "before_sync marker content mismatch"; exit 1; }

# 9. Verify rnex init with karpathy plugin performs wiki ingest for member repos
TEST_INIT_KW_WS="$TEST_TMP/karpathy-init-ingest-ws"
mkdir -p "$TEST_INIT_KW_WS/repos/seed-repo"
printf '# Seed Repo\nSeed repository description.\n' > "$TEST_INIT_KW_WS/repos/seed-repo/README.md"
cp "$CLI" "$TEST_INIT_KW_WS/rnex"
chmod +x "$TEST_INIT_KW_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_INIT_KW_WS/toolkit"
cp "$DIR/package.json" "$TEST_INIT_KW_WS/package.json"
git -C "$TEST_INIT_KW_WS" init -q

"$TEST_INIT_KW_WS/rnex" init -y --karpathy "$TEST_INIT_KW_WS" >/dev/null
[ -f "$TEST_INIT_KW_WS/wiki/repo-seed-repo.md" ] || { fail "seed-repo was not ingested during rnex init with karpathy plugin"; exit 1; }
grep -q "Seed Repo" "$TEST_INIT_KW_WS/wiki/repo-seed-repo.md" || { fail "seed-repo content mismatch after init ingest"; exit 1; }
grep -q "repo-seed-repo\.md" "$TEST_INIT_KW_WS/wiki/index.md" || { fail "seed-repo not registered in index.md after init"; exit 1; }
grep -q "seed-repo" "$TEST_INIT_KW_WS/wiki/hot.md" || { fail "seed-repo not registered in hot.md after init"; exit 1; }

# 10. Verify rnex repo add with karpathy plugin performs wiki ingest for newly added member repo
mkdir -p "$TEST_HOOK_WS/external/added-repo"
git -C "$TEST_HOOK_WS/external/added-repo" init -q
printf '# Added Member Repo\nNewly added member repository via rnex repo add.\n' > "$TEST_HOOK_WS/external/added-repo/README.md"
git -C "$TEST_HOOK_WS/external/added-repo" config user.email "test@example.com"
git -C "$TEST_HOOK_WS/external/added-repo" config user.name "Test User"
git -C "$TEST_HOOK_WS/external/added-repo" add README.md
git -C "$TEST_HOOK_WS/external/added-repo" commit -qm "Initial commit"

(cd "$TEST_HOOK_WS" && ./rnex repo add "$TEST_HOOK_WS/external/added-repo" --name added-repo >/dev/null)
[ -f "$TEST_HOOK_WS/wiki/repo-added-repo.md" ] || { fail "added-repo was not ingested during rnex repo add with karpathy plugin"; exit 1; }
grep -q "Added Member Repo" "$TEST_HOOK_WS/wiki/repo-added-repo.md" || { fail "added-repo content mismatch in wiki page"; exit 1; }
grep -q "repo-added-repo\.md" "$TEST_HOOK_WS/wiki/index.md" || { fail "added-repo not registered in index.md"; exit 1; }
grep -q "added-repo" "$TEST_HOOK_WS/wiki/hot.md" || { fail "added-repo not registered in hot.md"; exit 1; }
grep -q "Member Repo Ingest: added-repo" "$TEST_HOOK_WS/wiki/_log.md" || { fail "added-repo not logged in _log.md"; exit 1; }

# 11. Verify scaling across 15 member repositories strictly preserves the ~500-word ceiling on hot.md
for _i in $(seq 1 14); do
  mkdir -p "$TEST_HOOK_WS/repos/repo-$_i"
  printf '# Repository %s\nAutonomous microservice %s responsible for dedicated business domain tasks.\n' "$_i" "$_i" > "$TEST_HOOK_WS/repos/repo-$_i/README.md"
  printf '  repo-%s:\n' "$_i" >> "$TEST_HOOK_WS/rnex.yaml"
done
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)
_hot_wc="$(wc -w < "$TEST_HOOK_WS/wiki/hot.md")"
[ "$_hot_wc" -le 500 ] || { fail "hot.md word count ($_hot_wc) exceeded 500-word ceiling with 15 repositories"; exit 1; }

# 12. Verify rnex-wiki-page.template.md contains clean placeholders without /.rnex/.rnex
[ -f "$TEST_HOOK_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" ] || { fail "rnex-wiki-page.template.md missing in scoped plugin dir"; exit 1; }
! grep -q "/\.rnex/\.rnex" "$TEST_HOOK_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" || { fail "Corrupted /.rnex/.rnex found in rnex-wiki-page.template.md"; exit 1; }
grep -q "<wiki_dir>/" "$TEST_HOOK_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" || { fail "<wiki_dir>/ placeholder missing in rnex-wiki-page.template.md"; exit 1; }

# 13. Verify Mandatory Wiki-First Gate compiled into .rnex/ai-instructions.md and absent from AGENTS.md
grep -q "Read Wiki Hot Cache" "$TEST_HOOK_WS/.rnex/ai-instructions.md" || { fail "Read Wiki Hot Cache missing from compiled ai-instructions.md"; exit 1; }
! grep -q "Mandatory Wiki-First Access Gate" "$TEST_HOOK_WS/AGENTS.md" || { fail "AGENTS.md contains wiki instructions; should remain a single pointer"; exit 1; }

# 14. Verify rnex plugin karpathy-llm ingest and lint commands execute with options
(
  cd "$TEST_HOOK_WS"
  # Ingest with --repo option
  _ingest_repo_out="$(./rnex plugin karpathy-llm ingest --repo added-repo 2>&1)" || { fail "rnex plugin karpathy-llm ingest failed: $_ingest_repo_out"; exit 1; }
  echo "$_ingest_repo_out" | grep -q "Ingested member repository: added-repo" || { fail "Ingest output mismatch: $_ingest_repo_out"; exit 1; }

  # Ingest with --source option
  printf '# Architecture Overview\nImportant overview documentation.\n' > docs/arch-overview.md
  _ingest_src_out="$(./rnex plugin karpathy-llm ingest --source docs/arch-overview.md 2>&1)" || { fail "rnex plugin karpathy-llm ingest --source failed: $_ingest_src_out"; exit 1; }
  [ -f "wiki/arch-overview.md" ] || { fail "wiki/arch-overview.md not created by ingest --source"; exit 1; }

  # Lint command execution with --strict
  _lint_out="$(./rnex plugin karpathy-llm lint --strict 2>&1)" || { fail "rnex plugin karpathy-llm lint --strict failed: $_lint_out"; exit 1; }
  echo "$_lint_out" | grep -q "Wiki lint passed" || { fail "Lint output mismatch: $_lint_out"; exit 1; }
  grep -q "Wiki Lint Run" "wiki/_log.md" || { fail "Lint run not logged in wiki/_log.md"; exit 1; }

  # Verify lint_trigger and notify_on_changes are absent from plugin.yaml
  ! grep -q "lint_trigger" "$TEST_HOOK_WS/toolkit/plugins/karpathy-llm/plugin.yaml" || { fail "lint_trigger still present in plugin.yaml"; exit 1; }
  ! grep -q "notify_on_changes" "$TEST_HOOK_WS/toolkit/plugins/karpathy-llm/plugin.yaml" || { fail "notify_on_changes still present in plugin.yaml"; exit 1; }
)

# 15. Verify copilot integration documentation specifies .github/skills/rnex-*/SKILL.md
grep -q "\.github/skills/rnex-\*/SKILL\.md" "$DIR/toolkit/plugins/copilot/instructions/rnex-copilot-integration.md" || { fail "copilot integration missing .github/skills/rnex-*/SKILL.md"; exit 1; }

# 16. Verify scaffolding meta prompt specifies rules/behavioral.md
grep -q "rules/behavioral\.md" "$DIR/toolkit/plugins/karpathy-llm/instructions/rnex-scaffolding-meta-prompt.md" || { fail "rnex-scaffolding-meta-prompt.md missing rules/behavioral.md"; exit 1; }
! grep -q "rules/rnex-behavioral\.md" "$DIR/toolkit/plugins/karpathy-llm/instructions/rnex-scaffolding-meta-prompt.md" || { fail "rnex-scaffolding-meta-prompt.md still has stale rules/rnex-behavioral.md"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Strict separation of core skills, plugin skills, and zero-logic User Skill generator"
# 1. Assert toolkit/prompts/ and toolkit/workflows/ do not exist
[ ! -d "$DIR/toolkit/prompts" ] || { fail "toolkit/prompts/ directory still exists"; exit 1; }
[ ! -d "$DIR/toolkit/workflows" ] || { fail "toolkit/workflows/ directory still exists"; exit 1; }

# 2. Assert core skills exist exclusively in toolkit/skills/
[ -f "$DIR/toolkit/skills/clone-sync.md" ] || { fail "toolkit/skills/clone-sync.md missing"; exit 1; }
[ -f "$DIR/toolkit/skills/batch-exec.md" ] || { fail "toolkit/skills/batch-exec.md missing"; exit 1; }
[ -f "$DIR/toolkit/skills/workspace-status.md" ] || { fail "toolkit/skills/workspace-status.md missing"; exit 1; }
[ ! -f "$DIR/toolkit/skills/wiki-ingest.md" ] || { fail "Plugin skill wiki-ingest.md leaked into core toolkit/skills/"; exit 1; }
[ ! -f "$DIR/toolkit/skills/wiki-lint.md" ] || { fail "Plugin skill wiki-lint.md leaked into core toolkit/skills/"; exit 1; }

# 3. Assert plugin skills exist in toolkit/plugins/karpathy-llm/skills/
[ -f "$DIR/toolkit/plugins/karpathy-llm/skills/wiki-ingest.md" ] || { fail "toolkit/plugins/karpathy-llm/skills/wiki-ingest.md missing"; exit 1; }
[ -f "$DIR/toolkit/plugins/karpathy-llm/skills/wiki-lint.md" ] || { fail "toolkit/plugins/karpathy-llm/skills/wiki-lint.md missing"; exit 1; }

# 4. In a synced workspace with claude and karpathy-llm:
TEST_SEPARATION_WS="$TEST_TMP/skills-separation-ws"
mkdir -p "$TEST_SEPARATION_WS"
cp "$CLI" "$TEST_SEPARATION_WS/rnex"
chmod +x "$TEST_SEPARATION_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_SEPARATION_WS/toolkit"
cp "$DIR/package.json" "$TEST_SEPARATION_WS/package.json"
git -C "$TEST_SEPARATION_WS" init -q

cat <<EOF > "$TEST_SEPARATION_WS/rnex.yaml"
version: 0.6.16
repos_dir: ./repos
code_workspace: false
git_hooks: false
plugins:
  claude:
    skills: true
  karpathy-llm: {}
repos:
EOF

(cd "$TEST_SEPARATION_WS" && ./rnex sync -y >/dev/null)

# Verify core skills in .rnex/skills/
[ -f "$TEST_SEPARATION_WS/.rnex/skills/clone-sync.md" ] || { fail "clone-sync.md missing in .rnex/skills/"; exit 1; }
[ ! -f "$TEST_SEPARATION_WS/.rnex/skills/wiki-ingest.md" ] || { fail "wiki-ingest leaked into .rnex/skills/"; exit 1; }
[ ! -f "$TEST_SEPARATION_WS/.rnex/skills/wiki-lint.md" ] || { fail "wiki-lint leaked into .rnex/skills/"; exit 1; }

# Verify plugin skills in .rnex/plugins/karpathy-llm/skills/
[ -f "$TEST_SEPARATION_WS/.rnex/plugins/karpathy-llm/skills/wiki-ingest.md" ] || { fail "wiki-ingest.md missing in plugin skills/"; exit 1; }
[ -f "$TEST_SEPARATION_WS/.rnex/plugins/karpathy-llm/skills/wiki-lint.md" ] || { fail "wiki-lint.md missing in plugin skills/"; exit 1; }

# Verify User Skills generated in .claude/skills/
for _s in clone-sync batch-exec workspace-status; do
  _usk="$TEST_SEPARATION_WS/.claude/skills/rnex-${_s}/SKILL.md"
  [ -f "$_usk" ] || { fail "User skill rnex-${_s}/SKILL.md missing in .claude/skills/"; exit 1; }
  grep -q "name: rnex-${_s}" "$_usk" || { fail "User skill rnex-${_s} missing YAML frontmatter"; exit 1; }
  grep -q "CRITICAL: Do not execute inline heuristics" "$_usk" || { fail "User skill rnex-${_s} missing strict directive"; exit 1; }
  ! grep -q '```' "$_usk" || { fail "User skill rnex-${_s} contains inlined code patterns"; exit 1; }
done

for _s in wiki-ingest wiki-lint; do
  _usk="$TEST_SEPARATION_WS/.claude/skills/rnex-karpathy-llm-${_s}/SKILL.md"
  [ -f "$_usk" ] || { fail "Plugin user skill rnex-karpathy-llm-${_s}/SKILL.md missing in .claude/skills/"; exit 1; }
  grep -q "name: rnex-karpathy-llm-${_s}" "$_usk" || { fail "User skill rnex-karpathy-llm-${_s} missing YAML frontmatter"; exit 1; }
  grep -q "CRITICAL: Do not execute inline heuristics" "$_usk" || { fail "User skill rnex-karpathy-llm-${_s} missing strict directive"; exit 1; }
  ! grep -q '```' "$_usk" || { fail "User skill rnex-karpathy-llm-${_s} contains inlined code patterns"; exit 1; }
done

# Verify target paths in User Skills
grep -q "\.rnex/skills/clone-sync\.md" "$TEST_SEPARATION_WS/.claude/skills/rnex-clone-sync/SKILL.md" || { fail "rnex-clone-sync target path wrong"; exit 1; }
grep -q "\.rnex/plugins/karpathy-llm/skills/wiki-ingest\.md" "$TEST_SEPARATION_WS/.claude/skills/rnex-karpathy-llm-wiki-ingest/SKILL.md" || { fail "rnex-karpathy-llm-wiki-ingest target path wrong"; exit 1; }
grep -q "\.rnex/plugins/karpathy-llm/skills/wiki-lint\.md" "$TEST_SEPARATION_WS/.claude/skills/rnex-karpathy-llm-wiki-lint/SKILL.md" || { fail "rnex-karpathy-llm-wiki-lint target path wrong"; exit 1; }

# 5. Disable karpathy-llm via CLI command and verify unregistration
(cd "$TEST_SEPARATION_WS" && ./rnex plugin disable karpathy-llm >/dev/null)

# Plugin user skills unregistered
[ ! -d "$TEST_SEPARATION_WS/.claude/skills/rnex-karpathy-llm-wiki-ingest" ] || { fail "rnex-karpathy-llm-wiki-ingest not unregistered after plugin disable"; exit 1; }
[ ! -d "$TEST_SEPARATION_WS/.claude/skills/rnex-karpathy-llm-wiki-lint" ] || { fail "rnex-karpathy-llm-wiki-lint not unregistered after plugin disable"; exit 1; }
[ ! -d "$TEST_SEPARATION_WS/.claude/skills/rnex-wiki-ingest" ] || { fail "rnex-wiki-ingest not unregistered after plugin disable"; exit 1; }
[ ! -d "$TEST_SEPARATION_WS/.claude/skills/rnex-wiki-lint" ] || { fail "rnex-wiki-lint not unregistered after plugin disable"; exit 1; }

# Core user skills preserved
[ -f "$TEST_SEPARATION_WS/.claude/skills/rnex-clone-sync/SKILL.md" ] || { fail "rnex-clone-sync/SKILL.md deleted after disabling unrelated plugin"; exit 1; }
[ -f "$TEST_SEPARATION_WS/.claude/skills/rnex-batch-exec/SKILL.md" ] || { fail "rnex-batch-exec/SKILL.md deleted after disabling unrelated plugin"; exit 1; }
[ -f "$TEST_SEPARATION_WS/.claude/skills/rnex-workspace-status/SKILL.md" ] || { fail "rnex-workspace-status/SKILL.md deleted after disabling unrelated plugin"; exit 1; }

# 6. Verify rnex sync purges stale unprefixed user skills (rnex-wiki-*) and regenerates prefixed ones
mkdir -p "$TEST_SEPARATION_WS/.claude/skills/rnex-wiki-ingest"
touch "$TEST_SEPARATION_WS/.claude/skills/rnex-wiki-ingest/SKILL.md"
mkdir -p "$TEST_SEPARATION_WS/.claude/skills/rnex-wiki-lint"
touch "$TEST_SEPARATION_WS/.claude/skills/rnex-wiki-lint/SKILL.md"
(cd "$TEST_SEPARATION_WS" && ./rnex plugin enable karpathy-llm >/dev/null)
[ ! -d "$TEST_SEPARATION_WS/.claude/skills/rnex-wiki-ingest" ] || { fail "Stale unprefixed rnex-wiki-ingest was not purged by rnex sync"; exit 1; }
[ ! -d "$TEST_SEPARATION_WS/.claude/skills/rnex-wiki-lint" ] || { fail "Stale unprefixed rnex-wiki-lint was not purged by rnex sync"; exit 1; }
[ -f "$TEST_SEPARATION_WS/.claude/skills/rnex-karpathy-llm-wiki-ingest/SKILL.md" ] || { fail "rnex-karpathy-llm-wiki-ingest was not regenerated by rnex sync"; exit 1; }
[ -f "$TEST_SEPARATION_WS/.claude/skills/rnex-karpathy-llm-wiki-lint/SKILL.md" ] || { fail "rnex-karpathy-llm-wiki-lint was not regenerated by rnex sync"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Karpathy LLM multi-source intake: sources list, recursive glob, pruning, disabled repo filtering, two-level override, and legacy raw_dir fallback"
TEST_SOURCES_WS="$TEST_TMP/sources-intake-ws"
mkdir -p "$TEST_SOURCES_WS"
cp "$CLI" "$TEST_SOURCES_WS/rnex"
chmod +x "$TEST_SOURCES_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_SOURCES_WS/toolkit"
cp -r "$DIR/lib" "$TEST_SOURCES_WS/lib"
cp -r "$DIR/templates" "$TEST_SOURCES_WS/templates"
cp "$DIR/package.json" "$TEST_SOURCES_WS/package.json"
git -C "$TEST_SOURCES_WS" init -q

# 1. Default sources initialization on rnex init --karpathy
"$TEST_SOURCES_WS/rnex" init -y --karpathy "$TEST_SOURCES_WS" >/dev/null
grep -q "sources:" "$TEST_SOURCES_WS/rnex.yaml" || { fail "rnex.yaml missing sources after init --karpathy"; exit 1; }
grep -q -- "- docs" "$TEST_SOURCES_WS/rnex.yaml" || { fail "rnex.yaml missing - docs under sources"; exit 1; }
grep -q -- '- "repos/\*\*/README.md"' "$TEST_SOURCES_WS/rnex.yaml" || { fail "rnex.yaml missing - \"repos/**/README.md\" under sources"; exit 1; }
[ -d "$TEST_SOURCES_WS/docs" ] || { fail "Default docs directory was not created"; exit 1; }
[ -f "$TEST_SOURCES_WS/docs/.gitkeep" ] || { fail "Default docs/.gitkeep was not created"; exit 1; }
[ ! -d "$TEST_SOURCES_WS/repos/**" ] || { fail "Wildcard glob mistakenly created as directory"; exit 1; }

# 2. Recursive glob and pruning
mkdir -p "$TEST_SOURCES_WS/repos/api/pkg" "$TEST_SOURCES_WS/repos/api/node_modules/pkg" "$TEST_SOURCES_WS/repos/api/.rnex" "$TEST_SOURCES_WS/repos/api/.git" "$TEST_SOURCES_WS/repos/web"
echo "# Arch" > "$TEST_SOURCES_WS/docs/arch.md"
echo "# API" > "$TEST_SOURCES_WS/repos/api/README.md"
echo "# Pkg" > "$TEST_SOURCES_WS/repos/api/pkg/README.md"
echo "# Leaked Node" > "$TEST_SOURCES_WS/repos/api/node_modules/pkg/README.md"
echo "# Leaked Rnex" > "$TEST_SOURCES_WS/repos/api/.rnex/README.md"
echo "# Leaked Git" > "$TEST_SOURCES_WS/repos/api/.git/README.md"
echo "# Web" > "$TEST_SOURCES_WS/repos/web/README.md"

cat <<'EOF_REPOS' >> "$TEST_SOURCES_WS/rnex.yaml"
repos:
  api: {}
  web: {}
EOF_REPOS

_resolved="$(cd "$TEST_SOURCES_WS" && . "$TEST_SOURCES_WS/lib/core.sh" && . "$TEST_SOURCES_WS/lib/workspace.sh" && . "$TEST_SOURCES_WS/lib/yaml.sh" && . "$TEST_SOURCES_WS/lib/plugins.sh" && NEXUS_DIR="$TEST_SOURCES_WS" resolve_plugin_sources "$(get_plugin_config_list karpathy-llm sources)")"

echo "$_resolved" | grep -q "^docs/arch.md$" || { fail "docs/arch.md not resolved in sources: $_resolved"; exit 1; }
echo "$_resolved" | grep -q "^repos/api/README.md$" || { fail "repos/api/README.md not resolved in sources: $_resolved"; exit 1; }
echo "$_resolved" | grep -q "^repos/api/pkg/README.md$" || { fail "repos/api/pkg/README.md not resolved in sources: $_resolved"; exit 1; }
echo "$_resolved" | grep -q "^repos/web/README.md$" || { fail "repos/web/README.md not resolved in sources: $_resolved"; exit 1; }
! echo "$_resolved" | grep -q "node_modules" || { fail "node_modules not pruned from resolved sources: $_resolved"; exit 1; }
! echo "$_resolved" | grep -q "\.rnex" || { fail ".rnex not pruned from resolved sources: $_resolved"; exit 1; }
! echo "$_resolved" | grep -q "\.git" || { fail ".git not pruned from resolved sources: $_resolved"; exit 1; }

# Verify plugin info displays effective sources list
_pinfo_out="$(cd "$TEST_SOURCES_WS" && ./rnex plugin info karpathy-llm)"
echo "$_pinfo_out" | grep -q "sources" || { fail "plugin info missing sources option: $_pinfo_out"; exit 1; }
echo "$_pinfo_out" | grep -q "docs, repos/\*\*/README.md" || { fail "plugin info missing effective sources list: $_pinfo_out"; exit 1; }

# 3. Disabled repo exclusion via .local.rnex.yaml
cat <<'EOF_LOCAL_DIS' > "$TEST_SOURCES_WS/.local.rnex.yaml"
repos:
  web:
    enabled: false
EOF_LOCAL_DIS

_resolved_dis="$(cd "$TEST_SOURCES_WS" && . "$TEST_SOURCES_WS/lib/core.sh" && . "$TEST_SOURCES_WS/lib/workspace.sh" && . "$TEST_SOURCES_WS/lib/yaml.sh" && . "$TEST_SOURCES_WS/lib/plugins.sh" && NEXUS_DIR="$TEST_SOURCES_WS" resolve_plugin_sources "$(get_plugin_config_list karpathy-llm sources)")"

echo "$_resolved_dis" | grep -q "^repos/api/README.md$" || { fail "repos/api/README.md missing after disabling web: $_resolved_dis"; exit 1; }
! echo "$_resolved_dis" | grep -q "^repos/web/README.md$" || { fail "Disabled repos/web/README.md was not excluded: $_resolved_dis"; exit 1; }
_dis_count="$(printf '%s\n' "$_resolved_dis" | wc -l | tr -d ' ')"
[ "$_dis_count" -eq 3 ] || { fail "Expected exactly 3 resolved files after disabling web, got $_dis_count: $_resolved_dis"; exit 1; }

# 4. Two-level config override: .local.rnex.yaml sources replaces rnex.yaml sources entirely
cat <<'EOF_LOCAL_SRC' >> "$TEST_SOURCES_WS/.local.rnex.yaml"
plugins:
  karpathy-llm:
    sources:
      - "repos/*/README.md"
EOF_LOCAL_SRC

_resolved_override="$(cd "$TEST_SOURCES_WS" && . "$TEST_SOURCES_WS/lib/core.sh" && . "$TEST_SOURCES_WS/lib/workspace.sh" && . "$TEST_SOURCES_WS/lib/yaml.sh" && . "$TEST_SOURCES_WS/lib/plugins.sh" && NEXUS_DIR="$TEST_SOURCES_WS" resolve_plugin_sources "$(get_plugin_config_list karpathy-llm sources)")"

# Should contain repos/api/README.md, but NOT docs/arch.md (overridden) and NOT repos/api/pkg/README.md (single-level glob)
echo "$_resolved_override" | grep -q "^repos/api/README.md$" || { fail "repos/api/README.md missing in single-level glob: $_resolved_override"; exit 1; }
! echo "$_resolved_override" | grep -q "^docs/arch.md$" || { fail "docs/arch.md was not overridden by local sources list: $_resolved_override"; exit 1; }
! echo "$_resolved_override" | grep -q "^repos/api/pkg/README.md$" || { fail "repos/*/README.md incorrectly matched nested README: $_resolved_override"; exit 1; }

# 5. Legacy raw_dir fallback and automatic rewrite to sources on rnex sync
rm -f "$TEST_SOURCES_WS/.local.rnex.yaml"
cat <<'EOF_LEGACY' > "$TEST_SOURCES_WS/rnex.yaml"
version: 0.7.22
plugins:
  karpathy-llm:
    raw_dir: custom_raw
    ingest_member_readmes: true
repos:
  api: {}
EOF_LEGACY

mkdir -p "$TEST_SOURCES_WS/custom_raw"
echo "# Legacy Source" > "$TEST_SOURCES_WS/custom_raw/legacy.md"

_status_legacy_out="$(cd "$TEST_SOURCES_WS" && ./rnex status 2>&1)"
echo "$_status_legacy_out" | grep -q "Deprecated: raw_dir" || { fail "Deprecation notice missing in rnex status with legacy raw_dir: $_status_legacy_out"; exit 1; }

_sync_legacy_out="$(cd "$TEST_SOURCES_WS" && ./rnex sync -y 2>&1)"
! grep -q "raw_dir:" "$TEST_SOURCES_WS/rnex.yaml" || { fail "raw_dir was not rewritten to sources on rnex sync: $(cat "$TEST_SOURCES_WS/rnex.yaml")"; exit 1; }
! grep -q "ingest_member_readmes" "$TEST_SOURCES_WS/rnex.yaml" || { fail "ingest_member_readmes was not removed on rnex sync: $(cat "$TEST_SOURCES_WS/rnex.yaml")"; exit 1; }
grep -q "^    sources:$" "$TEST_SOURCES_WS/rnex.yaml" || { fail "sources key missing after rnex sync rewrite: $(cat "$TEST_SOURCES_WS/rnex.yaml")"; exit 1; }
grep -q "^      - custom_raw$" "$TEST_SOURCES_WS/rnex.yaml" || { fail "sources list item '- custom_raw' missing after rnex sync rewrite: $(cat "$TEST_SOURCES_WS/rnex.yaml")"; exit 1; }
[ -d "$TEST_SOURCES_WS/custom_raw" ] || { fail "custom_raw missing after sync"; exit 1; }

_status_after_sync="$(cd "$TEST_SOURCES_WS" && ./rnex status 2>&1)"
! echo "$_status_after_sync" | grep -q "Deprecated: raw_dir" || { fail "Deprecation notice still present in rnex status after sync rewrite: $_status_after_sync"; exit 1; }

_resolved_legacy="$(cd "$TEST_SOURCES_WS" && . "$TEST_SOURCES_WS/lib/core.sh" && . "$TEST_SOURCES_WS/lib/workspace.sh" && . "$TEST_SOURCES_WS/lib/yaml.sh" && . "$TEST_SOURCES_WS/lib/plugins.sh" && NEXUS_DIR="$TEST_SOURCES_WS" resolve_plugin_sources "$(get_plugin_config_list karpathy-llm sources 2>/dev/null)")"

echo "$_resolved_legacy" | grep -q "^custom_raw/legacy.md$" || { fail "Migrated custom_raw source was not resolved: $_resolved_legacy"; exit 1; }

# 6. Flow array syntax [docs, "repos/*/README.md"]
cat <<'EOF_FLOW' > "$TEST_SOURCES_WS/rnex.yaml"
version: 0.7.26
plugins:
  karpathy-llm:
    sources: [docs, "repos/*/README.md"]
repos:
  api: {}
  web:
    enabled: false
EOF_FLOW

_resolved_flow="$(cd "$TEST_SOURCES_WS" && . "$TEST_SOURCES_WS/lib/core.sh" && . "$TEST_SOURCES_WS/lib/workspace.sh" && . "$TEST_SOURCES_WS/lib/yaml.sh" && . "$TEST_SOURCES_WS/lib/plugins.sh" && NEXUS_DIR="$TEST_SOURCES_WS" resolve_plugin_sources "$(get_plugin_config_list karpathy-llm sources)")"
echo "$_resolved_flow" | grep -q "^docs/arch.md$" || { fail "Flow array missing docs/arch.md: $_resolved_flow"; exit 1; }
echo "$_resolved_flow" | grep -q "^repos/api/README.md$" || { fail "Flow array missing repos/api/README.md: $_resolved_flow"; exit 1; }
! echo "$_resolved_flow" | grep -q "^repos/web/README.md$" || { fail "Flow array included disabled repos/web/README.md: $_resolved_flow"; exit 1; }
! echo "$_resolved_flow" | grep -q "^repos/api/pkg/README.md$" || { fail "Flow array single-level glob matched nested pkg: $_resolved_flow"; exit 1; }

pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm plugin wiki ingest and lint with custom repos_dir (packages/)"
TEST_KPKG_WS="$TEST_TMP/karpathy-custom-repos-dir-ws"
mkdir -p "$TEST_KPKG_WS"
cp "$CLI" "$TEST_KPKG_WS/rnex"
chmod +x "$TEST_KPKG_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_KPKG_WS/toolkit"
cp "$DIR/package.json" "$TEST_KPKG_WS/package.json"
git -C "$TEST_KPKG_WS" init -q

# Initialize workspace with --repos-dir packages
(cd "$TEST_KPKG_WS" && ./rnex init -y --repos-dir packages "$TEST_KPKG_WS" >/dev/null)

# Enable karpathy-llm plugin
(cd "$TEST_KPKG_WS" && ./rnex plugin enable karpathy-llm >/dev/null)

# Prepare a member repo
_pkg_remote="$TEST_TMP/pkg-remote-core"
mkdir -p "$_pkg_remote"
git -C "$_pkg_remote" init -q
cat <<'CORE_README' > "$_pkg_remote/README.md"
# Core Package

Shared utility functions and common domain models.
CORE_README
git -C "$_pkg_remote" add .
git -C "$_pkg_remote" commit -q -m "initial commit"

# Add core repo into packages/
(cd "$TEST_KPKG_WS" && ./rnex repo add "$_pkg_remote" --name core >/dev/null)
[ -d "$TEST_KPKG_WS/packages/core" ] || { fail "core repo not in packages/core"; exit 1; }

# Run wiki ingest
(cd "$TEST_KPKG_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Verify atomic wiki page created and references packages/core/README.md in sources
[ -f "$TEST_KPKG_WS/wiki/repo-core.md" ] || { fail "repo-core.md missing after ingest"; exit 1; }
grep -q 'sources:[ ]*\["packages/core/README\.md"\]' "$TEST_KPKG_WS/wiki/repo-core.md" || { fail "repo-core.md does not reference packages/core/README.md in sources"; exit 1; }
grep -q "Core Package" "$TEST_KPKG_WS/wiki/repo-core.md" || { fail "repo-core.md missing title Core Package"; exit 1; }

# Verify index.md and _log.md
grep -q "repo-core\.md" "$TEST_KPKG_WS/wiki/index.md" || { fail "repo-core.md missing from wiki/index.md"; exit 1; }
grep -q "packages/core/README\.md" "$TEST_KPKG_WS/wiki/_log.md" || { fail "_log.md missing packages/core/README.md entry"; exit 1; }

# Run wiki lint and verify clean pass without broken source warnings
_lint_out="$(cd "$TEST_KPKG_WS" && ./rnex plugin karpathy-llm lint 2>&1)"
echo "$_lint_out" | grep -q "Wiki lint passed" || { fail "Wiki lint did not pass: $_lint_out"; exit 1; }
! echo "$_lint_out" | grep -q "references broken source file" || { fail "Wiki lint reported broken source file: $_lint_out"; exit 1; }

# Verify custom wiki_dir ("knowledge") and copilot co-existence in compiled ai-instructions.md
(cd "$TEST_KPKG_WS" && ./rnex plugin enable copilot >/dev/null)
cat <<'KPKG_LOCAL_EOF' > "$TEST_KPKG_WS/.local.rnex.yaml"
plugins:
  karpathy-llm:
    wiki_dir: "knowledge"
KPKG_LOCAL_EOF
(cd "$TEST_KPKG_WS" && ./rnex sync -y >/dev/null)
_kpkg_ai="$TEST_KPKG_WS/.rnex/ai-instructions.md"
grep -qF "1. **Step 1 — Read Wiki Hot Cache**: Read \`knowledge/hot.md\`" "$_kpkg_ai" || { fail "Step 1 does not reference knowledge/hot.md"; exit 1; }
! grep -qF 'rules/behavioral.md' "$_kpkg_ai" || { fail "ai-instructions.md references external behavioral.md"; exit 1; }
! grep -qF '# GitHub Copilot Integration' "$_kpkg_ai" || { fail "Copilot setup docs compiled into ai-instructions.md"; exit 1; }
_kpkg_lines="$(wc -l < "$_kpkg_ai" | tr -d ' ')"
[ "$_kpkg_lines" -lt 60 ] || { fail "ai-instructions.md too long: $_kpkg_lines lines (expected < 60)"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm recursive directory intake: bare directory sources, nested subdirectories, spaces/brackets, slug collision prevention, and hidden file exclusion"
TEST_REC_WS="$TEST_TMP/karpathy-recursive-intake-ws"
mkdir -p "$TEST_REC_WS"
cp "$CLI" "$TEST_REC_WS/rnex"
chmod +x "$TEST_REC_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_REC_WS/toolkit"
cp -r "$DIR/lib" "$TEST_REC_WS/lib"
cp -r "$DIR/templates" "$TEST_REC_WS/templates"
cp "$DIR/package.json" "$TEST_REC_WS/package.json"
git -C "$TEST_REC_WS" init -q

# Initialize workspace and enable karpathy-llm
(cd "$TEST_REC_WS" && ./rnex init -y "$TEST_REC_WS" >/dev/null)
(cd "$TEST_REC_WS" && ./rnex plugin enable karpathy-llm >/dev/null)

# 1. Multi-line block YAML configuration: bare directory "docs"
cat <<'EOF_REC_YAML' > "$TEST_REC_WS/rnex.yaml"
version: 0.7.26
plugins:
  karpathy-llm:
    enabled: true
    sources:
      - "docs"
EOF_REC_YAML

# 2. Populate directory structure with edge cases
mkdir -p "$TEST_REC_WS/docs/api"
mkdir -p "$TEST_REC_WS/docs/guide"
mkdir -p "$TEST_REC_WS/docs/nested/deep"
mkdir -p "$TEST_REC_WS/docs/.obsidian"

# Top-level document directly under configured directory (should preserve basename overview.md)
cat <<'EOF_DOC' > "$TEST_REC_WS/docs/overview.md"
# Workspace Overview
Core system architecture and operational concepts.
EOF_DOC

# Two nested README.md files in different subdirectories (slug collision prevention)
cat <<'EOF_DOC' > "$TEST_REC_WS/docs/api/README.md"
# API Specification
REST and WebSocket API endpoints and contracts.
EOF_DOC

cat <<'EOF_DOC' > "$TEST_REC_WS/docs/guide/README.md"
# Guide Index
Step-by-step developer guide and workflows.
EOF_DOC

# Deeply nested file with spaces and brackets in filename
cat <<'EOF_DOC' > "$TEST_REC_WS/docs/nested/deep/spec [v1].md"
# Deep Spec V1
Detailed protocol specifications and technical parameters.
EOF_DOC

# Hidden files that must be ignored
cat <<'EOF_DOC' > "$TEST_REC_WS/docs/.hidden.md"
# Hidden File
Should not be ingested.
EOF_DOC

cat <<'EOF_DOC' > "$TEST_REC_WS/docs/.obsidian/note.md"
# Obsidian Private Note
Should not be ingested.
EOF_DOC

cat <<'EOF_DOC' > "$TEST_REC_WS/docs/api/.secret.env"
SECRET=value
EOF_DOC

# 3. Execute rnex plugin karpathy-llm ingest
(cd "$TEST_REC_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# 4. Verify slug generation and file presence
[ -f "$TEST_REC_WS/wiki/overview.md" ] || { fail "wiki/overview.md missing after ingest"; exit 1; }
[ -f "$TEST_REC_WS/wiki/doc-docs-api-readme.md" ] || { fail "wiki/doc-docs-api-readme.md missing (API README collision)"; exit 1; }
[ -f "$TEST_REC_WS/wiki/doc-docs-guide-readme.md" ] || { fail "wiki/doc-docs-guide-readme.md missing (Guide README collision)"; exit 1; }
[ -f "$TEST_REC_WS/wiki/doc-docs-nested-deep-spec-v1.md" ] || { fail "wiki/doc-docs-nested-deep-spec-v1.md missing (brackets/spaces file)"; exit 1; }

# Verify hidden files were NOT ingested
[ ! -f "$TEST_REC_WS/wiki/hidden.md" ] || { fail "Hidden file .hidden.md was incorrectly ingested"; exit 1; }
[ ! -f "$TEST_REC_WS/wiki/doc-docs-hidden.md" ] || { fail "Hidden file .hidden.md was incorrectly ingested as slug"; exit 1; }
[ ! -f "$TEST_REC_WS/wiki/note.md" ] || { fail "Hidden folder file note.md was incorrectly ingested"; exit 1; }
[ ! -f "$TEST_REC_WS/wiki/doc-docs-obsidian-note.md" ] || { fail "Hidden folder file .obsidian/note.md was incorrectly ingested"; exit 1; }

# 5. Verify frontmatter source references in generated pages
grep -q 'sources:[ ]*\["docs/overview\.md"\]' "$TEST_REC_WS/wiki/overview.md" || { fail "overview.md sources frontmatter incorrect: $(grep 'sources:' "$TEST_REC_WS/wiki/overview.md")"; exit 1; }
grep -q 'sources:[ ]*\["docs/api/README\.md"\]' "$TEST_REC_WS/wiki/doc-docs-api-readme.md" || { fail "doc-docs-api-readme.md sources frontmatter incorrect"; exit 1; }
grep -q 'sources:[ ]*\["docs/guide/README\.md"\]' "$TEST_REC_WS/wiki/doc-docs-guide-readme.md" || { fail "doc-docs-guide-readme.md sources frontmatter incorrect"; exit 1; }
grep -q 'sources:[ ]*\["docs/nested/deep/spec \[v1\]\.md"\]' "$TEST_REC_WS/wiki/doc-docs-nested-deep-spec-v1.md" || { fail "doc-docs-nested-deep-spec-v1.md sources frontmatter incorrect: $(grep 'sources:' "$TEST_REC_WS/wiki/doc-docs-nested-deep-spec-v1.md")"; exit 1; }

# 6. Verify wiki/index.md, wiki/hot.md, and wiki/_log.md
grep -q "overview\.md" "$TEST_REC_WS/wiki/index.md" || { fail "overview.md missing from wiki/index.md"; exit 1; }
grep -q "doc-docs-api-readme\.md" "$TEST_REC_WS/wiki/index.md" || { fail "doc-docs-api-readme.md missing from wiki/index.md"; exit 1; }
grep -q "doc-docs-guide-readme\.md" "$TEST_REC_WS/wiki/index.md" || { fail "doc-docs-guide-readme.md missing from wiki/index.md"; exit 1; }
grep -q "doc-docs-nested-deep-spec-v1\.md" "$TEST_REC_WS/wiki/index.md" || { fail "doc-docs-nested-deep-spec-v1.md missing from wiki/index.md"; exit 1; }

grep -q "spec \[v1\]\.md" "$TEST_REC_WS/wiki/_log.md" || { fail "_log.md missing spec [v1].md entry"; exit 1; }

# 7. Verify rnex plugin karpathy-llm lint --strict passes cleanly
_lint_rec_out="$(cd "$TEST_REC_WS" && ./rnex plugin karpathy-llm lint --strict 2>&1)" || { fail "rnex plugin karpathy-llm lint --strict failed: $_lint_rec_out"; exit 1; }
echo "$_lint_rec_out" | grep -q "Wiki lint passed" || { fail "Lint output mismatch: $_lint_rec_out"; exit 1; }

# 8. Test Two-Level Override with inline flow array syntax: .local.rnex.yaml sources: ["custom_docs"]
cat <<'EOF_LOCAL_FLOW' > "$TEST_REC_WS/.local.rnex.yaml"
plugins:
  karpathy-llm:
    sources: ["custom_docs"]
EOF_LOCAL_FLOW

mkdir -p "$TEST_REC_WS/custom_docs/nested"
cat <<'EOF_DOC' > "$TEST_REC_WS/custom_docs/nested/feature.md"
# Feature Spec
Specification for custom feature.
EOF_DOC

(cd "$TEST_REC_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)
[ -f "$TEST_REC_WS/wiki/doc-custom-docs-nested-feature.md" ] || { fail "wiki/doc-custom-docs-nested-feature.md missing after override ingest"; exit 1; }
grep -q 'sources:[ ]*\["custom_docs/nested/feature\.md"\]' "$TEST_REC_WS/wiki/doc-custom-docs-nested-feature.md" || { fail "feature.md sources frontmatter incorrect"; exit 1; }

_lint_override_out="$(cd "$TEST_REC_WS" && ./rnex plugin karpathy-llm lint --strict 2>&1)" || { fail "rnex plugin karpathy-llm lint --strict after override failed: $_lint_override_out"; exit 1; }
echo "$_lint_override_out" | grep -q "Wiki lint passed" || { fail "Lint output mismatch after override: $_lint_override_out"; exit 1; }

pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
