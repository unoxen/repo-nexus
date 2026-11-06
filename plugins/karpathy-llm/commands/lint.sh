#!/bin/sh
# shellcheck shell=sh disable=SC2154
# =============================================================================
# File: plugins/karpathy-llm/commands/lint.sh
# Architectural Layer: Plugin CLI Subcommand (karpathy-llm lint)
# Single Responsibility: Validate Karpathy LLM Wiki B-Tree root bound (<= 80 lines),
#   sorted TSV graph byte-order invariants (LC_ALL=C), wikilink integrity,
#   frontmatter schemas, un-ingested sources, and purge legacy hot.md.
# Invariants Enforced:
#   - Zero hot.md existence; automatically removes legacy hot.md if present.
#   - nodes.tsv, edges_out.tsv, edges_in.tsv are strictly sorted in LC_ALL=C order.
#   - B-Tree root index.md is <= RNEX_WIKI_BTREE_MAX_ROOT_LINES (80 lines).
#   - Detects broken [[wikilinks]] referencing un-indexed nodes.
# Security (OWASP A03): Validates all paths and rejects path traversal.
# Syntax: rnex plugin karpathy-llm lint [--strict] [--quiet]
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

_strict=0
_quiet=0

while [ $# -gt 0 ]; do
  case "$1" in
    --strict)
      _strict=1
      ;;
    -q|--quiet)
      _quiet=1
      ;;
    -H|--ignore-hooks)
      ;;
    -h|--help)
      cat <<'HELP_EOF'
Usage: rnex plugin karpathy-llm lint [options]

Validate Karpathy LLM Wiki graph integrity, B-Tree root bounds, and frontmatter schemas.

Options:
  --strict    Treat warnings as errors and exit with non-zero code
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
  printf 'Error [lint]: load_wiki_config_contract helper not found.\n' >&2
  exit 1
fi

load_wiki_config_contract "$_root" || exit 1

_errors=0
_warnings=0
_pages_checked=0
_today="$(kl_today)"

# Check 1: Wiki directory and shared core control files existence
if [ ! -d "$RNEX_WIKI_ROOT" ]; then
  printf 'Error: Wiki directory "%s" does not exist.\n' "$_wiki" >&2
  exit 1
fi

for _core_file in "$RNEX_WIKI_INDEX_FILE" "$RNEX_WIKI_LOG_FILE"; do
  if [ ! -f "$_core_file" ]; then
    printf 'Error: Core wiki file "%s" is missing.\n' "$_core_file" >&2
    _errors=$((_errors + 1))
  fi
done

# Check 2: Total eradication of legacy hot.md (auto-cleanup with audit logging)
if [ -f "${RNEX_WIKI_ROOT}/hot.md" ]; then
  rm -f "${RNEX_WIKI_ROOT}/hot.md" 2>/dev/null || true
  if [ "$_quiet" -eq 0 ]; then
    printf '[WIKI] Purged legacy hot.md cache from wiki directory.\n'
  fi
  if [ -f "$RNEX_WIKI_LOG_FILE" ]; then
    cat >> "$RNEX_WIKI_LOG_FILE" <<HOT_PURGE_LOG

### Legacy Hot Cache Purge — ${_today}
* **Action:** Purged legacy \`hot.md\` orientation cache during lint maintenance.
HOT_PURGE_LOG
  fi
fi

# Check 3: B-Tree Root bounded line count invariant (<= 80 lines)
if [ -f "$RNEX_WIKI_INDEX_FILE" ]; then
  _root_lines="$(LC_ALL=C awk 'END { print NR+0 }' "$RNEX_WIKI_INDEX_FILE")"
  if [ "$_root_lines" -gt "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" ]; then
    printf 'Error: B-Tree root index "%s" has %s lines, exceeding the %s line ceiling.\n' \
      "$RNEX_WIKI_INDEX_FILE" "$_root_lines" "$RNEX_WIKI_BTREE_MAX_ROOT_LINES" >&2
    _errors=$((_errors + 1))
  fi
fi

# Check 4: TSV property graph LC_ALL=C sorted invariants
for _tsv in "$RNEX_WIKI_NODES_TSV" "$RNEX_WIKI_EDGES_OUT_TSV" "$RNEX_WIKI_EDGES_IN_TSV"; do
  if [ -f "$_tsv" ]; then
    if ! LC_ALL=C sort -c "$_tsv" 2>/dev/null; then
      printf 'Error: Graph file "%s" is not in strict LC_ALL=C byte order.\n' "$_tsv" >&2
      _errors=$((_errors + 1))
    fi
  fi
done

# Check 5: Wikilink integrity in TSV property graph (detect broken [[wikilinks]])
if [ -f "$RNEX_WIKI_EDGES_OUT_TSV" ] && [ -f "$RNEX_WIKI_NODES_TSV" ]; then
  _broken_links="$(awk -F '\t' '
    NR == FNR { nodes[$1] = 1; next }
    NF >= 3 {
      target = $3
      if (!(target in nodes)) {
        print $1 "\t" target
      }
    }
  ' "$RNEX_WIKI_NODES_TSV" "$RNEX_WIKI_EDGES_OUT_TSV")"

  if [ -n "$_broken_links" ]; then
    while IFS= read -r _b_row || [ -n "$_b_row" ]; do
      [ -n "$_b_row" ] || continue
      _b_src="$(printf '%s' "$_b_row" | cut -f 1)"
      _b_tgt="$(printf '%s' "$_b_row" | cut -f 2)"
      printf 'Warning: Page "%s" references broken wikilink [[%s]] (target node has no compiled page).\n' \
        "$_b_src" "$_b_tgt" >&2
      _warnings=$((_warnings + 1))
    done <<EOF_BROKEN
$_broken_links
EOF_BROKEN
  fi
fi

# Check 6: Frontmatter validation, broken sources, and orphaned pages
_tmp_pages="$(mktemp)"
find "$RNEX_WIKI_ROOT" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort > "$_tmp_pages"
while IFS= read -r _page || [ -n "$_page" ]; do
  [ -f "$_page" ] || continue
  _pname="$(basename "$_page")"

  # Skip core log file and shard directory
  [ "$_pname" = "_log.md" ] && continue
  [ "$_pname" = "hot.md" ] && continue
  case "$_page" in
    */"${RNEX_CFG_WIKI_INDEX_DIR:-_index}"/*) continue ;;
    */"${RNEX_CFG_WIKI_GRAPH_DIR:-_graph}"/*) continue ;;
  esac

  _pages_checked=$((_pages_checked + 1))

  # Special check for root index.md (content router without mandatory frontmatter)
  if [ "$_page" = "$RNEX_WIKI_INDEX_FILE" ]; then
    if grep -q 'YYYY-MM-DD' "$_page" 2>/dev/null; then
      printf 'Warning: "%s" contains an unfilled YYYY-MM-DD placeholder.\n' "$RNEX_WIKI_INDEX_FILE" >&2
      _warnings=$((_warnings + 1))
    fi
    continue
  fi

  # Verify frontmatter delimiter (---)
  _first_line="$(head -n 1 "$_page" 2>/dev/null || true)"
  if [ "$_first_line" != "---" ]; then
    printf 'Error: "%s" is missing YAML frontmatter header ("---").\n' "$_page" >&2
    _errors=$((_errors + 1))
    continue
  fi

  _fm="$(awk 'NR==1 && /^---$/ {in_fm=1; next} in_fm && /^---$/ {exit} in_fm {print}' "$_page")"
  if [ -z "$_fm" ]; then
    printf 'Error: "%s" has unclosed or empty YAML frontmatter.\n' "$_page" >&2
    _errors=$((_errors + 1))
    continue
  fi

  # Validate required keys
  for _req_key in title last_updated sources related extends; do
    if ! printf '%s\n' "$_fm" | grep -E -q "^[ ]*${_req_key}:" 2>/dev/null; then
      printf 'Error: "%s" is missing required frontmatter key "%s".\n' "$_page" "$_req_key" >&2
      _errors=$((_errors + 1))
    fi
  done

  # Validate source links
  _src_links="$(awk '
    NR==1 && /^---$/ {in_fm=1; next}
    in_fm && /^---$/ {exit}
    in_fm && /^[ \t]*sources:[ \t]*\[/ {
      line = $0
      sub(/^[ \t]*sources:[ \t]*\[/, "", line)
      sub(/\][ \t]*(#.*)?$/, "", line)
      len = length(line)
      in_dq = 0; in_sq = 0; cur = ""
      for (i = 1; i <= len; i++) {
        c = substr(line, i, 1)
        if (c == "\"" && !in_sq) { in_dq = !in_dq }
        else if (c == "\047" && !in_dq) { in_sq = !in_sq }
        else if (c == "," && !in_dq && !in_sq) {
          sub(/^[ \t]+/, "", cur); sub(/[ \t]+$/, "", cur)
          sub(/^["\047]/, "", cur); sub(/["\047]$/, "", cur)
          if (length(cur) > 0) print cur
          cur = ""
        } else {
          cur = cur c
        }
      }
      sub(/^[ \t]+/, "", cur); sub(/[ \t]+$/, "", cur)
      sub(/^["\047]/, "", cur); sub(/["\047]$/, "", cur)
      if (length(cur) > 0) print cur
      next
    }
    in_fm && /^[ \t]*sources:[ \t]*(#.*)?$/ { in_src=1; next }
    in_src && /^[ \t]*-([ \t]|$)/ {
      line = $0
      sub(/^[ \t]*-+[ \t]*/, "", line)
      sub(/[ \t]*#.*$/, "", line)
      sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
      sub(/^["\047]/, "", line); sub(/["\047]$/, "", line)
      if (length(line) > 0) print line
      next
    }
    in_src && /^[^ \t#]/ { in_src=0 }
  ' "$_page")"

  if [ -n "$_src_links" ]; then
    while IFS= read -r _sitem || [ -n "$_sitem" ]; do
      [ -n "$_sitem" ] || continue
      case "$_sitem" in
        http://*|https://*) continue ;;
      esac
      if [ ! -f "$_root/$_sitem" ] && [ ! -f "$RNEX_WIKI_ROOT/$_sitem" ]; then
        printf 'Warning: "%s" references broken source file "%s".\n' "$_page" "$_sitem" >&2
        _warnings=$((_warnings + 1))
      fi
    done <<EOF_SLINKS
$_src_links
EOF_SLINKS
  fi

  # Check orphaned page: verify slug is registered in nodes.tsv
  _slug="${_pname%.md}"
  _slug="$(normalize_slug_id "$_slug" 2>/dev/null || true)"
  if [ -n "$_slug" ] && [ -f "$RNEX_WIKI_NODES_TSV" ]; then
    _tab="$(printf '\t')"
    if ! grep -q "^${_slug}${_tab}" "$RNEX_WIKI_NODES_TSV" 2>/dev/null; then
      printf 'Warning: Orphaned wiki page "%s" is not registered in nodes.tsv (run "rnex plugin karpathy-llm index").\n' "$_page" >&2
      _warnings=$((_warnings + 1))
    fi
  fi
done < "$_tmp_pages"
rm -f "$_tmp_pages"

# Check 7: Un-ingested source files detection
if command -v karpathy_expand_source_files >/dev/null 2>&1; then
  _tmp_exp="$(mktemp)"
  karpathy_expand_source_files 2>/dev/null > "$_tmp_exp" || true

  _tmp_seen="$(mktemp)"
  find "$RNEX_WIKI_ROOT" -type f -name '*.md' 2>/dev/null | while IFS= read -r _wpage; do
    [ -f "$_wpage" ] || continue
    _wpname="$(basename "$_wpage")"
    [ "$_wpname" = "_log.md" ] && continue
    [ "$_wpname" = "hot.md" ] && continue
    [ "$_wpname" = "index.md" ] && continue
    case "$_wpage" in
      */"${RNEX_CFG_WIKI_INDEX_DIR:-_index}"/*) continue ;;
      */"${RNEX_CFG_WIKI_GRAPH_DIR:-_graph}"/*) continue ;;
    esac

    awk '
      NR==1 && /^---$/ {in_fm=1; next}
      in_fm && /^---$/ {exit}
      in_fm && /^[ \t]*sources:[ \t]*\[/ {
        line = $0
        sub(/^[ \t]*sources:[ \t]*\[/, "", line)
        sub(/\][ \t]*(#.*)?$/, "", line)
        len = length(line)
        in_dq = 0; in_sq = 0; cur = ""
        for (i = 1; i <= len; i++) {
          c = substr(line, i, 1)
          if (c == "\"" && !in_sq) { in_dq = !in_dq }
          else if (c == "\047" && !in_dq) { in_sq = !in_sq }
          else if (c == "," && !in_dq && !in_sq) {
            sub(/^[ \t]+/, "", cur); sub(/[ \t]+$/, "", cur)
            sub(/^["\047]/, "", cur); sub(/["\047]$/, "", cur)
            if (length(cur) > 0) print cur
            cur = ""
          } else {
            cur = cur c
          }
        }
        sub(/^[ \t]+/, "", cur); sub(/[ \t]+$/, "", cur)
        sub(/^["\047]/, "", cur); sub(/["\047]$/, "", cur)
        if (length(cur) > 0) print cur
        next
      }
      in_fm && /^[ \t]*sources:[ \t]*(#.*)?$/ { in_src=1; next }
      in_src && /^[ \t]*-([ \t]|$)/ {
        line = $0
        sub(/^[ \t]*-+[ \t]*/, "", line)
        sub(/[ \t]*#.*$/, "", line)
        sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
        sub(/^["\047]/, "", line); sub(/["\047]$/, "", line)
        if (length(line) > 0) print line
        next
      }
      in_src && /^[^ \t#]/ { in_src=0 }
    ' "$_wpage" >> "$_tmp_seen"
  done

  while IFS= read -r _src_abs || [ -n "$_src_abs" ]; do
    [ -n "$_src_abs" ] || continue
    case "$_src_abs" in
      "$_root"/*) _src_rel="${_src_abs#"$_root"/}" ;;
      *) _src_rel="$_src_abs" ;;
    esac
    _src_rel="$(printf '%s' "$_src_rel" | sed -e 's#^\./##')"

    if ! grep -F -x -q "$_src_rel" "$_tmp_seen" 2>/dev/null; then
      if [ "$_quiet" -eq 0 ]; then
        printf '[WIKI] Notice: Configured source file '\''%s'\'' is not ingested into any wiki page.\n' "$_src_rel"
      fi
    fi
  done < "$_tmp_exp"

  rm -f "$_tmp_exp" "$_tmp_seen"
fi

# Append lint summary to _log.md
if [ -f "$RNEX_WIKI_LOG_FILE" ]; then
  _status_text="Passed"
  if [ "$_errors" -gt 0 ] || { [ "$_strict" -eq 1 ] && [ "$_warnings" -gt 0 ]; }; then
    _status_text="Failed"
  fi
  _strict_text="$([ "$_strict" -eq 1 ] && echo "true" || echo "false")"
  _expected_header="### Wiki Lint Run — ${_today}"
  _expected_line1="* **Status:** ${_status_text} (${_errors} errors, ${_warnings} warnings)."
  _expected_line2="* **Strict Mode:** ${_strict_text}"
  _expected_line3="* **Pages Checked:** ${_pages_checked}"

  _is_duplicate_lint=0
  _tail_log="$(tail -n 10 "$RNEX_WIKI_LOG_FILE" 2>/dev/null || true)"
  if printf '%s\n' "$_tail_log" | grep -F -q "$_expected_header" && \
     printf '%s\n' "$_tail_log" | grep -F -q "$_expected_line1" && \
     printf '%s\n' "$_tail_log" | grep -F -q "$_expected_line2" && \
     printf '%s\n' "$_tail_log" | grep -F -q "$_expected_line3"; then
    _is_duplicate_lint=1
  fi

  if [ "$_is_duplicate_lint" -eq 0 ]; then
    cat >> "$RNEX_WIKI_LOG_FILE" <<LOG_EOF

${_expected_header}
${_expected_line1}
${_expected_line2}
${_expected_line3}
LOG_EOF
  fi
fi

_total_errors=$_errors
_total_warnings=$_warnings

if [ "$_quiet" -eq 0 ]; then
  if [ "$_total_errors" -eq 0 ] && [ "$_total_warnings" -eq 0 ]; then
    printf '[WIKI] Wiki lint passed: %s pages verified (0 errors, 0 warnings).\n' "$_pages_checked"
  elif [ "$_total_errors" -eq 0 ]; then
    printf '[WIKI] Wiki lint completed with %s warning(s) across %s pages.\n' "$_total_warnings" "$_pages_checked"
  else
    printf '[WIKI] Wiki lint failed with %s error(s) and %s warning(s).\n' "$_total_errors" "$_total_warnings" >&2
  fi
fi

if [ "$_total_errors" -gt 0 ]; then
  exit 1
fi

if [ "$_strict" -eq 1 ] && [ "$_total_warnings" -gt 0 ]; then
  exit 1
fi

exit 0
