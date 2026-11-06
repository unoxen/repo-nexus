#!/bin/sh
# shellcheck shell=sh disable=SC2154
# =============================================================================
# File: plugins/karpathy-llm/commands/init.sh
# Architectural Layer: Plugin CLI Subcommand (karpathy-llm init)
# Single Responsibility: Deterministically initialize the Karpathy LLM Wiki
#   B-Tree index root (index.md <= 80 lines), leaf shards (_index/*.md),
#   sorted TSV property graph (_graph/*.tsv), and audit log (_log.md).
# Invariants Enforced:
#   - Zero creation of hot.md (Single Source of Truth).
#   - Index root file contains strictly no YAML frontmatter and is <= 80 lines.
#   - Shards and graph files are initialized in strict LC_ALL=C byte order.
# Security (OWASP A03): Validates workspace root and enforces safe paths.
# Syntax: rnex plugin karpathy-llm init [--quiet]
# =============================================================================
set -e

_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
for _kl_common in \
  "${RNEX_PLUGIN_DIR:-}/hooks/_common.sh" \
  "$(dirname "$0")/../hooks/_common.sh" \
  "$_root/.rnex/plugins/karpathy-llm/hooks/_common.sh" \
  "$_root/plugins/karpathy-llm/hooks/_common.sh"; do
  # shellcheck source=/dev/null
  [ -f "$_kl_common" ] && { . "$_kl_common"; break; }
done

_quiet=0

while [ $# -gt 0 ]; do
  case "$1" in
    -q|--quiet)
      _quiet=1
      ;;
    -h|--help)
      cat <<'HELP_EOF'
Usage: rnex plugin karpathy-llm init [options]

Initialize the Karpathy LLM Wiki directory, B-Tree leaf shards, and sorted TSV graph store.

Options:
  -q, --quiet Suppress informational output
  -h, --help  Show this help message
HELP_EOF
      exit 0
      ;;
    *)
      printf 'Error: Unknown option "%s". Use --help for usage.\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

# Fail-fast: ensure configuration contract is loaded
if ! command -v load_wiki_config_contract >/dev/null 2>&1; then
  printf 'Error [init]: load_wiki_config_contract helper not found.\n' >&2
  exit 1
fi

load_wiki_config_contract "$_root" || exit 1

# 1. Initialize wiki directory structure
mkdir -p "$RNEX_WIKI_ROOT"
mkdir -p "$RNEX_WIKI_BTREE_DIR"
mkdir -p "$RNEX_WIKI_GRAPH_DIR"

# 2. Initialize Sorted TSV Property Graph Store (nodes.tsv, edges_out.tsv, edges_in.tsv)
init_wiki_graph_store || {
  printf 'Error [init]: Failed to initialize TSV graph store.\n' >&2
  exit 1
}

# 3. Initialize B-Tree leaf shards and bounded Root router (index.md)
init_wiki_btree_store || {
  printf 'Error [init]: Failed to initialize B-Tree index store.\n' >&2
  exit 1
}

# 4. Initialize append-only operational audit log (_log.md)
_today="$(kl_today)"
if [ ! -f "$RNEX_WIKI_LOG_FILE" ]; then
  cat > "$RNEX_WIKI_LOG_FILE" <<LOG_INIT
# Karpathy Wiki Operation Log

Append-only audit trail recording all ingest and maintenance runs.

---

### Initial Setup — ${_today}
* **Action:** Initialized Karpathy LLM Wiki B-Tree index and TSV graph architecture via \`karpathy-llm\` plugin.
LOG_INIT
fi

# 5. Enforce total eradication of legacy hot.md
if [ -f "${RNEX_WIKI_ROOT}/hot.md" ]; then
  rm -f "${RNEX_WIKI_ROOT}/hot.md" 2>/dev/null || true
  if [ -f "$RNEX_WIKI_LOG_FILE" ]; then
    cat >> "$RNEX_WIKI_LOG_FILE" <<LOG_PURGE

### Legacy Hot Cache Purge — ${_today}
* **Action:** Purged legacy \`hot.md\` orientation cache in favor of deterministic B-Tree and TSV graph routing.
LOG_PURGE
  fi
fi

if [ "$_quiet" -eq 0 ]; then
  printf '[WIKI] Initialized Karpathy LLM Wiki at %s\n' "$RNEX_WIKI_ROOT"
  printf '[WIKI] B-Tree Root: %s (<= %s lines)\n' "$RNEX_WIKI_INDEX_FILE" "$RNEX_WIKI_BTREE_MAX_ROOT_LINES"
  printf '[WIKI] Leaf Shards: %s/*.md\n' "$RNEX_WIKI_BTREE_DIR"
  printf '[WIKI] Sorted Graph: %s/*.tsv\n' "$RNEX_WIKI_GRAPH_DIR"
fi

exit 0
