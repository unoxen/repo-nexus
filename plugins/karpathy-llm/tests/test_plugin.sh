#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# File: plugins/karpathy-llm/tests/test_plugin.sh
# Architectural Layer: Quality Assurance / Integration Test Automation
# Design Pattern: Test Suite (Template Method)
# Responsibilities:
#   - Validates Karpathy LLM Wiki plugin manifest, commands, and hooks.
#   - Asserts B-Tree sharded index (_index/) compilation and shard splitting.
#   - Asserts sorted TSV graph store (_graph/) population and neighborhood traversal.
#   - Validates fast O(log N) prefix search and strict linting.
#   - Enforces 100% negative assertions against legacy hot.md cache.
# ============================================================================
set -e

[ -n "$DIR" ] && [ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
[ -f "$DIR/rnex" ] || DIR="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
. "$DIR/tests/test_helper.sh"

TEST_KARPATHY_WS="$TEST_TMP/karpathy-plugin-ws"
mkdir -p "$TEST_KARPATHY_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_KARPATHY_WS"
cd "$TEST_KARPATHY_WS"

_kl_pdir="$TEST_KARPATHY_WS/plugins/karpathy-llm"

# --------------------------------------------------------------------------
run_test "Karpathy-llm: manifest integrity, version parity, and documentation accuracy"
_cli_ver="$("$TEST_KARPATHY_WS/rnex" --version | awk '{print $2}')"
_m_ver="$(awk '/^version:[ ]*/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); print; exit }' "$_kl_pdir/plugin.yaml")"
[ "$_m_ver" = "$_cli_ver" ] || { fail "Plugin version ($_m_ver) does not match CLI version ($_cli_ver)"; exit 1; }

_yaml_file="$_kl_pdir/plugin.yaml"
# Assert placeholders are quoted in plugin.yaml and hot.md is removed
grep -q 'templates/index\.md:[ ]*"{wiki_dir}/index\.md"' "$_yaml_file" || { fail "index.md placeholder not quoted in plugin.yaml"; exit 1; }
! grep -q 'templates/hot\.md' "$_yaml_file" || { fail "hot.md should not be in plugin.yaml"; exit 1; }

# Assert B-Tree and TSV Graph configuration defaults
grep -q 'btree_shard_max_entries:' "$_yaml_file" || { fail "btree_shard_max_entries missing in plugin.yaml"; exit 1; }
grep -q 'btree_root_max_lines:' "$_yaml_file" || { fail "btree_root_max_lines missing in plugin.yaml"; exit 1; }
grep -q 'graph_default_depth:' "$_yaml_file" || { fail "graph_default_depth missing in plugin.yaml"; exit 1; }
grep -q 'index_dir: "_index"' "$_yaml_file" || { fail "index_dir default missing in plugin.yaml"; exit 1; }
grep -q 'graph_dir: "_graph"' "$_yaml_file" || { fail "graph_dir default missing in plugin.yaml"; exit 1; }

# Assert subcommands registered
grep -q "init:" "$_yaml_file" || { fail "init command missing in plugin.yaml"; exit 1; }
grep -q "ingest:" "$_yaml_file" || { fail "ingest command missing in plugin.yaml"; exit 1; }
grep -q "index:" "$_yaml_file" || { fail "index command missing in plugin.yaml"; exit 1; }
grep -q "graph:" "$_yaml_file" || { fail "graph command missing in plugin.yaml"; exit 1; }
grep -q "search:" "$_yaml_file" || { fail "search command missing in plugin.yaml"; exit 1; }
grep -q "lint:" "$_yaml_file" || { fail "lint command missing in plugin.yaml"; exit 1; }

# Verify valid YAML parsing if ruby is available
if command -v ruby >/dev/null 2>&1; then
  ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$_yaml_file" || { fail "karpathy-llm plugin.yaml is not valid YAML"; exit 1; }
fi

# Assert obsolete options absent
! grep -q "lint_trigger" "$_yaml_file" || { fail "lint_trigger still present in plugin.yaml"; exit 1; }
! grep -q "notify_on_changes" "$_yaml_file" || { fail "notify_on_changes still present in plugin.yaml"; exit 1; }
! grep -q "ingest_member_readmes" "$_yaml_file" || { fail "ingest_member_readmes still present in plugin.yaml"; exit 1; }
! grep -q "hot_file" "$_yaml_file" || { fail "hot_file still present in plugin.yaml"; exit 1; }

_readme_file="$_kl_pdir/README.md"
[ -f "$_readme_file" ] || { fail "README.md missing"; exit 1; }
grep -q "sources" "$_readme_file" || { fail "README.md does not document sources"; exit 1; }
! grep -q "ingest_member_readmes" "$_readme_file" || { fail "README.md still mentions obsolete ingest_member_readmes"; exit 1; }
! grep -q "auto_index" "$_readme_file" || { fail "README.md still mentions auto_index"; exit 1; }
! grep -q "run_deterministic_checks" "$_readme_file" || { fail "README.md still mentions run_deterministic_checks"; exit 1; }
! grep -q "ai_cmd" "$_readme_file" || { fail "README.md still mentions ai_cmd"; exit 1; }

_prompt_file="$_kl_pdir/instructions/rnex-scaffolding-meta-prompt.md"
[ -f "$_prompt_file" ] || { fail "rnex-scaffolding-meta-prompt.md missing"; exit 1; }
grep -q "sources: \[\][ ]*#[ ]*\./docs/ files this page was derived from" "$_prompt_file" || { fail "sources example does not reference ./docs/"; exit 1; }
grep -q "# Typed relation fields — paths relative to wiki/" "$_prompt_file" || { fail "relations example does not reference wiki/"; exit 1; }
grep -q "rules/behavioral\.md" "$_prompt_file" || { fail "rnex-scaffolding-meta-prompt.md missing rules/behavioral.md"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: init --karpathy sets up B-Tree shards, TSV graph store, bounded root, and zero hot.md"
"$TEST_KARPATHY_WS/rnex" init -y --karpathy "$TEST_KARPATHY_WS" >/dev/null
[ -d "$TEST_KARPATHY_WS/wiki" ] || { fail "wiki/ directory missing after init --karpathy"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/index.md" ] || { fail "wiki/index.md missing after init --karpathy"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_log.md" ] || { fail "wiki/_log.md missing after init --karpathy"; exit 1; }
[ -d "$TEST_KARPATHY_WS/docs" ] || { fail "docs/ directory missing after init --karpathy"; exit 1; }

# Negative assertion: hot.md must NOT exist
[ ! -e "$TEST_KARPATHY_WS/wiki/hot.md" ] || { fail "wiki/hot.md created after init --karpathy"; exit 1; }

# B-Tree index directory and shards
[ -d "$TEST_KARPATHY_WS/wiki/_index" ] || { fail "wiki/_index/ directory missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_index/overview.md" ] || { fail "wiki/_index/overview.md missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_index/concepts.md" ] || { fail "wiki/_index/concepts.md missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_index/entities.md" ] || { fail "wiki/_index/entities.md missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_index/sources.md" ] || { fail "wiki/_index/sources.md missing"; exit 1; }

# TSV Property Graph directory and tables
[ -d "$TEST_KARPATHY_WS/wiki/_graph" ] || { fail "wiki/_graph/ directory missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_graph/nodes.tsv" ] || { fail "wiki/_graph/nodes.tsv missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_graph/edges_out.tsv" ] || { fail "wiki/_graph/edges_out.tsv missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_graph/edges_in.tsv" ] || { fail "wiki/_graph/edges_in.tsv missing"; exit 1; }

# Verify clean B-Tree Root index.md (strictly <= 80 lines, no YAML frontmatter)
_first_idx_line="$(head -n 1 "$TEST_KARPATHY_WS/wiki/index.md" 2>/dev/null || true)"
[ "$_first_idx_line" = "# Wiki Index (B-Tree Root Router)" ] || { fail "wiki/index.md header mismatch: $_first_idx_line"; exit 1; }
! grep -q "^---" "$TEST_KARPATHY_WS/wiki/index.md" || { fail "wiki/index.md contains YAML frontmatter"; exit 1; }
! grep -q "YYYY-MM-DD" "$TEST_KARPATHY_WS/wiki/index.md" || { fail "wiki/index.md contains YYYY-MM-DD placeholder"; exit 1; }
! grep -q "last_updated" "$TEST_KARPATHY_WS/wiki/index.md" || { fail "wiki/index.md contains last_updated"; exit 1; }
_root_lines="$(wc -l < "$TEST_KARPATHY_WS/wiki/index.md")"
[ "$_root_lines" -le 80 ] || { fail "wiki/index.md exceeded 80 lines: $_root_lines"; exit 1; }
grep -q "B-Tree Domain Shards" "$TEST_KARPATHY_WS/wiki/index.md" || { fail "wiki/index.md missing B-Tree Domain Shards section"; exit 1; }
grep -q "Sorted TSV Property Graph" "$TEST_KARPATHY_WS/wiki/index.md" || { fail "wiki/index.md missing Sorted TSV Property Graph section"; exit 1; }

# Verify dynamic date in _log.md
grep -q -E '^### Initial Setup — 20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$TEST_KARPATHY_WS/wiki/_log.md" || { fail "wiki/_log.md missing valid Initial Setup date header"; exit 1; }

# Scoped assets in .rnex/plugins/karpathy-llm/
[ -d "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm" ] || { fail ".rnex/plugins/karpathy-llm missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm/rules/behavioral.md" ] || { fail "behavioral.md missing in scoped dir"; exit 1; }
[ -f "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm/skills/wiki-ingest.md" ] || { fail "wiki-ingest.md missing in scoped dir"; exit 1; }
[ -f "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm/skills/wiki-lint.md" ] || { fail "wiki-lint.md missing in scoped dir"; exit 1; }
[ -f "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" ] || { fail "rnex-wiki-page.template.md missing"; exit 1; }
! grep -q "/\.rnex/\.rnex" "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" || { fail "Corrupted /.rnex/.rnex in template"; exit 1; }

# Instructions compilation: B-Tree 3-step retrieval protocol in .rnex/ai-instructions.md
_ai_content="$(cat "$TEST_KARPATHY_WS/.rnex/ai-instructions.md")"
echo "$_ai_content" | grep -q "B-Tree router" || { fail "B-Tree router instructions missing in ai-instructions.md"; exit 1; }
! echo "$_ai_content" | grep -q "wiki/hot.md" || { fail "ai-instructions.md still references wiki/hot.md"; exit 1; }
! echo "$_ai_content" | grep -q "Read Wiki Hot Cache" || { fail "ai-instructions.md still references Read Wiki Hot Cache"; exit 1; }

# Plugin info inspection
_pinfo="$(cd "$TEST_KARPATHY_WS" && ./rnex plugin info karpathy-llm 2>&1)"
echo "$_pinfo" | grep -q "karpathy-llm" || { fail "Plugin name missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "wiki_dir" || { fail "wiki_dir option missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "sources" || { fail "sources option missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "init" || { fail "init command missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "ingest" || { fail "ingest command missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "index" || { fail "index command missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "graph" || { fail "graph command missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "search" || { fail "search command missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "lint" || { fail "lint command missing from info: $_pinfo"; exit 1; }
pass

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

# Clean up synthetic mock provider
(cd "$TEST_KARPATHY_WS" && ./rnex plugin disable mock-provider >/dev/null)
rm -rf "$TEST_KARPATHY_WS/plugins/mock-provider" "$TEST_KARPATHY_WS/.mock"
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: configurable wiki_dir, placeholder resolution, and leaked dir cleanup"
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
[ -f "$TEST_KARPATHY_WS/docs/wiki/index.md" ] || { fail "docs/wiki/index.md missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/docs/wiki/_log.md" ] || { fail "docs/wiki/_log.md missing"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/docs/wiki/hot.md" ] || { fail "docs/wiki/hot.md found in custom wiki"; exit 1; }

# Verify bogus directories were purged by sync
[ ! -d "$TEST_KARPATHY_WS/\"{wiki_dir}" ] || { fail "Bogus directory \"{wiki_dir} still exists"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/\"{raw_dir}" ] || { fail "Bogus directory \"{raw_dir} still exists"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/{wiki_dir}" ] || { fail "Bogus directory {wiki_dir} still exists"; exit 1; }
[ ! -d "$TEST_KARPATHY_WS/{raw_dir}" ] || { fail "Bogus directory {raw_dir} still exists"; exit 1; }

# Verify updating wiki_dir to ./custom-wiki and ./wiki works cleanly
cat <<'EOF_CFG2' > "$TEST_KARPATHY_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: ./custom-wiki
    sources: [intake/raw]
repos:
EOF_CFG2
(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_KARPATHY_WS/custom-wiki/index.md" ] || { fail "custom-wiki/index.md missing"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/custom-wiki/hot.md" ] || { fail "custom-wiki/hot.md found"; exit 1; }

cat <<'EOF_CFG3' > "$TEST_KARPATHY_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: ./wiki
    sources: [docs, "repos/**/README.md"]
repos:
EOF_CFG3
(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)
[ -f "$TEST_KARPATHY_WS/wiki/index.md" ] || { fail "wiki/index.md missing"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/wiki/hot.md" ] || { fail "wiki/hot.md found"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: member repository README auto-ingestion, non-destructive curation, and log deduplication"
mkdir -p "$TEST_KARPATHY_WS/repos/auth-svc"
printf '# Auth Service\nAuthentication and authorization microservice.\n' > "$TEST_KARPATHY_WS/repos/auth-svc/README.md"
printf '  auth-svc:\n' >> "$TEST_KARPATHY_WS/rnex.yaml"

(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)

# Verify member repo README ingested into atomic wiki page
[ -f "$TEST_KARPATHY_WS/wiki/repo-auth-svc.md" ] || { fail "repo-auth-svc.md missing after wiki ingest"; exit 1; }
grep -q 'title: "Member Repo: auth-svc"' "$TEST_KARPATHY_WS/wiki/repo-auth-svc.md" || { fail "Frontmatter title missing"; exit 1; }
grep -q 'tags: \[member-repo, auth-svc\]' "$TEST_KARPATHY_WS/wiki/repo-auth-svc.md" || { fail "Frontmatter tags missing"; exit 1; }
grep -q 'sources: \["repos/auth-svc/README.md"\]' "$TEST_KARPATHY_WS/wiki/repo-auth-svc.md" || { fail "Frontmatter sources missing"; exit 1; }
grep -q "Authentication and authorization microservice" "$TEST_KARPATHY_WS/wiki/repo-auth-svc.md" || { fail "Summary missing"; exit 1; }

# Verify nodes.tsv and B-Tree entities shard registration
grep -q '^repo-auth-svc[ 	]' "$TEST_KARPATHY_WS/wiki/_graph/nodes.tsv" || { fail "repo-auth-svc not in nodes.tsv"; exit 1; }
grep -q 'repo-auth-svc' "$TEST_KARPATHY_WS/wiki/_index/entities.md" || { fail "repo-auth-svc not in _index/entities.md"; exit 1; }
[ ! -e "$TEST_KARPATHY_WS/wiki/hot.md" ] || { fail "hot.md found in auth-svc test workspace"; exit 1; }
grep -q "Member Repo Ingest: auth-svc" "$TEST_KARPATHY_WS/wiki/_log.md" || { fail "Ingest log missing from _log.md"; exit 1; }

# Curate repo-auth-svc.md with custom fields and body
cat <<'EOF_PAGE' > "$TEST_KARPATHY_WS/wiki/repo-auth-svc.md"
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

# Update source README to simulate change
sleep 1
printf '# Auth Service (Upgraded)\nUpdated authentication logic.\n' > "$TEST_KARPATHY_WS/repos/auth-svc/README.md"

(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)

# Verify curated fields and custom notes are strictly preserved
grep -q 'title: "Member Repo: auth-svc (Curated)"' "$TEST_KARPATHY_WS/wiki/repo-auth-svc.md" || { fail "Curated title overwritten"; exit 1; }
grep -q 'related: \["repo-billing\.md"\]' "$TEST_KARPATHY_WS/wiki/repo-auth-svc.md" || { fail "Curated related overwritten"; exit 1; }
grep -q 'extends: \["specs/oauth2\.md"\]' "$TEST_KARPATHY_WS/wiki/repo-auth-svc.md" || { fail "Curated extends overwritten"; exit 1; }
grep -q "Curated Invariant" "$TEST_KARPATHY_WS/wiki/repo-auth-svc.md" || { fail "Curated notes body overwritten"; exit 1; }

# Verify _log.md has only 1 entry for auth-svc ingest (no duplicate entries)
_log_cnt="$(grep -c "Member Repo Ingest: auth-svc" "$TEST_KARPATHY_WS/wiki/_log.md" || true)"
[ "$_log_cnt" -eq 1 ] || { fail "Expected 1 log entry for auth-svc, got $_log_cnt"; exit 1; }

# Verify disabled member repos are NOT ingested
mkdir -p "$TEST_KARPATHY_WS/repos/disabled-repo"
printf '# Disabled Repo\n' > "$TEST_KARPATHY_WS/repos/disabled-repo/README.md"
cat <<'EOF_DIS' >> "$TEST_KARPATHY_WS/rnex.yaml"
  disabled-repo:
    enabled: false
EOF_DIS
(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)
[ ! -f "$TEST_KARPATHY_WS/wiki/repo-disabled-repo.md" ] || { fail "Disabled repository was ingested into wiki"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: B-Tree sharding, automatic shard splitting, and O(log N) prefix search"
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
---
title: "Concept: ${_cname}"
tags: [concept]
---

# ${_cname}
Detailed explanation of ${_cname} pattern.
EOF_C
done

# Run index rebuild to compile nodes.tsv and B-Tree shards
(cd "$TEST_BTREE_WS" && ./rnex plugin karpathy-llm index --rebuild >/dev/null)

# Verify that concepts shard split into a-m and n-z sub-shards
[ -f "$TEST_BTREE_WS/wiki/_index/concepts-a-m.md" ] || { fail "concepts-a-m.md missing after split"; exit 1; }
[ -f "$TEST_BTREE_WS/wiki/_index/concepts-n-z.md" ] || { fail "concepts-n-z.md missing after split"; exit 1; }

# Verify sorted contents in each shard
grep -q "auth-tokens" "$TEST_BTREE_WS/wiki/_index/concepts-a-m.md" || { fail "auth-tokens missing from concepts-a-m.md"; exit 1; }
grep -q "jwt" "$TEST_BTREE_WS/wiki/_index/concepts-a-m.md" || { fail "jwt missing from concepts-a-m.md"; exit 1; }
grep -q "networking" "$TEST_BTREE_WS/wiki/_index/concepts-n-z.md" || { fail "networking missing from concepts-n-z.md"; exit 1; }
grep -q "queues" "$TEST_BTREE_WS/wiki/_index/concepts-n-z.md" || { fail "queues missing from concepts-n-z.md"; exit 1; }

# Verify B-Tree Root routing table reflects sub-shards and is bounded (<= 80 lines)
_root_lines="$(wc -l < "$TEST_BTREE_WS/wiki/index.md")"
[ "$_root_lines" -le 80 ] || { fail "Root index.md exceeded 80 lines: $_root_lines"; exit 1; }
grep -q 'concepts-a-m' "$TEST_BTREE_WS/wiki/index.md" || { fail "concepts-a-m missing from root router table"; exit 1; }
grep -q 'concepts-n-z' "$TEST_BTREE_WS/wiki/index.md" || { fail "concepts-n-z missing from root router table"; exit 1; }

# Test O(log N) prefix search lookup
_search_res="$( (cd "$TEST_BTREE_WS" && ./rnex plugin karpathy-llm search "caching") 2>/dev/null )"
echo "$_search_res" | grep -q "caching" || { fail "Search for caching failed: $_search_res"; exit 1; }
echo "$_search_res" | grep -q "_index/concepts-a-m.md" || { fail "Search did not return shard path: $_search_res"; exit 1; }

# Test prefix search matching multiple entries starting with 'n'
_search_multi="$( (cd "$TEST_BTREE_WS" && ./rnex plugin karpathy-llm search "n") 2>/dev/null )"
echo "$_search_multi" | grep -q "networking" || { fail "Search prefix 'n' did not match networking: $_search_multi"; exit 1; }

# Test prefix search with non-existent prefix (reports no matching nodes, exit 0)
_search_none="$( (cd "$TEST_BTREE_WS" && ./rnex plugin karpathy-llm search "xyz-not-found") 2>/dev/null || true )"
echo "$_search_none" | grep -q 'No matching wiki nodes found for prefix "xyz-not-found"' || { fail "Search for non-existent prefix failed to report no matches: $_search_none"; exit 1; }

[ ! -e "$TEST_BTREE_WS/wiki/hot.md" ] || { fail "hot.md found in btree test workspace"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: multi-source intake, recursive directory resolution, slug collision, and legacy raw_dir migration"
TEST_INTAKE_WS="$TEST_TMP/karpathy-intake-ws"
mkdir -p "$TEST_INTAKE_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_INTAKE_WS"
cd "$TEST_INTAKE_WS"
"$TEST_INTAKE_WS/rnex" init -y --karpathy "$TEST_INTAKE_WS" >/dev/null

mkdir -p "$TEST_INTAKE_WS/docs/api" "$TEST_INTAKE_WS/docs/guide" "$TEST_INTAKE_WS/docs/nested/deep" "$TEST_INTAKE_WS/docs/.obsidian"
cat <<'EOF_DOC' > "$TEST_INTAKE_WS/docs/overview.md"
# Workspace Overview
Core architecture and concepts.
EOF_DOC

cat <<'EOF_DOC' > "$TEST_INTAKE_WS/docs/api/README.md"
# API Specification
Endpoints and contracts.
EOF_DOC

cat <<'EOF_DOC' > "$TEST_INTAKE_WS/docs/guide/README.md"
# Guide Index
Step-by-step developer guide.
EOF_DOC

cat <<'EOF_DOC' > "$TEST_INTAKE_WS/docs/nested/deep/spec [v1].md"
# Deep Spec V1
Detailed specifications.
EOF_DOC

cat <<'EOF_DOC' > "$TEST_INTAKE_WS/docs/.hidden.md"
# Hidden File
Should not be ingested.
EOF_DOC

cat <<'EOF_DOC' > "$TEST_INTAKE_WS/docs/.obsidian/note.md"
# Obsidian Note
Should not be ingested.
EOF_DOC

(cd "$TEST_INTAKE_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

[ -f "$TEST_INTAKE_WS/wiki/docs-overview.md" ] || { fail "docs-overview.md missing after ingest"; exit 1; }
[ -f "$TEST_INTAKE_WS/wiki/docs-api-readme.md" ] || { fail "docs-api-readme.md missing (API README collision)"; exit 1; }
[ -f "$TEST_INTAKE_WS/wiki/docs-guide-readme.md" ] || { fail "docs-guide-readme.md missing (Guide README collision)"; exit 1; }
[ -f "$TEST_INTAKE_WS/wiki/docs-nested-deep-spec-v1.md" ] || { fail "docs-nested-deep-spec-v1.md missing (spaces/brackets)"; exit 1; }
[ ! -f "$TEST_INTAKE_WS/wiki/hidden.md" ] || { fail "Hidden file was ingested"; exit 1; }
[ ! -f "$TEST_INTAKE_WS/wiki/note.md" ] || { fail "Hidden directory file was ingested"; exit 1; }

# Test legacy raw_dir migration on sync
cat <<'EOF_LEGACY' > "$TEST_INTAKE_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    raw_dir: custom_raw
    ingest_member_readmes: true
repos:
EOF_LEGACY
mkdir -p "$TEST_INTAKE_WS/custom_raw"
echo "# Legacy Raw Note" > "$TEST_INTAKE_WS/custom_raw/legacy.md"

(cd "$TEST_INTAKE_WS" && ./rnex sync -y >/dev/null)
! grep -q "raw_dir:" "$TEST_INTAKE_WS/rnex.yaml" || { fail "raw_dir was not rewritten to sources on sync"; exit 1; }
! grep -q "ingest_member_readmes" "$TEST_INTAKE_WS/rnex.yaml" || { fail "ingest_member_readmes was not stripped on sync"; exit 1; }
grep -q "sources:" "$TEST_INTAKE_WS/rnex.yaml" || { fail "sources key missing after sync rewrite"; exit 1; }
grep -q -- "- custom_raw" "$TEST_INTAKE_WS/rnex.yaml" || { fail "- custom_raw missing under sources"; exit 1; }
[ ! -e "$TEST_INTAKE_WS/wiki/hot.md" ] || { fail "hot.md found in intake workspace"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: CLI commands ingest and lint with options and strict validation"
# Test ingest with --source option
printf '# Roadmap\nFuture project roadmap.\n' > "$TEST_INTAKE_WS/docs/roadmap.md"
(cd "$TEST_INTAKE_WS" && ./rnex plugin karpathy-llm ingest --source docs/roadmap.md >/dev/null)
[ -f "$TEST_INTAKE_WS/wiki/docs-roadmap.md" ] || { fail "wiki/docs-roadmap.md not created by ingest --source"; exit 1; }

# Test lint passing
_lint_ok="$(cd "$TEST_INTAKE_WS" && ./rnex plugin karpathy-llm lint 2>&1)" || { fail "lint failed: $_lint_ok"; exit 1; }
echo "$_lint_ok" | grep -q "Wiki lint passed" || { fail "Lint output mismatch: $_lint_ok"; exit 1; }

# Test lint --strict failing on broken source link
cat > "$TEST_INTAKE_WS/wiki/broken-doc.md" <<'EOF_BROKEN'
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
(cd "$TEST_INTAKE_WS" && ./rnex plugin karpathy-llm lint --strict >/dev/null 2>&1) || _lint_strict_err=1
[ "$_lint_strict_err" -eq 1 ] || { fail "lint --strict did not exit non-zero on broken source link"; exit 1; }
rm -f "$TEST_INTAKE_WS/wiki/broken-doc.md"

# Test lint --strict failing on broken wikilink
cat > "$TEST_INTAKE_WS/wiki/broken-link-page.md" <<'EOF_BLP'
---
title: Broken Wikilink Page
---

# Broken Page
References missing target [[nonexistent-target-slug]].
EOF_BLP

(cd "$TEST_INTAKE_WS" && ./rnex plugin karpathy-llm index --rebuild >/dev/null)
_lint_wl_err=0
_lint_wl_out="$( (cd "$TEST_INTAKE_WS" && ./rnex plugin karpathy-llm lint --strict) 2>&1 )" || _lint_wl_err=1
[ "$_lint_wl_err" -eq 1 ] || { fail "lint --strict did not exit non-zero on broken wikilink"; exit 1; }
echo "$_lint_wl_out" | grep -q "nonexistent-target-slug" || { fail "lint output did not mention broken wikilink: $_lint_wl_out"; exit 1; }

rm -f "$TEST_INTAKE_WS/wiki/broken-link-page.md"
(cd "$TEST_INTAKE_WS" && ./rnex plugin karpathy-llm index --rebuild >/dev/null)

# Test auto-purge of legacy hot.md during lint
touch "$TEST_INTAKE_WS/wiki/hot.md"
[ -f "$TEST_INTAKE_WS/wiki/hot.md" ] || { fail "Failed to seed fake hot.md"; exit 1; }
(cd "$TEST_INTAKE_WS" && ./rnex plugin karpathy-llm lint >/dev/null)
[ ! -e "$TEST_INTAKE_WS/wiki/hot.md" ] || { fail "hot.md was not purged by lint"; exit 1; }
grep -q "Legacy Hot Cache Purge" "$TEST_INTAKE_WS/wiki/_log.md" || { fail "_log.md missing audit of hot.md purge"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: single-file ingestion, --file flag, missing-file validation, and batch fallback"
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

printf '# Document A\nSingle file A content.\n' > "$TEST_SF_WS/raw/doc-a.md"
printf '# Document B\nSingle file B content.\n' > "$TEST_SF_WS/raw/doc-b.md"
printf '# Document C\nSingle file C content.\n' > "$TEST_SF_WS/raw/doc-c.md"

# Test Case 1: Positional single file ingestion
(cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest raw/doc-a.md >/dev/null)
[ -f "$TEST_SF_WS/wiki/raw-doc-a.md" ] || { fail "wiki/raw-doc-a.md missing after single-file positional ingest"; exit 1; }
[ ! -f "$TEST_SF_WS/wiki/raw-doc-b.md" ] || { fail "wiki/raw-doc-b.md should not have been ingested during single-file ingest"; exit 1; }
[ ! -f "$TEST_SF_WS/wiki/raw-doc-c.md" ] || { fail "wiki/raw-doc-c.md should not have been ingested during single-file ingest"; exit 1; }

# Test Case 2: --file / -f flag single file ingestion
(cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest --file raw/doc-b.md >/dev/null)
[ -f "$TEST_SF_WS/wiki/raw-doc-b.md" ] || { fail "wiki/raw-doc-b.md missing after --file ingest"; exit 1; }
[ ! -f "$TEST_SF_WS/wiki/raw-doc-c.md" ] || { fail "wiki/raw-doc-c.md should not have been ingested during --file ingest"; exit 1; }

# Test Case 3: Missing file error and exit code non-zero
_missing_err=0
_err_out="$( (cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest raw/nonexistent.md) 2>&1 )" || _missing_err=1
[ "$_missing_err" -eq 1 ] || { fail "ingest of nonexistent file expected non-zero exit code"; exit 1; }
echo "$_err_out" | grep -q 'File not found: "raw/nonexistent.md"' || { fail "Missing file error message mismatch: $_err_out"; exit 1; }

# Test Case 3b: Directory argument error and exit code non-zero
_dir_err=0
_dir_out="$( (cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest raw) 2>&1 )" || _dir_err=1
[ "$_dir_err" -eq 1 ] || { fail "ingest of directory argument expected non-zero exit code"; exit 1; }
echo "$_dir_out" | grep -q 'Expected a file path, but "raw" is a directory' || { fail "Directory error message mismatch: $_dir_out"; exit 1; }

# Test Case 4: Batch fallback when no file argument is passed
(cd "$TEST_SF_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)
[ -f "$TEST_SF_WS/wiki/raw-doc-c.md" ] || { fail "wiki/raw-doc-c.md missing after batch fallback ingest"; exit 1; }
[ ! -e "$TEST_SF_WS/wiki/hot.md" ] || { fail "hot.md found in single-file test workspace"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: nested repos/**/README.md slug routing, graph edge population, and subgraph traversal"
TEST_NESTED_WS="$TEST_TMP/karpathy-nested-ws"
mkdir -p "$TEST_NESTED_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_NESTED_WS"
cd "$TEST_NESTED_WS"
"$TEST_NESTED_WS/rnex" init -y --karpathy "$TEST_NESTED_WS" >/dev/null

# 1. Nested repository README under repos/app-repo/apps/web/README.md
mkdir -p "$TEST_NESTED_WS/repos/app-repo/apps/web"
printf '# Root App\nRoot repo architecture.\n' > "$TEST_NESTED_WS/repos/app-repo/README.md"
printf '# Web App\nNested sub-application architecture.\n' > "$TEST_NESTED_WS/repos/app-repo/apps/web/README.md"
cat <<'EOF_NESTED_CFG' >> "$TEST_NESTED_WS/rnex.yaml"
  app-repo:
EOF_NESTED_CFG

(cd "$TEST_NESTED_WS" && ./rnex sync -y >/dev/null)
(cd "$TEST_NESTED_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Verify root member repo README routes to repo-app-repo.md
[ -f "$TEST_NESTED_WS/wiki/repo-app-repo.md" ] || { fail "repo-app-repo.md missing for root member repo"; exit 1; }

# Verify nested README routes to repos-app-repo-apps-web-readme.md (not repo-app-repo.md)
[ -f "$TEST_NESTED_WS/wiki/repos-app-repo-apps-web-readme.md" ] || { fail "repos-app-repo-apps-web-readme.md missing for nested repo README"; exit 1; }

# 2. Add an interlinked page to test graph edge population and traversal
cat <<'EOF_GATEWAY' > "$TEST_NESTED_WS/wiki/gateway.md"
---
title: "API Gateway"
tags: [concept]
---

# API Gateway
Routes traffic to [[repo-app-repo]] and [[repos-app-repo-apps-web-readme]].
EOF_GATEWAY

(cd "$TEST_NESTED_WS" && ./rnex plugin karpathy-llm index --rebuild >/dev/null)

# Verify Outbound dependencies for gateway
_graph_gw="$(cd "$TEST_NESTED_WS" && ./rnex plugin karpathy-llm graph gateway --depth 1)"
echo "$_graph_gw" | grep -q -- "- \`gateway\` --\[links_to\]--> \`\[\[repo-app-repo\]\]\`" || { fail "Outbound edge to repo-app-repo missing: $_graph_gw"; exit 1; }
echo "$_graph_gw" | grep -q -- "- \`gateway\` --\[links_to\]--> \`\[\[repos-app-repo-apps-web-readme\]\]\`" || { fail "Outbound edge to nested readme missing: $_graph_gw"; exit 1; }

# Verify Inbound backlinks for repo-app-repo
_graph_repo="$(cd "$TEST_NESTED_WS" && ./rnex plugin karpathy-llm graph repo-app-repo --depth 1)"
echo "$_graph_repo" | grep -q -- "- \`\[\[gateway\]\]\` --\[links_to\]--> \`repo-app-repo\`" || { fail "Inbound backlink from gateway missing: $_graph_repo"; exit 1; }

# 3. _log.md idempotency test
_log_bytes_before="$(wc -c < "$TEST_NESTED_WS/wiki/_log.md" | tr -d ' ')"
(cd "$TEST_NESTED_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)
_log_bytes_after="$(wc -c < "$TEST_NESTED_WS/wiki/_log.md" | tr -d ' ')"
[ "$_log_bytes_before" = "$_log_bytes_after" ] || { fail "_log.md changed on repeated ingest with 0 new files (before=$_log_bytes_before, after=$_log_bytes_after)"; exit 1; }

[ ! -e "$TEST_NESTED_WS/wiki/hot.md" ] || { fail "hot.md found in nested test workspace"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: deterministic index rebuild, graph consistency, and complete hot.md purge"
TEST_HOT_WS="$TEST_TMP/karpathy-hot-ws"
mkdir -p "$TEST_HOT_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_HOT_WS"
cd "$TEST_HOT_WS"
"$TEST_HOT_WS/rnex" init -y --karpathy "$TEST_HOT_WS" >/dev/null

# 1. Verify wiki/hot.md is NOT in git.ignore or .gitignore
! grep -q "wiki/hot.md" "$TEST_HOT_WS/rnex.yaml" || { fail "wiki/hot.md should not be in default git.ignore in rnex.yaml"; exit 1; }
! grep -q "wiki/hot.md" "$TEST_HOT_WS/.gitignore" || { fail "wiki/hot.md should not be in .gitignore"; exit 1; }

# 2. Create 15 source files, including one with a massive 10,000-character single-line paragraph
_huge_line="$(awk 'BEGIN { for (i=0; i<200; i++) printf "MassiveUnbrokenContextPayloadSegment_%d_WithVerboseDetails ", i }')"
for _fidx in $(seq 1 15); do
  printf '# Source Doc %s\n%s\n' "$_fidx" "$_huge_line" > "$TEST_HOT_WS/docs/doc-$_fidx.md"
done

(cd "$TEST_HOT_WS" && ./rnex plugin karpathy-llm ingest >/dev/null)

# Verify B-Tree Root index.md is bounded (<= 80 lines)
_root_lines="$(wc -l < "$TEST_HOT_WS/wiki/index.md")"
[ "$_root_lines" -le 80 ] || { fail "index.md size exceeded 80 lines: $_root_lines lines"; exit 1; }

# Verify sorted TSV graph files exist and pass strict LC_ALL=C sort check
LC_ALL=C sort -c "$TEST_HOT_WS/wiki/_graph/nodes.tsv" || { fail "nodes.tsv is not sorted in LC_ALL=C order"; exit 1; }
LC_ALL=C sort -c "$TEST_HOT_WS/wiki/_graph/edges_out.tsv" || { fail "edges_out.tsv is not sorted in LC_ALL=C order"; exit 1; }
LC_ALL=C sort -c "$TEST_HOT_WS/wiki/_graph/edges_in.tsv" || { fail "edges_in.tsv is not sorted in LC_ALL=C order"; exit 1; }

# 3. Simulate legacy hot.md existence and verify automatic purge during index --rebuild and lint
echo "legacy hot cache content" > "$TEST_HOT_WS/wiki/hot.md"
[ -f "$TEST_HOT_WS/wiki/hot.md" ] || { fail "Failed to seed fake hot.md"; exit 1; }

(cd "$TEST_HOT_WS" && ./rnex plugin karpathy-llm index --rebuild >/dev/null)
[ ! -e "$TEST_HOT_WS/wiki/hot.md" ] || { fail "hot.md was not purged by index --rebuild"; exit 1; }

echo "another legacy hot cache" > "$TEST_HOT_WS/wiki/hot.md"
(cd "$TEST_HOT_WS" && ./rnex plugin karpathy-llm lint >/dev/null)
[ ! -e "$TEST_HOT_WS/wiki/hot.md" ] || { fail "hot.md was not purged by lint"; exit 1; }
grep -q "Legacy Hot Cache Purge" "$TEST_HOT_WS/wiki/_log.md" || { fail "_log.md missing audit record of hot.md purge"; exit 1; }

# Verify no hot.md references in wiki files (except _log.md audit entries)
_stray_hot="$(find "$TEST_HOT_WS/wiki" -name "*.md" ! -name "_log.md" -exec grep -l "hot\.md" {} + 2>/dev/null || true)"
[ -z "$_stray_hot" ] || { fail "Stray hot.md reference in wiki files: $_stray_hot"; exit 1; }
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
