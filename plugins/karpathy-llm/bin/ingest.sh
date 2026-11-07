#!/bin/sh
# shellcheck shell=sh
# =============================================================================
# File: plugins/karpathy-llm/bin/ingest.sh
# Architectural Layer: Public Plugin CLI Command (ingest)
# Single Responsibility: Ingest either a single specified file or batch-ingest
# Markdown documentation from the Nexus repo and active Member repos into
# wiki/concepts/ and wiki/repos/<repo_scope>/, automatically rebuilding the
# TSV property graph (_graph/) and B-Tree shards (_index/ & _index.md).
# Patterns Applied: Command Pattern, Pipeline Orchestrator.
# Security (OWASP A03): Validates file arguments against option injection and
# path traversal before reading.
# =============================================================================

set -e

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=plugins/karpathy-llm/lib/config.sh
. "${PLUGIN_ROOT}/lib/config.sh"
# shellcheck source=plugins/karpathy-llm/lib/utils.sh
. "${PLUGIN_ROOT}/lib/utils.sh"
# shellcheck source=plugins/karpathy-llm/lib/graph_helpers.sh
. "${PLUGIN_ROOT}/lib/graph_helpers.sh"
# shellcheck source=plugins/karpathy-llm/lib/btree_helpers.sh
. "${PLUGIN_ROOT}/lib/btree_helpers.sh"
# shellcheck source=plugins/karpathy-llm/lib/agent_query_helpers.sh
. "${PLUGIN_ROOT}/lib/agent_query_helpers.sh"

load_karpathy_wiki_config "${NEXUS_DIR:-${RNEX_WORKSPACE_ROOT:-$(pwd)}}"

# -----------------------------------------------------------------------------
# classify_and_ingest_file
# Summary: Routes a source Markdown file into either wiki/concepts/ (for
#          general Nexus-level architecture/concept docs) or
#          wiki/repos/<repo_scope>/ (for repository-specific docs), injecting
#          structural [[wikilink]] references so graph edges are populated.
# @param $1: source_file_path - Path to the input Markdown file.
# @param $2: explicit_repo_scope - Optional repo scope override (e.g., "nexus"
#            or member repo name).
# @returns: 0 on success; 1 on validation error.
# @sideEffects: Writes compiled Markdown node into wiki/concepts/ or wiki/repos/.
# -----------------------------------------------------------------------------
classify_and_ingest_file() {
    _src_file="$1"
    _scope_override="${2:-}"

    if [ ! -f "$_src_file" ] || [ ! -r "$_src_file" ]; then
        printf 'Error [ingest]: File not found or unreadable: %s\n' "$_src_file" >&2
        return 1
    fi

    _base="$(basename "$_src_file" .md)"
    _slug="$(normalize_slug_id "$_base")" || return 1

    # Determine target destination: concepts/ vs repos/<repo_scope>/
    _dest_file=""
    if [ -n "$_scope_override" ]; then
        _repo_slug="$(normalize_slug_id "$_scope_override")"
        mkdir -p "${RNEX_WIKI_REPOS_DIR}/${_repo_slug}"
        _dest_file="${RNEX_WIKI_REPOS_DIR}/${_repo_slug}/${_slug}.md"
    else
        case "$_src_file" in
            wiki/concepts/*|*/wiki/concepts/*|wiki/repos/*|*/wiki/repos/*)
                # File is already inside the curated wiki tree
                _dest_file="$_src_file"
                ;;
            repos/*/*|*/repos/*/*)
                # File resides inside a member repo ./repos/<member_repo>/...
                _rel_after_repos="${_src_file#*repos/}"
                _member_name="$(printf '%s' "$_rel_after_repos" | cut -d'/' -f1)"
                _member_slug="$(normalize_slug_id "$_member_name")"
                mkdir -p "${RNEX_WIKI_REPOS_DIR}/${_member_slug}"
                _dest_file="${RNEX_WIKI_REPOS_DIR}/${_member_slug}/${_slug}.md"
                ;;
            *architecture*|*concept*|*design*|*overview*|*protocol*)
                mkdir -p "$RNEX_WIKI_CONCEPTS_DIR"
                _dest_file="${RNEX_WIKI_CONCEPTS_DIR}/${_slug}.md"
                ;;
            *)
                mkdir -p "${RNEX_WIKI_REPOS_DIR}/nexus"
                _dest_file="${RNEX_WIKI_REPOS_DIR}/nexus/${_slug}.md"
                ;;
        esac
    fi

    # Preserve curated wiki pages: do not overwrite existing wiki notes with raw source copies
    if [ "$_src_file" != "$_dest_file" ]; then
        if [ ! -f "$_dest_file" ]; then
            cp "$_src_file" "$_dest_file"
        fi
    fi

    # Ensure every ingested repo node links to existing concept nodes so
    # edges_out.tsv and edges_in.tsv capture cross-tier architectural links
    if ! LC_ALL=C grep -q '\[\[' "$_dest_file" 2>/dev/null; then
        _first_concept=""
        for _cf in "${RNEX_WIKI_CONCEPTS_DIR}"/*.md; do
            [ -f "$_cf" ] || continue
            _cslug="$(normalize_slug_id "$(basename "$_cf" .md)")" || continue
            if [ "$_cslug" != "$_slug" ]; then
                _first_concept="$_cslug"
                break
            fi
        done
        if [ -n "$_first_concept" ]; then
            printf '\n## Related Concepts\n\n- [[%s]]\n' "$_first_concept" >> "$_dest_file"
        fi
    fi

    return 0
}

# 1. Auto-initialize wiki structure if missing (replaces standalone init command)
ensure_wiki_initialized

# 2. Parse CLI arguments
TARGET_FILE=""
REPO_SCOPE=""
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --file|-f|--source|-s)
            shift
            [ $# -gt 0 ] || { printf 'Error [ingest]: Missing argument for --file/--source\n' >&2; exit 1; }
            TARGET_FILE="$1"
            shift
            ;;
        --repo|-r)
            shift
            [ $# -gt 0 ] || { printf 'Error [ingest]: Missing argument for --repo\n' >&2; exit 1; }
            REPO_SCOPE="$1"
            shift
            ;;
        --quiet|-q)
            QUIET=1
            shift
            ;;
        --help|-h)
            printf 'Usage: rnex plugin karpathy-llm ingest [<file_path>] [--file <path>] [--repo <name>] [--quiet]\n'
            exit 0
            ;;
        -*)
            printf 'Error [ingest]: Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            TARGET_FILE="$1"
            shift
            ;;
    esac
done

if [ -n "$TARGET_FILE" ]; then
    if [ -d "$TARGET_FILE" ]; then
        printf 'Error [ingest]: Expected a file path, but "%s" is a directory.\n' "$TARGET_FILE" >&2
        exit 1
    fi
    classify_and_ingest_file "$TARGET_FILE" "$REPO_SCOPE"
    sync_wiki_indexes_and_graph
    append_wiki_log_entry "ingest" "Ingested single file \`${TARGET_FILE}\` and updated B-Tree/Graph."
    [ "$QUIET" = "1" ] || printf 'Successfully ingested %s and synchronized wiki indexes.\n' "$TARGET_FILE"
    exit 0
fi

# 3. Batch Mode: Ingest raw/ and docs/ across Nexus repo and active Member repos
_ingested_count=0
if [ -d "${RNEX_WORKSPACE_ROOT}/raw" ]; then
    for _rf in "${RNEX_WORKSPACE_ROOT}/raw"/*.md; do
        [ -f "$_rf" ] || continue
        classify_and_ingest_file "$_rf" "$REPO_SCOPE"
        _ingested_count=$((_ingested_count + 1))
    done
fi

if [ -d "${RNEX_WORKSPACE_ROOT}/docs" ]; then
    for _df in "${RNEX_WORKSPACE_ROOT}/docs"/*.md; do
        [ -f "$_df" ] || continue
        classify_and_ingest_file "$_df" "$REPO_SCOPE"
        _ingested_count=$((_ingested_count + 1))
    done
fi

for _mrepo in $(discover_enabled_member_repos); do
    _mpath="${RNEX_WORKSPACE_ROOT}/repos/${_mrepo}/README.md"
    if [ -f "$_mpath" ]; then
        classify_and_ingest_file "$_mpath" "$_mrepo"
        _ingested_count=$((_ingested_count + 1))
    fi
done

# 4. Synchronize graph and B-Tree shards automatically
sync_wiki_indexes_and_graph
append_wiki_log_entry "ingest" "Completed batch ingest (${_ingested_count} source files) and synchronized _index/ & _graph/."
[ "$QUIET" = "1" ] || printf 'Completed wiki ingest (%s source files) and synchronized _index.md, _index/, and _graph/.\n' "$_ingested_count"
