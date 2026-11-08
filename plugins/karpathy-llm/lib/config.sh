#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/lib/config.sh
# Architectural Layer: Configuration Management Contract (Fail-Fast)
# Single Responsibility: Validate and expose read-only runtime configuration
# contracts for the flat Karpathy LLM Wiki B-Tree engine (wiki/*.md).
# Patterns Applied: Singleton Configuration Contract, Dependency Inversion (DIP).
# Standards: POSIX Shell (/bin/sh), OWASP A03/A04 Input Validation.
# =============================================================================

# Guard against multiple inclusion
if [ "${RNEX_KARPATHY_CONFIG_SH_SOURCED:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
RNEX_KARPATHY_CONFIG_SH_SOURCED=1

# -----------------------------------------------------------------------------
# load_karpathy_wiki_config
# Summary: Initializes, validates, and exports immutable runtime configuration
#          contracts for the flat Karpathy LLM Wiki B-Tree engine.
# @param $1: ws_root - Optional workspace root path (defaults to RNEX_WORKSPACE_ROOT or PWD).
# @returns: 0 on valid configuration; 1 on schema or security traversal error.
# @sideEffects: Exports read-only RNEX_WIKI_* configuration environment variables.
# -----------------------------------------------------------------------------
load_karpathy_wiki_config() {
    _ws_root="${1:-${RNEX_WORKSPACE_ROOT:-$(pwd)}}"

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

    # Reject path traversal or absolute paths in wiki_dir (OWASP A03)
    case "$RNEX_WIKI_REL_DIR" in
        *".."*|/*)
            printf 'Error [config]: wiki_dir must be a safe workspace-relative path.\n' >&2
            return 1
            ;;
    esac

    # Resolve root router filename (index.md)
    if [ -n "${RNEX_CFG_INDEX_FILE:-}" ]; then
        _idx_name="$RNEX_CFG_INDEX_FILE"
    else
        _idx_name="$(_lookup_karpathy_cfg "index_file")"
        [ -n "$_idx_name" ] || _idx_name="index.md"
    fi

    # Resolve audit log filename (log.md)
    if [ -n "${RNEX_CFG_LOG_FILE:-}" ]; then
        _log_name="$RNEX_CFG_LOG_FILE"
    else
        _log_name="$(_lookup_karpathy_cfg "log_file")"
        [ -n "$_log_name" ] || _log_name="log.md"
    fi

    # Core directory and file paths (Zero Underscore Prefixes)
    RNEX_WIKI_ROOT="${RNEX_WORKSPACE_ROOT}/${RNEX_WIKI_REL_DIR}"
    RNEX_WIKI_INDEX_FILE="${RNEX_WIKI_ROOT}/${_idx_name}"
    RNEX_WIKI_LOG_FILE="${RNEX_WIKI_ROOT}/${_log_name}"

    # B-Tree Capacity Constraints
    if [ -n "${RNEX_CFG_BTREE_SHARD_MAX_ENTRIES:-}" ]; then
        RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES="$RNEX_CFG_BTREE_SHARD_MAX_ENTRIES"
    else
        RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES="$(_lookup_karpathy_cfg "btree_shard_max_entries")"
        [ -n "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" ] || RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES=100
    fi

    if [ -n "${RNEX_CFG_BTREE_ROOT_MAX_LINES:-}" ]; then
        RNEX_WIKI_BTREE_MAX_ROOT_LINES="$RNEX_CFG_BTREE_ROOT_MAX_LINES"
    else
        RNEX_WIKI_BTREE_MAX_ROOT_LINES="$(_lookup_karpathy_cfg "btree_root_max_lines")"
        [ -n "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ] || RNEX_WIKI_BTREE_MAX_ROOT_LINES=80
    fi

    case "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" in
        ''|*[!0-9]*|0) RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES=100 ;;
    esac
    case "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" in
        ''|*[!0-9]*|0) RNEX_WIKI_BTREE_MAX_ROOT_LINES=80 ;;
    esac
    RNEX_WIKI_BTREE_ROOT_MAX_LINES="$RNEX_WIKI_BTREE_MAX_ROOT_LINES"

    export RNEX_WORKSPACE_ROOT RNEX_WIKI_ROOT RNEX_WIKI_INDEX_FILE RNEX_WIKI_LOG_FILE
    export RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES RNEX_WIKI_BTREE_MAX_ROOT_LINES RNEX_WIKI_BTREE_ROOT_MAX_LINES

    return 0
}

# -----------------------------------------------------------------------------
# load_wiki_config_contract
# Summary: Backwards-compatible contract loader aliasing load_karpathy_wiki_config.
# @param $1: ws_root - Optional workspace root path.
# @returns: 0 on valid configuration; 1 on schema validation error.
# @sideEffects: Delegates directly to load_karpathy_wiki_config.
# -----------------------------------------------------------------------------
load_wiki_config_contract() {
    load_karpathy_wiki_config "$@"
}

# -----------------------------------------------------------------------------
# is_repo_enabled
# Summary: Determines whether a member repository is enabled or disabled
#          in rnex.yaml or .local.rnex.yaml.
# @param $1: repo_name - Target member repository identifier.
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
# Summary: Discovers active, enabled member repository names from ./repos/*
#          and the manifest rnex.yaml so flat B-Tree shards (wiki/repos-*.md)
#          are maintained per active member repo.
# @returns: Newline-delimited list of canonical member repo names on stdout.
# @sideEffects: Inspects filesystem ./repos/ directory and rnex.yaml manifest.
# -----------------------------------------------------------------------------
discover_enabled_member_repos() {
    _repos_base="${RNEX_WORKSPACE_ROOT}/${RNEX_CFG_REPOS_DIR:-repos}"
    _manifest="${RNEX_WORKSPACE_ROOT}/rnex.yaml"

    {
        if [ -d "$_repos_base" ]; then
            for _d in "$_repos_base"/*; do
                [ -d "$_d" ] || continue
                _b="$(basename "$_d")"
                [ "$_b" != "*" ] && [ "$_b" != ".gitkeep" ] && printf '%s\n' "$_b"
            done
        fi

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
