#!/bin/sh
# shellcheck shell=sh disable=SC2154
# =============================================================================
# File: plugins/karpathy-llm/commands/index.sh
# Architectural Layer: Plugin CLI Subcommand (karpathy-llm index)
# Single Responsibility: Scan curated Markdown pages under wiki/, synchronize
#   the sorted TSV property graph (nodes.tsv, edges_out.tsv, edges_in.tsv),
#   and compile B-Tree leaf shards (_index/*.md) and root router (index.md).
# Patterns Applied: Builder Pattern, Information Expert (GRASP).
# Security (OWASP A03): Validates paths, sanitizes TSV fields, rejects traversal.
# Syntax: rnex plugin karpathy-llm index [--rebuild] [--quiet]
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

_rebuild=0
_quiet=0

while [ $# -gt 0 ]; do
  case "$1" in
    --rebuild)
      _rebuild=1
      ;;
    -q|--quiet)
      _quiet=1
      ;;
    -h|--help)
      cat <<'HELP_EOF'
Usage: rnex plugin karpathy-llm index [options]

Rebuild sorted TSV graph and compile B-Tree leaf shards and root router.

Options:
  --rebuild   Truncate and rebuild graph tables from scratch
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
  printf 'Error [index]: load_wiki_config_contract helper not found.\n' >&2
  exit 1
fi

load_wiki_config_contract "$_root" || exit 1

if [ ! -d "$RNEX_WIKI_ROOT" ]; then
  printf 'Error [index]: Wiki directory does not exist: %s\n' "$RNEX_WIKI_ROOT" >&2
  exit 1
fi

init_wiki_graph_store || exit 1

# If --rebuild requested, truncate TSV tables before scanning
if [ "$_rebuild" -eq 1 ]; then
  : > "$RNEX_WIKI_NODES_TSV"
  : > "$RNEX_WIKI_EDGES_OUT_TSV"
  : > "$RNEX_WIKI_EDGES_IN_TSV"
fi

# Clean up legacy hot.md if found
if [ -f "${RNEX_WIKI_ROOT}/hot.md" ]; then
  rm -f "${RNEX_WIKI_ROOT}/hot.md" 2>/dev/null || true
  if [ -f "$RNEX_WIKI_LOG_FILE" ]; then
    _today="$(get_iso_utc_date)"
    cat >> "$RNEX_WIKI_LOG_FILE" <<HOT_PURGE_LOG

### Legacy Hot Cache Purge — ${_today}
* **Action:** Purged legacy \`hot.md\` orientation cache during index rebuild.
HOT_PURGE_LOG
  fi
fi

_indexed_count=0

# Scan all Markdown files in wiki/ (excluding index.md, _log.md, _index, _graph)
# ShellCheck-clean find loop
find "$RNEX_WIKI_ROOT" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort | while IFS= read -r _page_path; do
  [ -f "$_page_path" ] || continue
  _fname="$(basename "$_page_path")"

  # Skip control files and shard files
  case "$_fname" in
    index.md|_log.md|hot.md) continue ;;
  esac

  # Skip files in _index or _graph directories
  case "$_page_path" in
    */"${RNEX_CFG_WIKI_INDEX_DIR:-_index}"/*) continue ;;
    */"${RNEX_CFG_WIKI_GRAPH_DIR:-_graph}"/*) continue ;;
  esac

  # Relative path inside wiki
  _page_rel="${_page_path#"${RNEX_WIKI_ROOT}"/}"
  _page_rel="$(printf '%s' "$_page_rel" | sed -e 's#^\./##')"

  # Derive node slug
  _node_slug="${_fname%.md}"
  _node_slug="$(normalize_slug_id "$_node_slug")" || continue

  # Determine shard assignment:
  # 1. Directory-based shard if page is in a subdirectory (e.g. concepts/jwt.md -> concepts)
  # 2. Tag-based or naming-convention heuristic if in wiki root
  case "$_page_rel" in
    */*)
      _shard="${_page_rel%%/*}"
      ;;
    repo-*)
      _shard="entities"
      ;;
    docs-*)
      _shard="sources"
      ;;
    *)
      # Inspect frontmatter tags
      _tags="$(awk '
        NR==1 && /^---$/ { in_fm=1; next }
        in_fm && /^---$/ { exit }
        in_fm && /^[ \t]*tags:[ \t]*/ {
          sub(/^[ \t]*tags:[ \t]*\[?/, "")
          sub(/\][ \t]*$/, "")
          print
          exit
        }
      ' "$_page_path")"
      case "$_tags" in
        *member-repo*|*entity*|*entities*) _shard="entities" ;;
        *concept*)                         _shard="concepts" ;;
        *intake*|*source*)                 _shard="sources" ;;
        *overview*)                        _shard="overview" ;;
        *)                                 _shard="overview" ;;
      esac
      ;;
  esac

  # Extract title
  _title="$(awk '
    NR==1 && /^---$/ { in_fm=1; next }
    in_fm && /^---$/ { in_fm=0; next }
    in_fm && /^[ \t]*title:[ \t]*/ {
      sub(/^[ \t]*title:[ \t]*["\047]?/, "")
      sub(/["\047]?[ \t]*$/, "")
      print
      exit
    }
    !in_fm && /^#[^#]/ {
      sub(/^#[ \t]*/, "")
      sub(/[ \t]*$/, "")
      print
      exit
    }
  ' "$_page_path")"
  [ -n "$_title" ] || _title="$_node_slug"

  # Extract summary
  _summary="$(awk '
    /^## Summary/ { in_sum=1; next }
    in_sum && /^## / { exit }
    in_sum && NF > 0 {
      gsub(/^[ \t]+|[ \t]+$/, "")
      print
      exit
    }
  ' "$_page_path")"
  if [ -z "$_summary" ]; then
    _summary="$(kl_truncate_summary "$_title" 15 120)"
  fi
  [ -n "$_summary" ] || _summary="Compiled wiki page."

  upsert_graph_node_and_edges "$_node_slug" "$_shard" "$_page_rel" "$_title" "$_summary" "$_page_path"
done

# Rebalance leaf shards and compile bounded root router
rebalance_btree_shards_and_compile_root || {
  printf 'Error [index]: Failed to compile B-Tree shards and root router.\n' >&2
  exit 1
}

_total_nodes="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_NODES_TSV")"
_total_edges="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_EDGES_OUT_TSV")"

if [ "$_quiet" -eq 0 ]; then
  printf '[WIKI] Index synchronized: %s nodes, %s edges.\n' "$_total_nodes" "$_total_edges"
  printf '[WIKI] Root router compiled: %s\n' "$RNEX_WIKI_INDEX_FILE"
fi

exit 0
