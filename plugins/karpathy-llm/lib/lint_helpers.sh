#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2016
# =============================================================================
# File: plugins/karpathy-llm/lib/lint_helpers.sh
# Architectural Layer: Domain Helpers (helpers/)
# Single Responsibility: Validate and auto-heal existing Markdown files inside
# .rnex/wiki/ (root router bounds, orphan shards, dead workspace references,
# deterministic sorting, relative Markdown links, [[wikilinks]], symlink absence)
# WITHOUT reading or checking rnex config `sources`.
#
# Design Patterns & Principles:
#   - Single Responsibility Principle (SRP): Confined strictly to inspecting,
#     validating, and auto-healing existing wiki documentation. Zero ingestion.
#   - Auto-Healing & Self-Repair: Heals out-of-order catalog entries, links orphan
#     shards into index.md, prunes dead document references, and removes symlinks.
#   - Conditional Mutation Logging: Appends an audit entry to log.md ONLY when
#     actual repairs/modifications are made. Clean runs never mutate log.md.
#
# Standards: Pure POSIX Shell (/bin/sh), OWASP ASVS A03/A04 Reference Integrity.
# =============================================================================

# Guard against redundant multiple inclusion
if [ "${RNEX_KARPATHY_LINT_HELPERS_SH_SOURCED:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
RNEX_KARPATHY_LINT_HELPERS_SH_SOURCED=1

# Ensure btree helpers are available for index router compilation and logging
if ! command -v compile_root_index_router >/dev/null 2>&1; then
    _lh_script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
    # shellcheck source=plugins/karpathy-llm/lib/btree_helpers.sh
    . "${_lh_script_dir}/btree_helpers.sh"
fi

# -----------------------------------------------------------------------------
# lint_existing_wiki_directory
# Summary: Performs structural validation and auto-healing across all existing
#          Markdown documents inside $RNEX_WIKI_ROOT:
#            1. Verifies wiki directory exists.
#            2. Auto-heals legacy artifacts and purges prohibited symlinks.
#            3. Prunes dead workspace document references (deleted source files).
#            4. Auto-heals deterministic LC_ALL=C sort order of catalog entries.
#            5. Rebuilds root router index.md (linking orphan shards, unlinking
#               deleted shards, updating entry counts).
#            6. Enforces index.md line count <= RNEX_WIKI_BTREE_MAX_ROOT_LINES.
#            7. Validates relative Markdown links and [[wikilinks]].
#            8. Mutates log.md ONLY if repairs were applied (zero changes on clean runs).
# @param $1: strict (0 or 1, default 0).
# @param $2: quiet  (0 or 1, default 0).
# @returns: 0 if valid or healed; 1 if any unresolvable failure or rule fails.
# -----------------------------------------------------------------------------
lint_existing_wiki_directory() {
    _strict="${1:-0}"
    _quiet="${2:-0}"
    _fixes_count=0
    _errors=0

    # Ensure upward relative prefix is reliably initialized
    _up_prefix="${RNEX_WIKI_UP_PREFIX:-}"
    if [ -z "$_up_prefix" ] && command -v compute_upward_rel_prefix >/dev/null 2>&1; then
        _up_prefix="$(compute_upward_rel_prefix "$RNEX_WIKI_REL_DIR")"
    fi
    [ -n "$_up_prefix" ] || _up_prefix="../../"
    RNEX_WIKI_UP_PREFIX="$_up_prefix"
    export RNEX_WIKI_UP_PREFIX

    # 1. Verify wiki directory exists
    if [ ! -d "$RNEX_WIKI_ROOT" ]; then
        printf 'Lint Error: Wiki directory "%s" does not exist.\n' "$RNEX_WIKI_REL_DIR" >&2
        return 1
    fi

    # 2. Auto-heal legacy artifacts and remove prohibited symlinks
    purge_legacy_wiki_artifacts
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
                '- **'*'(`'*'`)'*)
                    _doc_rel="$(printf '%s\n' "$_line" | sed -n 's/^- \*\*.*(`\([^`]*\)`).*/\1/p')"
                    if [ -n "$_doc_rel" ] && [ ! -f "${RNEX_WORKSPACE_ROOT}/${_doc_rel}" ]; then
                        _shard_pruned=1
                        _fixes_count=$((_fixes_count + 1))
                        append_wiki_log_entry "lint" "deleted: \`${_doc_rel}\` (pruned dead reference from \`${_base_md}\`)"
                        continue
                    fi

                    # Auto-heal broken links inside catalog entry summary if source document exists
                    if [ -n "$_doc_rel" ] && [ -f "${RNEX_WORKSPACE_ROOT}/${_doc_rel}" ]; then
                        # 4a-1. Auto-heal entry title link target depth if it does not match RNEX_WIKI_UP_PREFIX
                        _expected_target="${RNEX_WIKI_UP_PREFIX}${_doc_rel}"
                        _curr_target="$(printf '%s\n' "$_line" | sed -n 's/^- \*\*\[[^]]*\](\([^)]*\)).*/\1/p')"
                        if [ -n "$_curr_target" ] && [ "$_curr_target" != "$_expected_target" ]; then
                            _title_text="$(printf '%s\n' "$_line" | sed -n 's/^- \*\*\[\([^]]*\)\].*/\1/p')"
                            _rest="${_line#*(\`"${_doc_rel}"\`)}"
                            _line="- **[${_title_text}](${_expected_target})** (\`${_doc_rel}\`)${_rest}"
                            _shard_pruned=1
                            _fixes_count=$((_fixes_count + 1))
                            append_wiki_log_entry "lint" "updated: \`${_doc_rel}\` in \`${_base_md}\` (auto-healed entry link depth)"
                        fi

                        # 4a-2. Auto-heal links inside catalog entry summary
                        case "$_line" in
                            *']('*')'*)
                                _prefix="${_line%% — *}"
                                _sum_part="${_line#* — }"
                                if [ "$_prefix" != "$_line" ] && [ -n "$_sum_part" ]; then
                                    _healed_sum="$(rewrite_markdown_links_in_summary \
                                        "$_sum_part" \
                                        "$_doc_rel" \
                                        "$RNEX_WORKSPACE_ROOT" \
                                        "${RNEX_WIKI_UP_PREFIX:-../../}" \
                                        "${RNEX_WIKI_RELATIVE_LINKS:-rewrite}")"
                                    _healed_sum="$(sanitize_markdown_summary "$_healed_sum")"
                                    if [ "$_healed_sum" != "$_sum_part" ]; then
                                        _line="${_prefix} — ${_healed_sum}"
                                        _shard_pruned=1
                                        _fixes_count=$((_fixes_count + 1))
                                        append_wiki_log_entry "lint" "updated: \`${_doc_rel}\` in \`${_base_md}\` (auto-healed broken link targets)"
                                    fi
                                fi
                                ;;
                        esac
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

        # 4b. Check and auto-heal LC_ALL=C sort order of catalog entries
        _entries_tmp="${RNEX_WIKI_ROOT}/.sort_entries.$$"
        _hdr_tmp="${RNEX_WIKI_ROOT}/.sort_header.$$"
        LC_ALL=C grep '^- \*\*' "$_wiki_md" > "$_entries_tmp" 2>/dev/null || : > "$_entries_tmp"
        if [ -s "$_entries_tmp" ]; then
            if ! LC_ALL=C sort -c "$_entries_tmp" 2>/dev/null; then
                LC_ALL=C grep -v '^- \*\*' "$_wiki_md" > "$_hdr_tmp"
                cat "$_hdr_tmp" > "$_wiki_md"
                LC_ALL=C sort -u "$_entries_tmp" >> "$_wiki_md"
                rm -f "$_hdr_tmp"
                _fixes_count=$((_fixes_count + 1))
                append_wiki_log_entry "lint" "updated: \`${_base_md}\` (auto-healed LC_ALL=C sort order)"
            fi
        fi
        rm -f "$_entries_tmp"
    done

    # 4b-2. Detect and dissolve any legacy numeric shards (e.g. *-1.md, *-2.md, *-aa-1.md)
    for _num_shard in "${RNEX_WIKI_ROOT}"/*-[0-9]*.md; do
        [ -f "$_num_shard" ] || continue
        _num_bname="$(basename "$_num_shard")"
        case "$_num_bname" in
            index.md|log.md) continue ;;
        esac

        _raw_entries="${_num_shard}.raw.$$"
        LC_ALL=C grep '^- \*\*' "$_num_shard" > "$_raw_entries" 2>/dev/null || : > "$_raw_entries"
        rm -f "$_num_shard"
        append_wiki_log_entry "lint" "deleted: \`${_num_bname}\` (purged non-semantic numeric shard)"
        _fixes_count=$((_fixes_count + 1))

        if [ -s "$_raw_entries" ]; then
            while IFS= read -r _entry_line <&6; do
                [ -n "$_entry_line" ] || continue
                _rel_path="$(printf '%s' "$_entry_line" | sed -n 's/.*(`\([^`]*\)`).*/\1/p')"
                _title="$(printf '%s' "$_entry_line" | sed -n 's/^- \*\*\[\([^]]*\)\].*/\1/p')"
                [ -n "$_title" ] || _title="$(printf '%s' "$_entry_line" | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p')"
                [ -n "$_title" ] || _title="untitled"

                if [ -n "$_rel_path" ]; then
                    _shard_id="$(derive_shard_id_for_workspace_path "$_rel_path")"
                else
                    _shard_id="$(derive_base_id_for_shard "${_num_bname%.md}")"
                fi

                # Auto-heal entry relative link depth if source file exists
                if [ -n "$_rel_path" ] && [ -f "${RNEX_WORKSPACE_ROOT}/${_rel_path}" ]; then
                    _expected_target="${RNEX_WIKI_UP_PREFIX}${_rel_path}"
                    _curr_target="$(printf '%s\n' "$_entry_line" | sed -n 's/^- \*\*\[[^]]*\](\([^)]*\)).*/\1/p')"
                    if [ -n "$_curr_target" ] && [ "$_curr_target" != "$_expected_target" ]; then
                        _rest="${_entry_line#*(\`"${_rel_path}"\`)}"
                        _entry_line="- **[${_title}](${_expected_target})** (\`${_rel_path}\`)${_rest}"
                    fi
                fi

                _target_shard_file="$(resolve_target_btree_shard_file "$_shard_id" "$_title")"
                _target_shard_id="$(basename "$_target_shard_file" .md)"

                _t_entries="${_target_shard_file}.entries.$$"
                if [ -f "$_target_shard_file" ]; then
                    LC_ALL=C grep '^- \*\*' "$_target_shard_file" > "$_t_entries" 2>/dev/null || : > "$_t_entries"
                else
                    : > "$_t_entries"
                fi
                printf '%s\n' "$_entry_line" >> "$_t_entries"
                atomic_sort_unique_file "$_t_entries"

                _t_tmp="${_target_shard_file}.tmp.$$"
                printf '# Wiki Index Shard: %s\n<!-- base: %s -->\n\n' "$_target_shard_id" "$_shard_id" > "$_t_tmp"
                cat "$_t_entries" >> "$_t_tmp"
                rm -f "$_t_entries"
                mv "$_t_tmp" "$_target_shard_file"
                append_wiki_log_entry "lint" "updated: \`${_target_shard_id}.md\` (re-routed entry from purged numeric shard)"
            done 6< "$_raw_entries"
        fi
        rm -f "$_raw_entries"
    done

    # 4b-3. Detect and re-route misplaced entries in existing leaf shards
    for _wiki_md in "${RNEX_WIKI_ROOT}"/repo-nexus*.md "${RNEX_WIKI_ROOT}"/repos-*.md; do
        [ -f "$_wiki_md" ] || continue
        _base_md="$(basename "$_wiki_md")"
        case "$_base_md" in
            index.md|log.md) continue ;;
        esac

        _sid="${_base_md%.md}"
        _base_id="$(derive_base_id_for_shard "$_sid")"
        [ "$_sid" != "$_base_id" ] || continue
        _sfx="${_sid#"${_base_id}-"}"

        case "$_sfx" in
            *-*)
                _sp="${_sfx%%-*}"
                _ep="${_sfx#*-}"
                [ "${#_sp}" -eq "${#_ep}" ] || continue
                ;;
            *)
                _sp="$_sfx"
                _ep="$_sfx"
                ;;
        esac

        _valid_entries="${_wiki_md}.valid.$$"
        _misplaced_entries="${_wiki_md}.misplaced.$$"
        : > "$_valid_entries"
        : > "$_misplaced_entries"

        LC_ALL=C awk \
            -v sp="$_sp" \
            -v ep="$_ep" \
            -v k="${#_sp}" \
            -v val_file="$_valid_entries" \
            -v mis_file="$_misplaced_entries" '
            function get_title(line,   m) {
                if (match(line, /^- \*\*\[[^]]+\]/)) {
                    m = substr(line, 6)
                    sub(/\].*$/, "", m)
                    return m
                } else if (match(line, /^- \*\*[^*]+\*\*/)) {
                    m = substr(line, 6)
                    sub(/\*\*.*$/, "", m)
                    return m
                }
                return ""
            }
            /^- \*\*/ {
                t = tolower(get_title($0))
                pfx = substr(t, 1, k)
                if ((sp == "a" && pfx < sp) || (pfx >= sp && pfx <= ep)) {
                    print $0 >> val_file
                } else {
                    print $0 >> mis_file
                }
            }
        ' "$_wiki_md"

        if [ -s "$_misplaced_entries" ]; then
            _mis_count="$(LC_ALL=C grep -c '^- \*\*' "$_misplaced_entries" 2>/dev/null || true)"
            _hdr_tmp="${_wiki_md}.hdr.$$"
            LC_ALL=C grep -v '^- \*\*' "$_wiki_md" > "$_hdr_tmp"
            cat "$_hdr_tmp" > "$_wiki_md"
            cat "$_valid_entries" >> "$_wiki_md"
            rm -f "$_hdr_tmp"

            if [ ! -s "$_valid_entries" ]; then
                rm -f "$_wiki_md"
                append_wiki_log_entry "lint" "deleted: \`${_base_md}\` (empty after extracting misplaced entries)"
            else
                append_wiki_log_entry "lint" "updated: \`${_base_md}\` (removed ${_mis_count} misplaced entries)"
            fi
            _fixes_count=$((_fixes_count + 1))

            while IFS= read -r _m_line <&7; do
                [ -n "$_m_line" ] || continue
                _rel_path="$(printf '%s' "$_m_line" | sed -n 's/.*(`\([^`]*\)`).*/\1/p')"
                _title="$(printf '%s' "$_m_line" | sed -n 's/^- \*\*\[\([^]]*\)\].*/\1/p')"
                [ -n "$_title" ] || _title="$(printf '%s' "$_m_line" | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p')"
                [ -n "$_title" ] || _title="untitled"

                if [ -n "$_rel_path" ]; then
                    _t_shard_id="$(derive_shard_id_for_workspace_path "$_rel_path")"
                else
                    _t_shard_id="$_base_id"
                fi

                # Auto-heal entry relative link depth if source file exists
                if [ -n "$_rel_path" ] && [ -f "${RNEX_WORKSPACE_ROOT}/${_rel_path}" ]; then
                    _expected_target="${RNEX_WIKI_UP_PREFIX}${_rel_path}"
                    _curr_target="$(printf '%s\n' "$_m_line" | sed -n 's/^- \*\*\[[^]]*\](\([^)]*\)).*/\1/p')"
                    if [ -n "$_curr_target" ] && [ "$_curr_target" != "$_expected_target" ]; then
                        _rest="${_m_line#*(\`"${_rel_path}"\`)}"
                        _m_line="- **[${_title}](${_expected_target})** (\`${_rel_path}\`)${_rest}"
                    fi
                fi

                _target_shard_file="$(resolve_target_btree_shard_file "$_t_shard_id" "$_title")"
                _target_shard_id="$(basename "$_target_shard_file" .md)"

                _t_entries="${_target_shard_file}.entries.$$"
                if [ -f "$_target_shard_file" ]; then
                    LC_ALL=C grep '^- \*\*' "$_target_shard_file" > "$_t_entries" 2>/dev/null || : > "$_t_entries"
                else
                    : > "$_t_entries"
                fi
                printf '%s\n' "$_m_line" >> "$_t_entries"
                atomic_sort_unique_file "$_t_entries"

                _t_tmp="${_target_shard_file}.tmp.$$"
                printf '# Wiki Index Shard: %s\n<!-- base: %s -->\n\n' "$_target_shard_id" "$_t_shard_id" > "$_t_tmp"
                cat "$_t_entries" >> "$_t_tmp"
                rm -f "$_t_entries"
                mv "$_t_tmp" "$_target_shard_file"
                append_wiki_log_entry "lint" "updated: \`${_target_shard_id}.md\` (re-routed misplaced entry \"${_title}\")"
            done 7< "$_misplaced_entries"
        fi
        rm -f "$_valid_entries" "$_misplaced_entries"
    done

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

    # 6e. Verify zero non-semantic numeric shards (*-[0-9]*.md) exist
    for _num_check in "${RNEX_WIKI_ROOT}"/*-[0-9]*.md; do
        [ -f "$_num_check" ] || continue
        _nc_bname="$(basename "$_num_check")"
        case "$_nc_bname" in
            index.md|log.md) continue ;;
        esac
        printf 'Lint Error [%s]: Prohibited non-semantic numeric shard found in wiki.\n' "$_nc_bname" >&2
        _errors=$((_errors + 1))
    done

    # 7. In --strict mode or on fatal errors, fail
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
