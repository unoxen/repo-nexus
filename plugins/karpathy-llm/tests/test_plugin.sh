#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# File: plugins/karpathy-llm/tests/test_plugin.sh
# Architectural Layer: Quality Assurance / Integration Test Automation
# Design Pattern: Test Suite (Template Method)
# Responsibilities:
#   - Validates Karpathy LLM Wiki plugin manifest, version parity, and strict 2-command CLI.
#   - Asserts non-empty and strictly symmetric sorted TSV property graph edges.
#   - Asserts 2-pillar B-Tree taxonomy (concepts/ & repos/) and multi-shard generation.
#   - Validates root router bounds (wiki/_index.md <= 80 lines) and hot.md purge.
#   - Verifies auto-healing directory migration and strict linting.
#   - Tests internal agent query helpers (_search and _graph).
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
# Assert template points to {wiki_dir}/_index.md and legacy templates are absent
grep -q 'templates/_index\.md:[ ]*"{wiki_dir}/_index\.md"' "$_yaml_file" || { fail "_index.md placeholder missing or unquoted in plugin.yaml"; exit 1; }
! grep -q 'templates/index\.md' "$_yaml_file" || { fail "legacy index.md should not be in plugin.yaml"; exit 1; }
! grep -q 'templates/hot\.md' "$_yaml_file" || { fail "hot.md should not be in plugin.yaml"; exit 1; }

# Assert B-Tree and TSV Graph configuration defaults
grep -q 'btree_shard_max_entries:' "$_yaml_file" || { fail "btree_shard_max_entries missing in plugin.yaml"; exit 1; }
grep -q 'btree_root_max_lines:' "$_yaml_file" || { fail "btree_root_max_lines missing in plugin.yaml"; exit 1; }
grep -q 'graph_default_depth:' "$_yaml_file" || { fail "graph_default_depth missing in plugin.yaml"; exit 1; }
grep -q 'index_dir: "_index"' "$_yaml_file" || { fail "index_dir default missing in plugin.yaml"; exit 1; }
grep -q 'graph_dir: "_graph"' "$_yaml_file" || { fail "graph_dir default missing in plugin.yaml"; exit 1; }
grep -q 'index_file: "_index.md"' "$_yaml_file" || { fail "index_file default missing in plugin.yaml"; exit 1; }
grep -q 'log_file: "_log.md"' "$_yaml_file" || { fail "log_file default missing in plugin.yaml"; exit 1; }

# Assert ONLY ingest and lint are registered under commands:
grep -q '^[ ]*ingest:' "$_yaml_file" || { fail "ingest command missing in plugin.yaml"; exit 1; }
grep -q '^[ ]*lint:' "$_yaml_file" || { fail "lint command missing in plugin.yaml"; exit 1; }
! grep -q '^[ ]*init:' "$_yaml_file" || { fail "init command must NOT be in plugin.yaml commands"; exit 1; }
! grep -q '^[ ]*index:' "$_yaml_file" || { fail "index command must NOT be in plugin.yaml commands"; exit 1; }
! grep -q '^[ ]*graph:' "$_yaml_file" || { fail "graph command must NOT be in plugin.yaml commands"; exit 1; }
! grep -q '^[ ]*search:' "$_yaml_file" || { fail "search command must NOT be in plugin.yaml commands"; exit 1; }

# Assert deprecated public scripts are deleted from bin/ and commands/
[ ! -e "$_kl_pdir/bin/init.sh" ] || { fail "bin/init.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/bin/index.sh" ] || { fail "bin/index.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/bin/search.sh" ] || { fail "bin/search.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/bin/graph.sh" ] || { fail "bin/graph.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/commands/init.sh" ] || { fail "commands/init.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/commands/index.sh" ] || { fail "commands/index.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/commands/search.sh" ] || { fail "commands/search.sh still exists"; exit 1; }
[ ! -e "$_kl_pdir/commands/graph.sh" ] || { fail "commands/graph.sh still exists"; exit 1; }

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
# Test 2: Plan Test 1 — Strict 2-Command Public CLI Surface
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
# Test 3: Plan Test 2 — Non-Empty & Strictly Symmetric edges_out.tsv and edges_in.tsv
# --------------------------------------------------------------------------
run_test "Karpathy-llm: non-empty & strictly symmetric edges_out.tsv and edges_in.tsv via two-pass compiler"
# Create concepts node: wiki/concepts/zero-trust.md
mkdir -p "$TEST_KARPATHY_WS/wiki/concepts" "$TEST_KARPATHY_WS/wiki/repos/backend"
cat <<'EOF_ZT' > "$TEST_KARPATHY_WS/wiki/concepts/zero-trust.md"
# Zero Trust Architecture

Strict verification security model where every request is authenticated and authorized.
EOF_ZT

# Create repo node referencing concepts: wiki/repos/backend/auth-service.md
cat <<'EOF_AUTH' > "$TEST_KARPATHY_WS/wiki/repos/backend/auth-service.md"
# Auth Service

Authentication and authorization service implementing [[zero-trust]] verification.
For details on architecture, see [Zero Trust](../../concepts/zero-trust.md).
EOF_AUTH

# Run ingest targeting the new document
(cd "$TEST_KARPATHY_WS" && ./rnex plugin karpathy-llm ingest wiki/repos/backend/auth-service.md >/dev/null)

# Assert edges_out.tsv and edges_in.tsv are strictly non-empty
[ -s "$TEST_KARPATHY_WS/wiki/_graph/edges_out.tsv" ] || { fail "wiki/_graph/edges_out.tsv is empty"; exit 1; }
[ -s "$TEST_KARPATHY_WS/wiki/_graph/edges_in.tsv" ] || { fail "wiki/_graph/edges_in.tsv is empty"; exit 1; }

# Assert forward edge: auth-service links_to zero-trust
grep -q '^auth-service[ 	]links_to[ 	]zero-trust$' "$TEST_KARPATHY_WS/wiki/_graph/edges_out.tsv" || {
  fail "edges_out.tsv missing 'auth-service links_to zero-trust': $(cat "$TEST_KARPATHY_WS/wiki/_graph/edges_out.tsv")"; exit 1;
}

# Assert backward edge: zero-trust links_to auth-service
grep -q '^zero-trust[ 	]links_to[ 	]auth-service$' "$TEST_KARPATHY_WS/wiki/_graph/edges_in.tsv" || {
  fail "edges_in.tsv missing 'zero-trust links_to auth-service': $(cat "$TEST_KARPATHY_WS/wiki/_graph/edges_in.tsv")"; exit 1;
}

# Assert exact edge symmetry (line counts match)
_out_cnt="$(LC_ALL=C awk 'END { print NR+0 }' "$TEST_KARPATHY_WS/wiki/_graph/edges_out.tsv")"
_in_cnt="$(LC_ALL=C awk 'END { print NR+0 }' "$TEST_KARPATHY_WS/wiki/_graph/edges_in.tsv")"
[ "$_out_cnt" -eq "$_in_cnt" ] || { fail "Asymmetric edge counts: edges_out=$_out_cnt, edges_in=$_in_cnt"; exit 1; }

# Assert LC_ALL=C sorted order on all 3 tables
LC_ALL=C sort -c "$TEST_KARPATHY_WS/wiki/_graph/nodes.tsv" || { fail "nodes.tsv is not sorted"; exit 1; }
LC_ALL=C sort -c "$TEST_KARPATHY_WS/wiki/_graph/edges_out.tsv" || { fail "edges_out.tsv is not sorted"; exit 1; }
LC_ALL=C sort -c "$TEST_KARPATHY_WS/wiki/_graph/edges_in.tsv" || { fail "edges_in.tsv is not sorted"; exit 1; }

# Test internal agent query helpers (_search and _graph)
# shellcheck source=/dev/null
. "$_kl_pdir/lib/config.sh"
# shellcheck source=/dev/null
. "$_kl_pdir/lib/utils.sh"
# shellcheck source=/dev/null
. "$_kl_pdir/lib/agent_query_helpers.sh"
load_karpathy_wiki_config "$TEST_KARPATHY_WS"

_search_out="$(agent_internal_search "zero-trust")"
echo "$_search_out" | grep -q "zero-trust" || { fail "agent_internal_search failed to find zero-trust: $_search_out"; exit 1; }

_graph_out="$(agent_internal_graph "auth-service")"
echo "$_graph_out" | grep -q "\[\[zero-trust\]\]" || { fail "agent_internal_graph failed for auth-service: $_graph_out"; exit 1; }

_graph_in="$(agent_internal_graph "zero-trust")"
echo "$_graph_in" | grep -q "auth-service" || { fail "agent_internal_graph failed for zero-trust backlink: $_graph_in"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 4: Plan Test 3 — wiki/_index.md & Concepts + Multi-Shard repos-* Taxonomy
# --------------------------------------------------------------------------
run_test "Karpathy-llm: wiki/_index.md & concepts + multi-shard repos-* taxonomy with shard splitting"
# Assert root router is _index.md (bounded <= 80 lines)
[ -f "$TEST_KARPATHY_WS/wiki/_index.md" ] || { fail "wiki/_index.md missing"; exit 1; }
_root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$TEST_KARPATHY_WS/wiki/_index.md")"
[ "$_root_lines" -le 80 ] || { fail "wiki/_index.md exceeded 80 lines: $_root_lines"; exit 1; }

# Negative assertions: legacy files and folders must NOT exist
[ ! -e "$TEST_KARPATHY_WS/wiki/index.md" ] || { fail "legacy wiki/index.md exists"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/wiki/hot.md" ] || { fail "legacy wiki/hot.md exists"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/wiki/overview" ] || { fail "legacy wiki/overview/ exists"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/wiki/entities" ] || { fail "legacy wiki/entities/ exists"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/wiki/sources" ] || { fail "legacy wiki/sources/ exists"; exit 1; }

# Baseline shards must exist
[ -f "$TEST_KARPATHY_WS/wiki/_index/concepts.md" ] || { fail "wiki/_index/concepts.md missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_index/repos-nexus.md" ] || { fail "wiki/_index/repos-nexus.md missing"; exit 1; }

# Add member repository 'backend' to workspace config and verify shard generation
cat <<'EOF_CFG_BE' > "$TEST_KARPATHY_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
repos:
  backend:
EOF_CFG_BE

(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)
(cd "$TEST_KARPATHY_WS" && ./rnex plugin karpathy-llm lint >/dev/null)

[ -f "$TEST_KARPATHY_WS/wiki/_index/repos-backend.md" ] || { fail "wiki/_index/repos-backend.md missing after lint"; exit 1; }

# Create sub-scoped pages for backend: api/routes.md and db/models.md
mkdir -p "$TEST_KARPATHY_WS/wiki/repos/backend/api" "$TEST_KARPATHY_WS/wiki/repos/backend/db"
cat <<'EOF_ROUTES' > "$TEST_KARPATHY_WS/wiki/repos/backend/api/routes.md"
# Backend API Routes

REST endpoints for authentication and user access.
EOF_ROUTES

cat <<'EOF_MODELS' > "$TEST_KARPATHY_WS/wiki/repos/backend/db/models.md"
# Database Models

Relational schemas for credentials and audit logs.
EOF_MODELS

# Run lint to trigger multi-shard compilation
(cd "$TEST_KARPATHY_WS" && ./rnex plugin karpathy-llm lint >/dev/null)

# Assert multiple shards exist for the backend repository
[ -f "$TEST_KARPATHY_WS/wiki/_index/repos-backend-api.md" ] || { fail "wiki/_index/repos-backend-api.md missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_index/repos-backend-db.md" ] || { fail "wiki/_index/repos-backend-db.md missing"; exit 1; }

# Assert sub-shards are registered in wiki/_index.md
grep -q 'repos-backend-api' "$TEST_KARPATHY_WS/wiki/_index.md" || { fail "repos-backend-api missing from wiki/_index.md"; exit 1; }
grep -q 'repos-backend-db' "$TEST_KARPATHY_WS/wiki/_index.md" || { fail "repos-backend-db missing from wiki/_index.md"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 5: B-Tree Sharding and Automatic Sub-Shard Splitting on Threshold
# --------------------------------------------------------------------------
run_test "Karpathy-llm: B-Tree sharding, automatic shard splitting (a-m / n-z), and root line bounds"
TEST_BTREE_WS="$TEST_TMP/karpathy-btree-ws"
mkdir -p "$TEST_BTREE_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_BTREE_WS"
cd "$TEST_BTREE_WS"

cat <<'EOF_BTREE_CFG' > "$TEST_BTREE_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: wiki
    btree_shard_max_entries: 5
    sources: [docs]
repos:
EOF_BTREE_CFG

"$TEST_BTREE_WS/rnex" init -y --karpathy "$TEST_BTREE_WS" >/dev/null

# Create 8 concept notes under wiki/concepts/ to exceed the split threshold of 5
mkdir -p "$TEST_BTREE_WS/wiki/concepts"
for _cname in "auth-tokens" "caching" "distributed-locks" "encryption" "jwt" "message-brokers" "networking" "queues"; do
  cat <<EOF_C > "$TEST_BTREE_WS/wiki/concepts/${_cname}.md"
# ${_cname}
Detailed explanation of ${_cname} architecture.
EOF_C
done

# Run lint to rebalance B-Tree shards
(cd "$TEST_BTREE_WS" && ./rnex plugin karpathy-llm lint >/dev/null)

# Verify concepts shard split into a-m and n-z sub-shards
[ -f "$TEST_BTREE_WS/wiki/_index/concepts-a-m.md" ] || { fail "concepts-a-m.md missing after split"; exit 1; }
[ -f "$TEST_BTREE_WS/wiki/_index/concepts-n-z.md" ] || { fail "concepts-n-z.md missing after split"; exit 1; }

# Verify sorted contents in each shard
grep -q "auth-tokens" "$TEST_BTREE_WS/wiki/_index/concepts-a-m.md" || { fail "auth-tokens missing from concepts-a-m.md"; exit 1; }
grep -q "jwt" "$TEST_BTREE_WS/wiki/_index/concepts-a-m.md" || { fail "jwt missing from concepts-a-m.md"; exit 1; }
grep -q "networking" "$TEST_BTREE_WS/wiki/_index/concepts-n-z.md" || { fail "networking missing from concepts-n-z.md"; exit 1; }
grep -q "queues" "$TEST_BTREE_WS/wiki/_index/concepts-n-z.md" || { fail "queues missing from concepts-n-z.md"; exit 1; }

# Verify B-Tree Root routing table reflects sub-shards and is bounded (<= 80 lines)
_bt_root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$TEST_BTREE_WS/wiki/_index.md")"
[ "$_bt_root_lines" -le 80 ] || { fail "Root _index.md exceeded 80 lines: $_bt_root_lines"; exit 1; }
grep -q 'concepts-a-m' "$TEST_BTREE_WS/wiki/_index.md" || { fail "concepts-a-m missing from root router table"; exit 1; }
grep -q 'concepts-n-z' "$TEST_BTREE_WS/wiki/_index.md" || { fail "concepts-n-z missing from root router table"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 6: Single-File Ingestion, Options, Error Validation, and Batch Fallback
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
[ -f "$TEST_SF_WS/wiki/repos/nexus/doc-a.md" ] || { fail "wiki/repos/nexus/doc-a.md missing after single-file positional ingest"; exit 1; }
[ ! -f "$TEST_SF_WS/wiki/repos/nexus/doc-b.md" ] || { fail "doc-b should not have been ingested"; exit 1; }
[ ! -f "$TEST_SF_WS/wiki/repos/nexus/doc-c.md" ] || { fail "doc-c should not have been ingested"; exit 1; }

# Test Case 2: --file / -f flag single file ingestion
(cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest --file raw/doc-b.md >/dev/null)
[ -f "$TEST_SF_WS/wiki/repos/nexus/doc-b.md" ] || { fail "wiki/repos/nexus/doc-b.md missing after --file ingest"; exit 1; }
[ ! -f "$TEST_SF_WS/wiki/repos/nexus/doc-c.md" ] || { fail "doc-c should not have been ingested"; exit 1; }

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
[ -f "$TEST_SF_WS/wiki/repos/nexus/doc-c.md" ] || { fail "wiki/repos/nexus/doc-c.md missing after batch fallback ingest"; exit 1; }
[ ! -e "$TEST_SF_WS/wiki/hot.md" ] || { fail "hot.md found in single-file test workspace"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 7: Auto-healing Directory Migration and Purge during lint
# --------------------------------------------------------------------------
run_test "Karpathy-llm: auto-healing directory migration (overview/entities/sources -> concepts/repos) and purge"
TEST_MIG_WS="$TEST_TMP/karpathy-mig-ws"
mkdir -p "$TEST_MIG_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_MIG_WS"
cd "$TEST_MIG_WS"
"$TEST_MIG_WS/rnex" init -y --karpathy "$TEST_MIG_WS" >/dev/null

# Plant legacy directories and deprecated files
mkdir -p "$TEST_MIG_WS/wiki/overview" "$TEST_MIG_WS/wiki/entities" "$TEST_MIG_WS/wiki/sources/payment-svc"
echo "# Legacy Concept" > "$TEST_MIG_WS/wiki/overview/legacy-concept.md"
echo "# Nexus Core Entity" > "$TEST_MIG_WS/wiki/entities/nexus-entity.md"
echo "# Payment Invoice Service" > "$TEST_MIG_WS/wiki/sources/payment-svc/invoice.md"
echo "stale hot cache" > "$TEST_MIG_WS/wiki/hot.md"
echo "stale root router" > "$TEST_MIG_WS/wiki/index.md"

# Run lint to auto-heal and migrate
(cd "$TEST_MIG_WS" && ./rnex plugin karpathy-llm lint >/dev/null)

# Verify legacy directories are purged
[ ! -d "$TEST_MIG_WS/wiki/overview" ] || { fail "legacy overview/ was not deleted"; exit 1; }
[ ! -d "$TEST_MIG_WS/wiki/entities" ] || { fail "legacy entities/ was not deleted"; exit 1; }
[ ! -d "$TEST_MIG_WS/wiki/sources" ] || { fail "legacy sources/ was not deleted"; exit 1; }
[ ! -e "$TEST_MIG_WS/wiki/hot.md" ] || { fail "legacy hot.md was not deleted"; exit 1; }
[ ! -e "$TEST_MIG_WS/wiki/index.md" ] || { fail "legacy index.md was not deleted"; exit 1; }

# Verify migrated destination files exist
[ -f "$TEST_MIG_WS/wiki/concepts/legacy-concept.md" ] || { fail "legacy-concept.md not migrated to concepts/"; exit 1; }
[ -f "$TEST_MIG_WS/wiki/repos/nexus/nexus-entity.md" ] || { fail "nexus-entity.md not migrated to repos/nexus/"; exit 1; }
[ -f "$TEST_MIG_WS/wiki/repos/payment-svc/invoice.md" ] || { fail "invoice.md not migrated to repos/payment-svc/"; exit 1; }

# Verify valid _index.md compiled
[ -f "$TEST_MIG_WS/wiki/_index.md" ] || { fail "wiki/_index.md missing after migration"; exit 1; }
pass

# --------------------------------------------------------------------------
# Test 8: Strict Linting on Broken Links & Sources
# --------------------------------------------------------------------------
run_test "Karpathy-llm: strict linting detects broken wikilinks and missing source references"
TEST_STRICT_WS="$TEST_TMP/karpathy-strict-ws"
mkdir -p "$TEST_STRICT_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_STRICT_WS"
cd "$TEST_STRICT_WS"
"$TEST_STRICT_WS/rnex" init -y --karpathy "$TEST_STRICT_WS" >/dev/null

# Clean lint must succeed
(cd "$TEST_STRICT_WS" && ./rnex plugin karpathy-llm lint --strict >/dev/null) || {
  fail "Initial clean lint --strict failed"; exit 1;
}

# Test broken wikilink detection
cat <<'EOF_BWL' > "$TEST_STRICT_WS/wiki/concepts/broken-link.md"
# Broken Link Test
References an unresolvable slug [[missing-concept-slug]].
EOF_BWL

_strict_wl_err=0
(cd "$TEST_STRICT_WS" && ./rnex plugin karpathy-llm lint --strict >/dev/null 2>&1) || _strict_wl_err=1
[ "$_strict_wl_err" -eq 1 ] || { fail "lint --strict did not exit non-zero on broken wikilink"; exit 1; }

rm -f "$TEST_STRICT_WS/wiki/concepts/broken-link.md"

# Test broken frontmatter sources detection
cat <<'EOF_BSRC' > "$TEST_STRICT_WS/wiki/concepts/broken-source.md"
---
sources: ["docs/nonexistent-source.md"]
---
# Broken Source Test
Content here.
EOF_BSRC

_strict_src_err=0
(cd "$TEST_STRICT_WS" && ./rnex plugin karpathy-llm lint --strict >/dev/null 2>&1) || _strict_src_err=1
[ "$_strict_src_err" -eq 1 ] || { fail "lint --strict did not exit non-zero on broken source link"; exit 1; }

rm -f "$TEST_STRICT_WS/wiki/concepts/broken-source.md"

# Lint should pass again once broken files are removed
(cd "$TEST_STRICT_WS" && ./rnex plugin karpathy-llm lint --strict >/dev/null) || {
  fail "lint --strict failed after removing broken files"; exit 1;
}
pass

# --------------------------------------------------------------------------
# Test 9: User Skill Projection and Disable Cleanup
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
[ -f "$TEST_KARPATHY_WS/wiki/_index.md" ] || { fail "wiki/_index.md was deleted on disable"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/wiki/hot.md" ] || { fail "wiki/hot.md exists after disable"; exit 1; }

# Re-enable karpathy-llm for subsequent tests and clean up mock provider
(cd "$TEST_KARPATHY_WS" && ./rnex plugin enable karpathy-llm >/dev/null)
(cd "$TEST_KARPATHY_WS" && ./rnex plugin disable mock-provider >/dev/null)
rm -rf "$TEST_KARPATHY_WS/plugins/mock-provider" "$TEST_KARPATHY_WS/.mock"
pass

# --------------------------------------------------------------------------
# Test 10: Configurable wiki_dir and Leaked Placeholder Purge
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
[ -d "$TEST_KARPATHY_WS/docs/wiki/_index" ] || { fail "Custom docs/wiki/_index missing"; exit 1; }
[ -d "$TEST_KARPATHY_WS/docs/wiki/_graph" ] || { fail "Custom docs/wiki/_graph missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/docs/wiki/_index.md" ] || { fail "docs/wiki/_index.md missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/docs/wiki/_log.md" ] || { fail "docs/wiki/_log.md missing"; exit 1; }
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
# Test 11: Member Repository Ingestion and Curation Preservation
# --------------------------------------------------------------------------
run_test "Karpathy-llm: member repository ingestion and curation preservation"
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

# Verify member repo README was ingested into wiki/repos/auth-svc/readme.md
[ -f "$TEST_REPO_WS/wiki/repos/auth-svc/readme.md" ] || { fail "wiki/repos/auth-svc/readme.md missing after ingest"; exit 1; }
grep -q "Authentication and authorization microservice" "$TEST_REPO_WS/wiki/repos/auth-svc/readme.md" || {
  fail "Member README content missing"; exit 1;
}

# Verify nodes.tsv registration
grep -q 'auth-svc-readme' "$TEST_REPO_WS/wiki/_graph/nodes.tsv" || {
  fail "auth-svc-readme not registered in nodes.tsv: $(cat "$TEST_REPO_WS/wiki/_graph/nodes.tsv")"; exit 1;
}

# Curate the member repo file with custom invariant
cat <<'EOF_CURATED' >> "$TEST_REPO_WS/wiki/repos/auth-svc/readme.md"

## Curated Invariant
- Tokens must validate JWKS with exponential caching.
EOF_CURATED

# Re-run ingest to verify curation is preserved when source hasn't changed
(cd "$TEST_REPO_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)
grep -q "Curated Invariant" "$TEST_REPO_WS/wiki/repos/auth-svc/readme.md" || {
  fail "Curated invariant was overwritten on re-ingest"; exit 1;
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
[ ! -d "$TEST_REPO_WS/wiki/repos/disabled-repo" ] || { fail "Disabled repository was ingested into wiki"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
