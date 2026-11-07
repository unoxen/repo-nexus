#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/config.sh
# Architectural Layer: Configuration Management Contract (Fail-Fast)
# Single Responsibility: Validate and expose immutable runtime configuration
# variables for the Karpathy LLM Wiki plugin (Zero Hardcoding / Fail-Fast).
# Patterns Applied: Singleton Config Contract, Dependency Inversion (DIP).
# Security (OWASP A03/A05): Rejects path traversal sequences ("..") and enforces positive
# integer bounds on B-Tree and Graph thresholds.
# =============================================================================

# Guard against multiple inclusion
[ "${RNEX_KARPATHY_CONFIG_SH_SOURCED:-0}" = "1" ] && return 0
RNEX_KARPATHY_CONFIG_SH_SOURCED=1

# -----------------------------------------------------------------------------
# load_karpathy_wiki_config
# Summary: Initializes and validates all RNEX_WIKI_* configuration variables.
# @param $1: workspace_root - Optional workspace root path (defaults to PWD or RNEX_WORKSPACE_ROOT).
# @returns: 0 on valid configuration; 1 on schema or security validation error.
# @sideEffects: Exports read-only RNEX_WIKI_* environment contracts.
# -----------------------------------------------------------------------------
load_karpathy_wiki_config() {
    _ws_root="${1:-${NEXUS_DIR:-${RNEX_ROOT:-${RNEX_WORKSPACE_ROOT:-$(pwd)}}}}"

    # Reject path traversal in workspace root (OWASP A03)
    case "$_ws_root" in
        *".."*)
            printf 'Error [config]: Invalid workspace root path traversal detected.\n' >&2
            return 1
            ;;
    esac

    RNEX_WORKSPACE_ROOT="$_ws_root"

    # Helper to lookup config from yaml_plugin_get with deterministic rnex.yaml fallback
    _lookup_karpathy_cfg() {
        _k="$1"
        _v=""
        if command -v yaml_plugin_get >/dev/null 2>&1; then
            _v="$(yaml_plugin_get "karpathy-llm" "$_k" 2>/dev/null || true)"
        fi
        if [ -z "$_v" ]; then
            for _cf in "${RNEX_WORKSPACE_ROOT}/.local.rnex.yaml" "${RNEX_WORKSPACE_ROOT}/rnex.yaml"; do
                [ -f "$_cf" ] || continue
                _v="$(LC_ALL=C awk -v target_k="$_k" '
                    BEGIN { in_plugin=0 }
                    /^[ ]*karpathy-llm:[ ]*$/ { in_plugin=1; next }
                    in_plugin && /^[^ ]/ { in_plugin=0 }
                    in_plugin && $1 ~ ("^" target_k ":") {
                        line = $0
                        sub(/^[^:]+:[ ]*/, "", line)
                        sub(/[ ]*#.*$/, "", line)
                        gsub(/^["\047]|["\047]$/, "", line)
                        print line
                        exit
                    }
                ' "$_cf" 2>/dev/null)"
                [ -n "$_v" ] && break
            done
        fi
        printf '%s' "$_v"
    }

    # Query relative wiki directory with precedence: env -> _lookup_karpathy_cfg -> fallback
    if [ -n "${RNEX_CFG_WIKI_DIR:-}" ]; then
        RNEX_WIKI_REL_DIR="$RNEX_CFG_WIKI_DIR"
    else
        RNEX_WIKI_REL_DIR="$(_lookup_karpathy_cfg "wiki_dir")"
        [ -n "$RNEX_WIKI_REL_DIR" ] || RNEX_WIKI_REL_DIR="wiki"
    fi

    case "$RNEX_WIKI_REL_DIR" in
        *".."*|/*)
            printf 'Error [config]: wiki_dir must be a safe workspace-relative path.\n' >&2
            return 1
            ;;
    esac

    # Resolve root router filename (_index.md)
    if [ -n "${RNEX_CFG_INDEX_FILE:-}" ]; then
        _idx_name="$RNEX_CFG_INDEX_FILE"
    else
        _idx_name="$(_lookup_karpathy_cfg "index_file")"
        [ -n "$_idx_name" ] || _idx_name="_index.md"
    fi

    # Resolve audit log filename (_log.md)
    if [ -n "${RNEX_CFG_LOG_FILE:-}" ]; then
        _log_name="$RNEX_CFG_LOG_FILE"
    else
        _log_name="$(_lookup_karpathy_cfg "log_file")"
        [ -n "$_log_name" ] || _log_name="_log.md"
    fi

    # Resolve B-Tree shard directory name (_index)
    if [ -n "${RNEX_CFG_INDEX_DIR:-}" ]; then
        _idx_dir_name="$RNEX_CFG_INDEX_DIR"
    else
        _idx_dir_name="$(_lookup_karpathy_cfg "index_dir")"
        [ -n "$_idx_dir_name" ] || _idx_dir_name="_index"
    fi

    # Resolve TSV graph directory name (_graph)
    if [ -n "${RNEX_CFG_GRAPH_DIR:-}" ]; then
        _grp_dir_name="$RNEX_CFG_GRAPH_DIR"
    else
        _grp_dir_name="$(_lookup_karpathy_cfg "graph_dir")"
        [ -n "$_grp_dir_name" ] || _grp_dir_name="_graph"
    fi

    # Core directory & file contracts
    RNEX_WIKI_ROOT="${RNEX_WORKSPACE_ROOT}/${RNEX_WIKI_REL_DIR}"
    RNEX_WIKI_INDEX_FILE="${RNEX_WIKI_ROOT}/${_idx_name}"
    RNEX_WIKI_LOG_FILE="${RNEX_WIKI_ROOT}/${_log_name}"

    # Tier 2 B-Tree Shards & Tier 3 Property Graph directories
    RNEX_WIKI_BTREE_DIR="${RNEX_WIKI_ROOT}/${_idx_dir_name}"
    RNEX_WIKI_GRAPH_DIR="${RNEX_WIKI_ROOT}/${_grp_dir_name}"
    RNEX_WIKI_NODES_TSV="${RNEX_WIKI_GRAPH_DIR}/nodes.tsv"
    RNEX_WIKI_EDGES_OUT_TSV="${RNEX_WIKI_GRAPH_DIR}/edges_out.tsv"
    RNEX_WIKI_EDGES_IN_TSV="${RNEX_WIKI_GRAPH_DIR}/edges_in.tsv"

    # Numeric capacity thresholds with positive integer validation
    RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES="${RNEX_CFG_BTREE_SHARD_MAX_ENTRIES:-}"
    if [ -z "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" ]; then
        RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES="$(_lookup_karpathy_cfg "btree_shard_max_entries")"
    fi
    [ -n "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" ] || RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES=100

    RNEX_WIKI_BTREE_MAX_ROOT_LINES="${RNEX_CFG_BTREE_MAX_ROOT_LINES:-${RNEX_CFG_BTREE_ROOT_MAX_LINES:-}}"
    if [ -z "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ]; then
        RNEX_WIKI_BTREE_MAX_ROOT_LINES="$(_lookup_karpathy_cfg "btree_max_root_lines")"
        [ -n "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ] || RNEX_WIKI_BTREE_MAX_ROOT_LINES="$(_lookup_karpathy_cfg "btree_root_max_lines")"
    fi
    [ -n "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ] || RNEX_WIKI_BTREE_MAX_ROOT_LINES=80
    RNEX_WIKI_BTREE_ROOT_MAX_LINES="$RNEX_WIKI_BTREE_MAX_ROOT_LINES"

    RNEX_WIKI_GRAPH_DEFAULT_DEPTH="${RNEX_CFG_GRAPH_DEFAULT_DEPTH:-}"
    if [ -z "$RNEX_WIKI_GRAPH_DEFAULT_DEPTH" ]; then
        RNEX_WIKI_GRAPH_DEFAULT_DEPTH="$(_lookup_karpathy_cfg "graph_default_depth")"
    fi
    [ -n "$RNEX_WIKI_GRAPH_DEFAULT_DEPTH" ] || RNEX_WIKI_GRAPH_DEFAULT_DEPTH=1

    case "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" in
        ''|*[!0-9]*|0) RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES=100 ;;
    esac
    case "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" in
        ''|*[!0-9]*|0) RNEX_WIKI_BTREE_MAX_ROOT_LINES=80; RNEX_WIKI_BTREE_ROOT_MAX_LINES=80 ;;
    esac
    case "$RNEX_WIKI_GRAPH_DEFAULT_DEPTH" in
        ''|*[!0-9]*|0) RNEX_WIKI_GRAPH_DEFAULT_DEPTH=1 ;;
    esac

    export RNEX_WORKSPACE_ROOT RNEX_WIKI_ROOT RNEX_WIKI_INDEX_FILE RNEX_WIKI_LOG_FILE
    export RNEX_WIKI_BTREE_DIR RNEX_WIKI_GRAPH_DIR RNEX_WIKI_NODES_TSV
    export RNEX_WIKI_EDGES_OUT_TSV RNEX_WIKI_EDGES_IN_TSV
    export RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES RNEX_WIKI_BTREE_MAX_ROOT_LINES RNEX_WIKI_BTREE_ROOT_MAX_LINES
    export RNEX_WIKI_GRAPH_DEFAULT_DEPTH

    RNEX_KARPATHY_CONFIG_LOADED=1
    return 0
}

# -----------------------------------------------------------------------------
# load_wiki_config_contract
# Summary: Backwards-compatible contract loader aliasing load_karpathy_wiki_config.
# @param $1: workspace_root - Optional workspace root path.
# @returns: 0 on valid configuration; 1 on schema validation error.
# @sideEffects: Exports read-only RNEX_WIKI_* configuration environment variables.
# -----------------------------------------------------------------------------
load_wiki_config_contract() {
    load_karpathy_wiki_config "$@"
}

# -----------------------------------------------------------------------------
# is_repo_enabled
# Summary: Determines whether a member repository is enabled or disabled
#          in rnex.yaml or .local.rnex.yaml.
# @param $1: repo_name - Target repository name.
# @returns: 0 if enabled (or default enabled); 1 if explicitly disabled.
# @pure
# -----------------------------------------------------------------------------
is_repo_enabled() {
    _r_name="$1"
    [ -n "$_r_name" ] || return 1

    if command -v yaml_repo_enabled >/dev/null 2>&1; then
        yaml_repo_enabled "$_r_name" 2>/dev/null && return 0 || return 1
    fi

    for _mf in "${RNEX_WORKSPACE_ROOT}/.local.rnex.yaml" "${RNEX_WORKSPACE_ROOT}/rnex.yaml"; do
        [ -f "$_mf" ] || continue
        _status="$(LC_ALL=C awk -v r="$_r_name" '
            BEGIN { in_r=0 }
            $1 == (r ":") { in_r=1; next }
            in_r && /^[ ]{1,2}[a-zA-Z0-9._-]+:/ { in_r=0 }
            in_r && /^[^ ]/ { in_r=0 }
            in_r && /^[ ]*enabled:[ ]*false/ { print "disabled"; exit }
            in_r && /^[ ]*enabled:[ ]*true/ { print "enabled"; exit }
        ' "$_mf" 2>/dev/null)"
        if [ "$_status" = "disabled" ]; then
            return 1
        elif [ "$_status" = "enabled" ]; then
            return 0
        fi
    done
    return 0
}

# -----------------------------------------------------------------------------
# discover_enabled_member_repos
# Summary: Discovers active member repository names from ./repos/* and/or
#          rnex.yaml so the wiki maintains at least one repos-<member>.md shard
#          per active member repository alongside repo-nexus.md.
# @returns: Newline-delimited list of canonical member repo names on stdout.
# @sideEffects: Reads filesystem ./repos/ directory and rnex.yaml manifest.
# -----------------------------------------------------------------------------
discover_enabled_member_repos() {
    _repos_base="${RNEX_WORKSPACE_ROOT}/${RNEX_CFG_REPOS_DIR:-repos}"
    _manifest="${RNEX_WORKSPACE_ROOT}/rnex.yaml"

    {
        # 1. Discover physical member repo directories under ./repos/
        if [ -d "$_repos_base" ]; then
            for _d in "$_repos_base"/*; do
                [ -d "$_d" ] || continue
                _b="$(basename "$_d")"
                [ "$_b" != "*" ] && [ "$_b" != ".gitkeep" ] && printf '%s\n' "$_b"
            done
        fi

        # 2. Query core yaml_list_repos if available in runtime
        if command -v yaml_list_repos >/dev/null 2>&1; then
            yaml_list_repos 2>/dev/null || true
        fi

        # 3. Parse declared repo keys under `repos:` in rnex.yaml if present
        if [ -f "$_manifest" ]; then
            LC_ALL=C awk '
                /^repos:[[:space:]]*$/ { in_repos=1; next }
                in_repos && /^[^[:space:]#]/ { in_repos=0 }
                in_repos && /^[[:space:]]{2}[a-zA-Z0-9._-]+:[[:space:]]*$/ {
                    key = $1
                    sub(/:$/, "", key)
                    if (key != "hooks" && key != "enabled" && key != "url" && key != "path" && key != "branch") {
                        print key
                    }
                }
            ' "$_manifest"
        fi
    } | LC_ALL=C sort -u | while IFS= read -r _cand; do
        [ -n "$_cand" ] || continue
        is_repo_enabled "$_cand" || continue
        printf '%s\n' "$_cand"
    done
}
