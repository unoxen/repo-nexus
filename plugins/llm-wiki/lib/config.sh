#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/llm-wiki/lib/config.sh
# Architectural Layer: Configuration Management Contract (Fail-Fast)
# Single Responsibility: Validate and expose read-only runtime configuration
# contracts for the LLM Wiki engine, defaulting to .rnex/wiki.
#
# Design Patterns & Principles:
#   - Contract-First Design: Centralizes configuration loading, sanitization,
#     and validation into a strict, immutable contract before filesystem I/O.
#   - Fail-Fast Principle: Immediate rejection of path traversal attempts,
#     non-existent workspace roots, or invalid numeric capacity thresholds.
#   - Dependency Inversion Principle (DIP): Downstream modules depend strictly
#     on standardized environment variables (RNEX_WIKI_*) rather than reading
#     raw config files or hardcoding path constants.
#
# Standards: Pure POSIX Shell (/bin/sh), OWASP ASVS A03/A04 Input Validation.
# =============================================================================

# Guard against redundant multiple inclusion
if [ "${RNEX_LLM_WIKI_CONFIG_SH_SOURCED:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
RNEX_LLM_WIKI_CONFIG_SH_SOURCED=1

# Ensure pure utilities are loaded for compute_upward_rel_prefix
if ! command -v compute_upward_rel_prefix >/dev/null 2>&1; then
    _cfg_script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
    # shellcheck source=plugins/llm-wiki/lib/utils.sh
    . "${_cfg_script_dir}/utils.sh"
fi

# -----------------------------------------------------------------------------
# _lookup_llm_wiki_cfg
# Summary: Looks up a configuration key for the llm-wiki plugin from the
#          workspace YAML configuration (supporting yaml_plugin_get,
#          .local.rnex.yaml, and rnex.yaml).
# @param $1: target_key - Configuration setting key name.
# @returns: Setting value string on stdout, or empty string if not configured.
# @pure (Read-only configuration inspection)
# -----------------------------------------------------------------------------
_lookup_llm_wiki_cfg() {
    _k="$1"
    _v=""
    if command -v yaml_plugin_get >/dev/null 2>&1; then
        _v="$(yaml_plugin_get "llm-wiki" "$_k" 2>/dev/null || true)"
    fi
    if [ -z "$_v" ] && [ -n "${RNEX_WORKSPACE_ROOT:-}" ]; then
        for _cf in "${RNEX_WORKSPACE_ROOT}/.local.rnex.yaml" "${RNEX_WORKSPACE_ROOT}/rnex.yaml"; do
            [ -f "$_cf" ] || continue
            _v="$(LC_ALL=C awk -v target_k="$_k" '
                BEGIN { in_plugin=0 }
                /^[ ]*llm-wiki:[ ]*(#.*)?$/ { in_plugin=1; next }
                in_plugin && /^[ ]{1,2}[a-zA-Z0-9._-]+:/ { in_plugin=0 }
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

# -----------------------------------------------------------------------------
# load_wiki_config_contract
# Summary: Initializes, validates, and exports immutable runtime configuration
#          variables for the deterministic B-Tree wiki store, defaulting to
#          the strictly encapsulated .rnex/wiki directory.
# @param $1: workspace_root - Optional absolute path to workspace root
#            (defaults to RNEX_WORKSPACE_ROOT or current directory).
# @returns: 0 on valid configuration; 1 on schema validation or security error.
# @throws: Writes descriptive error to stderr and returns 1 on invalid config.
# @sideEffects: Exports RNEX_WORKSPACE_ROOT, RNEX_WIKI_*, and RNEX_WIKI_UP_PREFIX.
# -----------------------------------------------------------------------------
load_wiki_config_contract() {
    _ws_root="${1:-${RNEX_WORKSPACE_ROOT:-$(pwd)}}"

    # Reject empty or non-directory workspace roots
    if [ -z "$_ws_root" ] || [ ! -d "$_ws_root" ]; then
        printf 'Error [config]: Invalid workspace_root supplied to load_wiki_config_contract.\n' >&2
        return 1
    fi

    # Reject path traversal in workspace root (OWASP A03)
    case "$_ws_root" in
        *".."*)
            printf 'Error [config]: Invalid workspace root path traversal detected (OWASP A03).\n' >&2
            return 1
            ;;
    esac

    RNEX_WORKSPACE_ROOT="${_ws_root%/}"

    # Resolve workspace member repositories directory (default: repos)
    if [ -z "${RNEX_CFG_REPOS_DIR:-}" ]; then
        _cfg_rdir=""
        if command -v yaml_get_repos_dir >/dev/null 2>&1; then
            _cfg_rdir="$(yaml_get_repos_dir 2>/dev/null || true)"
        fi
        if [ -z "$_cfg_rdir" ]; then
            for _rcf in "${RNEX_WORKSPACE_ROOT}/.local.rnex.yaml" "${RNEX_WORKSPACE_ROOT}/rnex.yaml"; do
                [ -f "$_rcf" ] || continue
                _cfg_rdir="$(LC_ALL=C awk '
                    /^reposDir:[ ]*/ {
                        line = $0
                        sub(/^[^:]+:[ ]*/, "", line)
                        sub(/[ ]*#.*$/, "", line)
                        gsub(/^["\047]|["\047]$/, "", line)
                        print line
                        exit
                    }
                ' "$_rcf" 2>/dev/null)"
                [ -n "$_cfg_rdir" ] && break
            done
        fi
        _cfg_rdir="${_cfg_rdir#./}"
        _cfg_rdir="${_cfg_rdir%/}"
        [ -n "$_cfg_rdir" ] || _cfg_rdir="repos"
        RNEX_CFG_REPOS_DIR="$_cfg_rdir"
    fi

    # Default wiki directory is strictly encapsulated inside .rnex/wiki
    if [ -n "${RNEX_CFG_WIKI_DIR:-}" ]; then
        _wiki_rel="$RNEX_CFG_WIKI_DIR"
    else
        _wiki_rel="$(_lookup_llm_wiki_cfg "wikiDir")"
        [ -n "$_wiki_rel" ] || _wiki_rel=".rnex/wiki"
    fi

    # Normalize relative path: strip leading "./" and trailing "/"
    _wiki_rel="${_wiki_rel#./}"
    _wiki_rel="${_wiki_rel%/}"

    # OWASP A03: Reject empty paths, path traversal (".."), or absolute paths
    case "$_wiki_rel" in
        ''|*..*|/*)
            printf 'Error [security]: Unsafe wikiDir path "%s" rejected (OWASP A03).\n' "$_wiki_rel" >&2
            return 1
            ;;
    esac

    RNEX_WIKI_REL_DIR="$_wiki_rel"
    RNEX_WIKI_ROOT="${RNEX_WORKSPACE_ROOT}/${_wiki_rel}"

    # Resolve root router filename (default: index.md)
    if [ -n "${RNEX_CFG_INDEX_FILE:-}" ]; then
        _idx_name="$RNEX_CFG_INDEX_FILE"
    else
        _idx_name="$(_lookup_llm_wiki_cfg "indexFile")"
        [ -n "$_idx_name" ] || _idx_name="index.md"
    fi
    RNEX_WIKI_INDEX_FILE="${RNEX_WIKI_ROOT}/${_idx_name}"

    # Resolve audit log filename (default: log.md)
    if [ -n "${RNEX_CFG_LOG_FILE:-}" ]; then
        _log_name="$RNEX_CFG_LOG_FILE"
    else
        _log_name="$(_lookup_llm_wiki_cfg "logFile")"
        [ -n "$_log_name" ] || _log_name="log.md"
    fi
    RNEX_WIKI_LOG_FILE="${RNEX_WIKI_ROOT}/${_log_name}"

    # Compute upward relative prefix from wiki directory to workspace root
    RNEX_WIKI_UP_PREFIX="$(compute_upward_rel_prefix "$RNEX_WIKI_REL_DIR")"

    # Capacity constraints: maximum root lines and maximum shard entries
    if [ -n "${RNEX_CFG_BTREE_ROOT_MAX_LINES:-}" ]; then
        RNEX_WIKI_BTREE_MAX_ROOT_LINES="$RNEX_CFG_BTREE_ROOT_MAX_LINES"
    else
        RNEX_WIKI_BTREE_MAX_ROOT_LINES="$(_lookup_llm_wiki_cfg "btreeRootMaxLines")"
        [ -n "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ] || RNEX_WIKI_BTREE_MAX_ROOT_LINES=80
    fi

    if [ -n "${RNEX_CFG_BTREE_SHARD_MAX_ENTRIES:-}" ]; then
        RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES="$RNEX_CFG_BTREE_SHARD_MAX_ENTRIES"
    else
        RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES="$(_lookup_llm_wiki_cfg "btreeShardMaxEntries")"
        [ -n "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" ] || RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES=100
    fi

    # Audit log capacity: maximum records before oldest entries are pruned (default: 1000)
    if [ -n "${RNEX_CFG_LOG_MAX_RECORDS:-}" ]; then
        RNEX_WIKI_LOG_MAX_RECORDS="$RNEX_CFG_LOG_MAX_RECORDS"
    else
        RNEX_WIKI_LOG_MAX_RECORDS="$(_lookup_llm_wiki_cfg "logMaxRecords")"
        [ -n "$RNEX_WIKI_LOG_MAX_RECORDS" ] || RNEX_WIKI_LOG_MAX_RECORDS=1000
    fi

    # Record summary capacity: maximum character length of each wiki record summary (default: 100)
    if [ -n "${RNEX_CFG_RECORD_SUMMARY_MAX_LENGTH:-}" ]; then
        RNEX_WIKI_RECORD_SUMMARY_MAX_LENGTH="$RNEX_CFG_RECORD_SUMMARY_MAX_LENGTH"
    else
        RNEX_WIKI_RECORD_SUMMARY_MAX_LENGTH="$(_lookup_llm_wiki_cfg "recordSummaryMaxLength")"
        [ -n "$RNEX_WIKI_RECORD_SUMMARY_MAX_LENGTH" ] || RNEX_WIKI_RECORD_SUMMARY_MAX_LENGTH=100
    fi

    # Enforce strictly positive integers for capacity thresholds
    for _num_val in "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" "$RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES" "$RNEX_WIKI_LOG_MAX_RECORDS" "$RNEX_WIKI_RECORD_SUMMARY_MAX_LENGTH"; do
        case "$_num_val" in
            ''|*[!0-9]*|0)
                printf 'Error [config]: Numeric threshold "%s" must be a positive integer.\n' "$_num_val" >&2
                return 1
                ;;
        esac
    done

    # Relative links handling strategy: rewrite (default) or strip/delete
    if [ -n "${RNEX_CFG_RELATIVE_LINKS:-}" ]; then
        RNEX_WIKI_RELATIVE_LINKS="$RNEX_CFG_RELATIVE_LINKS"
    else
        RNEX_WIKI_RELATIVE_LINKS="$(_lookup_llm_wiki_cfg "relativeLinks")"
        [ -n "$RNEX_WIKI_RELATIVE_LINKS" ] || RNEX_WIKI_RELATIVE_LINKS="rewrite"
    fi

    case "$RNEX_WIKI_RELATIVE_LINKS" in
        strip|delete|unlink)
            RNEX_WIKI_RELATIVE_LINKS="strip"
            ;;
        *)
            RNEX_WIKI_RELATIVE_LINKS="rewrite"
            ;;
    esac

    export RNEX_WORKSPACE_ROOT RNEX_CFG_REPOS_DIR RNEX_WIKI_REL_DIR RNEX_WIKI_ROOT \
           RNEX_WIKI_INDEX_FILE RNEX_WIKI_LOG_FILE RNEX_WIKI_UP_PREFIX \
           RNEX_WIKI_BTREE_MAX_ROOT_LINES RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES \
           RNEX_WIKI_RELATIVE_LINKS RNEX_WIKI_LOG_MAX_RECORDS \
           RNEX_WIKI_RECORD_SUMMARY_MAX_LENGTH

    return 0
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
