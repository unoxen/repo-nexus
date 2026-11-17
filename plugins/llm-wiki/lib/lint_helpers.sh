#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2016
# =============================================================================
# File: plugins/llm-wiki/lib/lint_helpers.sh
# Architectural Layer: Domain Helpers (helpers/)
# Single Responsibility: Validate and auto-heal existing Markdown files inside
# .rnex/wiki/ (document headers/summaries in default deep mode, root router
# bounds, orphan shards, dead workspace references, deterministic sorting,
# misplaced entries, relative Markdown links, [[wikilinks]], symlink absence)
# WITHOUT inspecting rnex config `sources` or ingesting unindexed files.
#
# Design Patterns & Principles:
#   - Single Responsibility Principle (SRP): Confined strictly to inspecting,
#     validating, and auto-healing existing wiki documentation. Zero ingestion
#     of unindexed workspace files.
#   - Strategy Pattern (GoF):
#       * Deep mode (default, `_shallow=0`): Reconstructs each catalog entry
#         from its authoritative source file via `build_wiki_entry_line` and
#         heals any stale title, summary, or link target.
#       * Shallow mode (`--shallow`, `_shallow=1`): Validates and heals link
#         depths and summary link targets without reading source file content.
#   - Don't Repeat Yourself (DRY): Reuses RNEX_WIKI_AWK_LIB,
#     build_wiki_entry_line, heal_entry_title_link_depth,
#     reroute_wiki_entry_line, consolidate_gapped_sub_shards, and
#     write_btree_shard_entries from utils.sh and btree_helpers.sh.
#   - Conditional Mutation Logging: Appends an audit entry to log.md ONLY when
#     actual repairs/modifications are made. Clean runs never mutate log.md.
#
# Standards: Pure POSIX Shell (/bin/sh), OWASP ASVS A03/A04 Reference Integrity.
# =============================================================================

# Guard against redundant multiple inclusion
if [ "${RNEX_LLM_WIKI_LINT_HELPERS_SH_SOURCED:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
RNEX_LLM_WIKI_LINT_HELPERS_SH_SOURCED=1

# Ensure btree helpers are available for index router compilation and logging
if ! command -v compile_root_index_router >/dev/null 2>&1; then
    _lh_script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
    # shellcheck source=plugins/llm-wiki/lib/btree_helpers.sh
    . "${_lh_script_dir}/btree_helpers.sh"
fi

# -----------------------------------------------------------------------------
# _lint_heal_entry_deep
# Summary: Deep per-entry healing strategy. Reconstructs the canonical catalog
#          entry line from the authoritative workspace Markdown file (H1 title,
#          link target, and summary paragraph) via build_wiki_entry_line.
# @pattern Strategy (Deep Content Validation)
# @param $1: entry_line - Current catalog bullet line in the shard.
# @param $2: doc_rel    - Workspace-relative path of the referenced document.
# @param $3: shard_name - Basename of the shard file (for audit logging).
# @returns: Canonical entry line on stdout; exit 0 if repaired, exit 1 if
#           already up to date.
# @sideEffects: Appends an `updated:` record to log.md when repaired.
# -----------------------------------------------------------------------------
_lint_heal_entry_deep() {
    _lhd_line="$1"
    _lhd_rel="$2"
    _lhd_shard="$3"

    _lhd_expected="$(build_wiki_entry_line \
        "$_lhd_rel" \
        "${RNEX_WIKI_UP_PREFIX:-../../}" \
        "${RNEX_WIKI_RELATIVE_LINKS:-rewrite}")" || {
        printf '%s\n' "$_lhd_line"
        return 1
    }

    if [ "$_lhd_expected" != "$_lhd_line" ]; then
        append_wiki_log_entry "lint" "updated: \`${_lhd_rel}\` in \`${_lhd_shard}\` (refreshed stale wiki entry)"
        printf '%s\n' "$_lhd_expected"
        return 0
    fi

    printf '%s\n' "$_lhd_line"
    return 1
}

# -----------------------------------------------------------------------------
# _lint_heal_entry_shallow
# Summary: Shallow per-entry healing strategy (`--shallow`). Validates and
#          auto-heals only the entry title link depth and relative links inside
#          the existing summary text without reading the source document.
# @pattern Strategy (Shallow Link-Only Validation)
# @param $1: entry_line - Current catalog bullet line in the shard.
# @param $2: doc_rel    - Workspace-relative path of the referenced document.
# @param $3: shard_name - Basename of the shard file (for audit logging).
# @returns: Healed entry line on stdout; exit 0 if repaired, exit 1 if unchanged.
# @sideEffects: Appends `updated:` record(s) to log.md when repaired.
# -----------------------------------------------------------------------------
_lint_heal_entry_shallow() {
    _lhs_line="$1"
    _lhs_rel="$2"
    _lhs_shard="$3"
    _lhs_changed=0

    # 1. Auto-heal entry title link target depth if it drifted from RNEX_WIKI_UP_PREFIX
    if _lhs_healed="$(heal_entry_title_link_depth "$_lhs_line" "$_lhs_rel")"; then
        _lhs_line="$_lhs_healed"
        _lhs_changed=1
        append_wiki_log_entry "lint" "updated: \`${_lhs_rel}\` in \`${_lhs_shard}\` (auto-healed entry link depth)"
    fi

    # 2. Auto-heal links inside catalog entry summary
    _lhs_marker="** (\`${_lhs_rel}\`) — "
    case "$_lhs_line" in
        *"$_lhs_marker"*)
            _lhs_prefix="${_lhs_line%%"$_lhs_marker"*}** (\`${_lhs_rel}\`)"
            _lhs_sum="${_lhs_line#*"$_lhs_marker"}"
            case "$_lhs_sum" in
                *']('*')'*|*'[['*']]'*)
                    _lhs_healed_sum="$(rewrite_markdown_links_in_summary \
                        "$_lhs_sum" \
                        "$_lhs_rel" \
                        "$RNEX_WORKSPACE_ROOT" \
                        "${RNEX_WIKI_UP_PREFIX:-../../}" \
                        "${RNEX_WIKI_RELATIVE_LINKS:-rewrite}" \
                        "1")"
                    _lhs_healed_sum="$(sanitize_markdown_summary "$_lhs_healed_sum")"
                    if [ "$_lhs_healed_sum" != "$_lhs_sum" ]; then
                        _lhs_line="${_lhs_prefix} — ${_lhs_healed_sum}"
                        _lhs_changed=1
                        append_wiki_log_entry "lint" "updated: \`${_lhs_rel}\` in \`${_lhs_shard}\` (auto-healed broken link targets)"
                    fi
                    ;;
            esac
            ;;
    esac

    printf '%s\n' "$_lhs_line"
    [ "$_lhs_changed" -eq 1 ] && return 0
    return 1
}

# -----------------------------------------------------------------------------
# lint_existing_wiki_directory
# Summary: Performs structural and content validation and auto-healing across
#          all existing Markdown documents inside $RNEX_WIKI_ROOT:
#            1. Verifies wiki directory exists.
#            2. Removes prohibited symbolic links.
#            3. Prunes dead workspace document references (deleted source files)
#               and heals entries (deep content refresh by default; link-only
#               when shallow=1).
#            4. Auto-heals deterministic LC_ALL=C sort order, re-routes
#               misplaced entries, consolidates gapped sub-shards, and splits
#               oversized shards.
#            5. Rebuilds root router index.md (linking orphan shards, unlinking
#               deleted shards, updating entry counts).
#            6. Enforces index.md line count <= RNEX_WIKI_BTREE_MAX_ROOT_LINES
#               and shard entry count <= RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES.
#            7. Validates relative Markdown links and [[wikilinks]].
#            8. Mutates log.md ONLY if repairs were applied (zero changes on clean runs).
# @param $1: shallow (0 = deep content + link validation [default], 1 = link-only).
# @param $2: quiet   (0 or 1, default 0).
# @returns: 0 if valid or healed; 1 if any unresolvable failure or rule fails.
# @sideEffects: Auto-heals wiki shards, index.md, and appends to log.md when repairs occur.
# -----------------------------------------------------------------------------
lint_existing_wiki_directory() {
    _shallow="${1:-0}"
    _quiet="${2:-0}"
    _fixes_count=0
    _errors=0

    # Ensure upward relative prefix is reliably initialized
    _up_prefix="$(resolve_wiki_up_prefix)"
    RNEX_WIKI_UP_PREFIX="$_up_prefix"
    export RNEX_WIKI_UP_PREFIX

    # 1. Verify wiki directory exists
    if [ ! -d "$RNEX_WIKI_ROOT" ]; then
        printf 'Lint Error: Wiki directory "%s" does not exist.\n' "$RNEX_WIKI_REL_DIR" >&2
        return 1
    fi

    # 2. Remove prohibited symbolic links
    _symlinks="$(find "$RNEX_WIKI_ROOT" -type l -print 2>/dev/null || true)"
    if [ -n "$_symlinks" ]; then
        find "$RNEX_WIKI_ROOT" -type l -exec rm -f {} + 2>/dev/null || true
        _fixes_count=$((_fixes_count + 1))
        append_wiki_log_entry "lint" "deleted: prohibited symbolic links in ${RNEX_WIKI_REL_DIR}"
    fi

    # 3. Ensure baseline leaf shard exists if wiki is empty
    ensure_baseline_flat_shards

    # 4. Prune dead workspace document references & re-sort entries in each shard
    for _wiki_md in "${RNEX_WIKI_ROOT}"/*.md; do
        [ -f "$_wiki_md" ] || continue
        _base_md="$(basename "$_wiki_md")"
        case "$_base_md" in
            index.md|log.md) continue ;;
        esac

        # 4a. Check for dead workspace document references & auto-heal entry links
        _shard_tmp="${_wiki_md}.tmp.$$"
        _shard_pruned=0
        while IFS= read -r _line || [ -n "$_line" ]; do
            case "$_line" in
                '- **'*)
                    _doc_rel="$(extract_entry_rel_path "$_line")"
                    if [ -z "$_doc_rel" ]; then
                        _shard_pruned=1
                        _fixes_count=$((_fixes_count + 1))
                        append_wiki_log_entry "lint" "deleted: malformed catalog entry from \`${_base_md}\`"
                        continue
                    fi
                    if [ ! -f "${RNEX_WORKSPACE_ROOT}/${_doc_rel}" ]; then
                        _shard_pruned=1
                        _fixes_count=$((_fixes_count + 1))
                        append_wiki_log_entry "lint" "deleted: \`${_doc_rel}\` (pruned dead reference from \`${_base_md}\`)"
                        continue
                    fi

                    # 4a-1. Apply active per-entry healing strategy:
                    #       - Deep mode (_shallow=0, default): reconstruct canonical
                    #         entry line from the source document (title, link, summary).
                    #       - Shallow mode (_shallow=1): heal only link depth and
                    #         summary relative links without reading source content.
                    if [ "$_shallow" -eq 1 ]; then
                        if _healed_line="$(_lint_heal_entry_shallow "$_line" "$_doc_rel" "$_base_md")"; then
                            _line="$_healed_line"
                            _shard_pruned=1
                            _fixes_count=$((_fixes_count + 1))
                        fi
                    else
                        if _healed_line="$(_lint_heal_entry_deep "$_line" "$_doc_rel" "$_base_md")"; then
                            _line="$_healed_line"
                            _shard_pruned=1
                            _fixes_count=$((_fixes_count + 1))
                        fi
                    fi
                    ;;
            esac
            printf '%s\n' "$_line" >> "$_shard_tmp"
        done < "$_wiki_md"

        if [ "$_shard_pruned" -eq 1 ]; then
            mv "$_shard_tmp" "$_wiki_md"
        else
            rm -f "$_shard_tmp"
        fi

        # 4b. Check and auto-heal LC_ALL=C sort order (and duplicate lines) of catalog entries
        _entries_tmp="${RNEX_WIKI_ROOT}/.sort_entries.$$"
        _hdr_tmp="${RNEX_WIKI_ROOT}/.sort_header.$$"
        LC_ALL=C grep '^- \*\*' "$_wiki_md" > "$_entries_tmp" 2>/dev/null || : > "$_entries_tmp"
        if [ -s "$_entries_tmp" ]; then
            if ! LC_ALL=C sort -cu "$_entries_tmp" 2>/dev/null; then
                LC_ALL=C grep -v '^- \*\*' "$_wiki_md" > "$_hdr_tmp" 2>/dev/null || : > "$_hdr_tmp"
                cat "$_hdr_tmp" > "$_wiki_md"
                LC_ALL=C sort -u "$_entries_tmp" >> "$_wiki_md"
                rm -f "$_hdr_tmp"
                _fixes_count=$((_fixes_count + 1))
                append_wiki_log_entry "lint" "updated: \`${_base_md}\` (auto-healed LC_ALL=C sort order)"
            fi
        fi
        rm -f "$_entries_tmp"
    done

    # 4b-2. Detect and re-route misplaced entries or invalid sub-shards in leaf shards
    for _wiki_md in "${RNEX_WIKI_ROOT}"/repo-nexus*.md "${RNEX_WIKI_ROOT}"/repos-*.md; do
        [ -f "$_wiki_md" ] || continue
        _base_md="$(basename "$_wiki_md")"
        case "$_base_md" in
            index.md|log.md) continue ;;
        esac

        _sid="${_base_md%.md}"
        _base_id="$(derive_base_id_for_shard "$_sid")"

        # Heal embedded base metadata comment if it drifted from canonical _base_id
        _curr_meta_base="$(sed -n 's/^<!-- base: \(.*\) -->$/\1/p' "$_wiki_md" 2>/dev/null | head -n 1)"
        if [ -n "$_curr_meta_base" ] && [ "$_curr_meta_base" != "$_base_id" ]; then
            _meta_tmp="${_wiki_md}.meta.$$"
            sed "s/^<!-- base: .* -->$/<!-- base: ${_base_id} -->/" "$_wiki_md" > "$_meta_tmp" && mv "$_meta_tmp" "$_wiki_md"
            rm -f "$_meta_tmp"
        fi

        _is_sub=0
        _is_invalid_sub=0
        _sp=""
        _ep=""
        if [ "$_sid" != "$_base_id" ]; then
            _sfx="${_sid#"${_base_id}-"}"
            case "$_sfx" in
                *-*)
                    _sp="${_sfx%%-*}"
                    _ep="${_sfx#*-}"
                    case "${_sp}${_ep}" in
                        *[!a-z]*|'')
                            _is_invalid_sub=1
                            ;;
                        *)
                            if [ "${#_sp}" -eq "${#_ep}" ] && expr "$_sp" \<= "$_ep" >/dev/null 2>&1; then
                                _is_sub=1
                            else
                                _is_invalid_sub=1
                            fi
                            ;;
                    esac
                    ;;
                *)
                    case "$_sfx" in
                        *[!a-z]*|'')
                            _is_invalid_sub=1
                            ;;
                        *)
                            _sp="$_sfx"
                            _ep="$_sfx"
                            _is_sub=1
                            ;;
                    esac
                    ;;
            esac
        fi

        _valid_entries="${_wiki_md}.valid.$$"
        _misplaced_entries="${_wiki_md}.misplaced.$$"
        : > "$_valid_entries"
        : > "$_misplaced_entries"

        LC_ALL=C awk \
            -v base_id="$_base_id" \
            -v repos_dir="${RNEX_CFG_REPOS_DIR:-repos}" \
            -v is_sub="$_is_sub" \
            -v is_invalid_sub="$_is_invalid_sub" \
            -v sp="$_sp" \
            -v ep="$_ep" \
            -v k="${#_sp}" \
            -v val_file="$_valid_entries" \
            -v mis_file="$_misplaced_entries" "
            ${RNEX_WIKI_AWK_LIB}
            /^- \*\*/ {
                if (is_invalid_sub == 1) {
                    print \$0 >> mis_file
                    next
                }
                p_rel = get_rel_path(\$0)
                exp_base = expected_base_shard(p_rel, repos_dir)
                if (exp_base != \"\" && exp_base != base_id) {
                    print \$0 >> mis_file
                    next
                }
                if (is_sub == 1 && k > 0) {
                    kt = clean_alpha_key(get_title(\$0))
                    kp = clean_alpha_key(get_path(\$0))
                    if (kt != \"\") t = kt kp
                    else if (kp != \"\") t = kp
                    else t = \"untitled\"

                    pfx = substr(t, 1, k)
                    while (length(pfx) < k) pfx = pfx \"a\"
                    if ((sp == \"a\" && pfx < sp) || (pfx >= sp && (ep == \"z\" || pfx <= ep))) {
                        print \$0 >> val_file
                    } else {
                        print \$0 >> mis_file
                    }
                } else {
                    print \$0 >> val_file
                }
            }
        " "$_wiki_md"

        if [ -s "$_misplaced_entries" ] || [ "$_is_invalid_sub" -eq 1 ]; then
            _mis_count="$(LC_ALL=C grep -c '^- \*\*' "$_misplaced_entries" 2>/dev/null || true)"
            [ -n "$_mis_count" ] || _mis_count=0
            _hdr_tmp="${_wiki_md}.hdr.$$"
            LC_ALL=C grep -v '^- \*\*' "$_wiki_md" > "$_hdr_tmp" 2>/dev/null || : > "$_hdr_tmp"
            cat "$_hdr_tmp" > "$_wiki_md"
            cat "$_valid_entries" >> "$_wiki_md"
            rm -f "$_hdr_tmp"

            if [ ! -s "$_valid_entries" ]; then
                rm -f "$_wiki_md"
                append_wiki_log_entry "lint" "deleted: \`${_base_md}\` (empty after extracting misplaced entries)"
                # If a valid sub-shard became empty and sibling sub-shards exist,
                # create the base shard file so Step 4b-3 consolidates the gapped
                # sibling partition cleanly.
                if [ "$_is_sub" -eq 1 ]; then
                    for _sib_f in "${RNEX_WIKI_ROOT}/${_base_id}-"*.md; do
                        if [ -f "$_sib_f" ]; then
                            _base_f="${RNEX_WIKI_ROOT}/${_base_id}.md"
                            if [ ! -f "$_base_f" ]; then
                                printf '# Wiki Index Shard: %s\n<!-- base: %s -->\n\n' \
                                    "$_base_id" "$_base_id" > "$_base_f"
                            fi
                            break
                        fi
                    done
                fi
            else
                append_wiki_log_entry "lint" "updated: \`${_base_md}\` (removed ${_mis_count} misplaced entries)"
            fi
            _fixes_count=$((_fixes_count + 1))

            while IFS= read -r _m_line <&7; do
                [ -n "$_m_line" ] || continue
                _rerouted="$(reroute_wiki_entry_line "$_m_line" "$_base_id")"
                _target_shard_id="${_rerouted%%|*}"
                _title="${_rerouted#*|}"
                append_wiki_log_entry "lint" "updated: \`${_target_shard_id}.md\` (re-routed misplaced entry \"${_title}\")"
            done 7< "$_misplaced_entries"
        fi
        rm -f "$_valid_entries" "$_misplaced_entries"
    done

    # 4b-3. Consolidate gapped sub-shards back into their base shard whenever
    #       both a base shard file and its sub-shards exist simultaneously,
    #       allowing Step 4c to cleanly rebalance into gap-free B-Tree ranges.
    _consolidated_count="$(consolidate_gapped_sub_shards "lint")"
    if [ -n "$_consolidated_count" ] && [ "$_consolidated_count" -gt 0 ]; then
        _fixes_count=$((_fixes_count + _consolidated_count))
    fi

    # 4c. Auto-heal oversized B-Tree leaf shards (> RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES)
    _splits_count="$(split_oversized_btree_shards "lint")"
    if [ -n "$_splits_count" ] && [ "$_splits_count" -gt 0 ]; then
        _fixes_count=$((_fixes_count + _splits_count))
    fi

    # 5. Rebuild root router index.md (linking orphan shards, pruning missing shards, updating counts)
    _idx_old_sum=""
    if [ -f "$RNEX_WIKI_INDEX_FILE" ]; then
        _idx_old_sum="$(cksum < "$RNEX_WIKI_INDEX_FILE" 2>/dev/null || true)"
    fi
    compile_root_index_router
    _idx_new_sum="$(cksum < "$RNEX_WIKI_INDEX_FILE" 2>/dev/null || true)"
    if [ "$_idx_old_sum" != "$_idx_new_sum" ]; then
        _fixes_count=$((_fixes_count + 1))
        append_wiki_log_entry "lint" "updated: \`index.md\` (recompiled root router table)"
    fi

    # 6. Post-healing invariant checks
    # 6a. Verify index.md line count <= RNEX_WIKI_BTREE_MAX_ROOT_LINES
    _root_lines="$(wc -l < "$RNEX_WIKI_INDEX_FILE" | tr -d ' ')"
    if [ "$_root_lines" -gt "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ]; then
        printf 'Lint Error: "%s/index.md" has %s lines (exceeds max %s).\n' \
            "$RNEX_WIKI_REL_DIR" "$_root_lines" "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" >&2
        _errors=$((_errors + 1))
    fi

    # 6b. Verify zero remaining symlinks
    _symlinks="$(find "$RNEX_WIKI_ROOT" -type l -print 2>/dev/null || true)"
    if [ -n "$_symlinks" ]; then
        printf 'Lint Error: Prohibited symbolic links could not be removed: %s\n' "$_symlinks" >&2
        _errors=$((_errors + 1))
    fi

    # 6c. Verify relative Markdown links and wikilinks inside existing wiki files
    for _wiki_md in "${RNEX_WIKI_ROOT}"/*.md; do
        [ -f "$_wiki_md" ] || continue
        _base_md="$(basename "$_wiki_md")"
        _links_tmp="${RNEX_WIKI_ROOT}/.lint_links.$$"
        LC_ALL=C awk '
            {
                line = $0
                while (match(line, /\[[^]]*\]\([^)]+\)/)) {
                    m = substr(line, RSTART, RLENGTH)
                    sub(/^\[[^]]*\]\(/, "", m)
                    sub(/\)$/, "", m)
                    sub(/[#?].*$/, "", m)
                    if (m != "") print m
                    line = substr(line, RSTART + RLENGTH)
                }
            }
        ' "$_wiki_md" > "$_links_tmp"
        while IFS= read -r _link_target <&5; do
            case "$_link_target" in
                ''|http://*|https://*|mailto:*|ftp://*|//|\#*) continue ;;
            esac
            if [ ! -e "${RNEX_WIKI_ROOT}/${_link_target}" ] && [ ! -e "${RNEX_WORKSPACE_ROOT}/${_link_target}" ]; then
                printf 'Lint Error [%s]: Broken Markdown link target "%s".\n' \
                    "$_base_md" "$_link_target" >&2
                _errors=$((_errors + 1))
            fi
        done 5< "$_links_tmp"
        rm -f "$_links_tmp"

        _wikilinks_tmp="${RNEX_WIKI_ROOT}/.lint_wikilinks.$$"
        LC_ALL=C awk '
            {
                line = $0
                while (match(line, /\[\[[^]]+\]\]/)) {
                    m = substr(line, RSTART, RLENGTH)
                    sub(/^\[\[/, "", m)
                    sub(/\]\]$/, "", m)
                    sub(/\|.*$/, "", m)
                    if (m != "") print m
                    line = substr(line, RSTART + RLENGTH)
                }
            }
        ' "$_wiki_md" > "$_wikilinks_tmp"
        while IFS= read -r _wl <&6; do
            [ -n "$_wl" ] || continue
            case "$_wl" in
                ''|*/*) continue ;;
            esac
            _target_wl="${RNEX_WIKI_ROOT}/${_wl}.md"
            _target_exact="${RNEX_WIKI_ROOT}/${_wl}"
            if [ ! -e "$_target_wl" ] && [ ! -e "$_target_exact" ]; then
                printf 'Lint Error [%s]: Broken wikilink "[[%s]]".\n' "$_base_md" "$_wl" >&2
                _errors=$((_errors + 1))
            fi
        done 6< "$_wikilinks_tmp"
        rm -f "$_wikilinks_tmp"
    done

    # 6d. Verify no leaf shard exceeds RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES (default: 100)
    for _wiki_md in "${RNEX_WIKI_ROOT}"/*.md; do
        [ -f "$_wiki_md" ] || continue
        _base_md="$(basename "$_wiki_md")"
        case "$_base_md" in
            index.md|log.md) continue ;;
        esac
        _rec_cnt="$(LC_ALL=C grep -c '^- \*\*' "$_wiki_md" 2>/dev/null || true)"
        [ -n "$_rec_cnt" ] || _rec_cnt=0
        if [ "$_rec_cnt" -gt "${RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES:-100}" ]; then
            printf 'Lint Error [%s]: Shard has %s records (exceeds max %s).\n' \
                "$_base_md" "$_rec_cnt" "${RNEX_WIKI_BTREE_SHARD_MAX_ENTRIES:-100}" >&2
            _errors=$((_errors + 1))
        fi
    done

    # 7. On fatal errors, fail
    if [ "$_errors" -gt 0 ]; then
        if [ "$_fixes_count" -gt 0 ]; then
            append_wiki_log_entry "lint" "Repaired ${_fixes_count} wiki issue(s) before encountering fatal error(s)."
        fi
        printf 'Wiki lint failed with %s error(s) in %s.\n' "$_errors" "$RNEX_WIKI_REL_DIR" >&2
        return 1
    fi

    # 8. Record audit log entry ONLY if fixes were made (conditional mutation)
    if [ "$_fixes_count" -gt 0 ]; then
        append_wiki_log_entry "lint" "Repaired ${_fixes_count} wiki issue(s) in ${RNEX_WIKI_REL_DIR}: auto-healed shards, router index, and references."
        if [ "$_quiet" -ne 1 ]; then
            printf 'Wiki lint passed: repaired %s issue(s) in %s.\n' "$_fixes_count" "$RNEX_WIKI_REL_DIR"
        fi
    else
        if [ "$_quiet" -ne 1 ]; then
            printf 'Wiki lint passed: all existing docs and references in %s are valid.\n' "$RNEX_WIKI_REL_DIR"
        fi
    fi

    return 0
}
