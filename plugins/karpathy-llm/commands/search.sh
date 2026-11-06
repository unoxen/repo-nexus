#!/bin/sh
# shellcheck shell=sh disable=SC2154
# =============================================================================
# File: plugins/karpathy-llm/commands/search.sh
# Architectural Layer: Plugin CLI Subcommand (karpathy-llm search)
# Single Responsibility: Execute O(log N) prefix searches over sorted nodes.tsv
#   returning matching wiki pages, shard paths, and concise summaries in < 1 ms.
# Complexity: O(log N) prefix binary search in LC_ALL=C locale.
# Security (OWASP A03): Validates search query and normalizes prefixes.
# Syntax: rnex plugin karpathy-llm search <prefix>
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

_query_prefix=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat <<'HELP_EOF'
Usage: rnex plugin karpathy-llm search <prefix>

Perform an O(log N) binary search for wiki nodes beginning with <prefix>.

Options:
  -h, --help  Show this help message
HELP_EOF
      exit 0
      ;;
    -*)
      printf 'Error: Unknown option "%s". Use --help for usage.\n' "$1" >&2
      exit 1
      ;;
    *)
      if [ -n "$_query_prefix" ]; then
        printf 'Error: Too many arguments. Specify a single prefix query.\n' >&2
        exit 1
      fi
      _query_prefix="$1"
      ;;
  esac
  shift
done

if [ -z "$_query_prefix" ]; then
  printf 'Error: Missing search prefix. Usage: rnex plugin karpathy-llm search <prefix>\n' >&2
  exit 1
fi

_norm_prefix="$(normalize_slug_id "$_query_prefix" 2>/dev/null || printf '%s' "$_query_prefix" | tr '[:upper:]' '[:lower:]')"

# Fail-fast: ensure configuration contract is loaded
if ! command -v load_wiki_config_contract >/dev/null 2>&1; then
  printf 'Error [search]: load_wiki_config_contract helper not found.\n' >&2
  exit 1
fi

load_wiki_config_contract "$_root" || exit 1

if [ ! -f "$RNEX_WIKI_NODES_TSV" ]; then
  printf 'Error [search]: Graph store not initialized (%s missing).\n' "$RNEX_WIKI_NODES_TSV" >&2
  exit 1
fi

_matches="$(binary_search_sorted_prefix "$_norm_prefix" "$RNEX_WIKI_NODES_TSV")"

if [ -z "$_matches" ]; then
  printf 'No matching wiki nodes found for prefix "%s".\n' "$_query_prefix"
  exit 0
fi

printf 'Matching Wiki Nodes (Prefix: "%s"):\n' "$_norm_prefix"
printf '%s\n' "$_matches" | while IFS="$(printf '\t')" read -r _nid _nshard _npath _ntitle _nsummary; do
  [ -n "$_nid" ] || continue
  _act_shard="$_nshard"
  if [ -f "${RNEX_WIKI_BTREE_DIR}/${_nshard}-a-m.md" ]; then
    _first="$(printf '%.1s' "$_nid" | tr '[:upper:]' '[:lower:]')"
    case "$_first" in
      [a-m]) _act_shard="${_nshard}-a-m" ;;
      *)     _act_shard="${_nshard}-n-z" ;;
    esac
  fi
  printf -- "- **[[%s]]** — %s: %s (Shard: \`_index/%s.md\`, Path: \`%s\`)\n" \
    "$_nid" "$_ntitle" "$_nsummary" "$_act_shard" "$_npath"
done

exit 0
