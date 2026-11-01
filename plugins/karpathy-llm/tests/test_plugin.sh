#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# plugins/karpathy-llm/tests/test_plugin.sh — Karpathy LLM Wiki Plugin Tests
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
[ -d "$_kl_pdir" ] || _kl_pdir="$TEST_KARPATHY_WS/toolkit/plugins/karpathy-llm"

# --------------------------------------------------------------------------
run_test "Karpathy-llm: manifest integrity, version parity, and documentation accuracy"
_cli_ver="$("$TEST_KARPATHY_WS/rnex" --version | awk '{print $2}')"
_m_ver="$(awk '/^version:[ ]*/ { sub(/^version:[ ]*/, ""); sub(/[ ]*#.*/, ""); print; exit }' "$_kl_pdir/plugin.yaml")"
[ "$_m_ver" = "$_cli_ver" ] || { fail "Plugin version ($_m_ver) does not match CLI version ($_cli_ver)"; exit 1; }

_yaml_file="$_kl_pdir/plugin.yaml"
# Assert placeholders are quoted in plugin.yaml
grep -q 'templates/index\.md:[ ]*"{wiki_dir}/index\.md"' "$_yaml_file" || { fail "index.md placeholder not quoted in plugin.yaml"; exit 1; }
grep -q 'templates/hot\.md:[ ]*"{wiki_dir}/hot\.md"' "$_yaml_file" || { fail "hot.md placeholder not quoted in plugin.yaml"; exit 1; }

# Verify valid YAML parsing if ruby is available
if command -v ruby >/dev/null 2>&1; then
  ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$_yaml_file" || { fail "karpathy-llm plugin.yaml is not valid YAML"; exit 1; }
fi

# Assert obsolete options absent
! grep -q "lint_trigger" "$_yaml_file" || { fail "lint_trigger still present in plugin.yaml"; exit 1; }
! grep -q "notify_on_changes" "$_yaml_file" || { fail "notify_on_changes still present in plugin.yaml"; exit 1; }
! grep -q "ingest_member_readmes" "$_yaml_file" || { fail "ingest_member_readmes still present in plugin.yaml"; exit 1; }

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
run_test "Karpathy-llm: init --karpathy sets up wiki templates, Hot Cache gate, and scoped assets"
"$TEST_KARPATHY_WS/rnex" init -y --karpathy "$TEST_KARPATHY_WS" >/dev/null
[ -d "$TEST_KARPATHY_WS/wiki" ] || { fail "wiki/ directory missing after init --karpathy"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/index.md" ] || { fail "wiki/index.md missing after init --karpathy"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/hot.md" ] || { fail "wiki/hot.md missing after init --karpathy"; exit 1; }
[ -f "$TEST_KARPATHY_WS/wiki/_log.md" ] || { fail "wiki/_log.md missing after init --karpathy"; exit 1; }
[ -d "$TEST_KARPATHY_WS/docs" ] || { fail "docs/ directory missing after init --karpathy"; exit 1; }

# Scoped assets in .rnex/plugins/karpathy-llm/
[ -d "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm" ] || { fail ".rnex/plugins/karpathy-llm missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm/rules/behavioral.md" ] || { fail "behavioral.md missing in scoped dir"; exit 1; }
[ -f "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm/skills/wiki-ingest.md" ] || { fail "wiki-ingest.md missing in scoped dir"; exit 1; }
[ -f "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm/skills/wiki-lint.md" ] || { fail "wiki-lint.md missing in scoped dir"; exit 1; }
[ -f "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" ] || { fail "rnex-wiki-page.template.md missing"; exit 1; }
! grep -q "/\.rnex/\.rnex" "$TEST_KARPATHY_WS/.rnex/plugins/karpathy-llm/templates/rnex-wiki-page.template.md" || { fail "Corrupted /.rnex/.rnex in template"; exit 1; }

# Instructions compilation: Step 1 Read Wiki Hot Cache gate in .rnex/ai-instructions.md
_ai_content="$(cat "$TEST_KARPATHY_WS/.rnex/ai-instructions.md")"
echo "$_ai_content" | grep -q "Read Wiki Hot Cache" || { fail "Read Wiki Hot Cache missing in ai-instructions.md"; exit 1; }
echo "$_ai_content" | grep -q "wiki/hot.md" || { fail "wiki/hot.md missing in ai-instructions.md"; exit 1; }
! grep -q "Mandatory Wiki-First Access Gate" "$TEST_KARPATHY_WS/AGENTS.md" || { fail "AGENTS.md leaked wiki instructions; should remain single router block"; exit 1; }

# Plugin info inspection
_pinfo="$(cd "$TEST_KARPATHY_WS" && ./rnex plugin info karpathy-llm 2>&1)"
echo "$_pinfo" | grep -q "karpathy-llm" || { fail "Plugin name missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "wiki_dir" || { fail "wiki_dir option missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "sources" || { fail "sources option missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "ingest" || { fail "ingest command missing from info: $_pinfo"; exit 1; }
echo "$_pinfo" | grep -q "lint" || { fail "lint command missing from info: $_pinfo"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: user skill projection with synthetic provider and disable unregistration"
# Create a synthetic mock provider plugin to test User Skill projection without depending on other real plugins
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

# Verify plugin-owned user skills are projected into active provider directory with rnex-karpathy-llm- prefix
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
[ -f "$TEST_KARPATHY_WS/wiki/hot.md" ] || { fail "wiki/hot.md was deleted on disable"; exit 1; }

# Clean up synthetic mock provider
(cd "$TEST_KARPATHY_WS" && ./rnex plugin disable mock-provider >/dev/null)
rm -rf "$TEST_KARPATHY_WS/plugins/mock-provider" "$TEST_KARPATHY_WS/.mock"
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: configurable wiki_dir, placeholder resolution, and leaked dir cleanup"
# Re-enable karpathy-llm with custom wiki_dir and raw_dir
cat <<'EOF_CFG' > "$TEST_KARPATHY_WS/rnex.yaml"
version: 1.0.0
plugins:
  karpathy-llm:
    wiki_dir: docs/wiki
    raw_dir: intake/raw
repos:
EOF_CFG

# Simulate pre-existing leaked bogus placeholder directories in workspace root
mkdir -p "$TEST_KARPATHY_WS/\"{wiki_dir}" "$TEST_KARPATHY_WS/\"{raw_dir}" "$TEST_KARPATHY_WS/{wiki_dir}" "$TEST_KARPATHY_WS/{raw_dir}"

(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)

# Verify custom directories created instead of default
[ -d "$TEST_KARPATHY_WS/docs/wiki" ] || { fail "Custom docs/wiki directory was not created"; exit 1; }
[ -d "$TEST_KARPATHY_WS/intake/raw" ] || { fail "Custom intake/raw directory was not created"; exit 1; }
[ -f "$TEST_KARPATHY_WS/docs/wiki/index.md" ] || { fail "docs/wiki/index.md missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/docs/wiki/hot.md" ] || { fail "docs/wiki/hot.md missing"; exit 1; }
[ -f "$TEST_KARPATHY_WS/docs/wiki/_log.md" ] || { fail "docs/wiki/_log.md missing"; exit 1; }

# Verify template substitutions reflect custom paths without corruption
grep -q "intake/raw/" "$TEST_KARPATHY_WS/docs/wiki/index.md" || { fail "docs/wiki/index.md missing intake/raw/"; exit 1; }
grep -q "docs/wiki/" "$TEST_KARPATHY_WS/docs/wiki/hot.md" || { fail "docs/wiki/hot.md missing docs/wiki/"; exit 1; }
! grep -q "docs/docs/wiki" "$TEST_KARPATHY_WS/docs/wiki/hot.md" || { fail "Found duplicated path docs/docs/wiki"; exit 1; }
! grep -q "intake/intake/raw" "$TEST_KARPATHY_WS/docs/wiki/hot.md" || { fail "Found duplicated path intake/intake/raw"; exit 1; }

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
[ -f "$TEST_KARPATHY_WS/custom-wiki/hot.md" ] || { fail "custom-wiki/hot.md missing"; exit 1; }

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
[ -f "$TEST_KARPATHY_WS/wiki/hot.md" ] || { fail "wiki/hot.md missing"; exit 1; }
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

# Verify index.md and hot.md registration
grep -q "repo-auth-svc\.md" "$TEST_KARPATHY_WS/wiki/index.md" || { fail "repo-auth-svc.md not in index.md"; exit 1; }
grep -q "auth-svc" "$TEST_KARPATHY_WS/wiki/hot.md" || { fail "auth-svc missing from hot.md"; exit 1; }
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
run_test "Karpathy-llm: hot.md <= 500-word condensation scaling across 15+ repos"
cat <<'EOF_HOT_INIT' >> "$TEST_KARPATHY_WS/wiki/hot.md"

## Core Architecture Invariants
The meta repository coordinates distributed services communicating over typed RPC boundaries. Each microservice encapsulates its own persistent state, schema migrations, and event listeners. AI coding assistants must consult atomic wiki pages before executing cross-module refactors. Distributed consensus protocols require state machine replication across regional clusters with bounded clock skew. Network partitions must be handled with eventual consistency for non-critical audit records while retaining strict serializability for financial ledger entries. Background reconcilers execute periodic health audits to detect stale cache entries, orphan pointers, and dangling foreign keys across schemas. Every service implements idempotent processing semantics to prevent duplicate transaction execution during retry storms. High availability clusters maintain warm standby nodes across redundant failure zones. Audit trails record every administrative event with cryptographic integrity verification.
The meta repository coordinates distributed services communicating over typed RPC boundaries. Each microservice encapsulates its own persistent state, schema migrations, and event listeners. AI coding assistants must consult atomic wiki pages before executing cross-module refactors. Distributed consensus protocols require state machine replication across regional clusters with bounded clock skew. Network partitions must be handled with eventual consistency for non-critical audit records while retaining strict serializability for financial ledger entries. Background reconcilers execute periodic health audits to detect stale cache entries, orphan pointers, and dangling foreign keys across schemas. Every service implements idempotent processing semantics to prevent duplicate transaction execution during retry storms. High availability clusters maintain warm standby nodes across redundant failure zones. Audit trails record every administrative event with cryptographic integrity verification.
EOF_HOT_INIT

for _idx in $(seq 1 15); do
  mkdir -p "$TEST_KARPATHY_WS/repos/repo-$_idx"
  printf '# Member Repo %s\nHigh performance microservice module %s for distributed workflows.\n' "$_idx" "$_idx" > "$TEST_KARPATHY_WS/repos/repo-$_idx/README.md"
  printf '  repo-%s:\n' "$_idx" >> "$TEST_KARPATHY_WS/rnex.yaml"
done

(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)
_wc="$(wc -w < "$TEST_KARPATHY_WS/wiki/hot.md")"
[ "$_wc" -le 500 ] || { fail "hot.md word count ($_wc) exceeded 500 words"; exit 1; }
grep -q "Member Repositories" "$TEST_KARPATHY_WS/wiki/hot.md" || { fail "Missing condensed summary line in hot.md"; exit 1; }

# Idempotency check: repeat sync does not duplicate summary line
(cd "$TEST_KARPATHY_WS" && ./rnex sync -y >/dev/null)
_sum_cnt="$(grep -c "Member Repositories" "$TEST_KARPATHY_WS/wiki/hot.md" || true)"
[ "$_sum_cnt" -eq 1 ] || { fail "Duplicate summary lines generated on repeated sync: count $_sum_cnt"; exit 1; }
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: multi-source intake, recursive directory resolution, slug collision, and legacy raw_dir migration"
TEST_INTAKE_WS="$TEST_TMP/karpathy-intake-ws"
mkdir -p "$TEST_INTAKE_WS"
setup_plugin_test_workspace karpathy-llm "$TEST_INTAKE_WS"
cd "$TEST_INTAKE_WS"
"$TEST_INTAKE_WS/rnex" init -y --karpathy "$TEST_INTAKE_WS" >/dev/null

# Populate directory structure with edge cases
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

[ -f "$TEST_INTAKE_WS/wiki/overview.md" ] || { fail "overview.md missing after ingest"; exit 1; }
[ -f "$TEST_INTAKE_WS/wiki/doc-docs-api-readme.md" ] || { fail "doc-docs-api-readme.md missing (API README collision)"; exit 1; }
[ -f "$TEST_INTAKE_WS/wiki/doc-docs-guide-readme.md" ] || { fail "doc-docs-guide-readme.md missing (Guide README collision)"; exit 1; }
[ -f "$TEST_INTAKE_WS/wiki/doc-docs-nested-deep-spec-v1.md" ] || { fail "doc-docs-nested-deep-spec-v1.md missing (spaces/brackets)"; exit 1; }
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
pass

# --------------------------------------------------------------------------
run_test "Karpathy-llm: CLI commands ingest and lint with options and strict validation"
# Test ingest with --source option
printf '# Roadmap\nFuture project roadmap.\n' > "$TEST_INTAKE_WS/docs/roadmap.md"
(cd "$TEST_INTAKE_WS" && ./rnex plugin karpathy-llm ingest --source docs/roadmap.md >/dev/null)
[ -f "$TEST_INTAKE_WS/wiki/roadmap.md" ] || { fail "wiki/roadmap.md not created by ingest --source"; exit 1; }

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
pass

if [ "${_STANDALONE_RUN:-0}" -eq 1 ]; then
  report_results
fi
