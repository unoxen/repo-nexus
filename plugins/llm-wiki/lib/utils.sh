#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2016
# =============================================================================
# File: plugins/llm-wiki/lib/utils.sh
# Architectural Layer: Pure General Utilities (utils/ — Zero Domain Dependencies)
# Single Responsibility: Provide stateless, deterministic, dependency-free
# string, slug, path normalization, globstar matching, relative link prefix
# calculation, markdown sanitization, catalog entry parsing, shared AWK
# functions, ISO-8601 UTC date retrieval, and atomic file sorting.
#
# Design Patterns & Principles:
#   - Single Responsibility Principle (SRP): Each utility function addresses
#     one atomic data transformation or string manipulation task.
#   - Don't Repeat Yourself (DRY): Exports RNEX_WIKI_AWK_LIB containing shared
#     AWK functions reused across B-Tree routing, shard splitting, and linting.
#   - Functional Purity: All utilities are strictly pure and side-effect free,
#     except for get_iso_utc_date (reads system clock) and atomic_sort_unique_file
#     (atomic filesystem sort operation).
#   - Zero Domain Dependencies: Operates in complete isolation without reading
#     global configuration files or mutating workspace state.
#
# Standards: Pure POSIX Shell (/bin/sh), OWASP ASVS A03 Input Sanitization.
# =============================================================================

# Guard against redundant multiple inclusion in subshells or helper chains
if [ "${RNEX_LLM_WIKI_UTILS_SH_SOURCED:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
RNEX_LLM_WIKI_UTILS_SH_SOURCED=1

# -----------------------------------------------------------------------------
# Shared AWK Library Contract (RNEX_WIKI_AWK_LIB)
# Summary: Reusable POSIX AWK function definitions for B-Tree key normalization,
#          catalog entry title/path extraction, slug normalization, and base
#          shard derivation. Injected into AWK invocations to prevent duplication.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2089
RNEX_WIKI_AWK_LIB='
function clean_alpha_key(str,   res, i, c, d) {
    res = ""
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c >= "a" && c <= "z") {
            res = res c
        } else if (c >= "A" && c <= "Z") {
            res = res tolower(c)
        } else if (c >= "0" && c <= "9") {
            d = c + 0
            if (d == 0) res = res "zero"
            else if (d == 1) res = res "one"
            else if (d == 2) res = res "two"
            else if (d == 3) res = res "three"
            else if (d == 4) res = res "four"
            else if (d == 5) res = res "five"
            else if (d == 6) res = res "six"
            else if (d == 7) res = res "seven"
            else if (d == 8) res = res "eight"
            else if (d == 9) res = res "nine"
        }
    }
    return res
}
function get_title(line,   m) {
    if (match(line, /^- \*\*\[[^]]+\]/)) {
        m = substr(line, 6)
        sub(/\].*$/, "", m)
        return m
    } else if (match(line, /^- \*\*[^*]+\*\*/)) {
        m = substr(line, 5)
        sub(/\*\*.*$/, "", m)
        return m
    }
    return ""
}
function get_rel_path(line,   m) {
    if (match(line, /\*\* \(`[^`]+`\)/)) {
        m = substr(line, RSTART + 5, RLENGTH - 7)
        return m
    } else if (match(line, /\(`[^`]+`\)/)) {
        m = substr(line, RSTART + 2, RLENGTH - 4)
        return m
    }
    return ""
}
function get_path(line,   m) {
    m = get_rel_path(line)
    if (m != "") return m
    if (match(line, /\]\([^)]+\)/)) {
        m = substr(line, RSTART + 2, RLENGTH - 3)
        return m
    }
    return ""
}
function normalize_slug(s,   r) {
    r = tolower(s)
    gsub(/[^a-z0-9._-]+/, "-", r)
    gsub(/--+/, "-", r)
    gsub(/^-+|-+$/, "", r)
    return (r != "") ? r : "unknown"
}
function expected_base_shard(rel_path, rdir,   rest, n, parts) {
    if (rel_path == "") return ""
    sub(/\/$/, "", rdir)
    if (index(rel_path, rdir "/") == 1) {
        rest = substr(rel_path, length(rdir) + 2)
        n = split(rest, parts, "/")
        if (n >= 3) {
            return "repos-" normalize_slug(parts[1]) "-" normalize_slug(parts[2])
        } else {
            return "repos-" normalize_slug(parts[1])
        }
    } else if (index(rel_path, "/") > 0) {
        n = split(rel_path, parts, "/")
        return "repo-nexus-" normalize_slug(parts[1])
    } else {
        return "repo-nexus"
    }
}
function is_utf8_cont(b) {
    return (b >= "\200" && b <= "\277")
}
function sanitize_utf8(str,   out, i, n, b1, b2, b3, b4) {
    out = ""
    n = length(str)
    i = 1
    while (i <= n) {
        b1 = substr(str, i, 1)
        if (b1 < "\200") {
            out = out b1
            i++
        } else if (b1 >= "\302" && b1 <= "\337" && (i + 1) <= n) {
            b2 = substr(str, i + 1, 1)
            if (is_utf8_cont(b2)) {
                out = out b1 b2
                i += 2
            } else {
                i++
            }
        } else if (b1 >= "\340" && b1 <= "\357" && (i + 2) <= n) {
            b2 = substr(str, i + 1, 1)
            b3 = substr(str, i + 2, 1)
            if (is_utf8_cont(b2) && is_utf8_cont(b3)) {
                out = out b1 b2 b3
                i += 3
            } else {
                i++
            }
        } else if (b1 >= "\360" && b1 <= "\364" && (i + 3) <= n) {
            b2 = substr(str, i + 1, 1)
            b3 = substr(str, i + 2, 1)
            b4 = substr(str, i + 3, 1)
            if (is_utf8_cont(b2) && is_utf8_cont(b3) && is_utf8_cont(b4)) {
                out = out b1 b2 b3 b4
                i += 4
            } else {
                i++
            }
        } else {
            i++
        }
    }
    return out
}
'
# shellcheck disable=SC2090
export RNEX_WIKI_AWK_LIB

# -----------------------------------------------------------------------------
# get_iso_utc_date
# Summary: Returns the current UTC date formatted strictly in ISO-8601
#          representation (YYYY-MM-DD).
# @returns: 10-character ISO-8601 date string on stdout.
# @pure (Deterministic with respect to system clock at invocation time)
# -----------------------------------------------------------------------------
get_iso_utc_date() {
    date -u +"%Y-%m-%d"
}

# -----------------------------------------------------------------------------
# normalize_slug_id
# Summary: Converts an arbitrary string or file stem into a canonical lowercase
#          alphanumeric slug (a-z, 0-9, period, underscore, hyphen) suitable for
#          deterministic B-Tree shard file names or entry keys.
# @param $1: raw_identifier - Input title, filename, or token string.
# @returns: Canonical slug on stdout; returns 1 if resulting slug is empty.
# @pure
# -----------------------------------------------------------------------------
normalize_slug_id() {
    _slug="$(printf '%s' "$1" \
        | LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
    if [ -z "$_slug" ]; then
        return 1
    fi
    printf '%s\n' "$_slug"
    return 0
}

# -----------------------------------------------------------------------------
# normalize_workspace_rel_path
# Summary: Normalizes an absolute or relative path to a safe, canonical
#          workspace-relative file path by stripping leading "./", redundant
#          slashes, and Windows CR characters.
#          Rejects path traversal ("..") and absolute paths outside the root.
# @param $1: workspace_root - Absolute workspace root path.
# @param $2: target_path    - Absolute or workspace-relative file path.
# @returns: Clean workspace-relative path on stdout, or 1 if outside root or invalid.
# @throws: Returns 1 on invalid path traversal or out-of-boundary access (OWASP A03).
# @pure
# -----------------------------------------------------------------------------
normalize_workspace_rel_path() {
    _ws_root="${1%/}"
    _raw_path="$(printf '%s' "$2" | LC_ALL=C tr -d '\r')"

    case "$_raw_path" in
        "${_ws_root}/"*)
            _rel="${_raw_path#"${_ws_root}/"}"
            ;;
        /*)
            # Absolute path outside workspace root is rejected (OWASP A03)
            return 1
            ;;
        *)
            _rel="$_raw_path"
            ;;
    esac

    # Strip leading "./", collapse redundant slashes, and strip trailing slash
    _rel="$(printf '%s' "$_rel" | LC_ALL=C sed 's#^\./##; s#///*#/#g; s#/$##')"
    case "$_rel" in
        ''|*..*|/*)
            return 1
            ;;
    esac
    printf '%s\n' "$_rel"
    return 0
}

# -----------------------------------------------------------------------------
# match_globstar_path
# Summary: Evaluates whether a workspace-relative candidate path matches a
#          POSIX glob or recursive globstar (**) pattern (including leading
#          "**/...", trailing ".../**", and multi-globstar ".../**/.../**").
# @param $1: candidate_path - Workspace-relative file path.
# @param $2: target_pattern - Glob or globstar pattern (e.g., "repos/**/README.md").
# @param $3: workspace_root - Optional workspace root prefix to strip.
# @returns: 0 if the candidate path matches the pattern; 1 otherwise.
# @pure
# -----------------------------------------------------------------------------
match_globstar_path() {
    _candidate_path="$1"
    _target_pat="$2"
    _ws_prefix="${3:-}"

    case "$_candidate_path" in
        *[\"\'\	\ ]*)
            _candidate_path="$(printf '%s' "$_candidate_path" | LC_ALL=C tr -d '"'\''' | LC_ALL=C sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            ;;
    esac
    case "$_target_pat" in
        *[\"\'\	\ ]*)
            _target_pat="$(printf '%s' "$_target_pat" | LC_ALL=C tr -d '"'\''' | LC_ALL=C sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            ;;
    esac

    while [ "${_candidate_path#./}" != "$_candidate_path" ]; do _candidate_path="${_candidate_path#./}"; done
    while [ "${_target_pat#./}" != "$_target_pat" ]; do _target_pat="${_target_pat#./}"; done
    _target_pat="${_target_pat%/}"

    if [ -n "$_ws_prefix" ]; then
        _candidate_path="${_candidate_path#"${_ws_prefix%/}/"}"
    fi

    if [ "$_candidate_path" = "$_target_pat" ] || [ "$_target_pat" = "**" ]; then
        return 0
    fi

    case "$_target_pat" in
        *\*\**\*\**)
            # Multi-globstar pattern (e.g., "**/.vitepress/**" or "repos/**/dist/**")
            _p1="${_target_pat%%\*\**}"
            _rest="${_target_pat#*\*\*}"
            _mid="${_rest%%\*\**}"
            _p2="${_rest##*\*\*}"
            _p1="${_p1#/}"
            _p2="${_p2#/}"
            _Virtual="/${_candidate_path}"
            # shellcheck disable=SC2254
            case "$_Virtual" in
                "/${_p1}"*${_mid}*${_p2})
                    if [ -n "$_p2" ]; then
                        _exp_fn="${_p2##*/}"
                        _act_fn="${_candidate_path##*/}"
                        if [ -n "$_exp_fn" ] && [ "$_exp_fn" != "*" ]; then
                            case "$_act_fn" in
                                $_exp_fn) return 0 ;;
                                *) return 1 ;;
                            esac
                        fi
                    fi
                    return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        *\*\**)
            _prefix="${_target_pat%%\*\**}"
            _suffix="${_target_pat##*\*\*}"
            _suffix="${_suffix#/}"

            if [ -z "$_suffix" ]; then
                # Trailing globstar (e.g., "docs/**" or "docs/.vitepress/**")
                # shellcheck disable=SC2254
                case "$_candidate_path" in
                    $_prefix*) return 0 ;;
                    *) return 1 ;;
                esac
            fi

            # shellcheck disable=SC2254
            case "$_candidate_path" in
                "$_prefix"*$_suffix)
                    _expected_filename="${_suffix##*/}"
                    _actual_filename="${_candidate_path##*/}"
                    if [ -n "$_expected_filename" ] && [ "$_expected_filename" != "*" ]; then
                        case "$_actual_filename" in
                            $_expected_filename) return 0 ;;
                            *) return 1 ;;
                        esac
                    fi
                    return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        *)
            # shellcheck disable=SC2254
            case "$_candidate_path" in
                $_target_pat) return 0 ;;
                *) return 1 ;;
            esac
            ;;
    esac
}

# -----------------------------------------------------------------------------
# compute_upward_rel_prefix
# Summary: Computes the upward relative traversal prefix ("../") needed to reach
#          the workspace root from a given workspace-relative directory
#          (e.g., ".rnex/wiki" -> "../../", "wiki" -> "../", "docs/wiki" -> "../../").
# @param $1: wiki_rel_dir - Clean workspace-relative directory path.
# @returns: Upward relative path prefix ending with "/" on stdout.
# @pure
# -----------------------------------------------------------------------------
compute_upward_rel_prefix() {
    _clean_dir="$(printf '%s' "$1" | LC_ALL=C sed 's#^\./##; s#/$##')"
    if [ -z "$_clean_dir" ] || [ "$_clean_dir" = "." ]; then
        return 0
    fi
    printf '%s' "$_clean_dir" | LC_ALL=C awk -F'/' '{
        prefix = ""
        for (i = 1; i <= NF; i++) {
            if ($i != "" && $i != ".") {
                prefix = prefix "../"
            }
        }
        print prefix
    }'
}

# -----------------------------------------------------------------------------
# extract_entry_rel_path
# Summary: Extracts the backtick-enclosed workspace-relative source path from a
#          formatted B-Tree shard catalog entry line.
# @param $1: entry_line - Catalog entry line (`- **[Title](link)** (\`path\`) — ...`).
# @returns: Workspace-relative path string on stdout.
# @pure
# -----------------------------------------------------------------------------
extract_entry_rel_path() {
    printf '%s\n' "$1" | LC_ALL=C awk 'match($0, /\*\* \(`[^`]+`\)/) { print substr($0, RSTART + 5, RLENGTH - 7) }'
}

# -----------------------------------------------------------------------------
# extract_entry_title
# Summary: Extracts the document title from a formatted B-Tree shard catalog
#          entry line, falling back to "untitled" if absent.
# @param $1: entry_line - Catalog entry line (`- **[Title](link)** (\`path\`) — ...`).
# @returns: Extracted title string on stdout.
# @pure
# -----------------------------------------------------------------------------
extract_entry_title() {
    _t="$(printf '%s\n' "$1" | LC_ALL=C sed -n 's/^- \*\*\[\([^]]*\)\].*/\1/p')"
    [ -n "$_t" ] || _t="$(printf '%s\n' "$1" | LC_ALL=C sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p')"
    [ -n "$_t" ] || _t="untitled"
    printf '%s\n' "$_t"
}

# -----------------------------------------------------------------------------
# strip_markdown_links
# Summary: Strips Markdown link syntax ([text](target)), image syntax
#          (![alt](target)), and wikilink syntax ([[target|text]] / [[target]])
#          from input text, retaining inner anchor, alt, or label text.
#          Leaves non-link bracketed text untouched.
# @param $1: raw_text - Input string containing Markdown links or text.
# @returns: Plain text with links stripped on stdout.
# @pure
# -----------------------------------------------------------------------------
strip_markdown_links() {
    _raw_str="$1"
    [ -n "$_raw_str" ] || return 0
    printf '%s\n' "$_raw_str" | LC_ALL=C awk '
        function strip_links(str,   out, rem, p, p2, p3, text, is_img, p_close) {
            # First strip markdown image tags ![alt](target) to alt text so nested badges [![alt](img)](url) become [alt](url)
            while (match(str, /!\[[^][]+\]\([^()]+\)/)) {
                text = substr(str, RSTART + 2, RLENGTH - 2)
                sub(/\]\([^()]*\)$/, "", text)
                str = substr(str, 1, RSTART - 1) text substr(str, RSTART + RLENGTH)
            }
            out = ""
            rem = str
            while (rem != "") {
                p = index(rem, "[")
                if (p == 0) {
                    out = out rem
                    break
                }
                is_img = 0
                if (p > 1 && substr(rem, p - 1, 1) == "!") {
                    out = out substr(rem, 1, p - 2)
                    is_img = 1
                } else {
                    out = out substr(rem, 1, p - 1)
                }
                rem = substr(rem, p)

                # Check for wikilink format [[target|label]] or [[target]]
                if (substr(rem, 1, 2) == "[[") {
                    p2 = index(rem, "]]")
                    if (p2 > 0) {
                        text = substr(rem, 3, p2 - 3)
                        p3 = index(text, "|")
                        if (p3 > 0) {
                            text = substr(text, p3 + 1)
                        }
                        out = out text
                        rem = substr(rem, p2 + 2)
                        continue
                    }
                }

                # Check for standard markdown link [text](target) where first ] is immediately followed by (
                p_close = index(substr(rem, 2), "]")
                if (p_close > 0 && substr(rem, 1 + p_close, 2) == "](") {
                    text = substr(rem, 2, p_close - 1)
                    if (index(text, "[") == 0) {
                        p3 = index(substr(rem, 1 + p_close + 2), ")")
                        if (p3 > 0) {
                            out = out text
                            rem = substr(rem, 1 + p_close + 2 + p3)
                            continue
                        }
                    }
                }

                # Standalone bracket not forming a valid link; preserve verbatim
                if (is_img) {
                    out = out "!["
                } else {
                    out = out "["
                }
                rem = substr(rem, 2)
            }
            return out
        }
        {
            print strip_links($0)
        }
    '
}

# -----------------------------------------------------------------------------
# normalize_relative_path
# Summary: Normalizes a relative path target against a base directory into
#          a clean workspace-relative path without filesystem operations.
#          Resolves "." and ".." segments and rejects path traversal above root.
# @param $1: base_dir    - Base directory relative to workspace root (e.g., "docs").
# @param $2: target_path - Target path (e.g., "../api/index.md", "./setup.md").
# @returns: Clean workspace-relative path on stdout, or returns 1 on traversal error.
# @pure
# -----------------------------------------------------------------------------
normalize_relative_path() {
    _base_dir="$1"
    _target_path="$2"
    _res="$(LC_ALL=C awk -v base_dir="$_base_dir" -v target="$_target_path" '
        BEGIN {
            if (substr(target, 1, 1) == "/") {
                combined = substr(target, 2)
            } else if (base_dir != "" && base_dir != ".") {
                combined = base_dir "/" target
            } else {
                combined = target
            }
            gsub(/\/+/, "/", combined)
            sub(/^\//, "", combined)
            sub(/\/$/, "", combined)

            n = split(combined, parts, "/")
            top = 0
            for (i = 1; i <= n; i++) {
                seg = parts[i]
                if (seg == "" || seg == ".") {
                    continue
                } else if (seg == "..") {
                    if (top > 0) {
                        top--
                    } else {
                        exit 1
                    }
                } else {
                    stack[++top] = seg
                }
            }
            res = ""
            for (i = 1; i <= top; i++) {
                res = (i == 1) ? stack[i] : res "/" stack[i]
            }
            print res
        }
    ' 2>/dev/null)" || return 1
    [ -n "$_res" ] || return 1
    printf '%s\n' "$_res"
    return 0
}

# -----------------------------------------------------------------------------
# sanitize_markdown_summary
# Summary: Sanitizes a single-line summary string by stripping control chars,
#          tabs, pipes, and newlines that could corrupt Markdown table or list
#          formatting. Collapses consecutive whitespace and truncates to the
#          configured maximum character length (default: 100) without slicing
#          through unclosed Markdown links or brackets.
# @param $1: raw_text - Input summary string.
# @param $2: max_len  - Optional maximum character length (positive integer, default: 100).
# @returns: Sanitized summary truncated to at most max_len characters on stdout.
# @pure
# -----------------------------------------------------------------------------
sanitize_markdown_summary() {
    [ -n "$1" ] || return 0
    _sms_max="${2:-100}"
    case "$_sms_max" in
        ''|*[!0-9]*|0) _sms_max=100 ;;
    esac
    printf '%s\n' "$1" \
        | LC_ALL=C tr '\t\r\n|' '    ' \
        | LC_ALL=C sed 's/  */ /g; s/^ //; s/ $//' \
        | LC_ALL=C awk -v max_len="$_sms_max" "
            ${RNEX_WIKI_AWK_LIB}
            function safe_truncate(s, m_len,   sub_s, i, ch, p, p_bra, p_open, anchor, pfx_end) {
                s = sanitize_utf8(s)
                if (length(s) <= m_len) return s
                sub_s = sanitize_utf8(substr(s, 1, m_len))
                p = 0
                for (i = length(sub_s); i >= 1; i--) {
                    ch = substr(sub_s, i, 1)
                    if (ch == \"]\") break
                    if (ch == \"[\") { p = i; break }
                }
                if (p > 0) {
                    if (p > 1 && substr(sub_s, p - 1, 1) == \"[\") p--
                    if (p > 1 && substr(sub_s, p - 1, 1) == \"!\") p--
                    if (p > 1) {
                        sub_s = substr(sub_s, 1, p - 1)
                    } else {
                        sub(/^!?\[\[?/, \"\", sub_s)
                    }
                } else {
                    p_bra = 0
                    for (i = length(sub_s); i >= 1; i--) {
                        if (substr(sub_s, i, 1) == \")\") break
                        if (substr(sub_s, i, 2) == \"](\") { p_bra = i; break }
                    }
                    if (p_bra > 0) {
                        p_open = 0
                        for (i = p_bra; i >= 1; i--) {
                            if (substr(sub_s, i, 1) == \"[\") { p_open = i; break }
                        }
                        if (p_open > 0) {
                            anchor = substr(sub_s, p_open + 1, p_bra - p_open - 1)
                            pfx_end = p_open - 1
                            if (pfx_end >= 1 && substr(sub_s, pfx_end, 1) == \"!\") pfx_end--
                            if (pfx_end >= 1) {
                                sub_s = substr(sub_s, 1, pfx_end)
                            } else {
                                sub_s = anchor
                            }
                        }
                    }
                }
                sub(/[[:space:]]+\$/, \"\", sub_s)
                return sub_s
            }
            {
                print safe_truncate(\$0, max_len + 0)
            }
        "
}

# -----------------------------------------------------------------------------
# sanitize_single_line_text
# Summary: Strips tabs, carriage returns, and newlines from a string and collapses
#          consecutive whitespace into a single space, trimming leading/trailing edges.
# @param $1: raw_text - Unsanitized input text.
# @returns: Single-line, whitespace-collapsed string on stdout.
# @pure
# -----------------------------------------------------------------------------
sanitize_single_line_text() {
    printf '%s' "$1" | LC_ALL=C tr '\t\r\n' '   ' | LC_ALL=C sed 's/  */ /g; s/^ //; s/ $//'
}

# -----------------------------------------------------------------------------
# atomic_sort_unique_file
# Summary: Sorts a file in-place using strict byte-order collation (LC_ALL=C)
#          and eliminates duplicate lines atomically via a temporary file.
# @param $1: target_file - File path to sort in place.
# @returns: 0 on success; 1 on failure.
# @sideEffects: Replaces $1 atomically with sorted unique lines.
# -----------------------------------------------------------------------------
atomic_sort_unique_file() {
    _target="$1"
    [ -f "$_target" ] || return 1
    _tmp="${_target}.tmp.$$"
    if LC_ALL=C sort -u "$_target" > "$_tmp"; then
        mv "$_tmp" "$_target"
        return 0
    fi
    rm -f "$_tmp"
    return 1
}
