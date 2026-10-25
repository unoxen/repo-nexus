#!/bin/sh
# shellcheck shell=sh disable=SC2154
# ============================================================================
# toolkit/plugins/karpathy-llm/commands/lint.sh — Karpathy LLM Wiki Linter
#
# Syntax: rnex plugin karpathy-llm lint [--strict] [--quiet]
# ============================================================================
set -e

_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
for _kl_common in \
  "${RNEX_PLUGIN_DIR:-}/hooks/_common.sh" \
  "$(dirname "$0")/../hooks/_common.sh" \
  "$_root/.rnex/plugins/karpathy-llm/hooks/_common.sh" \
  "$_root/toolkit/plugins/karpathy-llm/hooks/_common.sh"; do
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
    -h|--help)
      cat <<'HELP_EOF'
Usage: rnex plugin karpathy-llm lint [options]

Validate Karpathy LLM Wiki graph integrity, schema conformance, and word boundaries.

Options:
  --strict    Treat warnings as errors and exit with non-zero code
  -q, --quiet Suppress informational output
  -h, --help  Show this help message
HELP_EOF
      exit 0
      ;;
    *)
      echo "Error: Unknown option '$1'. Use --help for usage." >&2
      exit 1
      ;;
  esac
  shift
done

_errors=0
_warnings=0
_pages_checked=0
_today="$(date +%Y-%m-%d 2>/dev/null || date +%F 2>/dev/null || echo "2026-10-15")"

# Check 1: Wiki directory and core control files existence
if [ ! -d "$_wiki_path" ]; then
  echo "Error: Wiki directory '$_wiki' does not exist." >&2
  exit 1
fi

for _core_file in "index.md" "hot.md" "_log.md"; do
  if [ ! -f "$_wiki_path/$_core_file" ]; then
    echo "Error: Core wiki file '$_wiki/$_core_file' is missing." >&2
    _errors=$((_errors + 1))
  fi
done

# Check 2: hot.md word boundary (~500 words)
if [ -f "$_wiki_path/hot.md" ]; then
  _hot_words="$(wc -w < "$_wiki_path/hot.md" 2>/dev/null || echo 0)"
  if [ "$_hot_words" -gt 500 ]; then
    echo "Warning: '$_wiki/hot.md' word count (${_hot_words} words) exceeds ~500-word ceiling." >&2
    _warnings=$((_warnings + 1))
  fi
fi

# Check 3: Frontmatter validation, broken sources, and orphaned pages
for _page in "$_wiki_path"/*.md; do
  [ -f "$_page" ] || continue
  _pname="$(basename "$_page")"

  # Skip log file
  [ "$_pname" = "_log.md" ] && continue

  _pages_checked=$((_pages_checked + 1))

  # Special check for index.md
  if [ "$_pname" = "index.md" ]; then
    if ! grep -E -q '^[ ]*title:[ ]*.' "$_page" 2>/dev/null; then
      echo "Error: '$_wiki/index.md' missing frontmatter 'title'." >&2
      _errors=$((_errors + 1))
    fi
    if ! grep -E -q '^[ ]*last_updated:[ ]*.' "$_page" 2>/dev/null; then
      echo "Error: '$_wiki/index.md' missing frontmatter 'last_updated'." >&2
      _errors=$((_errors + 1))
    fi
    continue
  fi

  # Skip hot.md from atomic page schema checks
  [ "$_pname" = "hot.md" ] && continue

  # Verify frontmatter delimiter (---)
  _first_line="$(head -n 1 "$_page" 2>/dev/null || true)"
  if [ "$_first_line" != "---" ]; then
    echo "Error: '$_wiki/$_pname' is missing YAML frontmatter header ('---')." >&2
    _errors=$((_errors + 1))
    continue
  fi

  _fm="$(awk 'NR==1 && /^---$/ {in_fm=1; next} in_fm && /^---$/ {exit} in_fm {print}' "$_page")"
  if [ -z "$_fm" ]; then
    echo "Error: '$_wiki/$_pname' has unclosed or empty YAML frontmatter." >&2
    _errors=$((_errors + 1))
    continue
  fi

  # Validate required keys
  for _req_key in title last_updated sources related extends; do
    if ! echo "$_fm" | grep -E -q "^[ ]*${_req_key}:" 2>/dev/null; then
      echo "Error: '$_wiki/$_pname' is missing required frontmatter key '${_req_key}'." >&2
      _errors=$((_errors + 1))
    fi
  done

  # Validate source links
  _src_links="$(awk '
    NR==1 && /^---$/ {in_fm=1; next}
    in_fm && /^---$/ {exit}
    in_fm && /^[ ]*sources:[ ]*\[/ {
      line = $0
      sub(/^[ ]*sources:[ ]*\[/, "", line)
      sub(/\].*/, "", line)
      split(line, arr, ",")
      for (i in arr) {
        gsub(/[ "\047\r\t]/, "", arr[i])
        if (length(arr[i]) > 0) print arr[i]
      }
    }
    in_fm && /^[ ]*sources:[ ]*$/ { in_src=1; next }
    in_src && /^[ ]*-[ ]*/ {
      line = $0
      sub(/^[ ]*-[ ]*/, "", line)
      gsub(/[ "\047\r\t]/, "", line)
      if (length(line) > 0) print line
      next
    }
    in_src && /^[^ ]/ { in_src=0 }
  ' "$_page")"

  if [ -n "$_src_links" ]; then
    for _sitem in $_src_links; do
      [ -n "$_sitem" ] || continue
      case "$_sitem" in
        http://*|https://*) continue ;;
      esac
      if [ ! -f "$_root/$_sitem" ] && [ ! -f "$_wiki_path/$_sitem" ]; then
        echo "Warning: '$_wiki/$_pname' references broken source file '$_sitem'." >&2
        _warnings=$((_warnings + 1))
      fi
    done
  fi

  # Check orphaned page (must be referenced in index.md)
  if [ -f "$_wiki_path/index.md" ]; then
    if ! grep -F -q "$_pname" "$_wiki_path/index.md" 2>/dev/null; then
      echo "Warning: Orphaned wiki page '$_wiki/$_pname' is not referenced in '$_wiki/index.md'." >&2
      _warnings=$((_warnings + 1))
    fi
  fi
done

# Append lint summary to _log.md
if [ -f "$_wiki_path/_log.md" ]; then
  _status_text="Passed"
  if [ "$_errors" -gt 0 ] || { [ "$_strict" -eq 1 ] && [ "$_warnings" -gt 0 ]; }; then
    _status_text="Failed"
  fi
  cat >> "$_wiki_path/_log.md" <<LOG_EOF

### Wiki Lint Run — ${_today}
* **Status:** ${_status_text} (${_errors} errors, ${_warnings} warnings).
* **Strict Mode:** $([ "$_strict" -eq 1 ] && echo "true" || echo "false")
* **Pages Checked:** ${_pages_checked}
LOG_EOF
fi

if [ "$_quiet" -eq 0 ]; then
  if [ "$_errors" -eq 0 ] && [ "$_warnings" -eq 0 ]; then
    printf '[WIKI] Wiki lint passed: %s pages verified (0 errors, 0 warnings).\n' "$_pages_checked"
  elif [ "$_errors" -eq 0 ]; then
    printf '[WIKI] Wiki lint completed with %s warning(s) across %s pages.\n' "$_warnings" "$_pages_checked"
  else
    printf '[WIKI] Wiki lint failed with %s error(s) and %s warning(s).\n' "$_errors" "$_warnings" >&2
  fi
fi

if [ "$_errors" -gt 0 ]; then
  exit 1
fi

if [ "$_strict" -eq 1 ] && [ "$_warnings" -gt 0 ]; then
  exit 1
fi

exit 0
