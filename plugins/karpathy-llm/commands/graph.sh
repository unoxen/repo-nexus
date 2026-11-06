#!/bin/sh
# shellcheck shell=sh disable=SC2154
# =============================================================================
# File: plugins/karpathy-llm/commands/graph.sh
# Architectural Layer: Plugin CLI Subcommand (karpathy-llm graph)
# Single Responsibility: Execute O(log N) ego-subgraph lookups for a wiki node
#   across sorted TSV tables (nodes.tsv, edges_out.tsv, edges_in.tsv).
# Complexity: O(log N) lookup using C-locale prefix binary search.
# Security (OWASP A03): Validates node identifier and traversal depth.
# Syntax: rnex plugin karpathy-llm graph <node_id> [--depth 1|2]
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

_target_node=""
_depth="${RNEX_CFG_GRAPH_DEFAULT_DEPTH:-1}"

while [ $# -gt 0 ]; do
  case "$1" in
    --depth)
      shift
      [ -n "${1:-}" ] || { printf 'Error: --depth requires an integer argument (1 or 2)\n' >&2; exit 1; }
      _depth="$1"
      ;;
    --depth=*)
      _depth="${1#--depth=}"
      ;;
    -h|--help)
      cat <<'HELP_EOF'
Usage: rnex plugin karpathy-llm graph <node_id> [options]

Query 1-hop or 2-hop ego-subgraph neighborhood for a wiki node from sorted TSV tables.

Options:
  --depth <1|2> Traversal neighborhood depth (default: 1)
  -h, --help    Show this help message
HELP_EOF
      exit 0
      ;;
    -*)
      printf 'Error: Unknown option "%s". Use --help for usage.\n' "$1" >&2
      exit 1
      ;;
    *)
      if [ -n "$_target_node" ]; then
        printf 'Error: Too many arguments. Specify a single node_id.\n' >&2
        exit 1
      fi
      _target_node="$1"
      ;;
  esac
  shift
done

if [ -z "$_target_node" ]; then
  printf 'Error: Missing required node_id argument. Usage: rnex plugin karpathy-llm graph <node_id>\n' >&2
  exit 1
fi

case "$_depth" in
  1|2) ;;
  *)
    printf 'Error: Invalid depth "%s". Allowed values are 1 or 2.\n' "$_depth" >&2
    exit 1
    ;;
esac

# Fail-fast: ensure configuration contract is loaded
if ! command -v load_wiki_config_contract >/dev/null 2>&1; then
  printf 'Error [graph]: load_wiki_config_contract helper not found.\n' >&2
  exit 1
fi

load_wiki_config_contract "$_root" || exit 1

if [ ! -f "$RNEX_WIKI_NODES_TSV" ]; then
  printf 'Error [graph]: Graph store not initialized. Run "rnex plugin karpathy-llm index --rebuild" first.\n' >&2
  exit 1
fi

query_node_ego_subgraph "$_target_node" "$_depth"
exit 0
