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
grep -q 'wiki_dir: "\.rnex/wiki"' "$_yaml_file" || { fail "wiki_dir default missing in plugin.yaml"; exit 1; }
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
run_test "Karpathy-llm: zero symlinks in .rnex/wiki/ and zero symbolic links in plugin implementation"
# Assert no symlinks anywhere in .rnex/wiki/
_symlinks="$(find "$TEST_KARPATHY_WS/.rnex/wiki" -type l 2>/dev/null || true)"
[ -z "$_symlinks" ] || { fail "Forbidden symlinks found in wiki: $_symlinks"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/wiki" ] || { fail "Legacy ./wiki directory must not be created"; exit 1; }

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
run_test "Karpathy-llm: 100% configured sources coverage directly in flat .rnex/wiki/ shards"
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

# Verify flat B-Tree shards were created directly under .rnex/wiki/
[ -f "$TEST_COV_WS/.rnex/wiki/repo-nexus.md" ] || { fail ".rnex/wiki/repo-nexus.md missing"; exit 1; }
[ -f "$TEST_COV_WS/.rnex/wiki/repo-nexus-docs.md" ] || { fail ".rnex/wiki/repo-nexus-docs.md missing"; exit 1; }
[ -f "$TEST_COV_WS/.rnex/wiki/repos-service-a.md" ] || { fail ".rnex/wiki/repos-service-a.md missing"; exit 1; }
[ -f "$TEST_COV_WS/.rnex/wiki/repos-service-a-docs.md" ] || { fail ".rnex/wiki/repos-service-a-docs.md missing"; exit 1; }
[ -f "$TEST_COV_WS/.rnex/wiki/index.md" ] || { fail ".rnex/wiki/index.md missing"; exit 1; }
[ -f "$TEST_COV_WS/.rnex/wiki/log.md" ] || { fail ".rnex/wiki/log.md missing"; exit 1; }

# Verify indexed content in flat leaf shards
grep -qi 'readme' "$TEST_COV_WS/.rnex/wiki/repo-nexus.md" || { fail "README missing in repo-nexus.md"; exit 1; }
grep -qi 'agents' "$TEST_COV_WS/.rnex/wiki/repo-nexus.md" || { fail "AGENTS missing in repo-nexus.md"; exit 1; }
grep -qi 'architecture' "$TEST_COV_WS/.rnex/wiki/repo-nexus-docs.md" || { fail "architecture missing in repo-nexus-docs.md"; exit 1; }
grep -qi 'readme' "$TEST_COV_WS/.rnex/wiki/repos-service-a.md" || { fail "service-a README missing in repos-service-a.md"; exit 1; }
grep -qi 'api' "$TEST_COV_WS/.rnex/wiki/repos-service-a-docs.md" || { fail "service-a api missing in repos-service-a-docs.md"; exit 1; }

# Negative assertions: zero legacy ./wiki, zero graph, zero _index wrapper
[ ! -d "$TEST_COV_WS/wiki" ] || { fail "legacy ./wiki exists"; exit 1; }
[ ! -d "$TEST_COV_WS/.rnex/wiki/_graph" ] || { fail "wiki/_graph exists"; exit 1; }
[ ! -d "$TEST_COV_WS/.rnex/wiki/_index" ] || { fail "wiki/_index exists"; exit 1; }
[ ! -e "$TEST_COV_WS/.rnex/wiki/_index.md" ] || { fail "wiki/_index.md exists"; exit 1; }
[ ! -e "$TEST_COV_WS/.rnex/wiki/_log.md" ] || { fail "wiki/_log.md exists"; exit 1; }
[ ! -e "$TEST_COV_WS/.rnex/wiki/hot.md" ] || { fail "wiki/hot.md exists"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 5: Flat B-Tree Index Validation, Entry Formatting, and Zero TSV Tables
# --------------------------------------------------------------------------
run_test "Karpathy-llm: flat B-Tree entry formatting, root router links, and zero TSV tables"
# Verify root index.md table entries link to flat shards
grep -q 'repo-nexus\.md' "$TEST_COV_WS/.rnex/wiki/index.md" || { fail "repo-nexus.md missing from wiki/index.md table"; exit 1; }
grep -q 'repos-service-a\.md' "$TEST_COV_WS/.rnex/wiki/index.md" || { fail "repos-service-a.md missing from wiki/index.md table"; exit 1; }
grep -q 'repos-service-a-docs\.md' "$TEST_COV_WS/.rnex/wiki/index.md" || { fail "repos-service-a-docs.md missing from wiki/index.md table"; exit 1; }

# Verify entry line format: - **[<title>](<rel_link>)** (`<rel_path>`) — <summary>
grep -q '^- \*\*\[.*\](.*)\*\* (`README\.md`) — ' "$TEST_COV_WS/.rnex/wiki/repo-nexus.md" || {
  fail "repo-nexus.md entry formatting invalid: $(cat "$TEST_COV_WS/.rnex/wiki/repo-nexus.md")"; exit 1;
}

# Verify audit log contains ingest entry for actual updates
[ -s "$TEST_COV_WS/.rnex/wiki/log.md" ] || { fail "wiki/log.md is empty"; exit 1; }
grep -q '`ingest`' "$TEST_COV_WS/.rnex/wiki/log.md" || { fail "wiki/log.md missing ingest entry"; exit 1; }

# Record log checksum before idempotent ingest and lint
_log_cksum_before="$(cksum "$TEST_COV_WS/.rnex/wiki/log.md")"

# Re-run ingest with zero missing sources — must NOT update log.md
(cd "$TEST_COV_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)
_log_cksum_after_ingest="$(cksum "$TEST_COV_WS/.rnex/wiki/log.md")"
[ "$_log_cksum_before" = "$_log_cksum_after_ingest" ] || {
  fail "ingest modified log.md when zero new sources were ingested"; exit 1;
}

# Run lint — read-only verification must NOT update log.md
(cd "$TEST_COV_WS" && ./rnex plugin karpathy-llm lint >/dev/null)
_log_cksum_after_lint="$(cksum "$TEST_COV_WS/.rnex/wiki/log.md")"
[ "$_log_cksum_before" = "$_log_cksum_after_lint" ] || {
  fail "lint modified log.md when no wiki updates occurred"; exit 1;
}

# Assert ZERO TSV property graph files exist anywhere in wiki/
_tsv_files="$(find "$TEST_COV_WS/.rnex/wiki" -name "*.tsv" 2>/dev/null || true)"
[ -z "$_tsv_files" ] || { fail "Found TSV graph files in wiki: $_tsv_files"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 6: Zero wiki/concepts & wiki/repos Directories; repo-nexus Shard Naming
# --------------------------------------------------------------------------
run_test "Karpathy-llm: zero wiki/concepts & wiki/repos; primary shard is repo-nexus; index.md <= 80 lines"
[ ! -d "$TEST_COV_WS/.rnex/wiki/concepts" ] || { fail "Redundant wiki/concepts directory exists"; exit 1; }
[ ! -d "$TEST_COV_WS/.rnex/wiki/repos" ] || { fail "Redundant wiki/repos directory exists"; exit 1; }
[ ! -f "$TEST_COV_WS/.rnex/wiki/concepts.md" ] || { fail "Legacy concepts.md shard exists"; exit 1; }
[ ! -f "$TEST_COV_WS/.rnex/wiki/_index/concepts.md" ] || { fail "Legacy _index/concepts.md shard exists"; exit 1; }
[ -f "$TEST_COV_WS/.rnex/wiki/repo-nexus.md" ] || { fail "wiki/repo-nexus.md shard missing"; exit 1; }

# Verify wiki/index.md is <= 80 lines
_root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$TEST_COV_WS/.rnex/wiki/index.md")"
[ "$_root_lines" -le 80 ] || { fail "wiki/index.md exceeded 80 lines: $_root_lines"; exit 1; }

# Negative assertions: legacy files and folders must NOT exist
[ ! -e "$TEST_COV_WS/.rnex/wiki/_index.md" ] || { fail "legacy wiki/_index.md exists"; exit 1; }
[ ! -e "$TEST_COV_WS/.rnex/wiki/_log.md" ] || { fail "legacy wiki/_log.md exists"; exit 1; }
[ ! -e "$TEST_COV_WS/.rnex/wiki/hot.md" ] || { fail "legacy wiki/hot.md exists"; exit 1; }
[ ! -d "$TEST_COV_WS/.rnex/wiki/overview" ] || { fail "legacy wiki/overview/ exists"; exit 1; }
[ ! -d "$TEST_COV_WS/.rnex/wiki/entities" ] || { fail "legacy wiki/entities/ exists"; exit 1; }
[ ! -d "$TEST_COV_WS/.rnex/wiki/sources" ] || { fail "legacy wiki/sources/ exists"; exit 1; }
[ ! -d "$TEST_COV_WS/.rnex/wiki/_graph" ] || { fail "legacy wiki/_graph/ exists"; exit 1; }
[ ! -d "$TEST_COV_WS/.rnex/wiki/_index" ] || { fail "legacy wiki/_index/ exists"; exit 1; }

# Root router has Repo Nexus section and Member Repository section
grep -q 'Repo Nexus' "$TEST_COV_WS/.rnex/wiki/index.md" || { fail "Repo Nexus section missing in index.md"; exit 1; }
grep -q 'Member Repository' "$TEST_COV_WS/.rnex/wiki/index.md" || { fail "Member Repository section missing in index.md"; exit 1; }
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

# Create 8 documentation notes under docs/ to exceed the split threshold of 5 (4 in a-m, 4 in n-z)
mkdir -p "$TEST_BTREE_WS/docs"
for _cname in "auth-tokens" "caching" "encryption" "jwt" "networking" "queues" "routing" "security"; do
  cat <<EOF_C > "$TEST_BTREE_WS/docs/${_cname}.md"
# ${_cname}
Detailed explanation of ${_cname} architecture.
EOF_C
done

# Run ingest to compile and split B-Tree shards, then lint to verify integrity
(cd "$TEST_BTREE_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)
(cd "$TEST_BTREE_WS" && ./rnex plugin karpathy-llm lint >/dev/null)

# Verify repo-nexus-docs shard split into a-m and n-z sub-shards directly in wiki/
[ -f "$TEST_BTREE_WS/wiki/repo-nexus-docs-a-m.md" ] || { fail "repo-nexus-docs-a-m.md missing after split"; exit 1; }
[ -f "$TEST_BTREE_WS/wiki/repo-nexus-docs-n-z.md" ] || { fail "repo-nexus-docs-n-z.md missing after split"; exit 1; }
[ ! -d "$TEST_BTREE_WS/wiki/_index" ] || { fail "wiki/_index directory should not exist"; exit 1; }

# Verify sorted contents in each shard
grep -q "auth-tokens" "$TEST_BTREE_WS/wiki/repo-nexus-docs-a-m.md" || { fail "auth-tokens missing from repo-nexus-docs-a-m.md"; exit 1; }
grep -q "jwt" "$TEST_BTREE_WS/wiki/repo-nexus-docs-a-m.md" || { fail "jwt missing from repo-nexus-docs-a-m.md"; exit 1; }
grep -q "networking" "$TEST_BTREE_WS/wiki/repo-nexus-docs-n-z.md" || { fail "networking missing from repo-nexus-docs-n-z.md"; exit 1; }
grep -q "queues" "$TEST_BTREE_WS/wiki/repo-nexus-docs-n-z.md" || { fail "queues missing from repo-nexus-docs-n-z.md"; exit 1; }

# Verify B-Tree Root routing table reflects sub-shards and is bounded (<= 80 lines)
_bt_root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$TEST_BTREE_WS/wiki/index.md")"
[ "$_bt_root_lines" -le 80 ] || { fail "Root index.md exceeded 80 lines: $_bt_root_lines"; exit 1; }
grep -q 'repo-nexus-docs-a-m' "$TEST_BTREE_WS/wiki/index.md" || { fail "repo-nexus-docs-a-m missing from root router table"; exit 1; }
grep -q 'repo-nexus-docs-n-z' "$TEST_BTREE_WS/wiki/index.md" || { fail "repo-nexus-docs-n-z missing from root router table"; exit 1; }
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

# Test Case 4: Batch fallback when no file argument is passed
(cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)
grep -q 'doc-c' "$TEST_SF_WS/wiki/repo-nexus-raw.md" || { fail "doc-c missing from repo-nexus-raw.md after batch ingest"; exit 1; }
[ ! -e "$TEST_SF_WS/wiki/hot.md" ] || { fail "hot.md found in single-file test workspace"; exit 1; }
[ -z "$(find "$TEST_SF_WS/wiki" -type l 2>/dev/null || true)" ] || { fail "symlinks found in single-file workspace"; exit 1; }
[ ! -d "$TEST_SF_WS/wiki/_graph" ] || { fail "wiki/_graph found in single-file workspace"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 9: Standalone linting detects missing files, broken links, orphan shards, and sort violations
# --------------------------------------------------------------------------
run_test "Karpathy-llm: standalone linting detects missing files, broken links, orphan shards, and sort violations"
TEST_LINT_WS="$TEST_TMP/karpathy-lint-det-ws"
mkdir -p "$TEST_LINT_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_LINT_WS"
cd "$TEST_LINT_WS"
"$TEST_LINT_WS/rnex" init -y --karpathy "$TEST_LINT_WS" >/dev/null

mkdir -p "$TEST_LINT_WS/docs"
printf '# Doc One\nContent one.\n' > "$TEST_LINT_WS/docs/one.md"
printf '# Doc Two\nContent two.\n' > "$TEST_LINT_WS/docs/two.md"

cat <<'EOF_LINT_CFG' > "$TEST_LINT_WS/rnex.yaml"
version: 1.0.0
sources: [docs]
plugins:
  karpathy-llm:
repos:
EOF_LINT_CFG

(cd "$TEST_LINT_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# 1. Clean lint passes and does NOT mutate log.md
_log_init_sum="$(cksum < "$TEST_LINT_WS/.rnex/wiki/log.md")"
(cd "$TEST_LINT_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "Initial clean lint failed"; exit 1;
}
_log_after_clean="$(cksum < "$TEST_LINT_WS/.rnex/wiki/log.md")"
[ "$_log_init_sum" = "$_log_after_clean" ] || { fail "Clean lint unexpectedly mutated log.md"; exit 1; }

# 2. Orphan shard auto-healing
touch "$TEST_LINT_WS/.rnex/wiki/repo-nexus-orphan.md"
(cd "$TEST_LINT_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "Lint failed to auto-heal orphan shard"; exit 1;
}
grep -q "repo-nexus-orphan.md" "$TEST_LINT_WS/.rnex/wiki/index.md" || {
  fail "Orphan shard was not integrated into index.md by lint"; exit 1;
}
_log_after_orphan="$(cksum < "$TEST_LINT_WS/.rnex/wiki/log.md")"
[ "$_log_after_clean" != "$_log_after_orphan" ] || { fail "log.md was not mutated after orphan healing"; exit 1; }

# 3. Missing workspace document reference auto-healing (pruned)
printf -- '- **[Missing](../../docs/nonexistent.md)** (`docs/nonexistent.md`) — Broken.\n' >> "$TEST_LINT_WS/.rnex/wiki/repo-nexus-docs.md"
(cd "$TEST_LINT_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "Lint failed on dead workspace reference"; exit 1;
}
! grep -q "nonexistent.md" "$TEST_LINT_WS/.rnex/wiki/repo-nexus-docs.md" || {
  fail "Dead workspace reference was not pruned by lint"; exit 1;
}
_log_after_prune="$(cksum < "$TEST_LINT_WS/.rnex/wiki/log.md")"
[ "$_log_after_orphan" != "$_log_after_prune" ] || { fail "log.md was not mutated after reference pruning"; exit 1; }

# 4. Out-of-order catalog entries auto-healing
printf '# Wiki Index Shard: repo-nexus-docs\n\n- **[Zebra](../../docs/two.md)** (`docs/two.md`) — Two.\n- **[Alpha](../../docs/one.md)** (`docs/one.md`) — One.\n' > "$TEST_LINT_WS/.rnex/wiki/repo-nexus-docs.md"
(cd "$TEST_LINT_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "Lint failed to re-sort unsorted entries"; exit 1;
}
# Verify entries in repo-nexus-docs.md are now sorted
LC_ALL=C grep '^- \*\*' "$TEST_LINT_WS/.rnex/wiki/repo-nexus-docs.md" > "$TEST_LINT_WS/sorted.tmp"
LC_ALL=C sort -c "$TEST_LINT_WS/sorted.tmp" || { fail "Entries not in LC_ALL=C sort order after lint"; exit 1; }
rm -f "$TEST_LINT_WS/sorted.tmp"
_log_after_sort="$(cksum < "$TEST_LINT_WS/.rnex/wiki/log.md")"
[ "$_log_after_prune" != "$_log_after_sort" ] || { fail "log.md was not mutated after sort healing"; exit 1; }

# 5. Subsequent clean run does NOT mutate log.md
(cd "$TEST_LINT_WS" && ./rnex plugin karpathy-llm lint >/dev/null)
_log_final="$(cksum < "$TEST_LINT_WS/.rnex/wiki/log.md")"
[ "$_log_after_sort" = "$_log_final" ] || { fail "Subsequent clean lint mutated log.md"; exit 1; }
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
(cd "$TEST_STRICT_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Clean lint must succeed
(cd "$TEST_STRICT_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "Initial clean lint failed"; exit 1;
}

# Test root router bound violation rejection
cat <<'EOF_STRICT_CFG' > "$TEST_STRICT_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
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
[ -f "$TEST_KARPATHY_WS/.rnex/wiki/index.md" ] || { fail ".rnex/wiki/index.md was deleted on disable"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/.rnex/wiki/hot.md" ] || { fail "hot.md exists after disable"; exit 1; }

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
mkdir -p "$TEST_KARPATHY_WS/intake/raw"
printf '# Raw Doc\nRaw content.\n' > "$TEST_KARPATHY_WS/intake/raw/doc.md"

(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)
(cd "$TEST_KARPATHY_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

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
run_test "Karpathy-llm: member repository in-place ingestion (zero copying into .rnex/wiki/)"
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

# Verify member repo shard was compiled directly in .rnex/wiki/
[ -f "$TEST_REPO_WS/.rnex/wiki/repos-auth-svc.md" ] || {
  fail ".rnex/wiki/repos-auth-svc.md missing after ingest"; exit 1;
}
grep -q 'auth-svc' "$TEST_REPO_WS/.rnex/wiki/repos-auth-svc.md" || {
  fail "auth-svc missing from shard repos-auth-svc.md"; exit 1;
}
grep -q 'repos/auth-svc/README\.md' "$TEST_REPO_WS/.rnex/wiki/repos-auth-svc.md" || {
  fail "repos/auth-svc/README.md missing from shard repos-auth-svc.md"; exit 1;
}

# Verify NO files were copied into wiki/
[ ! -d "$TEST_REPO_WS/.rnex/wiki/repos" ] || {
  fail "Redundant wiki/repos directory created!"; exit 1;
}
[ ! -d "$TEST_REPO_WS/wiki" ] || {
  fail "Legacy ./wiki directory created!"; exit 1;
}
[ ! -f "$TEST_REPO_WS/.rnex/wiki/repo-auth-svc.md" ] || {
  fail "Legacy repo-auth-svc.md created!"; exit 1;
}
[ ! -d "$TEST_REPO_WS/.rnex/wiki/_graph" ] || {
  fail "wiki/_graph created!"; exit 1;
}
[ ! -d "$TEST_REPO_WS/.rnex/wiki/_index" ] || {
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
! grep -q 'disabled-repo' "$TEST_REPO_WS/.rnex/wiki/index.md" || {
  fail "Disabled repository was indexed in wiki/index.md"; exit 1;
}
[ ! -f "$TEST_REPO_WS/.rnex/wiki/repos-disabled-repo.md" ] || {
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

# Verify flat B-Tree shards were compiled for backend, frontend, and backend apps directly under .rnex/wiki/
[ -f "$TEST_GLOB_WS/.rnex/wiki/repos-backend.md" ] || { fail "repos-backend.md shard missing"; exit 1; }
[ -f "$TEST_GLOB_WS/.rnex/wiki/repos-frontend.md" ] || { fail "repos-frontend.md shard missing"; exit 1; }
[ -f "$TEST_GLOB_WS/.rnex/wiki/repos-backend-apps.md" ] || { fail "repos-backend-apps.md shard missing"; exit 1; }
[ ! -d "$TEST_GLOB_WS/.rnex/wiki/_index" ] || { fail "wiki/_index should not exist"; exit 1; }
[ ! -d "$TEST_GLOB_WS/.rnex/wiki/_graph" ] || { fail "wiki/_graph should not exist"; exit 1; }

# Verify nested READMEs appear in sub-scope shard
grep -q 'test-app' "$TEST_GLOB_WS/.rnex/wiki/repos-backend-apps.md" || {
  fail "repos-backend-apps.md missing link to test-app: $(cat "$TEST_GLOB_WS/.rnex/wiki/repos-backend-apps.md")"; exit 1;
}
grep -q 'other-app' "$TEST_GLOB_WS/.rnex/wiki/repos-backend-apps.md" || {
  fail "repos-backend-apps.md missing link to other-app: $(cat "$TEST_GLOB_WS/.rnex/wiki/repos-backend-apps.md")"; exit 1;
}

# Verify unconfigured member docs were NOT ingested
! grep -q 'architecture' "$TEST_GLOB_WS/.rnex/wiki/index.md" || {
  fail "Unexpected member docs (architecture.md) was indexed into wiki/index.md"; exit 1;
}
! grep -q 'setup' "$TEST_GLOB_WS/.rnex/wiki/index.md" || {
  fail "Unexpected member docs (setup.md) was indexed into wiki/index.md"; exit 1;
}
[ ! -f "$TEST_GLOB_WS/.rnex/wiki/repos-backend-docs.md" ] || {
  fail "Unexpected repos-backend-docs.md shard was created"; exit 1;
}

# Verify root router index.md references all three shards
grep -q 'repos-backend\.md' "$TEST_GLOB_WS/.rnex/wiki/index.md" || { fail "repos-backend.md missing from wiki/index.md"; exit 1; }
grep -q 'repos-frontend\.md' "$TEST_GLOB_WS/.rnex/wiki/index.md" || { fail "repos-frontend.md missing from wiki/index.md"; exit 1; }
grep -q 'repos-backend-apps\.md' "$TEST_GLOB_WS/.rnex/wiki/index.md" || { fail "repos-backend-apps.md missing from wiki/index.md"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 15: Missing-sources-only ingestion preserves custom summaries
# --------------------------------------------------------------------------
run_test "Karpathy-llm: missing-sources-only ingestion preserves custom summaries"
TEST_MISSING_WS="$TEST_TMP/karpathy-missing-ws"
mkdir -p "$TEST_MISSING_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_MISSING_WS"
cd "$TEST_MISSING_WS"

mkdir -p "$TEST_MISSING_WS/docs"
printf '# Nexus Readme\nRoot overview.\n' > "$TEST_MISSING_WS/README.md"
cat <<'EOF_MISS_YAML' > "$TEST_MISSING_WS/rnex.yaml"
version: 1.0.0
sources: [README.md, docs]
plugins:
  karpathy-llm:
repos:
EOF_MISS_YAML

"$TEST_MISSING_WS/rnex" init -y --karpathy "$TEST_MISSING_WS" >/dev/null
(cd "$TEST_MISSING_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

[ -f "$TEST_MISSING_WS/.rnex/wiki/repo-nexus.md" ] || { fail "repo-nexus.md missing"; exit 1; }

# Customize summary of README.md in .rnex/wiki/repo-nexus.md
sed 's/— .*/— Custom Preserved Summary/' "$TEST_MISSING_WS/.rnex/wiki/repo-nexus.md" > "$TEST_MISSING_WS/.rnex/wiki/repo-nexus.md.tmp"
mv "$TEST_MISSING_WS/.rnex/wiki/repo-nexus.md.tmp" "$TEST_MISSING_WS/.rnex/wiki/repo-nexus.md"

# Add a fresh new doc
printf '# Fresh Doc\nFresh content here.\n' > "$TEST_MISSING_WS/docs/fresh.md"
(cd "$TEST_MISSING_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

grep -q "Custom Preserved Summary" "$TEST_MISSING_WS/.rnex/wiki/repo-nexus.md" || {
  fail "Already-indexed source custom summary was overwritten"; exit 1;
}
grep -q "docs/fresh.md" "$TEST_MISSING_WS/.rnex/wiki/repo-nexus-docs.md" || {
  fail "Missing source docs/fresh.md was not ingested into repo-nexus-docs.md"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 16: Standalone lint checks ONLY existing .rnex/wiki/ docs (ignores unindexed sources)
# --------------------------------------------------------------------------
run_test "Karpathy-llm: standalone lint ignores unindexed workspace sources, auto-heals dead refs, and fails on unresolvable broken links"
printf '# Unindexed Doc\nNot yet ingested.\n' > "$TEST_MISSING_WS/docs/unindexed.md"

# Lint must pass when existing .rnex/wiki refs are intact (even with unindexed files in workspace)
(cd "$TEST_MISSING_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "Lint failed on valid wiki with unindexed workspace doc"; exit 1;
}

# Verify unindexed doc was NOT automatically ingested by lint (SRP)
! grep -q "unindexed.md" "$TEST_MISSING_WS/.rnex/wiki/index.md" || {
  fail "unindexed.md was unexpectedly indexed by lint"; exit 1;
}

# Append a dead reference to repo-nexus.md and verify lint auto-heals by pruning it
printf -- '- **[Dead](../../missing-file.md)** (`missing-file.md`) — Dead ref\n' >> "$TEST_MISSING_WS/.rnex/wiki/repo-nexus.md"
(cd "$TEST_MISSING_WS" && ./rnex plugin karpathy-llm lint >/dev/null)
! grep -q "missing-file.md" "$TEST_MISSING_WS/.rnex/wiki/repo-nexus.md" || {
  fail "Dead workspace reference was not pruned by lint"; exit 1;
}

# Unresolvable broken relative markdown link causes lint failure
printf '\n[Broken Target](nonexistent-target.md)\n' >> "$TEST_MISSING_WS/.rnex/wiki/repo-nexus.md"
_lint_fail=0
(cd "$TEST_MISSING_WS" && ./rnex plugin karpathy-llm lint >/dev/null 2>&1) || _lint_fail=1
[ "$_lint_fail" -eq 1 ] || { fail "Lint must fail when .rnex/wiki contains an unresolvable broken link"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 17: Relative link rewriting during ingestion and lint verification
# --------------------------------------------------------------------------
run_test "Karpathy-llm: relative links in source summaries are rewritten to valid paths from wiki"
TEST_REWRITE_WS="$TEST_TMP/karpathy-rewrite-ws"
mkdir -p "$TEST_REWRITE_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_REWRITE_WS"
cd "$TEST_REWRITE_WS"

mkdir -p "$TEST_REWRITE_WS/docs/sub"
printf '# Guide\nGuide content.\n' > "$TEST_REWRITE_WS/docs/guide.md"
printf '# Submodule\nSubmodule content.\n' > "$TEST_REWRITE_WS/docs/sub/module.md"

# Create a source document with intra-folder link, parent link, anchor link, and external link
cat <<'EOF_INT_MD' > "$TEST_REWRITE_WS/docs/intro.md"
# Introduction
See [guide](guide.md), [sub/mod](sub/module.md), [sec](#setup), [web](https://example.com).

## Setup
Setup details here.
EOF_INT_MD

cat <<'EOF_REW_YAML' > "$TEST_REWRITE_WS/rnex.yaml"
version: 1.0.0
sources: [docs]
plugins:
  karpathy-llm:
repos:
EOF_REW_YAML

"$TEST_REWRITE_WS/rnex" init -y --karpathy "$TEST_REWRITE_WS" >/dev/null
(cd "$TEST_REWRITE_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

_shard_content="$(cat "$TEST_REWRITE_WS/.rnex/wiki/repo-nexus-docs.md")"
# Verify guide.md was rewritten relative to wiki (../../docs/guide.md)
echo "$_shard_content" | grep -q '\[guide\](\.\./\.\./docs/guide\.md)' || {
  fail "Relative link guide.md was not rewritten: $_shard_content"; exit 1;
}
# Verify sub/module.md was rewritten relative to wiki (../../docs/sub/module.md)
echo "$_shard_content" | grep -q '\[sub/mod\](\.\./\.\./docs/sub/module\.md)' || {
  fail "Relative link sub/module.md was not rewritten: $_shard_content"; exit 1;
}
# Verify external link https://example.com was preserved
echo "$_shard_content" | grep -q '\[web\](https://example\.com)' || {
  fail "External link https://example.com was not preserved: $_shard_content"; exit 1;
}
# Verify anchor link #setup was rewritten to source doc (../../docs/intro.md#setup)
echo "$_shard_content" | grep -q '\[sec\](\.\./\.\./docs/intro\.md#setup)' || {
  fail "Anchor link #setup was not rewritten: $_shard_content"; exit 1;
}

# Standalone lint must succeed with zero broken link errors
(cd "$TEST_REWRITE_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "Lint failed on rewritten relative links in shard"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 18: Unresolvable relative links & title links are stripped of markup
# --------------------------------------------------------------------------
run_test "Karpathy-llm: dead relative links and title links stripped of link markup"
TEST_STRIP_WS="$TEST_TMP/karpathy-strip-ws"
mkdir -p "$TEST_STRIP_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_STRIP_WS"
cd "$TEST_STRIP_WS"

mkdir -p "$TEST_STRIP_WS/docs"
# Document with link in title and dead link in summary
cat <<'EOF_DEAD_MD' > "$TEST_STRIP_WS/docs/dead.md"
# [Getting Started](nonexistent/setup.md)
Please consult [Dead Target](nonexistent/target.md) and [Real Real](real.md) for info.
EOF_DEAD_MD
printf '# Real Doc\nReal content.\n' > "$TEST_STRIP_WS/docs/real.md"

cat <<'EOF_STRIP_YAML' > "$TEST_STRIP_WS/rnex.yaml"
version: 1.0.0
sources: [docs]
plugins:
  karpathy-llm:
repos:
EOF_STRIP_YAML

"$TEST_STRIP_WS/rnex" init -y --karpathy "$TEST_STRIP_WS" >/dev/null
(cd "$TEST_STRIP_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

_dead_shard="$(cat "$TEST_STRIP_WS/.rnex/wiki/repo-nexus-docs.md")"
# Verify title does not have nested markdown links
echo "$_dead_shard" | grep -q '^- \*\*\[Getting Started\]' || {
  fail "Title link was not stripped of markdown link syntax: $_dead_shard"; exit 1;
}
# Verify dead link was stripped to plain text
echo "$_dead_shard" | grep -q 'Please consult Dead Target and \[Real Real\](\.\./\.\./docs/real\.md)' || {
  fail "Dead link was not stripped or real link not rewritten: $_dead_shard"; exit 1;
}
# Verify lint succeeds with 0 errors
(cd "$TEST_STRIP_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "Lint failed on stripped dead links"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 19: Configurable relative_links: "strip" & CLI flag --strip-links
# --------------------------------------------------------------------------
run_test "Karpathy-llm: configurable relative_links: strip and CLI flag --strip-links"
TEST_MODE_WS="$TEST_TMP/karpathy-mode-ws"
mkdir -p "$TEST_MODE_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_MODE_WS"
cd "$TEST_MODE_WS"

mkdir -p "$TEST_MODE_WS/docs"
printf '# Target Doc\nTarget content.\n' > "$TEST_MODE_WS/docs/target.md"
cat <<'EOF_MODE_MD' > "$TEST_MODE_WS/docs/source.md"
# Source Doc
Check out [Target Doc](target.md) and [External](https://repo-nexus.dev).
EOF_MODE_MD

cat <<'EOF_MODE_YAML' > "$TEST_MODE_WS/rnex.yaml"
version: 1.0.0
sources: [docs]
plugins:
  karpathy-llm:
    relative_links: "strip"
repos:
EOF_MODE_YAML

"$TEST_MODE_WS/rnex" init -y --karpathy "$TEST_MODE_WS" >/dev/null
(cd "$TEST_MODE_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

_mode_shard="$(cat "$TEST_MODE_WS/.rnex/wiki/repo-nexus-docs.md")"
# Target Doc must be stripped to plain text Target Doc
echo "$_mode_shard" | grep -q 'Check out Target Doc and \[External\](https://repo-nexus\.dev)' || {
  fail "Strip mode did not strip relative link while preserving external URL: $_mode_shard"; exit 1;
}

# Lint passes
(cd "$TEST_MODE_WS" && ./rnex plugin karpathy-llm lint >/dev/null) || {
  fail "Lint failed on strip-mode wiki"; exit 1;
}

# Test CLI flag --strip-links override
printf '# Fresh One\nSee [Target Doc](target.md).\n' > "$TEST_MODE_WS/docs/fresh-one.md"
(cd "$TEST_MODE_WS" && ./rnex plugin karpathy-llm ingest --strip-links docs/fresh-one.md >/dev/null)
_fresh_shard="$(cat "$TEST_MODE_WS/.rnex/wiki/repo-nexus-docs.md")"
echo "$_fresh_shard" | grep -q 'See Target Doc\.' || {
  fail "--strip-links CLI flag failed to strip relative link: $_fresh_shard"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 20: Detailed operational log records created, updated, and deleted document actions
# --------------------------------------------------------------------------
run_test "Karpathy-llm: detailed operational log records created, updated, and deleted document actions"
TEST_DET_LOG_WS="$TEST_TMP/karpathy-det-log-ws"
mkdir -p "$TEST_DET_LOG_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_DET_LOG_WS"
cd "$TEST_DET_LOG_WS"

mkdir -p "$TEST_DET_LOG_WS/docs"
printf '# Doc Alpha\nAlpha doc content.\n' > "$TEST_DET_LOG_WS/docs/alpha.md"
printf '# Doc Beta\nBeta doc with [Alpha](alpha.md).\n' > "$TEST_DET_LOG_WS/docs/beta.md"

cat <<'EOF_DET_YAML' > "$TEST_DET_LOG_WS/rnex.yaml"
version: 1.0.0
sources: [docs]
plugins:
  karpathy-llm:
repos:
EOF_DET_YAML

"$TEST_DET_LOG_WS/rnex" init -y --karpathy "$TEST_DET_LOG_WS" >/dev/null
(cd "$TEST_DET_LOG_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

_log_content="$(cat "$TEST_DET_LOG_WS/.rnex/wiki/log.md")"

# 1. Assert created document actions recorded
echo "$_log_content" | grep -q 'created: `docs/alpha.md` (indexed into `repo-nexus-docs.md`)' || {
  fail "Missing created action for docs/alpha.md in log: $_log_content"; exit 1;
}
echo "$_log_content" | grep -q 'created: `docs/beta.md` (indexed into `repo-nexus-docs.md`)' || {
  fail "Missing created action for docs/beta.md in log: $_log_content"; exit 1;
}
# 2. Assert index.md router creation/update recorded
echo "$_log_content" | grep -q 'index.md` (root router table)' || {
  fail "Missing index.md action in log: $_log_content"; exit 1;
}

# 3. Test deleted document action during lint (pruning dead reference)
rm -f "$TEST_DET_LOG_WS/docs/alpha.md"
(cd "$TEST_DET_LOG_WS" && ./rnex plugin karpathy-llm lint >/dev/null)
_log_after_del="$(cat "$TEST_DET_LOG_WS/.rnex/wiki/log.md")"
echo "$_log_after_del" | grep -q 'deleted: `docs/alpha.md` (pruned dead reference from `repo-nexus-docs.md`)' || {
  fail "Missing deleted action for docs/alpha.md in log: $_log_after_del"; exit 1;
}

# 4. Test updated action during lint (re-sorting entries)
printf '# Wiki Index Shard: repo-nexus-docs\n\n- **[Zebra](../../docs/beta.md)** (`docs/beta.md`) — Z.\n- **[Alpha](../../docs/beta.md)** (`docs/beta.md`) — A.\n' > "$TEST_DET_LOG_WS/.rnex/wiki/repo-nexus-docs.md"
(cd "$TEST_DET_LOG_WS" && ./rnex plugin karpathy-llm lint >/dev/null)
_log_after_sort="$(cat "$TEST_DET_LOG_WS/.rnex/wiki/log.md")"
echo "$_log_after_sort" | grep -q 'updated: `repo-nexus-docs.md` (auto-healed LC_ALL=C sort order)' || {
  fail "Missing updated action for shard sort in log: $_log_after_sort"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 21: Operational log rolling buffer caps at max records (FIFO, pruning oldest first)
# --------------------------------------------------------------------------
run_test "Karpathy-llm: operational log rolling buffer prunes oldest records while preserving header"
TEST_ROLL_WS="$TEST_TMP/karpathy-roll-ws"
mkdir -p "$TEST_ROLL_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_ROLL_WS"
cd "$TEST_ROLL_WS"

cat <<'EOF_ROLL_YAML' > "$TEST_ROLL_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    log_max_records: 5
sources: [docs]
repos:
EOF_ROLL_YAML

"$TEST_ROLL_WS/rnex" init -y --karpathy "$TEST_ROLL_WS" >/dev/null
mkdir -p "$TEST_ROLL_WS/.rnex/wiki"

# Seed log with 7 entries (Oldest: Record 1, Newest: Record 7)
cat <<'EOF_SEED' > "$TEST_ROLL_WS/.rnex/wiki/log.md"
# Wiki Operational Log

- **2026-11-01** | `ingest` | Record 1
- **2026-11-02** | `ingest` | Record 2
- **2026-11-03** | `ingest` | Record 3
- **2026-11-04** | `ingest` | Record 4
- **2026-11-05** | `ingest` | Record 5
- **2026-11-06** | `ingest` | Record 6
- **2026-11-07** | `ingest` | Record 7
EOF_SEED

mkdir -p "$TEST_ROLL_WS/docs"
printf '# New Document\nNew document content.\n' > "$TEST_ROLL_WS/docs/new.md"
(cd "$TEST_ROLL_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

_roll_content="$(cat "$TEST_ROLL_WS/.rnex/wiki/log.md")"
_roll_rec_count="$(echo "$_roll_content" | LC_ALL=C grep -c '^- \*\*')"

# Assert total records capped at max (5)
[ "$_roll_rec_count" -le 5 ] || {
  fail "Log record count ($_roll_rec_count) exceeds log_max_records (5): $_roll_content"; exit 1;
}

# Assert oldest records (Record 1, Record 2) were pruned
! echo "$_roll_content" | grep -q 'Record 1' || {
  fail "Oldest Record 1 was not pruned from rolling log: $_roll_content"; exit 1;
}
! echo "$_roll_content" | grep -q 'Record 2' || {
  fail "Oldest Record 2 was not pruned from rolling log: $_roll_content"; exit 1;
}

# Assert newest records and header are present
echo "$_roll_content" | grep -q '# Wiki Operational Log' || {
  fail "Header block missing in pruned log: $_roll_content"; exit 1;
}
echo "$_roll_content" | grep -q 'created: `docs/new.md`' || {
  fail "Newest ingest action missing from log: $_roll_content"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 22: Recursive B-Tree shard breakdown beyond a-m/n-z (subdividing n-z into n-s/t-z)
# --------------------------------------------------------------------------
run_test "Karpathy-llm: recursive B-Tree shard breakdown beyond a-m/n-z into n-s and t-z"
TEST_RECURSE_WS="$TEST_TMP/karpathy-recurse-ws"
mkdir -p "$TEST_RECURSE_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_RECURSE_WS"
cd "$TEST_RECURSE_WS"

"$TEST_RECURSE_WS/rnex" init -y --karpathy "$TEST_RECURSE_WS" >/dev/null

cat <<'EOF_RECURSE_CFG' > "$TEST_RECURSE_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    btree_shard_max_entries: 100
    sources: [repos/test-repo/packages]
repos:
  test-repo:
    path: repos/test-repo
EOF_RECURSE_CFG

# Create member repository packages directory with 175 files spanning n through z
mkdir -p "$TEST_RECURSE_WS/repos/test-repo/packages"
_i=1
while [ "$_i" -le 175 ]; do
  _mod=$(( (_i - 1) % 13 ))
  _ch="$(printf '%s' "nopqrstuvwxyz" | cut -c $((_mod + 1)))"
  cat <<EOF_DOC > "$TEST_RECURSE_WS/repos/test-repo/packages/${_ch}-pkg-${_i}.md"
# ${_ch}-pkg-${_i}
Architecture description for package ${_ch}-${_i}.
EOF_DOC
  _i=$((_i + 1))
done

# Run ingest to compile B-Tree shards
(cd "$TEST_RECURSE_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Assert that repos-test-repo-packages-n-z.md was broken down and deleted
[ ! -f "$TEST_RECURSE_WS/wiki/repos-test-repo-packages-n-z.md" ] || {
  fail "repos-test-repo-packages-n-z.md should have been split and removed"; exit 1;
}

# Assert that sub-shards n-s and t-z were created
[ -f "$TEST_RECURSE_WS/wiki/repos-test-repo-packages-n-s.md" ] || {
  fail "repos-test-repo-packages-n-s.md missing after recursive split"; exit 1;
}
[ -f "$TEST_RECURSE_WS/wiki/repos-test-repo-packages-t-z.md" ] || {
  fail "repos-test-repo-packages-t-z.md missing after recursive split"; exit 1;
}

# Assert that every sub-shard has <= 100 records
_ns_count="$(LC_ALL=C grep -c '^- \*\*' "$TEST_RECURSE_WS/wiki/repos-test-repo-packages-n-s.md" 2>/dev/null || true)"
_tz_count="$(LC_ALL=C grep -c '^- \*\*' "$TEST_RECURSE_WS/wiki/repos-test-repo-packages-t-z.md" 2>/dev/null || true)"
[ "$_ns_count" -le 100 ] || { fail "Sub-shard n-s has $_ns_count records (> 100)"; exit 1; }
[ "$_tz_count" -le 100 ] || { fail "Sub-shard t-z has $_tz_count records (> 100)"; exit 1; }

# Assert index.md references n-s and t-z sub-shards and not n-z
grep -q 'repos-test-repo-packages-n-s.md' "$TEST_RECURSE_WS/wiki/index.md" || {
  fail "repos-test-repo-packages-n-s missing from root router table"; exit 1;
}
grep -q 'repos-test-repo-packages-t-z.md' "$TEST_RECURSE_WS/wiki/index.md" || {
  fail "repos-test-repo-packages-t-z missing from root router table"; exit 1;
}
! grep -q 'repos-test-repo-packages-n-z.md' "$TEST_RECURSE_WS/wiki/index.md" || {
  fail "Deleted repos-test-repo-packages-n-z still referenced in index.md"; exit 1;
}

# Assert log.md recorded creation of sub-shards
grep -q 'created: `repos-test-repo-packages-n-s.md` (split sub-shard)' "$TEST_RECURSE_WS/wiki/log.md" || {
  fail "Creation of n-s sub-shard not logged in log.md"; exit 1;
}
grep -q 'created: `repos-test-repo-packages-t-z.md` (split sub-shard)' "$TEST_RECURSE_WS/wiki/log.md" || {
  fail "Creation of t-z sub-shard not logged in log.md"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 23: Standalone lint auto-heals oversized leaf shards (> 100 records)
# --------------------------------------------------------------------------
run_test "Karpathy-llm: standalone lint auto-heals existing oversized shard (>100 records)"
TEST_LINT_SPLIT_WS="$TEST_TMP/karpathy-lint-split-ws"
mkdir -p "$TEST_LINT_SPLIT_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_LINT_SPLIT_WS"
cd "$TEST_LINT_SPLIT_WS"

"$TEST_LINT_SPLIT_WS/rnex" init -y --karpathy "$TEST_LINT_SPLIT_WS" >/dev/null
mkdir -p "$TEST_LINT_SPLIT_WS/wiki"
mkdir -p "$TEST_LINT_SPLIT_WS/repos/test-repo/packages"

# Seed oversized shard repos-test-repo-packages-n-z.md with 175 entries directly
cat <<'EOF_HDR' > "$TEST_LINT_SPLIT_WS/wiki/repos-test-repo-packages-n-z.md"
# Wiki Index Shard: repos-test-repo-packages-n-z

EOF_HDR

_i=1
while [ "$_i" -le 175 ]; do
  _mod=$(( (_i - 1) % 13 ))
  _ch="$(printf '%s' "nopqrstuvwxyz" | cut -c $((_mod + 1)))"
  # Create source file so links are valid
  touch "$TEST_LINT_SPLIT_WS/repos/test-repo/packages/${_ch}-pkg-${_i}.md"
  printf -- '- **[%s-pkg-%s](../repos/test-repo/packages/%s-pkg-%s.md)** (`repos/test-repo/packages/%s-pkg-%s.md`) — Description.\n' \
    "$_ch" "$_i" "$_ch" "$_i" "$_ch" "$_i" >> "$TEST_LINT_SPLIT_WS/wiki/repos-test-repo-packages-n-z.md"
  _i=$((_i + 1))
done

cat <<'EOF_LINT_CFG' > "$TEST_LINT_SPLIT_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    btree_shard_max_entries: 100
    sources: [repos/test-repo/packages]
repos:
  test-repo:
    path: repos/test-repo
EOF_LINT_CFG

# Run standalone lint -- should auto-heal and split the oversized shard without error
(cd "$TEST_LINT_SPLIT_WS" && ./rnex plugin karpathy-llm lint) || {
  fail "Standalone lint failed to auto-heal oversized shard"; exit 1;
}

# Assert that oversized shard was deleted
[ ! -f "$TEST_LINT_SPLIT_WS/wiki/repos-test-repo-packages-n-z.md" ] || {
  fail "Oversized repos-test-repo-packages-n-z.md was not split and removed by lint"; exit 1;
}

# Assert that n-s and t-z sub-shards exist and are <= 100 records
[ -f "$TEST_LINT_SPLIT_WS/wiki/repos-test-repo-packages-n-s.md" ] || {
  fail "repos-test-repo-packages-n-s.md missing after lint auto-heal"; exit 1;
}
[ -f "$TEST_LINT_SPLIT_WS/wiki/repos-test-repo-packages-t-z.md" ] || {
  fail "repos-test-repo-packages-t-z.md missing after lint auto-heal"; exit 1;
}
_lint_ns="$(LC_ALL=C grep -c '^- \*\*' "$TEST_LINT_SPLIT_WS/wiki/repos-test-repo-packages-n-s.md")"
_lint_tz="$(LC_ALL=C grep -c '^- \*\*' "$TEST_LINT_SPLIT_WS/wiki/repos-test-repo-packages-t-z.md")"
[ "$_lint_ns" -le 100 ] || { fail "n-s count after lint ($_lint_ns) > 100"; exit 1; }
[ "$_lint_tz" -le 100 ] || { fail "t-z count after lint ($_lint_tz) > 100"; exit 1; }

# Assert log.md recorded the auto-healing actions
grep -q 'created: `repos-test-repo-packages-n-s.md` (split sub-shard)' "$TEST_LINT_SPLIT_WS/wiki/log.md" || {
  fail "Lint creation of n-s shard not recorded in log.md"; exit 1;
}
grep -q 'deleted: `repos-test-repo-packages-n-z.md` (split into sub-shards)' "$TEST_LINT_SPLIT_WS/wiki/log.md" || {
  fail "Lint deletion of parent shard not recorded in log.md"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 24: Document routing into deep sub-shards during ingestion
# --------------------------------------------------------------------------
run_test "Karpathy-llm: document routing into deep sub-shards (n-s vs t-z)"
TEST_ROUTE_WS="$TEST_TMP/karpathy-route-ws"
mkdir -p "$TEST_ROUTE_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_ROUTE_WS"
cd "$TEST_ROUTE_WS"

"$TEST_ROUTE_WS/rnex" init -y --karpathy "$TEST_ROUTE_WS" >/dev/null
mkdir -p "$TEST_ROUTE_WS/wiki"

# Seed existing split sub-shards (a-m, n-s, t-z)
cat <<'EOF_AM' > "$TEST_ROUTE_WS/wiki/repos-test-repo-packages-a-m.md"
# Wiki Index Shard: repos-test-repo-packages-a-m

- **[auth](../../repos/test-repo/packages/auth.md)** (`repos/test-repo/packages/auth.md`) — Auth module
EOF_AM

cat <<'EOF_NS' > "$TEST_ROUTE_WS/wiki/repos-test-repo-packages-n-s.md"
# Wiki Index Shard: repos-test-repo-packages-n-s

- **[network](../../repos/test-repo/packages/network.md)** (`repos/test-repo/packages/network.md`) — Network module
EOF_NS

cat <<'EOF_TZ' > "$TEST_ROUTE_WS/wiki/repos-test-repo-packages-t-z.md"
# Wiki Index Shard: repos-test-repo-packages-t-z

- **[tools](../../repos/test-repo/packages/tools.md)** (`repos/test-repo/packages/tools.md`) — Tools module
EOF_TZ

cat <<'EOF_ROUTE_CFG' > "$TEST_ROUTE_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    btree_shard_max_entries: 100
    sources: [repos/test-repo/packages]
repos:
  test-repo:
    path: repos/test-repo
EOF_ROUTE_CFG

# Create a new package document starting with 'p' (belongs in n-s) and one starting with 'z' (belongs in t-z)
mkdir -p "$TEST_ROUTE_WS/repos/test-repo/packages"
printf '# package-manager\nPackage manager module.\n' > "$TEST_ROUTE_WS/repos/test-repo/packages/pkg-manager.md"
printf '# zebra-worker\nZebra worker module.\n' > "$TEST_ROUTE_WS/repos/test-repo/packages/zebra-worker.md"

(cd "$TEST_ROUTE_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Assert package-manager was routed to n-s and zebra-worker to t-z
grep -q 'package-manager' "$TEST_ROUTE_WS/wiki/repos-test-repo-packages-n-s.md" || {
  fail "package-manager was not routed to n-s shard"; exit 1;
}
grep -q 'zebra-worker' "$TEST_ROUTE_WS/wiki/repos-test-repo-packages-t-z.md" || {
  fail "zebra-worker was not routed to t-z shard"; exit 1;
}
# Assert base shard was not created
[ ! -f "$TEST_ROUTE_WS/wiki/repos-test-repo-packages.md" ] || {
  fail "Base shard should not be created when sub-shards exist"; exit 1;
}
# Assert n-z was not created
[ ! -f "$TEST_ROUTE_WS/wiki/repos-test-repo-packages-n-z.md" ] || {
  fail "Old n-z shard should not be created when deep sub-shards exist"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 25: Multi-letter B-Tree splitting by first 2 letters (pa-pm / pn-pz)
# --------------------------------------------------------------------------
run_test "Karpathy-llm: multi-letter B-Tree splitting by first 2 letters (p -> pa-pm and pn-pz)"
TEST_2LET_WS="$TEST_TMP/karpathy-2let-ws"
mkdir -p "$TEST_2LET_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_2LET_WS"
cd "$TEST_2LET_WS"

"$TEST_2LET_WS/rnex" init -y --karpathy "$TEST_2LET_WS" >/dev/null
mkdir -p "$TEST_2LET_WS/wiki"
mkdir -p "$TEST_2LET_WS/repos/test-repo/packages"

# Generate 150 docs starting with 'p': 75 package-* (pa), 75 python-* (py)
_i=1
while [ "$_i" -le 75 ]; do
  printf '# package-mod-%s\nPackage module %s.\n' "$_i" "$_i" > "$TEST_2LET_WS/repos/test-repo/packages/package-mod-${_i}.md"
  _i=$((_i + 1))
done
_j=1
while [ "$_j" -le 75 ]; do
  printf '# python-mod-%s\nPython module %s.\n' "$_j" "$_j" > "$TEST_2LET_WS/repos/test-repo/packages/python-mod-${_j}.md"
  _j=$((_j + 1))
done

cat <<'EOF_2LET_CFG' > "$TEST_2LET_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    btree_shard_max_entries: 100
    sources: [repos/test-repo/packages]
repos:
  test-repo:
    path: repos/test-repo
EOF_2LET_CFG

(cd "$TEST_2LET_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Verify that splitting produced 2-letter sub-shards (pa-pm and pn-pz)
[ -f "$TEST_2LET_WS/wiki/repos-test-repo-packages-pa-pm.md" ] || {
  fail "repos-test-repo-packages-pa-pm.md was not created"; exit 1;
}
[ -f "$TEST_2LET_WS/wiki/repos-test-repo-packages-pn-pz.md" ] || {
  fail "repos-test-repo-packages-pn-pz.md was not created"; exit 1;
}

# Verify entries are strictly <= 100 in each shard
_pa_pm_count="$(LC_ALL=C grep -c '^- \*\*' "$TEST_2LET_WS/wiki/repos-test-repo-packages-pa-pm.md" 2>/dev/null || true)"
_pn_pz_count="$(LC_ALL=C grep -c '^- \*\*' "$TEST_2LET_WS/wiki/repos-test-repo-packages-pn-pz.md" 2>/dev/null || true)"
[ "$_pa_pm_count" -le 100 ] || { fail "pa-pm shard has $_pa_pm_count entries (>100)"; exit 1; }
[ "$_pn_pz_count" -le 100 ] || { fail "pn-pz shard has $_pn_pz_count entries (>100)"; exit 1; }

# Verify standalone lint passes with 0 errors
(cd "$TEST_2LET_WS" && ./rnex plugin karpathy-llm lint) || {
  fail "Standalone lint failed on 2-letter sub-shards"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 26: Multi-letter B-Tree splitting by first 3 letters (paa-pam / pan-paz)
# --------------------------------------------------------------------------
run_test "Karpathy-llm: multi-letter B-Tree splitting by first 3 letters (pa -> paa-pam and pan-paz)"
TEST_3LET_WS="$TEST_TMP/karpathy-3let-ws"
mkdir -p "$TEST_3LET_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_3LET_WS"
cd "$TEST_3LET_WS"

"$TEST_3LET_WS/rnex" init -y --karpathy "$TEST_3LET_WS" >/dev/null
mkdir -p "$TEST_3LET_WS/wiki"
mkdir -p "$TEST_3LET_WS/repos/test-repo/packages"

# Generate 150 docs starting with 'pa': 75 package-* (pac -> paa-pam), 75 payment-* (pay -> pan-paz)
_i=1
while [ "$_i" -le 75 ]; do
  printf '# package-item-%s\nPackage item %s.\n' "$_i" "$_i" > "$TEST_3LET_WS/repos/test-repo/packages/package-item-${_i}.md"
  _i=$((_i + 1))
done
_j=1
while [ "$_j" -le 75 ]; do
  printf '# payment-item-%s\nPayment item %s.\n' "$_j" "$_j" > "$TEST_3LET_WS/repos/test-repo/packages/payment-item-${_j}.md"
  _j=$((_j + 1))
done

cat <<'EOF_3LET_CFG' > "$TEST_3LET_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    btree_shard_max_entries: 100
    sources: [repos/test-repo/packages]
repos:
  test-repo:
    path: repos/test-repo
EOF_3LET_CFG

(cd "$TEST_3LET_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Verify that splitting produced 3-letter sub-shards (paa-pam and pan-paz)
[ -f "$TEST_3LET_WS/wiki/repos-test-repo-packages-paa-pam.md" ] || {
  fail "repos-test-repo-packages-paa-pam.md was not created"; exit 1;
}
[ -f "$TEST_3LET_WS/wiki/repos-test-repo-packages-pan-paz.md" ] || {
  fail "repos-test-repo-packages-pan-paz.md was not created"; exit 1;
}

_paa_pam_count="$(LC_ALL=C grep -c '^- \*\*' "$TEST_3LET_WS/wiki/repos-test-repo-packages-paa-pam.md" 2>/dev/null || true)"
_pan_paz_count="$(LC_ALL=C grep -c '^- \*\*' "$TEST_3LET_WS/wiki/repos-test-repo-packages-pan-paz.md" 2>/dev/null || true)"
[ "$_paa_pam_count" -le 100 ] || { fail "paa-pam shard has $_paa_pam_count entries (>100)"; exit 1; }
[ "$_pan_paz_count" -le 100 ] || { fail "pan-paz shard has $_pan_paz_count entries (>100)"; exit 1; }

# Verify standalone lint passes with 0 errors
(cd "$TEST_3LET_WS" && ./rnex plugin karpathy-llm lint) || {
  fail "Standalone lint failed on 3-letter sub-shards"; exit 1;
}
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
