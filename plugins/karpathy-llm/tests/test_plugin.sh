#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2016
# ============================================================================
# File: plugins/karpathy-llm/tests/test_plugin.sh
# Architectural Layer: Quality Assurance / Integration Test Automation
# Design Pattern: Test Suite (Template Method)
# Responsibilities:
#   - Validates Karpathy LLM Wiki plugin manifest, version parity, and strict 2-command CLI.
#   - Asserts zero symbolic links (find wiki -type l) and Windows safety.
#   - Asserts zero redundant wiki/concepts and wiki/repos directories (in-place indexing).
#   - Asserts 100% configured sources coverage directly into flat leaf shards (wiki/*.md).
#   - Asserts complete removal of legacy graph TSVs (nodes.tsv, edges_out.tsv, edges_in.tsv).
#   - Asserts bounded root router (wiki/index.md <= 80 lines) and automatic shard splitting.
#   - Verifies auto-healing legacy purge and strict linting.
#   - Asserts sub-scope shard creation and recursive globstar (**) in-place source ingestion.
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
[ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
# shellcheck source=tests/test_helper.sh
. "$DIR/tests/test_helper.sh"

TEST_KARPATHY_WS="$TEST_TMP/karpathy-plugin-ws"
mkdir -p "$TEST_KARPATHY_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_KARPATHY_WS"
cd "$TEST_KARPATHY_WS"

_kl_pdir="$TEST_KARPATHY_WS/plugins/karpathy-llm"

# --------------------------------------------------------------------------
# Test 1: Manifest integrity, version parity, and strict 2-command declaration
# --------------------------------------------------------------------------
run_test "Karpathy-llm: manifest integrity, version parity, and 2-command surface"
_cli_ver="$("$TEST_KARPATHY_WS/rnex" --version | awk '{print $2}')"
_m_ver="$(awk '/^version:[ ]*/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); print; exit }' "$_kl_pdir/plugin.yaml")"
[ "$_m_ver" = "$_cli_ver" ] || { fail "Plugin version ($_m_ver) does not match CLI version ($_cli_ver)"; exit 1; }

_yaml_file="$_kl_pdir/plugin.yaml"
# Assert templates are not declared in plugin.yaml
! grep -q 'templates' "$_yaml_file" || { fail "templates should not be in plugin.yaml"; exit 1; }

# Assert flat B-Tree configuration defaults
grep -q 'btree_shard_max_entries:' "$_yaml_file" || { fail "btree_shard_max_entries missing in plugin.yaml"; exit 1; }
grep -q 'btree_root_max_lines:' "$_yaml_file" || { fail "btree_root_max_lines missing in plugin.yaml"; exit 1; }
grep -q 'wiki_dir: "wiki"' "$_yaml_file" || { fail "wiki_dir default missing in plugin.yaml"; exit 1; }
grep -q 'index_file: "index.md"' "$_yaml_file" || { fail "index_file default missing in plugin.yaml"; exit 1; }
grep -q 'log_file: "log.md"' "$_yaml_file" || { fail "log_file default missing in plugin.yaml"; exit 1; }

# Assert legacy graph and directory keys are completely purged
! grep -q 'graph_default_depth:' "$_yaml_file" || { fail "graph_default_depth must NOT be in plugin.yaml"; exit 1; }
! grep -q 'graph_dir:' "$_yaml_file" || { fail "graph_dir must NOT be in plugin.yaml"; exit 1; }
! grep -q 'index_dir:' "$_yaml_file" || { fail "index_dir must NOT be in plugin.yaml"; exit 1; }
! grep -q '_index' "$_yaml_file" || { fail "_index must NOT be in plugin.yaml"; exit 1; }
! grep -q '_graph' "$_yaml_file" || { fail "_graph must NOT be in plugin.yaml"; exit 1; }
! grep -q '_log' "$_yaml_file" || { fail "_log must NOT be in plugin.yaml"; exit 1; }

# Assert ONLY ingest and lint are registered under commands:
grep -q '^[ ]*ingest:' "$_yaml_file" || { fail "ingest command missing in plugin.yaml"; exit 1; }
grep -q '^[ ]*lint:' "$_yaml_file" || { fail "lint command missing in plugin.yaml"; exit 1; }
! grep -q '^[ ]*init:' "$_yaml_file" || { fail "init command must NOT be in plugin.yaml commands"; exit 1; }
! grep -q '^[ ]*index:' "$_yaml_file" || { fail "index command must NOT be in plugin.yaml commands"; exit 1; }
! grep -q '^[ ]*graph:' "$_yaml_file" || { fail "graph command must NOT be in plugin.yaml commands"; exit 1; }
! grep -q '^[ ]*search:' "$_yaml_file" || { fail "search command must NOT be in plugin.yaml commands"; exit 1; }

# Assert deprecated public scripts are deleted from bin/, commands/, and lib/
[ ! -e "$_kl_pdir/bin/init.sh" ] || { fail "bin/init.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/bin/index.sh" ] || { fail "bin/index.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/bin/search.sh" ] || { fail "bin/search.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/bin/graph.sh" ] || { fail "bin/graph.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/commands/init.sh" ] || { fail "commands/init.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/commands/index.sh" ] || { fail "commands/index.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/commands/search.sh" ] || { fail "commands/search.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/commands/graph.sh" ] || { fail "commands/graph.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/lib/graph_helpers.sh" ] || { fail "lib/graph_helpers.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/lib/agent_query_helpers.sh" ] || { fail "lib/agent_query_helpers.sh still exists"; exit 1; }

# Assert obsolete options absent
! grep -q "lint_trigger" "$_yaml_file" || { fail "lint_trigger still present in plugin.yaml"; exit 1; }
! grep -q "notify_on_changes" "$_yaml_file" || { fail "notify_on_changes still present in plugin.yaml"; exit 1; }
! grep -q "ingest_member_readmes" "$_yaml_file" || { fail "ingest_member_readmes still present in plugin.yaml"; exit 1; }
! grep -q "hot_file" "$_yaml_file" || { fail "hot_file still present in plugin.yaml"; exit 1; }

# Verify valid YAML parsing if ruby is available
if command -v ruby >/dev/null 2>&1; then
  ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$_yaml_file" || { fail "karpathy-llm plugin.yaml is not valid YAML"; exit 1; }
fi
pass

# --------------------------------------------------------------------------
# Test 2: Strict 2-Command Public CLI Surface
# --------------------------------------------------------------------------
run_test "Karpathy-llm: strict 2-command public CLI (ingest & lint succeed, init/index/search/graph rejected)"
"$TEST_KARPATHY_WS/rnex" init -y --karpathy "$TEST_KARPATHY_WS" >/dev/null

# 1. Public user command 1: ingest must succeed (exit 0)
(cd "$TEST_KARPATHY_WS" && ./rnex plugin karpathy-llm ingest >/dev/null) || {
  fail "rnex plugin karpathy-llm ingest failed with non-zero exit code"; exit 1;
}

# 2. Public user command 2: lint must succeed (exit 0)
(cd "$TEST_KARPATHY_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "rnex plugin karpathy-llm lint failed with non-zero exit code"; exit 1;
}

# 3. Deprecated subcommands must fail with non-zero exit code
_rc_init=0
(cd "$TEST_KARPATHY_WS" && ./rnex plugin karpathy-llm init >/dev/null 2>&1) || _rc_init=1
[ "$_rc_init" -eq 1 ] || { fail "rnex plugin karpathy-llm init should exit non-zero"; exit 1; }

_rc_index=0
(cd "$TEST_KARPATHY_WS" && ./rnex plugin karpathy-llm index >/dev/null 2>&1) || _rc_index=1
[ "$_rc_index" -eq 1 ] || { fail "rnex plugin karpathy-llm index should exit non-zero"; exit 1; }

_rc_search=0
(cd "$TEST_KARPATHY_WS" && ./rnex plugin karpathy-llm search "auth" >/dev/null 2>&1) || _rc_search=1
[ "$_rc_search" -eq 1 ] || { fail "rnex plugin karpathy-llm search should exit non-zero"; exit 1; }

_rc_graph=0
(cd "$TEST_KARPATHY_WS" && ./rnex plugin karpathy-llm graph "auth" >/dev/null 2>&1) || _rc_graph=1
[ "$_rc_graph" -eq 1 ] || { fail "rnex plugin karpathy-llm graph should exit non-zero"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 3: Zero-Symlinks & Windows Compatibility Test
# --------------------------------------------------------------------------
run_test "Karpathy-llm: zero symlinks in wiki/ and zero symbolic links in plugin implementation"
# Assert no symlinks anywhere in wiki/
_symlinks="$(find "$TEST_KARPATHY_WS/wiki" -type l 2>/dev/null || true)"
[ -z "$_symlinks" ] || { fail "Forbidden symlinks found in wiki: $_symlinks"; exit 1; }

# Assert no symlink creation in any operational plugin shell script
_ln_pat="ln ""-s"
_ln_matches="$(find "$_kl_pdir" -type f -name "*.sh" ! -path "*/tests/*" -exec grep -Hn "$_ln_pat" {} + 2>/dev/null || true)"
if [ -n "$_ln_matches" ]; then
  fail "Found forbidden symlink command in plugin implementation: $_ln_matches"; exit 1;
fi
pass

# --------------------------------------------------------------------------
# Test 4: 100% Configured sources Coverage Directly in Flat Leaf Shards
# --------------------------------------------------------------------------
run_test "Karpathy-llm: 100% configured sources coverage directly in flat wiki/ shards"
TEST_COV_WS="$TEST_TMP/karpathy-coverage-ws"
mkdir -p "$TEST_COV_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_COV_WS"
cd "$TEST_COV_WS"

mkdir -p "$TEST_COV_WS/docs" "$TEST_COV_WS/repos/service-a/docs"
printf '# Nexus Architecture\nRoot workspace design.\n' > "$TEST_COV_WS/docs/architecture.md"
printf '# Root Readme\nRoot overview.\n' > "$TEST_COV_WS/README.md"
printf '# Root Agents\nUniversal AI agent instructions.\n' > "$TEST_COV_WS/AGENTS.md"

printf '# Service A\nService A overview.\n' > "$TEST_COV_WS/repos/service-a/README.md"
printf '# Service A API\nService A REST endpoints.\n' > "$TEST_COV_WS/repos/service-a/docs/api.md"

cat <<'EOF_COV_YAML' > "$TEST_COV_WS/rnex.yaml"
version: 1.0.0
sources: [README.md, AGENTS.md, docs]
plugins:
  karpathy-llm:
repos:
  service-a:
    sources:
      - README.md
      - docs/api.md
EOF_COV_YAML

"$TEST_COV_WS/rnex" init -y --karpathy "$TEST_COV_WS" >/dev/null
(cd "$TEST_COV_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Verify flat B-Tree shards were created directly under wiki/ (no _index/ wrapper)
[ -f "$TEST_COV_WS/wiki/repo-nexus.md" ] || { fail "wiki/repo-nexus.md missing"; exit 1; }
[ -f "$TEST_COV_WS/wiki/repos-service-a.md" ] || { fail "wiki/repos-service-a.md missing"; exit 1; }
[ -f "$TEST_COV_WS/wiki/repos-service-a-docs.md" ] || { fail "wiki/repos-service-a-docs.md missing"; exit 1; }
[ -f "$TEST_COV_WS/wiki/index.md" ] || { fail "wiki/index.md missing"; exit 1; }
[ -f "$TEST_COV_WS/wiki/log.md" ] || { fail "wiki/log.md missing"; exit 1; }

# Verify indexed content in flat leaf shards
grep -q 'readme' "$TEST_COV_WS/wiki/repo-nexus.md" || { fail "README missing in repo-nexus.md"; exit 1; }
grep -q 'agents' "$TEST_COV_WS/wiki/repo-nexus.md" || { fail "AGENTS missing in repo-nexus.md"; exit 1; }
grep -q 'architecture' "$TEST_COV_WS/wiki/repo-nexus.md" || { fail "architecture missing in repo-nexus.md"; exit 1; }
grep -q 'readme' "$TEST_COV_WS/wiki/repos-service-a.md" || { fail "service-a README missing in repos-service-a.md"; exit 1; }
grep -q 'api' "$TEST_COV_WS/wiki/repos-service-a-docs.md" || { fail "service-a api missing in repos-service-a-docs.md"; exit 1; }

# Negative assertions: zero graph, zero _index wrapper, zero underscore prefixes
[ ! -d "$TEST_COV_WS/wiki/_graph" ] || { fail "wiki/_graph exists"; exit 1; }
[ ! -d "$TEST_COV_WS/wiki/_index" ] || { fail "wiki/_index exists"; exit 1; }
[ ! -e "$TEST_COV_WS/wiki/_index.md" ] || { fail "wiki/_index.md exists"; exit 1; }
[ ! -e "$TEST_COV_WS/wiki/_log.md" ] || { fail "wiki/_log.md exists"; exit 1; }
[ ! -e "$TEST_COV_WS/wiki/hot.md" ] || { fail "wiki/hot.md exists"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 5: Flat B-Tree Index Validation, Entry Formatting, and Zero TSV Tables
# --------------------------------------------------------------------------
run_test "Karpathy-llm: flat B-Tree entry formatting, root router links, and zero TSV tables"
# Verify root index.md table entries link to flat shards
grep -q 'repo-nexus\.md' "$TEST_COV_WS/wiki/index.md" || { fail "repo-nexus.md missing from wiki/index.md table"; exit 1; }
grep -q 'repos-service-a\.md' "$TEST_COV_WS/wiki/index.md" || { fail "repos-service-a.md missing from wiki/index.md table"; exit 1; }
grep -q 'repos-service-a-docs\.md' "$TEST_COV_WS/wiki/index.md" || { fail "repos-service-a-docs.md missing from wiki/index.md table"; exit 1; }

# Verify entry line format: - **<slug>** (`<rel_path>`) — <title>: <summary>
grep -q '^- \*\*readme\*\* (`README\.md`) — ' "$TEST_COV_WS/wiki/repo-nexus.md" || {
  fail "repo-nexus.md entry formatting invalid: $(cat "$TEST_COV_WS/wiki/repo-nexus.md")"; exit 1;
}

# Verify audit log contains ingest entry
[ -s "$TEST_COV_WS/wiki/log.md" ] || { fail "wiki/log.md is empty"; exit 1; }
grep -q '`ingest`' "$TEST_COV_WS/wiki/log.md" || { fail "wiki/log.md missing ingest entry"; exit 1; }

# Run lint and verify lint audit entry
(cd "$TEST_COV_WS" && ./rnex plugin karpathy-llm lint >/dev/null)
grep -q '`lint`' "$TEST_COV_WS/wiki/log.md" || { fail "wiki/log.md missing lint entry"; exit 1; }

# Assert ZERO TSV property graph files exist anywhere in wiki/
_tsv_files="$(find "$TEST_COV_WS/wiki" -name "*.tsv" 2>/dev/null || true)"
[ -z "$_tsv_files" ] || { fail "Found TSV graph files in wiki: $_tsv_files"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 6: Zero wiki/concepts & wiki/repos Directories; repo-nexus Shard Naming
# --------------------------------------------------------------------------
run_test "Karpathy-llm: zero wiki/concepts & wiki/repos; primary shard is repo-nexus; index.md <= 80 lines"
[ ! -d "$TEST_COV_WS/wiki/concepts" ] || { fail "Redundant wiki/concepts directory exists"; exit 1; }
[ ! -d "$TEST_COV_WS/wiki/repos" ] || { fail "Redundant wiki/repos directory exists"; exit 1; }
[ ! -f "$TEST_COV_WS/wiki/concepts.md" ] || { fail "Legacy concepts.md shard exists"; exit 1; }
[ ! -f "$TEST_COV_WS/wiki/_index/concepts.md" ] || { fail "Legacy _index/concepts.md shard exists"; exit 1; }
[ -f "$TEST_COV_WS/wiki/repo-nexus.md" ] || { fail "wiki/repo-nexus.md shard missing"; exit 1; }

# Verify wiki/index.md is <= 80 lines
_root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$TEST_COV_WS/wiki/index.md")"
[ "$_root_lines" -le 80 ] || { fail "wiki/index.md exceeded 80 lines: $_root_lines"; exit 1; }

# Negative assertions: legacy files and folders must NOT exist
[ ! -e "$TEST_COV_WS/wiki/_index.md" ] || { fail "legacy wiki/_index.md exists"; exit 1; }
[ ! -e "$TEST_COV_WS/wiki/_log.md" ] || { fail "legacy wiki/_log.md exists"; exit 1; }
[ ! -e "$TEST_COV_WS/wiki/hot.md" ] || { fail "legacy wiki/hot.md exists"; exit 1; }
[ ! -d "$TEST_COV_WS/wiki/overview" ] || { fail "legacy wiki/overview/ exists"; exit 1; }
[ ! -d "$TEST_COV_WS/wiki/entities" ] || { fail "legacy wiki/entities/ exists"; exit 1; }
[ ! -d "$TEST_COV_WS/wiki/sources" ] || { fail "legacy wiki/sources/ exists"; exit 1; }
[ ! -d "$TEST_COV_WS/wiki/_graph" ] || { fail "legacy wiki/_graph/ exists"; exit 1; }
[ ! -d "$TEST_COV_WS/wiki/_index" ] || { fail "legacy wiki/_index/ exists"; exit 1; }

# Root router has Repo Nexus section and Member Repositories section
grep -q 'Repo Nexus' "$TEST_COV_WS/wiki/index.md" || { fail "Repo Nexus section missing in index.md"; exit 1; }
grep -q 'Member Repositories' "$TEST_COV_WS/wiki/index.md" || { fail "Member Repositories section missing in index.md"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 7: B-Tree Sharding and Automatic Sub-Shard Splitting on Threshold
# --------------------------------------------------------------------------
run_test "Karpathy-llm: B-Tree sharding, automatic shard splitting (a-m / n-z), and root line bounds"
TEST_BTREE_WS="$TEST_TMP/karpathy-btree-ws"
mkdir -p "$TEST_BTREE_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_BTREE_WS"
cd "$TEST_BTREE_WS"
"$TEST_BTREE_WS/rnex" init -y --karpathy "$TEST_BTREE_WS" >/dev/null

cat <<'EOF_BTREE_CFG' > "$TEST_BTREE_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    btree_shard_max_entries: 5
    sources: [docs]
repos:
EOF_BTREE_CFG

# Create 8 documentation notes under docs/ to exceed the split threshold of 5
mkdir -p "$TEST_BTREE_WS/docs"
for _cname in "auth-tokens" "caching" "distributed-locks" "encryption" "jwt" "message-brokers" "networking" "queues"; do
  cat <<EOF_C > "$TEST_BTREE_WS/docs/${_cname}.md"
# ${_cname}
Detailed explanation of ${_cname} architecture.
EOF_C
done

# Run lint to rebalance B-Tree shards
(cd "$TEST_BTREE_WS" && ./rnex plugin karpathy-llm lint)

# Verify repo-nexus shard split into a-m and n-z sub-shards directly in wiki/
[ -f "$TEST_BTREE_WS/wiki/repo-nexus-a-m.md" ] || { fail "repo-nexus-a-m.md missing after split"; exit 1; }
[ -f "$TEST_BTREE_WS/wiki/repo-nexus-n-z.md" ] || { fail "repo-nexus-n-z.md missing after split"; exit 1; }
[ ! -d "$TEST_BTREE_WS/wiki/_index" ] || { fail "wiki/_index directory should not exist"; exit 1; }

# Verify sorted contents in each shard
grep -q "auth-tokens" "$TEST_BTREE_WS/wiki/repo-nexus-a-m.md" || { fail "auth-tokens missing from repo-nexus-a-m.md"; exit 1; }
grep -q "jwt" "$TEST_BTREE_WS/wiki/repo-nexus-a-m.md" || { fail "jwt missing from repo-nexus-a-m.md"; exit 1; }
grep -q "networking" "$TEST_BTREE_WS/wiki/repo-nexus-n-z.md" || { fail "networking missing from repo-nexus-n-z.md"; exit 1; }
grep -q "queues" "$TEST_BTREE_WS/wiki/repo-nexus-n-z.md" || { fail "queues missing from repo-nexus-n-z.md"; exit 1; }

# Verify B-Tree Root routing table reflects sub-shards and is bounded (<= 80 lines)
_bt_root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$TEST_BTREE_WS/wiki/index.md")"
[ "$_bt_root_lines" -le 80 ] || { fail "Root index.md exceeded 80 lines: $_bt_root_lines"; exit 1; }
grep -q 'repo-nexus-a-m' "$TEST_BTREE_WS/wiki/index.md" || { fail "repo-nexus-a-m missing from root router table"; exit 1; }
grep -q 'repo-nexus-n-z' "$TEST_BTREE_WS/wiki/index.md" || { fail "repo-nexus-n-z missing from root router table"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 8: Single-File Ingestion, Options, Error Validation, and Batch Fallback
# --------------------------------------------------------------------------
run_test "Karpathy-llm: single-file ingestion (--file/--source), error validation, and batch fallback"
TEST_SF_WS="$TEST_TMP/karpathy-singlefile-ws"
mkdir -p "$TEST_SF_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_SF_WS"
cd "$TEST_SF_WS"
"$TEST_SF_WS/rnex" init -y --karpathy "$TEST_SF_WS" >/dev/null

mkdir -p "$TEST_SF_WS/raw"
cat <<'EOF_CFG_SF' > "$TEST_SF_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    sources: [raw]
repos:
EOF_CFG_SF
(cd "$TEST_SF_WS" && ./rnex sync -y >/dev/null)

printf '# Document A\nSingle file A architecture.\n' > "$TEST_SF_WS/raw/doc-a.md"
printf '# Document B\nSingle file B architecture.\n' > "$TEST_SF_WS/raw/doc-b.md"
printf '# Document C\nSingle file C architecture.\n' > "$TEST_SF_WS/raw/doc-c.md"

# Test Case 1: Positional single file ingestion
(cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest raw/doc-a.md >/dev/null)
[ -f "$TEST_SF_WS/wiki/repo-nexus-raw.md" ] || { fail "repo-nexus-raw.md missing after single file ingest"; exit 1; }
grep -q 'doc-a' "$TEST_SF_WS/wiki/repo-nexus-raw.md" || { fail "doc-a missing in repo-nexus-raw.md after single file ingest"; exit 1; }

# Test Case 2: --file / -f flag single file ingestion
(cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest --file raw/doc-b.md >/dev/null)
grep -q 'doc-b' "$TEST_SF_WS/wiki/repo-nexus-raw.md" || { fail "doc-b missing in repo-nexus-raw.md after --file ingest"; exit 1; }

# Test Case 3: Missing file error and exit code non-zero
_missing_err=0
(cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest raw/nonexistent.md >/dev/null 2>&1) || _missing_err=1
[ "$_missing_err" -eq 1 ] || { fail "ingest of nonexistent file expected non-zero exit code"; exit 1; }

# Test Case 3b: Directory argument error and exit code non-zero
_dir_err=0
(cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest raw >/dev/null 2>&1) || _dir_err=1
[ "$_dir_err" -eq 1 ] || { fail "ingest of directory argument expected non-zero exit code"; exit 1; }

# Test Case 4: Batch fallback when no file argument is passed
(cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)
grep -q 'doc-c' "$TEST_SF_WS/wiki/repo-nexus-raw.md" || { fail "doc-c missing from repo-nexus-raw.md after batch ingest"; exit 1; }
[ ! -e "$TEST_SF_WS/wiki/hot.md" ] || { fail "hot.md found in single-file test workspace"; exit 1; }
[ -z "$(find "$TEST_SF_WS/wiki" -type l 2>/dev/null || true)" ] || { fail "symlinks found in single-file workspace"; exit 1; }
[ ! -d "$TEST_SF_WS/wiki/_graph" ] || { fail "wiki/_graph found in single-file workspace"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 9: Auto-healing Directory Migration and Purge during lint
# --------------------------------------------------------------------------
run_test "Karpathy-llm: auto-healing legacy purge (overview/entities/sources/concepts/repos/_graph/_index) during lint"
TEST_MIG_WS="$TEST_TMP/karpathy-mig-ws"
mkdir -p "$TEST_MIG_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_MIG_WS"
cd "$TEST_MIG_WS"
"$TEST_MIG_WS/rnex" init -y --karpathy "$TEST_MIG_WS" >/dev/null

# Plant legacy directories and deprecated files
mkdir -p "$TEST_MIG_WS/wiki/overview" \
         "$TEST_MIG_WS/wiki/entities" \
         "$TEST_MIG_WS/wiki/sources/payment-svc" \
         "$TEST_MIG_WS/wiki/concepts" \
         "$TEST_MIG_WS/wiki/repos" \
         "$TEST_MIG_WS/wiki/_graph" \
         "$TEST_MIG_WS/wiki/_index"
echo "# Legacy Concept" > "$TEST_MIG_WS/wiki/overview/legacy-concept.md"
echo "# Nexus Core Entity" > "$TEST_MIG_WS/wiki/entities/nexus-entity.md"
echo "# Payment Invoice Service" > "$TEST_MIG_WS/wiki/sources/payment-svc/invoice.md"
echo "# Old Concept" > "$TEST_MIG_WS/wiki/concepts/old.md"
echo "# Old Repo" > "$TEST_MIG_WS/wiki/repos/old.md"
echo "stale hot cache" > "$TEST_MIG_WS/wiki/hot.md"
echo "stale _index.md" > "$TEST_MIG_WS/wiki/_index.md"
echo "- **2024-01-01** | \`legacy\` | Historical audit log entry" > "$TEST_MIG_WS/wiki/_log.md"

# Run lint to auto-heal and purge
(cd "$TEST_MIG_WS" && ./rnex plugin karpathy-llm lint >/dev/null)

# Verify all legacy directories and files are purged
[ ! -d "$TEST_MIG_WS/wiki/overview" ] || { fail "legacy overview/ was not deleted"; exit 1; }
[ ! -d "$TEST_MIG_WS/wiki/entities" ] || { fail "legacy entities/ was not deleted"; exit 1; }
[ ! -d "$TEST_MIG_WS/wiki/sources" ] || { fail "legacy sources/ was not deleted"; exit 1; }
[ ! -d "$TEST_MIG_WS/wiki/concepts" ] || { fail "legacy concepts/ was not deleted"; exit 1; }
[ ! -d "$TEST_MIG_WS/wiki/repos" ] || { fail "legacy repos/ was not deleted"; exit 1; }
[ ! -d "$TEST_MIG_WS/wiki/_graph" ] || { fail "legacy _graph/ was not deleted"; exit 1; }
[ ! -d "$TEST_MIG_WS/wiki/_index" ] || { fail "legacy _index/ was not deleted"; exit 1; }
[ ! -e "$TEST_MIG_WS/wiki/hot.md" ] || { fail "legacy hot.md was not deleted"; exit 1; }
[ ! -e "$TEST_MIG_WS/wiki/_index.md" ] || { fail "legacy _index.md was not deleted"; exit 1; }
[ ! -e "$TEST_MIG_WS/wiki/_log.md" ] || { fail "legacy _log.md was not deleted"; exit 1; }

# Verify valid index.md compiled directly under wiki/
[ -f "$TEST_MIG_WS/wiki/index.md" ] || { fail "wiki/index.md missing after migration"; exit 1; }

# Verify _log.md was migrated to log.md and historical entries preserved
[ -f "$TEST_MIG_WS/wiki/log.md" ] || { fail "wiki/log.md missing after migration"; exit 1; }
grep -q 'Historical audit log entry' "$TEST_MIG_WS/wiki/log.md" || { fail "Historical log entry missing from migrated wiki/log.md"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 10: Strict Linting on Structure, Index Bounds, and Invariant Verification
# --------------------------------------------------------------------------
run_test "Karpathy-llm: strict linting enforces root router bounds, zero symlinks, and auto-healing"
TEST_STRICT_WS="$TEST_TMP/karpathy-strict-ws"
mkdir -p "$TEST_STRICT_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_STRICT_WS"
cd "$TEST_STRICT_WS"
"$TEST_STRICT_WS/rnex" init -y --karpathy "$TEST_STRICT_WS" >/dev/null

# Clean lint must succeed
(cd "$TEST_STRICT_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "Initial clean lint failed"; exit 1;
}

# Test root router bound violation rejection
cat <<'EOF_STRICT_CFG' > "$TEST_STRICT_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    btree_root_max_lines: 2
repos:
EOF_STRICT_CFG

_bound_err=0
(cd "$TEST_STRICT_WS" && ./rnex plugin karpathy-llm lint >/dev/null 2>&1) || _bound_err=1
[ "$_bound_err" -eq 1 ] || { fail "lint did not exit non-zero when index.md exceeded btree_root_max_lines"; exit 1; }

# Restore proper line bounds and verify lint passes
cat <<'EOF_STRICT_CFG2' > "$TEST_STRICT_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    btree_root_max_lines: 80
repos:
EOF_STRICT_CFG2

(cd "$TEST_STRICT_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "lint failed after restoring valid btree_root_max_lines"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 11: User Skill Projection and Disable Cleanup
# --------------------------------------------------------------------------
run_test "Karpathy-llm: user skill projection with synthetic provider and disable unregistration"
mkdir -p "$TEST_KARPATHY_WS/plugins/mock-provider"
cat <<'EOF_MOCK' > "$TEST_KARPATHY_WS/plugins/mock-provider/plugin.yaml"
name: mock-provider
version: 1.0.0
description: Mock AI provider for user skill projection testing
skill_dir: .mock/skills
config_defaults:
  skills: true
EOF_MOCK

(cd "$TEST_KARPATHY_WS" && ./rnex plugin enable mock-provider >/dev/null)
(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)

_usk_ingest="$TEST_KARPATHY_WS/.mock/skills/rnex-karpathy-llm-wiki-ingest/SKILL.md"
_usk_lint="$TEST_KARPATHY_WS/.mock/skills/rnex-karpathy-llm-wiki-lint/SKILL.md"
[ -f "$_usk_ingest" ] || { fail "rnex-karpathy-llm-wiki-ingest missing in .mock/skills/"; exit 1; }
[ -f "$_usk_lint" ] || { fail "rnex-karpathy-llm-wiki-lint missing in .mock/skills/"; exit 1; }
grep -q "name: rnex-karpathy-llm-wiki-ingest" "$_usk_ingest" || { fail "User skill missing YAML frontmatter name"; exit 1; }
grep -q "\.rnex/plugins/karpathy-llm/skills/wiki-ingest\.md" "$_usk_ingest" || { fail "User skill target pointer incorrect"; exit 1; }
grep -q "\.rnex/plugins/karpathy-llm/skills/wiki-lint\.md" "$_usk_lint" || { fail "User skill target pointer incorrect"; exit 1; }

# Disable karpathy-llm: verify plugin user skills cleaned up, scoped dir cleaned up, but wiki files preserved
(cd "$TEST_KARPATHY_WS" && ./rnex plugin disable karpathy-llm >/dev/null)
[ ! -d "$TEST_KARPATHY_WS/.mock/skills/rnex-karpathy-llm-wiki-ingest" ] || { fail "User skill not removed on disable"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/.mock/skills/rnex-karpathy-llm-wiki-lint" ] || { fail "User skill not removed on disable"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm" ] || { fail ".rnex/plugins/karpathy-llm not removed on disable"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/index.md" ] || { fail "wiki/index.md was deleted on disable"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/wiki/hot.md" ] || { fail "wiki/hot.md exists after disable"; exit 1; }

# Re-enable karpathy-llm for subsequent tests and clean up mock provider
(cd "$TEST_KARPATHY_WS" && ./rnex plugin enable karpathy-llm >/dev/null)
(cd "$TEST_KARPATHY_WS" && ./rnex plugin disable mock-provider >/dev/null)
rm -rf "$TEST_KARPATHY_WS/plugins/mock-provider" "$TEST_KARPATHY_WS/.mock"
pass

# --------------------------------------------------------------------------
# Test 12: Configurable wiki_dir and Leaked Placeholder Purge
# --------------------------------------------------------------------------
run_test "Karpathy-llm: configurable wiki_dir and leaked placeholder directory cleanup"
cat <<'EOF_CFG' > "$TEST_KARPATHY_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: docs/wiki
    sources: [intake/raw]
repos:
EOF_CFG

# Simulate pre-existing leaked bogus placeholder directories in workspace root
mkdir -p "$TEST_KARPATHY_WS/\"{wiki_dir}" "$TEST_KARPATHY_WS/\"{raw_dir}" "$TEST_KARPATHY_WS/{wiki_dir}" "$TEST_KARPATHY_WS/{raw_dir}"

(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)

[ -d "$TEST_KARPATHY_WS/docs/wiki" ] || { fail "Custom docs/wiki directory was not created"; exit 1; }
[ -d "$TEST_KARPATHY_WS/intake/raw" ] || { fail "Custom intake/raw directory was not created"; exit 1; }
[ -f "$TEST_KARPATHY_WS/docs/wiki/index.md" ] || { fail "docs/wiki/index.md missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/docs/wiki/log.md" ] || { fail "docs/wiki/log.md missing"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/docs/wiki/_index" ] || { fail "docs/wiki/_index should not exist"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/docs/wiki/_graph" ] || { fail "docs/wiki/_graph should not exist"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/docs/wiki/_index.md" ] || { fail "docs/wiki/_index.md should not exist"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/docs/wiki/_log.md" ] || { fail "docs/wiki/_log.md should not exist"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/docs/wiki/hot.md" ] || { fail "docs/wiki/hot.md found in custom wiki"; exit 1; }

# Verify bogus directories were purged by sync
[ ! -d "$TEST_KARPATHY_WS/\"{wiki_dir}" ] || { fail "Bogus directory \"{wiki_dir} still exists"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/\"{raw_dir}" ] || { fail "Bogus directory \"{raw_dir} still exists"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/{wiki_dir}" ] || { fail "Bogus directory {wiki_dir} still exists"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/{raw_dir}" ] || { fail "Bogus directory {raw_dir} still exists"; exit 1; }

# Reset configuration back to standard wiki
cat <<'EOF_CFG_RESET' > "$TEST_KARPATHY_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    sources: [docs]
repos:
EOF_CFG_RESET
(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)
pass

# --------------------------------------------------------------------------
# Test 13: Member Repository In-Place Ingestion (Zero Copying into wiki/)
# --------------------------------------------------------------------------
run_test "Karpathy-llm: member repository in-place ingestion (zero copying into wiki/)"
TEST_REPO_WS="$TEST_TMP/karpathy-repo-ws"
mkdir -p "$TEST_REPO_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_REPO_WS"
cd "$TEST_REPO_WS"

mkdir -p "$TEST_REPO_WS/repos/auth-svc"
printf '# Auth Service\nAuthentication and authorization microservice.\n' > "$TEST_REPO_WS/repos/auth-svc/README.md"

cat <<'EOF_REPO_CFG' > "$TEST_REPO_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
repos:
  auth-svc:
EOF_REPO_CFG

"$TEST_REPO_WS/rnex" init -y --karpathy "$TEST_REPO_WS" >/dev/null
(cd "$TEST_REPO_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Verify member repo shard was compiled directly in wiki/
[ -f "$TEST_REPO_WS/wiki/repos-auth-svc.md" ] || {
  fail "wiki/repos-auth-svc.md missing after ingest"; exit 1;
}
grep -q 'auth-svc' "$TEST_REPO_WS/wiki/repos-auth-svc.md" || {
  fail "auth-svc missing from shard repos-auth-svc.md"; exit 1;
}
grep -q 'repos/auth-svc/README\.md' "$TEST_REPO_WS/wiki/repos-auth-svc.md" || {
  fail "repos/auth-svc/README.md missing from shard repos-auth-svc.md"; exit 1;
}

# Verify NO files were copied into wiki/
[ ! -d "$TEST_REPO_WS/wiki/repos" ] || {
  fail "Redundant wiki/repos directory created!"; exit 1;
}
[ ! -f "$TEST_REPO_WS/wiki/repo-auth-svc.md" ] || {
  fail "Legacy wiki/repo-auth-svc.md created!"; exit 1;
}
[ ! -d "$TEST_REPO_WS/wiki/_graph" ] || {
  fail "wiki/_graph created!"; exit 1;
}
[ ! -d "$TEST_REPO_WS/wiki/_index" ] || {
  fail "wiki/_index created!"; exit 1;
}

# Verify disabled member repos are not ingested
mkdir -p "$TEST_REPO_WS/repos/disabled-repo"
printf '# Disabled Repo\n' > "$TEST_REPO_WS/repos/disabled-repo/README.md"
cat <<'EOF_DIS' >> "$TEST_REPO_WS/rnex.yaml"
  disabled-repo:
    enabled: false
EOF_DIS
(cd "$TEST_REPO_WS" && ./rnex sync -y >/dev/null)
(cd "$TEST_REPO_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)
! grep -q 'disabled-repo' "$TEST_REPO_WS/wiki/index.md" || {
  fail "Disabled repository was indexed in wiki/index.md"; exit 1;
}
[ ! -f "$TEST_REPO_WS/wiki/repos-disabled-repo.md" ] || {
  fail "Disabled repository shard was created"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 14: Recursive Globstar Ingestion (repos/**/README.md) & Exclusion of Unmatched Docs
# --------------------------------------------------------------------------
run_test "Karpathy-llm: recursive globstar discovery (repos/**/README.md) and member docs exclusion"
TEST_GLOB_WS="$TEST_TMP/karpathy-glob-ws"
mkdir -p "$TEST_GLOB_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_GLOB_WS"
cd "$TEST_GLOB_WS"

mkdir -p "$TEST_GLOB_WS/repos/backend/docs" "$TEST_GLOB_WS/repos/frontend/docs"
mkdir -p "$TEST_GLOB_WS/repos/backend/apps/test-app" "$TEST_GLOB_WS/repos/backend/apps/other-app"
printf '# Backend Service\nBackend API service.\n' > "$TEST_GLOB_WS/repos/backend/README.md"
printf '# Backend Architecture\nInternal architecture doc.\n' > "$TEST_GLOB_WS/repos/backend/docs/architecture.md"
printf '# Test App\nNested test app component.\n' > "$TEST_GLOB_WS/repos/backend/apps/test-app/README.md"
printf '# Other App\nNested other app component.\n' > "$TEST_GLOB_WS/repos/backend/apps/other-app/README.md"
printf '# Frontend Client\nFrontend web client.\n' > "$TEST_GLOB_WS/repos/frontend/README.md"
printf '# Frontend Setup\nInternal setup doc.\n' > "$TEST_GLOB_WS/repos/frontend/docs/setup.md"

cat <<'EOF_GLOB_CFG' > "$TEST_GLOB_WS/rnex.yaml"
version: 1.0.0
sources:
  - "repos/**/README.md"
plugins:
  karpathy-llm:
repos:
  backend:
  frontend:
EOF_GLOB_CFG

"$TEST_GLOB_WS/rnex" init -y --karpathy "$TEST_GLOB_WS" >/dev/null
(cd "$TEST_GLOB_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Verify flat B-Tree shards were compiled for backend, frontend, and backend apps directly under wiki/
[ -f "$TEST_GLOB_WS/wiki/repos-backend.md" ] || { fail "repos-backend.md shard missing"; exit 1; }
[ -f "$TEST_GLOB_WS/wiki/repos-frontend.md" ] || { fail "repos-frontend.md shard missing"; exit 1; }
[ -f "$TEST_GLOB_WS/wiki/repos-backend-apps.md" ] || { fail "repos-backend-apps.md shard missing"; exit 1; }
[ ! -d "$TEST_GLOB_WS/wiki/_index" ] || { fail "wiki/_index should not exist"; exit 1; }
[ ! -d "$TEST_GLOB_WS/wiki/_graph" ] || { fail "wiki/_graph should not exist"; exit 1; }

# Verify nested READMEs appear in sub-scope shard
grep -q 'test-app' "$TEST_GLOB_WS/wiki/repos-backend-apps.md" || {
  fail "repos-backend-apps.md missing link to test-app: $(cat "$TEST_GLOB_WS/wiki/repos-backend-apps.md")"; exit 1;
}
grep -q 'other-app' "$TEST_GLOB_WS/wiki/repos-backend-apps.md" || {
  fail "repos-backend-apps.md missing link to other-app: $(cat "$TEST_GLOB_WS/wiki/repos-backend-apps.md")"; exit 1;
}

# Verify unconfigured member docs were NOT ingested
! grep -q 'architecture' "$TEST_GLOB_WS/wiki/index.md" || {
  fail "Unexpected member docs (architecture.md) was indexed into wiki/index.md"; exit 1;
}
! grep -q 'setup' "$TEST_GLOB_WS/wiki/index.md" || {
  fail "Unexpected member docs (setup.md) was indexed into wiki/index.md"; exit 1;
}
[ ! -f "$TEST_GLOB_WS/wiki/repos-backend-docs.md" ] || {
  fail "Unexpected repos-backend-docs.md shard was created"; exit 1;
}

# Verify root router index.md references all three shards
grep -q 'repos-backend\.md' "$TEST_GLOB_WS/wiki/index.md" || { fail "repos-backend.md missing from wiki/index.md"; exit 1; }
grep -q 'repos-frontend\.md' "$TEST_GLOB_WS/wiki/index.md" || { fail "repos-frontend.md missing from wiki/index.md"; exit 1; }
grep -q 'repos-backend-apps\.md' "$TEST_GLOB_WS/wiki/index.md" || { fail "repos-backend-apps.md missing from wiki/index.md"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
