#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/config.sh
# Architectural Layer: Configuration Management Contract (Fail-Fast)
# Single Responsibility: Validate and expose read-only runtime configuration
# contracts for the Karpathy LLM Wiki B-Tree and Sorted TSV Graph engine.
# Extension Points: Environment overrides (RNEX_CFG_*) and workspace manifest
# lookup hooks (yaml_plugin_get).
# Patterns Applied: Contract-First Design, Fail-Fast Validation, Indirection.
# Security (OWASP A03/A04): Rejects path traversal tokens (".."), absolute paths,
# and non-numeric threshold settings before exposing runtime contracts.
# =============================================================================

# -----------------------------------------------------------------------------
# _resolve_wiki_cfg_val
# Summary: Resolves a single configuration key with precedence:
#          1. Explicit environment override ($1)
#          2. Workspace YAML configuration via yaml_plugin_get ($2)
#          3. Immutable fallback default ($3)
# @param $1: env_override - Value from RNEX_CFG_* environment variable (if set).
# @param $2: yaml_key     - Key name under plugins.karpathy-llm in rnex.yaml.
# @param $3: default_val  - Default fallback value when unset.
# @returns: Resolved configuration string on stdout.
# @pure (Deterministic resolution given current environment and config state)
# -----------------------------------------------------------------------------
_resolve_wiki_cfg_val() {
    _rwc_env="$1"
    _rwc_key="$2"
    _rwc_def="$3"

    # Step 1: Honor explicit RNEX_CFG_* environment variable override first
    if [ -n "$_rwc_env" ]; then
        printf '%s' "$_rwc_env"
        return 0
    fi

    # Step 2: Query workspace configuration adapter if loaded in runtime
    if command -v yaml_plugin_get >/dev/null 2>&1; then
        _rwc_yaml_val="$(yaml_plugin_get "karpathy-llm" "$_rwc_key" 2>/dev/null || true)"
        if [ -n "$_rwc_yaml_val" ]; then
            printf '%s' "$_rwc_yaml_val"
            return 0
        fi
    fi

    # Step 3: Fall back to schema contract default
    printf '%s' "$_rwc_def"
    return 0
}

# -----------------------------------------------------------------------------
# _validate_safe_rel_dir
# Summary: Validates that a relative directory token contains no path traversal
#          sequences (".."), leading slashes, or control characters (OWASP A03).
# @param $1: dir_val  - Directory relative path string to validate.
# @param $2: dir_name - Human-readable configuration key name for error output.
# @returns: 0 if valid and safe; 1 if unsafe or empty.
# @throws: Prints deterministic security error to stderr on invalid input.
# @pure
# -----------------------------------------------------------------------------
_validate_safe_rel_dir() {
    _vsd_val="$1"
    _vsd_name="$2"

    if [ -z "$_vsd_val" ]; then
        printf 'Error [security]: Empty %s path rejected (OWASP A03).\n' "$_vsd_name" >&2
        return 1
    fi

    # Reject path traversal tokens (".."), absolute paths ("/*"), and control chars
    case "$_vsd_val" in
        *..*|/*|*[!a-zA-Z0-9._/-]*)
            printf 'Error [security]: Unsafe %s path "%s" rejected (OWASP A03).\n' "$_vsd_name" "$_vsd_val" >&2
            return 1
            ;;
    esac
    return 0
}

# -----------------------------------------------------------------------------
# load_wiki_config_contract
# Summary: Initializes and validates immutable configuration variables for the
#          wiki B-Tree index and TSV graph store. Never references hot.md.
# @param $1: workspace_root - Absolute path to the rnex workspace root.
# @returns: 0 on valid configuration; 1 on schema validation failure.
# @throws: Writes validation errors to stderr and returns 1 (Fail-Fast).
# @sideEffects: Exports read-only RNEX_WIKI_* configuration environment variables.
# -----------------------------------------------------------------------------
load_wiki_config_contract() {
    _ws_root="$1"
    if [ -z "$_ws_root" ] || [ ! -d "$_ws_root" ]; then
        printf 'Error [config]: Invalid workspace_root supplied to load_wiki_config_contract.\n' >&2
        return 1
    fi

    # Resolve relative directories from config contract or defaults
    _wiki_rel="$(_resolve_wiki_cfg_val "${RNEX_CFG_WIKI_DIR:-}" "wiki_dir" "wiki")"
    _index_rel="$(_resolve_wiki_cfg_val "${RNEX_CFG_WIKI_INDEX_DIR:-${RNEX_CFG_INDEX_DIR:-}}" "index_dir" "_index")"
    _graph_rel="$(_resolve_wiki_cfg_val "${RNEX_CFG_WIKI_GRAPH_DIR:-${RNEX_CFG_GRAPH_DIR:-}}" "graph_dir" "_graph")"

    # Enforce OWASP A03 path sanitization on all relative directory segments
    _validate_safe_rel_dir "$_wiki_rel" "wiki_dir" || return 1
    _validate_safe_rel_dir "$_index_rel" "index_dir" || return 1
    _validate_safe_rel_dir "$_graph_rel" "graph_dir" || return 1

    RNEX_WIKI_ROOT="${_ws_root}/${_wiki_rel}"
    RNEX_WIKI_INDEX_FILE="${RNEX_WIKI_ROOT}/index.md"
    RNEX_WIKI_LOG_FILE="${RNEX_WIKI_ROOT}/_log.md"
    RNEX_WIKI_BTREE_DIR="${RNEX_WIKI_ROOT}/${_index_rel}"
    RNEX_WIKI_GRAPH_DIR="${RNEX_WIKI_ROOT}/${_graph_rel}"

    RNEX_WIKI_NODES_TSV="${RNEX_WIKI_GRAPH_DIR}/nodes.tsv"
    RNEX_WIKI_EDGES_OUT_TSV="${RNEX_WIKI_GRAPH_DIR}/edges_out.tsv"
    RNEX_WIKI_EDGES_IN_TSV="${RNEX_WIKI_GRAPH_DIR}/edges_in.tsv"

    RNEX_WIKI_BTREE_MAX_ROOT_LINES="$(_resolve_wiki_cfg_val "${RNEX_CFG_BTREE_ROOT_MAX_LINES:-}" "btree_root_max_lines" "80")"
    RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES="$(_resolve_wiki_cfg_val "${RNEX_CFG_BTREE_SHARD_MAX_ENTRIES:-}" "btree_shard_max_entries" "100")"
    RNEX_WIKI_GRAPH_DEFAULT_DEPTH="$(_resolve_wiki_cfg_val "${RNEX_CFG_GRAPH_DEFAULT_DEPTH:-}" "graph_default_depth" "1")"

    # Validate numeric thresholds against strict positive integer patterns (Fail-Fast)
    for _num_val in "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" "$RNEX_WIKI_GRAPH_DEFAULT_DEPTH"; do
        case "$_num_val" in
            ''|*[!0-9]*|0)
                printf 'Error [config]: Numeric threshold "%s" must be a positive integer.\n' "$_num_val" >&2
                return 1
                ;;
        esac
    done

    export RNEX_WIKI_ROOT RNEX_WIKI_INDEX_FILE RNEX_WIKI_LOG_FILE \
           RNEX_WIKI_BTREE_DIR RNEX_WIKI_GRAPH_DIR \
           RNEX_WIKI_NODES_TSV RNEX_WIKI_EDGES_OUT_TSV RNEX_WIKI_EDGES_IN_TSV \
           RNEX_WIKI_BTREE_MAX_ROOT_LINES RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES \
           RNEX_WIKI_GRAPH_DEFAULT_DEPTH
    return 0
}
