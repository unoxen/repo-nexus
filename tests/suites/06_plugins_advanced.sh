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
run_test "Disabling plugin in rnex.yaml followed by rnex sync cleanly removes instructions, assets, and User Skills"
# 1. Enable claude with skills: true so we can verify provider User Skills cleanup
cat <<'EOF_CFG2' > "$TEST_KWIKI_WS/rnex.yaml"
plugins:
  claude:
    instructions: true
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
echo "$_kw_active_ai" | grep -q "Karpathy LLM Wiki Knowledge Architecture" || { fail "Active ai-instructions.md missing Karpathy instructions"; exit 1; }

# 2. Disable karpathy-llm via enabled: false in rnex.yaml
cat <<'EOF_CFG3' > "$TEST_KWIKI_WS/rnex.yaml"
plugins:
  claude:
    instructions: true
    skills: true
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
run_test "Karpathy LLM plugin config default lint_trigger: manual and after_sync hook syncing raw_dir and member repository READMEs"
TEST_HOOK_WS="$TEST_TMP/karpathy-hook-sync-ws"
mkdir -p "$TEST_HOOK_WS"
cp "$CLI" "$TEST_HOOK_WS/rnex"
chmod +x "$TEST_HOOK_WS/rnex"
cp -r "$DIR/toolkit" "$TEST_HOOK_WS/toolkit"
cp "$DIR/package.json" "$TEST_HOOK_WS/package.json"
git -C "$TEST_HOOK_WS" init -q

"$TEST_HOOK_WS/rnex" init -y "$TEST_HOOK_WS" >/dev/null

# 1. Enable karpathy-llm and assert lint_trigger defaults to manual
(cd "$TEST_HOOK_WS" && ./rnex plugin enable karpathy-llm >/dev/null)
_pinfo="$(cd "$TEST_HOOK_WS" && ./rnex plugin info karpathy-llm 2>&1)"
echo "$_pinfo" | grep "lint_trigger:" | grep -q "current: manual" || { fail "Plugin info did not report default lint_trigger as manual: $_pinfo"; exit 1; }
grep -q 'lint_trigger: "manual"' "$TEST_HOOK_WS/rnex.yaml" || grep -q 'lint_trigger: manual' "$TEST_HOOK_WS/rnex.yaml" || { fail "rnex.yaml does not contain lint_trigger: manual"; exit 1; }

# 2. Mock a member repository initialization (./repos/mock-member-repo/README.md)
mkdir -p "$TEST_HOOK_WS/repos/mock-member-repo"
printf '# Mock Member Repo\nThis is a mock repository README.\n' > "$TEST_HOOK_WS/repos/mock-member-repo/README.md"

# Also place a sample document in custom/default raw_dir (./docs)
mkdir -p "$TEST_HOOK_WS/docs"
printf '# Intake Note\nImportant context notes.\n' > "$TEST_HOOK_WS/docs/intake-note.md"

# 3. Invoke rnex sync to trigger after_sync hook
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)

# 4. Confirm .rnex/wiki/raw staging directory is NOT created and docs/intake-note.md remains in-place
[ ! -d "$TEST_HOOK_WS/.rnex/wiki/raw" ] || { fail ".rnex/wiki/raw staging directory was created; should not exist"; exit 1; }
[ -f "$TEST_HOOK_WS/docs/intake-note.md" ] || { fail "docs/intake-note.md missing"; exit 1; }
grep -q "Intake Note" "$TEST_HOOK_WS/docs/intake-note.md" || { fail "Content mismatch in docs/intake-note.md"; exit 1; }

# 5a. Verify user-created files in .rnex/wiki/raw are strictly preserved, while duplicate staging is removed
mkdir -p "$TEST_HOOK_WS/.rnex/wiki/raw"
printf '# Custom User Draft\nDo not delete this uncommitted content!\n' > "$TEST_HOOK_WS/.rnex/wiki/raw/user-draft.md"
_sync_preserve_out="$(cd "$TEST_HOOK_WS" && ./rnex sync -y 2>&1)"
[ -f "$TEST_HOOK_WS/.rnex/wiki/raw/user-draft.md" ] || { fail "Custom user file in .rnex/wiki/raw was deleted by rnex sync"; exit 1; }
echo "$_sync_preserve_out" | grep -q "Warning: .rnex/wiki/raw contains custom or uncommitted files" || { fail "Missing preservation warning for .rnex/wiki/raw: $_sync_preserve_out"; exit 1; }

# Replace custom file with duplicate staging file matching docs/intake-note.md
rm -f "$TEST_HOOK_WS/.rnex/wiki/raw/user-draft.md"
cp "$TEST_HOOK_WS/docs/intake-note.md" "$TEST_HOOK_WS/.rnex/wiki/raw/intake-note.md"
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)
[ ! -d "$TEST_HOOK_WS/.rnex/wiki/raw" ] || { fail "Managed duplicate staging .rnex/wiki/raw was not cleaned up"; exit 1; }

# 5b. Confirm member repository README ingested into atomic wiki page
[ -f "$TEST_HOOK_WS/.rnex/wiki/repo-mock-member-repo.md" ] || { fail "repo-mock-member-repo.md missing after wiki ingest"; exit 1; }
grep -q 'title: "Member Repo: mock-member-repo"' "$TEST_HOOK_WS/.rnex/wiki/repo-mock-member-repo.md" || { fail "Frontmatter title missing in repo-mock-member-repo.md"; exit 1; }
grep -q 'tags: \[member-repo, mock-member-repo\]' "$TEST_HOOK_WS/.rnex/wiki/repo-mock-member-repo.md" || { fail "Frontmatter tags missing in repo-mock-member-repo.md"; exit 1; }
grep -q 'sources: \["repos/mock-member-repo/README.md"\]' "$TEST_HOOK_WS/.rnex/wiki/repo-mock-member-repo.md" || { fail "Frontmatter sources missing in repo-mock-member-repo.md"; exit 1; }
grep -q "This is a mock repository README." "$TEST_HOOK_WS/.rnex/wiki/repo-mock-member-repo.md" || { fail "Summary missing in repo-mock-member-repo.md"; exit 1; }
! grep -q "member-repositories.md" "$TEST_HOOK_WS/.rnex/wiki/repo-mock-member-repo.md" || { fail "Missing navigation page member-repositories.md was referenced"; exit 1; }
grep -q "See \[Wiki Index\](\./index.md)" "$TEST_HOOK_WS/.rnex/wiki/repo-mock-member-repo.md" || { fail "Did not reference real navigation index.md"; exit 1; }

# 5c. Confirm registration in navigation index (index.md)
[ -f "$TEST_HOOK_WS/.rnex/wiki/index.md" ] || { fail ".rnex/wiki/index.md missing"; exit 1; }
grep -q "repo-mock-member-repo\.md" "$TEST_HOOK_WS/.rnex/wiki/index.md" || { fail "repo-mock-member-repo.md not indexed in index.md"; exit 1; }
grep -q "Member Repo: mock-member-repo" "$TEST_HOOK_WS/.rnex/wiki/index.md" || { fail "Member repo title not in index.md"; exit 1; }

# 5d. Confirm registration in hot cache (hot.md)
[ -f "$TEST_HOOK_WS/.rnex/wiki/hot.md" ] || { fail ".rnex/wiki/hot.md missing"; exit 1; }
grep -q "mock-member-repo" "$TEST_HOOK_WS/.rnex/wiki/hot.md" || { fail "mock-member-repo missing from hot.md"; exit 1; }
grep -q "repos/mock-member-repo/" "$TEST_HOOK_WS/.rnex/wiki/hot.md" || { fail "repos/mock-member-repo/ missing from hot.md"; exit 1; }

# 5e. Confirm operation log entry (_log.md)
[ -f "$TEST_HOOK_WS/.rnex/wiki/_log.md" ] || { fail ".rnex/wiki/_log.md missing"; exit 1; }
grep -q "Member Repo Ingest: mock-member-repo" "$TEST_HOOK_WS/.rnex/wiki/_log.md" || { fail "Ingest log missing from _log.md"; exit 1; }

# 6. Verify disabled member repo READMEs are not synced
mkdir -p "$TEST_HOOK_WS/repos/disabled-member-repo"
printf '# Disabled Repo\n' > "$TEST_HOOK_WS/repos/disabled-member-repo/README.md"
cat <<'EOF_DIS' >> "$TEST_HOOK_WS/rnex.yaml"
repos:
  disabled-member-repo:
    enabled: false
EOF_DIS
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)
[ ! -d "$TEST_HOOK_WS/.rnex/wiki/raw" ] || { fail ".rnex/wiki/raw staging directory exists"; exit 1; }
[ ! -f "$TEST_HOOK_WS/.rnex/wiki/repo-disabled-member-repo.md" ] || { fail "Disabled repository should not be ingested into wiki"; exit 1; }

# 7. Verify an adjacent enabled repository is NOT affected by the disabled repository entry
mkdir -p "$TEST_HOOK_WS/repos/adjacent-enabled-repo"
printf '# Adjacent Enabled Repo\n' > "$TEST_HOOK_WS/repos/adjacent-enabled-repo/README.md"
cat <<'EOF_ADJ' >> "$TEST_HOOK_WS/rnex.yaml"
  adjacent-enabled-repo:
    url: ./repos/adjacent-enabled-repo
EOF_ADJ
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_HOOK_WS/.rnex/wiki/repo-adjacent-enabled-repo.md" ] || { fail "Adjacent enabled repository was not ingested into wiki"; exit 1; }
grep -q "Adjacent Enabled Repo" "$TEST_HOOK_WS/.rnex/wiki/repo-adjacent-enabled-repo.md" || { fail "Content mismatch in adjacent enabled repo wiki page"; exit 1; }
[ ! -d "$TEST_HOOK_WS/.rnex/wiki/raw" ] || { fail ".rnex/wiki/raw staging directory was created during sync"; exit 1; }

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
[ -f "$TEST_INIT_KW_WS/.rnex/wiki/repo-seed-repo.md" ] || { fail "seed-repo was not ingested during rnex init with karpathy plugin"; exit 1; }
grep -q "Seed Repo" "$TEST_INIT_KW_WS/.rnex/wiki/repo-seed-repo.md" || { fail "seed-repo content mismatch after init ingest"; exit 1; }
grep -q "repo-seed-repo\.md" "$TEST_INIT_KW_WS/.rnex/wiki/index.md" || { fail "seed-repo not registered in index.md after init"; exit 1; }
grep -q "seed-repo" "$TEST_INIT_KW_WS/.rnex/wiki/hot.md" || { fail "seed-repo not registered in hot.md after init"; exit 1; }

# 10. Verify rnex add with karpathy plugin performs wiki ingest for newly added member repo
mkdir -p "$TEST_HOOK_WS/external/added-repo"
git -C "$TEST_HOOK_WS/external/added-repo" init -q
printf '# Added Member Repo\nNewly added member repository via rnex add.\n' > "$TEST_HOOK_WS/external/added-repo/README.md"
git -C "$TEST_HOOK_WS/external/added-repo" config user.email "test@example.com"
git -C "$TEST_HOOK_WS/external/added-repo" config user.name "Test User"
git -C "$TEST_HOOK_WS/external/added-repo" add README.md
git -C "$TEST_HOOK_WS/external/added-repo" commit -qm "Initial commit"

(cd "$TEST_HOOK_WS" && ./rnex add added-repo "$TEST_HOOK_WS/external/added-repo" >/dev/null)
[ -f "$TEST_HOOK_WS/.rnex/wiki/repo-added-repo.md" ] || { fail "added-repo was not ingested during rnex add with karpathy plugin"; exit 1; }
grep -q "Added Member Repo" "$TEST_HOOK_WS/.rnex/wiki/repo-added-repo.md" || { fail "added-repo content mismatch in wiki page"; exit 1; }
grep -q "repo-added-repo\.md" "$TEST_HOOK_WS/.rnex/wiki/index.md" || { fail "added-repo not registered in index.md"; exit 1; }
grep -q "added-repo" "$TEST_HOOK_WS/.rnex/wiki/hot.md" || { fail "added-repo not registered in hot.md"; exit 1; }
grep -q "Member Repo Ingest: added-repo" "$TEST_HOOK_WS/.rnex/wiki/_log.md" || { fail "added-repo not logged in _log.md"; exit 1; }

# 11. Verify scaling across 15 member repositories strictly preserves the ~500-word ceiling on hot.md
for _i in $(seq 1 14); do
  mkdir -p "$TEST_HOOK_WS/repos/repo-$_i"
  printf '# Repository %s\nAutonomous microservice %s responsible for dedicated business domain tasks.\n' "$_i" "$_i" > "$TEST_HOOK_WS/repos/repo-$_i/README.md"
done
(cd "$TEST_HOOK_WS" && ./rnex sync -y >/dev/null)
_hot_wc="$(wc -w < "$TEST_HOOK_WS/.rnex/wiki/hot.md")"
[ "$_hot_wc" -le 500 ] || { fail "hot.md word count ($_hot_wc) exceeded 500-word ceiling with 15 repositories"; exit 1; }

# 12. Verify rnex-wiki-page.template.md contains clean placeholders without /.rnex/.rnex
[ -f "$TEST_HOOK_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" ] || { fail "rnex-wiki-page.template.md missing in scoped plugin dir"; exit 1; }
! grep -q "/\.rnex/\.rnex" "$TEST_HOOK_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" || { fail "Corrupted /.rnex/.rnex found in rnex-wiki-page.template.md"; exit 1; }
grep -q "<wiki_dir>/" "$TEST_HOOK_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" || { fail "<wiki_dir>/ placeholder missing in rnex-wiki-page.template.md"; exit 1; }

# 13. Verify Mandatory Wiki-First Gate compiled into .rnex/ai-instructions.md and absent from AGENTS.md
grep -q "Mandatory Wiki-First Access Gate" "$TEST_HOOK_WS/.rnex/ai-instructions.md" || { fail "Mandatory Wiki-First Access Gate missing from compiled ai-instructions.md"; exit 1; }
! grep -q "Mandatory Wiki-First Access Gate" "$TEST_HOOK_WS/AGENTS.md" || { fail "AGENTS.md contains wiki instructions; should remain a single pointer"; exit 1; }

# 14. Verify git_pre-push.sh emits explicit reminder and performs deterministic checks
(
  cd "$TEST_HOOK_WS"
  cat <<'EOF_PREPUSH' >> .local.rnex.yaml
plugins:
  karpathy-llm:
    lint_trigger: git-pre-push
EOF_PREPUSH
  _pre_push_out="$("$TEST_HOOK_WS/toolkit/plugins/karpathy-llm/hooks/git_pre-push.sh" 2>&1)"
  echo "$_pre_push_out" | grep -q "Reminder: Wiki files changed. Run the rnex-karpathy-llm-wiki-lint skill to verify." || { fail "git_pre-push.sh missing explicit reminder: $_pre_push_out"; exit 1; }
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
    instructions: true
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
(cd "$TEST_SEPARATION_WS" && ./rnex sync -y >/dev/null)

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
(cd "$TEST_SEPARATION_WS" && ./rnex sync -y >/dev/null)
[ ! -d "$TEST_SEPARATION_WS/.claude/skills/rnex-wiki-ingest" ] || { fail "Stale unprefixed rnex-wiki-ingest was not purged by rnex sync"; exit 1; }
[ ! -d "$TEST_SEPARATION_WS/.claude/skills/rnex-wiki-lint" ] || { fail "Stale unprefixed rnex-wiki-lint was not purged by rnex sync"; exit 1; }
[ -f "$TEST_SEPARATION_WS/.claude/skills/rnex-karpathy-llm-wiki-ingest/SKILL.md" ] || { fail "rnex-karpathy-llm-wiki-ingest was not regenerated by rnex sync"; exit 1; }
[ -f "$TEST_SEPARATION_WS/.claude/skills/rnex-karpathy-llm-wiki-lint/SKILL.md" ] || { fail "rnex-karpathy-llm-wiki-lint was not regenerated by rnex sync"; exit 1; }

pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
