#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# plugins/karpathy-llm/hooks/_common.sh — Shared Karpathy Wiki Hook Bootstrap
# ============================================================================

_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
NEXUS_DIR="$_root"
RNEX_ROOT="$_root"
WORKSPACE_YAML="${WORKSPACE_YAML:-$_root/rnex.yaml}"
WORKSPACE_LOCAL_YAML="${WORKSPACE_LOCAL_YAML:-$_root/.local.rnex.yaml}"
export NEXUS_DIR RNEX_ROOT WORKSPACE_YAML WORKSPACE_LOCAL_YAML

if ! command -v yaml_plugin_get >/dev/null 2>&1 || ! command -v plugin_primary_source_dir >/dev/null 2>&1; then
  _kl_hook_dir="$(dirname "${_kl_common:-$0}")"
  for _kl_lib in \
    "${RNEX_LIB_DIR:-}" \
    "$_kl_hook_dir/../../../../lib" \
    "$_kl_hook_dir/../../../lib" \
    "$_root/lib"; do
    if [ -n "$_kl_lib" ] && [ -f "$_kl_lib/yaml.sh" ]; then
      RNEX_LIB_DIR="$(cd "$_kl_lib" 2>/dev/null && pwd -P)"
      export RNEX_LIB_DIR
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/core.sh" 2>/dev/null || true
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/yaml.sh" 2>/dev/null || true
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/plugins.sh" 2>/dev/null || true
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/sdk.sh" 2>/dev/null || true
      break
    fi
  done
  if ! command -v provider_option_get >/dev/null 2>&1 && [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    # shellcheck source=/dev/null
    . "$_root/.rnex/bin/rnex-env.sh" 2>/dev/null || true
  fi
fi

get_cfg() {
  _gc_key="$1"; _gc_def="${2:-}"
  _gc_val=""
  if command -v yaml_plugin_get >/dev/null 2>&1; then
    _gc_val="$(yaml_plugin_get "karpathy-llm" "$_gc_key" 2>/dev/null || true)"
  elif command -v provider_option_get >/dev/null 2>&1; then
    _gc_val="$(provider_option_get "karpathy-llm" "$_gc_key" 2>/dev/null || true)"
  fi
  [ -n "$_gc_val" ] && printf '%s' "$_gc_val" || printf '%s' "$_gc_def"
}

# -----------------------------------------------------------------------------
# kl_today
# Summary: Returns the current UTC date formatted strictly as ISO-8601 YYYY-MM-DD.
# @returns: Outputs 10-character ISO-8601 date string to stdout.
# -----------------------------------------------------------------------------
kl_today() {
  date -u +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d 2>/dev/null || date +%F 2>/dev/null || echo "2026-10-15"
}

# Resolve configured wiki directory path, normalized without leading/trailing slashes.
karpathy_get_wiki_dir() {
  _kgw_w=""
  if command -v yaml_get_plugin_config >/dev/null 2>&1; then
    _kgw_w="$(yaml_get_plugin_config "karpathy-llm" "wiki_dir" 2>/dev/null || true)"
  fi
  [ -n "$_kgw_w" ] || _kgw_w="$(get_cfg "wiki_dir" "wiki")"
  _kgw_w="$(printf '%s' "$_kgw_w" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
  [ -n "$_kgw_w" ] || _kgw_w="wiki"
  printf '%s' "$_kgw_w"
}

_wiki="$(karpathy_get_wiki_dir)"
_wiki_path="$_root/$_wiki"

# Retrieve configured sources for karpathy-llm, falling back to legacy raw_dir
# or default sources ("docs" and active member repository README.md paths).
karpathy_get_sources() {
  _kgs_list=""
  _yaml_resolve_files 2>/dev/null || true
  if [ -n "${WORKSPACE_LOCAL_YAML:-}" ] && [ -f "$WORKSPACE_LOCAL_YAML" ]; then
    _kgs_list="$(_yaml_parse_plugin_list_from_file "$WORKSPACE_LOCAL_YAML" "karpathy-llm" "sources")"
  fi
  if [ -z "$_kgs_list" ] && [ -n "${WORKSPACE_YAML:-}" ] && [ -f "$WORKSPACE_YAML" ]; then
    _kgs_list="$(_yaml_parse_plugin_list_from_file "$WORKSPACE_YAML" "karpathy-llm" "sources")"
  fi
  if [ -n "$_kgs_list" ]; then
    printf '%s\n' "$_kgs_list"
    return 0
  fi

  # Check legacy raw_dir setting BEFORE falling back to default manifest sources
  _kgs_legacy_raw="$(get_cfg "raw_dir" "")"
  if [ -n "$_kgs_legacy_raw" ]; then
    _clean_lraw="$(printf '%s' "$_kgs_legacy_raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
    if [ -n "$_clean_lraw" ]; then
      printf '%s\n' "$_clean_lraw"
      return 0
    fi
  fi

  if command -v yaml_get_plugin_list >/dev/null 2>&1; then
    _kgs_list="$(yaml_get_plugin_list "karpathy-llm" "sources" 2>/dev/null || true)"
  fi
  if [ -n "$_kgs_list" ]; then
    printf '%s\n' "$_kgs_list"
    return 0
  fi

  # Default fallback: "docs" and active member repository README.md paths
  printf '%s\n' "docs"
  _kgs_found_repo=0
  if command -v yaml_list_repos >/dev/null 2>&1; then
    for _kgs_r in $(yaml_list_repos 2>/dev/null || true); do
      [ -n "$_kgs_r" ] || continue
      if command -v yaml_repo_enabled >/dev/null 2>&1; then
        yaml_repo_enabled "$_kgs_r" 2>/dev/null || continue
      fi
      _kgs_found_repo=1
      kl_resolve_repo_paths "$_kgs_r"
      printf '%s/README.md\n' "$_kl_repo_rel"
    done
  fi
  if [ "$_kgs_found_repo" -eq 0 ]; then
    printf '%s/**/README.md\n' "${_clean_repos:-repos}"
  fi
}

# Verify whether a file path qualifies as a valid non-hidden text documentation source.
_is_valid_source_file() {
  _iv_file="$1"
  _iv_wiki="${2:-}"
  [ -f "$_iv_file" ] || return 1

  # Exclude hidden files and directories
  case "$_iv_file" in
    .*|*/.*) return 1 ;;
  esac

  # Exclude internal metadata directories and node_modules
  case "$_iv_file" in
    */.git/*|*/.rnex/*|*/node_modules/*) return 1 ;;
  esac

  # Exclude files within the curated wiki directory
  if [ -n "$_iv_wiki" ]; then
    case "$_iv_file" in
      "$_iv_wiki"/*|"$_iv_wiki") return 1 ;;
    esac
  fi

  # Skip common binary file formats
  case "$_iv_file" in
    *.png|*.jpg|*.jpeg|*.gif|*.svg|*.ico|*.webp|*.bmp|*.tiff) return 1 ;;
    *.zip|*.tar|*.gz|*.tgz|*.bz2|*.xz|*.7z|*.rar) return 1 ;;
    *.pdf|*.doc|*.docx|*.xls|*.xlsx|*.ppt|*.pptx) return 1 ;;
    *.exe|*.bin|*.dll|*.so|*.dylib|*.class|*.pyc|*.o|*.a) return 1 ;;
    *.mp3|*.mp4|*.wav|*.avi|*.mov|*.webm|*.ogg|*.mkv) return 1 ;;
    *.woff|*.woff2|*.ttf|*.eot|*.otf) return 1 ;;
  esac

  # Fast-path common documentation and code text extensions
  case "$_iv_file" in
    *.md|*.markdown|*.txt|*.rst|*.adoc|*.json|*.yaml|*.yml|*.sh|*.py|*.js|*.ts|*.go|*.rs|*.c|*.h|*.cpp) return 0 ;;
  esac

  # Inspect file content type if file utility is available
  if command -v file >/dev/null 2>&1; then
    case "$(file -b "$_iv_file" 2>/dev/null || true)" in
      *text*|*ASCII*|*UTF-8*|*empty*) return 0 ;;
      *) return 1 ;;
    esac
  fi

  return 0
}

# -----------------------------------------------------------------------------
# kl_source_to_slug
# Summary: Converts a workspace-relative source document path into a canonical,
#          deterministic, collision-free wiki page slug.
# Architectural Layer: Plugin Domain Helper / Knowledge Graph Normalizer
# Design Pattern: Information Expert / Pure Function
#
# Transformation Rules:
#   1. Strip leading './' if present.
#   2. Strip '.markdown' or '.md' file extension.
#   3. Lowercase all characters; replace any non-alphanumeric character with a hyphen;
#      collapse consecutive hyphens into a single hyphen; trim leading/trailing hyphens.
#   4. Prefix with 'root-' ONLY if a root-level workspace file without directory
#      prefix normalizes to a reserved wiki control filename ('index', 'hot', 'log', '_log').
#
# Examples:
#   - docs/overview.md              -> docs-overview
#   - docs/api/README.md            -> docs-api-readme
#   - docs/nested/deep/spec [v1].md -> docs-nested-deep-spec-v1
#   - repos/app/apps/web/README.md  -> repos-app-apps-web-readme
#   - index.md                      -> root-index
#
# @param $1: src_rel - Workspace-relative source document path.
# @returns: Outputs normalized slug on stdout (without .md extension).
# @pure: Pure string transformation; zero side effects.
# -----------------------------------------------------------------------------
kl_source_to_slug() {
  _kss_src="$1"
  # Strip leading ./ if present
  while [ "${_kss_src#./}" != "$_kss_src" ]; do _kss_src="${_kss_src#./}"; done

  # Strip .markdown or .md extension
  case "$_kss_src" in
    *.markdown) _kss_base="${_kss_src%.markdown}" ;;
    *.md)       _kss_base="${_kss_src%.md}" ;;
    *)          _kss_base="$_kss_src" ;;
  esac

  # Normalize to lowercase alphanumeric separated by single hyphens
  _kss_slug="$(printf '%s' "$_kss_base" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"

  # Root-level files without directory prefix normalizing to reserved wiki control file names are prefixed with "root-"
  case "$_kss_slug" in
    index|hot|_log|log)
      case "$_kss_src" in
        */*) ;; # Has directory prefix (e.g. docs/index.md -> docs-index), not a reserved collision
        *)   _kss_slug="root-${_kss_slug}" ;;
      esac
      ;;
  esac

  [ -n "$_kss_slug" ] || _kss_slug="unnamed-doc"
  printf '%s' "$_kss_slug"
}

# Recursively expand source targets (directories, files, globs) into a deterministic,
# newline-delimited stream of absolute file paths.
karpathy_expand_source_files() {
  _kesf_override="${1:-}"
  _kesf_wiki_dir="$(karpathy_get_wiki_dir)"
  _kesf_wiki_abs="${NEXUS_DIR:-${RNEX_ROOT:-.}}/$_kesf_wiki_dir"
  _kesf_root="${NEXUS_DIR:-${RNEX_ROOT:-.}}"

  # Precompute disabled repository directory prefixes once to avoid per-file YAML lookups
  _kesf_disabled_repos=""
  if command -v yaml_list_repos >/dev/null 2>&1 && command -v yaml_repo_enabled >/dev/null 2>&1; then
    for _r_chk in $(yaml_list_repos 2>/dev/null || true); do
      [ -n "$_r_chk" ] || continue
      if ! yaml_repo_enabled "$_r_chk" 2>/dev/null; then
        kl_resolve_repo_paths "$_r_chk"
        _kesf_disabled_repos="${_kesf_disabled_repos:+$_kesf_disabled_repos }$_kl_repo_path"
      fi
    done
  fi

  _kesf_stream() {
    if [ -n "$_kesf_override" ]; then
      printf '%s\n' "$_kesf_override"
    else
      karpathy_get_sources
    fi
  }

  _kesf_stream | (
    while IFS= read -r _src || [ -n "$_src" ]; do
      _src="$(printf '%s' "$_src" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      while [ "${_src#./}" != "$_src" ]; do _src="${_src#./}"; done
      [ "$_src" = "." ] || _src="${_src%/}"
      [ -n "$_src" ] || continue

      case "$_src" in
        /*) _src_abs="$_src" ;;
        *)  _src_abs="$_kesf_root/$_src" ;;
      esac

      if [ -d "$_src_abs" ]; then
        # Case A: Directory — recursively discover non-hidden files, pruning metadata dirs
        find "$_src_abs" \( -name .git -o -name .rnex -o -name node_modules \) -prune -o -type f ! -name '.*' ! -path '*/.*' -print 2>/dev/null
      elif [ -f "$_src_abs" ]; then
        # Case B: Regular file — emit directly
        printf '%s\n' "$_src_abs"
      else
        # Case C: Glob pattern
        case "$_src" in
          *'**'*)
            case "$_src" in
              '**')
                find "$_kesf_root" \( -name .git -o -name .rnex -o -name node_modules \) -prune -o -type f ! -name '.*' ! -path '*/.*' -print 2>/dev/null
                ;;
              */'**')
                _sub="${_src%/\*\*}"
                [ -d "$_kesf_root/$_sub" ] && find "$_kesf_root/$_sub" \( -name .git -o -name .rnex -o -name node_modules \) -prune -o -type f ! -name '.*' ! -path '*/.*' -print 2>/dev/null
                ;;
              '**/'*)
                _pat="${_src#\*\*/}"
                find "$_kesf_root" \( -name .git -o -name .rnex -o -name node_modules \) -prune -o -type f -name "$_pat" ! -name '.*' ! -path '*/.*' -print 2>/dev/null
                ;;
              *'/**/'*)
                _sub="${_src%%/\*\*/*}"
                _pat="${_src#*/\*\*/}"
                [ -d "$_kesf_root/$_sub" ] && find "$_kesf_root/$_sub" \( -name .git -o -name .rnex -o -name node_modules \) -prune -o -type f -name "$_pat" ! -name '.*' ! -path '*/.*' -print 2>/dev/null
                ;;
              *)
                _sub="${_src%%\*\**}"
                _sub="${_sub%/}"
                _pat="${_src#*\*\*}"
                _pat="${_pat#/}"
                if [ -d "$_kesf_root/$_sub" ]; then
                  find "$_kesf_root/$_sub" \( -name .git -o -name .rnex -o -name node_modules \) -prune -o -type f -path "*$_pat" ! -name '.*' ! -path '*/.*' -print 2>/dev/null
                fi
                ;;
            esac
            ;;
          *'*'*|*'?'*|*'['*)
            (
              cd "$_kesf_root" 2>/dev/null || exit 0
              for _m in $_src; do
                [ -e "$_m" ] || continue
                if [ -d "$_m" ]; then
                  find "$_kesf_root/$_m" \( -name .git -o -name .rnex -o -name node_modules \) -prune -o -type f ! -name '.*' ! -path '*/.*' -print 2>/dev/null
                elif [ -f "$_m" ]; then
                  printf '%s/%s\n' "$_kesf_root" "$_m"
                fi
              done
            )
            ;;
        esac
      fi
    done
  ) | while IFS= read -r _cand_file || [ -n "$_cand_file" ]; do
    [ -n "$_cand_file" ] || continue
    # Exclude files belonging to precomputed disabled repositories
    _in_disabled=0
    if [ -n "$_kesf_disabled_repos" ]; then
      for _d_repo in $_kesf_disabled_repos; do
        case "$_cand_file" in
          "$_d_repo"/*|"$_d_repo") _in_disabled=1; break ;;
        esac
      done
    fi
    [ "$_in_disabled" -eq 1 ] && continue

    if _is_valid_source_file "$_cand_file" "$_kesf_wiki_abs"; then
      printf '%s\n' "$_cand_file"
    fi
  done | LC_ALL=C sort -u
}

_raw="$(get_cfg "raw_dir" "./docs")"
_raw="$(printf '%s' "$_raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
if command -v plugin_primary_source_dir >/dev/null 2>&1; then
  _psd="$(plugin_primary_source_dir "karpathy-llm" 2>/dev/null || true)"
  [ -n "$_psd" ] && _raw="$_psd"
fi
[ -n "$_raw" ] || _raw="docs"
_raw_path="$_root/$_raw"

if command -v yaml_get_repos_dir >/dev/null 2>&1; then
  _clean_repos="$(yaml_get_repos_dir 2>/dev/null)"
elif [ -n "${RNEX_REPOS_DIR:-}" ]; then
  _clean_repos="$RNEX_REPOS_DIR"
elif [ -n "${REPOS_DIR_REL:-}" ]; then
  _clean_repos="$REPOS_DIR_REL"
else
  _clean_repos="$(yaml_get_top_level "repos_dir" "repos" 2>/dev/null || printf 'repos')"
fi
_clean_repos="$(printf '%s' "$_clean_repos" | sed -e 's#^[[:space:]]*##' -e 's#[[:space:]]*$##' -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
[ -n "$_clean_repos" ] || _clean_repos="repos"
REPOS_DIR="${REPOS_DIR:-$_root/$_clean_repos}"

# Check whether the optional local git-ignored hot.md cache is enabled (default: true).
kl_hot_enabled() {
  _khe_val="$(get_cfg "hot_file" "")"
  [ -n "$_khe_val" ] || _khe_val="$(get_cfg "hotFile" "")"
  [ -n "$_khe_val" ] || _khe_val="$(get_cfg "hot" "true")"
  case "$_khe_val" in
    false|False|FALSE|no|No|NO|0|off|Off|OFF|none) return 1 ;;
    *) return 0 ;;
  esac
}

# Truncate a summary string to a strict word and character budget.
# Usage: kl_truncate_summary "<text>" [max_words] [max_chars]
kl_truncate_summary() {
  _kts_text="$1"
  _kts_words="${2:-10}"
  _kts_chars="${3:-75}"
  printf '%s\n' "$_kts_text" | sed -e 's/\[/ /g' -e 's/\]([^)]*)//g' -e 's/[`*_~<>]//g' -e 's/[.?!][[:space:]].*//' -e 's/[.?!]$//' | awk -v max_w="$_kts_words" -v max_c="$_kts_chars" '
    NR == 1 {
      out = ""
      for (i = 1; i <= NF && i <= max_w; i++) {
        cand = (out == "") ? $i : out " " $i
        if (length(cand) > max_c) {
          if (out == "") {
            out = substr($i, 1, max_c - 3) "..."
          }
          break
        }
        out = cand
      }
      print out
      exit
    }
  '
}

# Ensure the configured wiki directory and baseline control files (index.md, _log.md, and optional hot.md) exist.
kl_ensure_wiki_files() {
  mkdir -p "$_wiki_path"
  _kew_pdir=""
  if command -v find_plugin_dir >/dev/null 2>&1; then
    _kew_pdir="$(find_plugin_dir "karpathy-llm" 2>/dev/null || true)"
  fi
  if [ -z "$_kew_pdir" ]; then
    for _kew_cand in "$_root/.rnex/plugins/karpathy-llm" "$_root/plugins/karpathy-llm"; do
      if [ -d "$_kew_cand/templates" ]; then
        _kew_pdir="$_kew_cand"
        break
      fi
    done
  fi

  for _kew_f in index.md hot.md _log.md; do
    if [ "$_kew_f" = "hot.md" ] && ! kl_hot_enabled; then
      rm -f "$_wiki_path/hot.md" 2>/dev/null || true
      continue
    fi
    if [ ! -f "$_wiki_path/$_kew_f" ]; then
      if [ -n "$_kew_pdir" ] && [ -f "$_kew_pdir/templates/$_kew_f" ] && command -v plugin_instantiate_template >/dev/null 2>&1; then
        plugin_instantiate_template "karpathy-llm" "$_kew_pdir" "$_kew_pdir/templates/$_kew_f" "$_wiki_path/$_kew_f"
      elif [ -n "$_kew_pdir" ] && [ -f "$_kew_pdir/templates/$_kew_f" ]; then
        sed -e "s|{wiki_dir}|$_wiki|g" -e "s|{raw_dir}|$_raw|g" -e "s|{sources}|\`$_raw/\`|g" -e "s|{today}|$(kl_today)|g" "$_kew_pdir/templates/$_kew_f" > "$_wiki_path/$_kew_f"
      fi
    fi
  done

  _kew_today="$(kl_today)"
  if [ ! -f "$_wiki_path/index.md" ]; then
    cat > "$_wiki_path/index.md" <<INDEX_INIT
# Wiki Index

Master navigation index for the Karpathy LLM Wiki.

## Overview & Status
* **Operation Log:** [\`_log.md\`](./_log.md) — Timestamped ingest & maintenance history.

## Member Repositories

## Architecture & Concepts

INDEX_INIT
  fi

  if kl_hot_enabled && [ ! -f "$_wiki_path/hot.md" ]; then
    cat > "$_wiki_path/hot.md" <<HOT_INIT
# Hot Context (Compact Local Orientation Cache)

> Local git-ignored orientation cache for AI agents (~250 words max). Read this file first on startup, then consult \`${_wiki}/index.md\` on demand.

## 1. Architecture & Member Repo Map
* **Workspace Overview:** Karpathy LLM Wiki active.

## 2. Current Focus & Recent Ingests
* **Recent Ingests:** None yet.

## 3. Key Contracts & Boundaries
* **Wiki Index:** Consult [\`${_wiki}/index.md\`](./index.md) for the complete catalog of compiled pages.
HOT_INIT
  fi

  if [ ! -f "$_wiki_path/_log.md" ]; then
    cat > "$_wiki_path/_log.md" <<LOG_INIT
# Karpathy Wiki Operation Log

Append-only audit trail recording all ingest and maintenance runs.

---

### Initial Setup — ${_kew_today}
* **Action:** Initialized Karpathy LLM Wiki architecture via \`karpathy-llm\` plugin.
LOG_INIT
  fi
}

# Resolve physical path (_kl_repo_path) and workspace-relative path (_kl_repo_rel) for a member repository.
kl_resolve_repo_paths() {
  _krp_name="$1"
  _krp_custom="$(yaml_get "$_krp_name" "path" 2>/dev/null || true)"
  if [ -n "$_krp_custom" ]; then
    case "$_krp_custom" in
      /*)
        _kl_repo_path="$_krp_custom"
        case "$_krp_custom" in
          "$_root"/*) _kl_repo_rel="${_krp_custom#"$_root"/}" ;;
          *) _kl_repo_rel="$_krp_custom" ;;
        esac
        ;;
      *)
        _kl_repo_path="$_root/$_krp_custom"
        _kl_repo_rel="$_krp_custom"
        ;;
    esac
  else
    _kl_repo_path="$_root/$_clean_repos/$_krp_name"
    _kl_repo_rel="${_clean_repos}/${_krp_name}"
  fi
}

# Ingest member repository README into atomic wiki page, index.md, and hot.md.
# Usage: kl_ingest_member_readme <repo_name> <repo_path> <readme_filename> <repo_rel> [force_log]
kl_ingest_member_readme() {
  _m_repo="$1"
  _m_path="$2"
  _m_readme="$3"
  _m_rel_prefix="$4"
  _m_force_log="${5:-0}"
  _src_file="$_m_path/$_m_readme"
  _target_page="$_wiki_path/repo-${_m_repo}.md"
  _today="$(kl_today)"
  _KL_LAST_INGESTED=0

  [ -f "$_src_file" ] || return 0

  if [ -n "$_m_rel_prefix" ]; then
    _clean_rel="$(printf '%s' "$_m_rel_prefix" | sed -e 's#^[[:space:]]*##' -e 's#[[:space:]]*$##' -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
    _rel_source="${_clean_rel}/${_m_readme}"
    _rel_loc="${_clean_rel}/"
  else
    _rel_source="${_clean_repos}/${_m_repo}/${_m_readme}"
    _rel_loc="${_clean_repos}/${_m_repo}/"
  fi

  # 1. Parse repository title from first Markdown header
  _m_title="$(awk '
    /^#[^#]/ {
      sub(/^#[ ]*/, "")
      sub(/[ ]*$/, "")
      print
      exit
    }
  ' "$_src_file")"
  [ -z "$_m_title" ] && _m_title="Member Repo: ${_m_repo}"

  # 2. Parse repository summary (first non-header, non-badge, non-comment line), bounded to prevent huge lines
  _m_raw_summary="$(awk '
    NR == 1 && /^#[^#]/ { next }
    /^[ ]*(\[!\[|<img|<!--|---|```)/ { next }
    /^#/ { next }
    NF > 0 {
      gsub(/^[ ]+|[ ]+$/, "")
      print
      exit
    }
  ' "$_src_file")"
  _m_summary="$(kl_truncate_summary "$_m_raw_summary" 25 160)"
  [ -z "$_m_summary" ] && _m_summary="Core architecture, contracts, and implementation for member repository ${_m_repo}."

  # 3. Determine if target page needs generation (missing only — preserve curated pages)
  _needs_gen=0
  if [ ! -f "$_target_page" ]; then
    _needs_gen=1
  fi

  # Determine navigation reference (avoid linking to missing navigation pages)
  _nav_target="index.md"
  _nav_label="Wiki Index"
  _nav_related="[]"
  _nav_extends="[]"
  if [ -f "$_wiki_path/member-repositories.md" ]; then
    _nav_target="member-repositories.md"
    _nav_label="Member Repositories"
    _nav_related='["member-repositories.md"]'
    _nav_extends='["member-repositories.md"]'
  fi

  if [ "$_needs_gen" -eq 1 ]; then
    _KL_LAST_INGESTED=1
    cat > "$_target_page" <<PAGE_EOF
---
title: "Member Repo: ${_m_repo}"
tags: [member-repo, ${_m_repo}]
last_updated: ${_today}
sources: ["${_rel_source}"]
related: ${_nav_related}
extends: ${_nav_extends}
contradicts: []
mentioned_in: ["index.md"]
---

# ${_m_title}

## Summary
${_m_summary}

## Architecture & Responsibilities
* **Workspace Location:** \`${_rel_loc}\`
* **Intake Source:** \`${_rel_source}\`
* **Management:** Tracked as an autonomous Git member repository in Repo Nexus.

## Contextual Links
* See [${_nav_label}](./${_nav_target}) for workspace member repository catalog.
PAGE_EOF

    # Log operation only when newly ingested into shared wiki index (zero relation to hot.md)
    if [ -f "$_wiki_path/_log.md" ]; then
      cat >> "$_wiki_path/_log.md" <<LOG_EOF

### Member Repo Ingest: ${_m_repo} — ${_today}
* **Source:** \`${_rel_source}\`
* **Ingested Page:** \`repo-${_m_repo}.md\`
* **Status:** Ingested atomic member repository page into wiki index.
LOG_EOF
    fi
  fi

  # 4. Register in navigation index (index.md) if not already present
  if [ -f "$_wiki_path/index.md" ] && ! grep -q "repo-${_m_repo}\.md" "$_wiki_path/index.md"; then
    _tmp_idx="$(mktemp)"
    _idx_line="* [Member Repo: ${_m_repo}](./repo-${_m_repo}.md): ${_m_summary}"
    if grep -q "^## Member Repositories" "$_wiki_path/index.md"; then
      if LINE="$_idx_line" awk '
        /^## Member Repositories/ {
          print
          print ENVIRON["LINE"]
          next
        }
        /\* \*\([Aa]ctive member repositories/ { next }
        { print }
      ' "$_wiki_path/index.md" > "$_tmp_idx"; then
        mv "$_tmp_idx" "$_wiki_path/index.md"
      else
        rm -f "$_tmp_idx"
      fi
    elif grep -q "^## Architecture & Concepts" "$_wiki_path/index.md"; then
      if LINE="$_idx_line" awk '
        /^## Architecture & Concepts/ {
          print "## Member Repositories"
          print ENVIRON["LINE"]
          print ""
          print
          next
        }
        { print }
      ' "$_wiki_path/index.md" > "$_tmp_idx"; then
        mv "$_tmp_idx" "$_wiki_path/index.md"
      else
        rm -f "$_tmp_idx"
      fi
    else
      rm -f "$_tmp_idx"
      printf '\n## Member Repositories\n* [Member Repo: %s](./repo-%s.md): %s\n' "$_m_repo" "$_m_repo" "$_m_summary" >> "$_wiki_path/index.md"
    fi
  fi

  # 5. Independently register in local hot cache (hot.md) if enabled
  if ! kl_hot_enabled; then
    rm -f "$_wiki_path/hot.md" 2>/dev/null || true
    return 0
  fi

  _is_in_hot=0
  if grep -q "repo-${_m_repo}\.md" "$_wiki_path/hot.md" 2>/dev/null; then
    _is_in_hot=1
  elif grep -q "${_rel_loc}" "$_wiki_path/hot.md" 2>/dev/null; then
    _is_in_hot=1
  elif grep -E -q "^\* \*\*Member Repositories \([0-9]+ repos\):.*[ :]${_m_repo}(,|\.|$)" "$_wiki_path/hot.md" 2>/dev/null; then
    _is_in_hot=1
  fi

  if [ -f "$_wiki_path/hot.md" ] && [ "$_is_in_hot" -eq 0 ]; then
    _hot_summary="$(kl_truncate_summary "$_m_summary" 7 55)"
    [ -z "$_hot_summary" ] && _hot_summary="Member repository"
    _hot_line="* **[${_m_repo}](./repo-${_m_repo}.md)** (\`${_rel_loc}\`): ${_hot_summary}."
    _tmp_hot="$(mktemp)"
    if LINE="$_hot_line" awk '
      /^## 1\. Architecture & Member Repo Map/ {
        print
        print ENVIRON["LINE"]
        next
      }
      /\* \*\*Member Repositories:\*\* Map each member repo/ { next }
      { print }
    ' "$_wiki_path/hot.md" > "$_tmp_hot"; then
      mv "$_tmp_hot" "$_wiki_path/hot.md"
    else
      rm -f "$_tmp_hot"
    fi
  fi
}

# Enforce strict compact size on hot.md by bounding Section 1 (repos) and Section 2 (recent ingests).
# Usage: kl_condense_hot_cache [ingested_count] [ingested_repos_csv]
kl_condense_hot_cache() {
  _khc_ingested_cnt="${1:-0}"
  _khc_ingested_repos="${2:-}"
  if ! kl_hot_enabled; then
    rm -f "$_wiki_path/hot.md" 2>/dev/null || true
    return 0
  fi
  [ -f "$_wiki_path/hot.md" ] || return 0

  # 1. Bound Section 2 (Current Focus & Recent Ingests) to at most 8 compact lines (<= 115 chars each)
  _tmp_s2="$(mktemp)"
  if awk '
    BEGIN { in_s2 = 0; s2_cnt = 0; s2_overflow = 0 }
    /^## 2\. Current Focus & Recent Ingests/ { in_s2 = 1; print; next }
    in_s2 && /^## / {
      if (s2_overflow > 0) {
        print "* *(See [Wiki Index](./index.md) for all compiled pages)*"
      }
      in_s2 = 0
      print
      next
    }
    in_s2 {
      if ($0 ~ /^\* \*\*\(See \[Wiki Index\]/) { next }
      if ($0 ~ /^\* \*\*Active Tasks:\*\* Wiki initialization complete\./) { next }
      if ($0 ~ /^\* \*\*\[/) {
        s2_cnt++
        if (s2_cnt == 1) {
          has_real_ingest = 1
        }
        if (s2_cnt <= 8) {
          line = $0
          if (length(line) > 115) {
            line = substr(line, 1, 112) "..."
          }
          print line
        } else {
          s2_overflow++
        }
        next
      }
      if ($0 ~ /^\* \*\*Recent Ingests:\*\* None yet/) {
        if (s2_cnt > 0) next
      }
      print
      next
    }
    { print }
  ' "$_wiki_path/hot.md" > "$_tmp_s2"; then
    # Strip "Recent Ingests: None yet" if any real ingest bullet exists in Section 2
    if grep -q '^\* \*\*\[' "$_tmp_s2" 2>/dev/null; then
      _tmp_s2b="$(mktemp)"
      grep -v '^\* \*\*Recent Ingests:\*\* None yet' "$_tmp_s2" > "$_tmp_s2b" && mv "$_tmp_s2b" "$_tmp_s2"
      rm -f "$_tmp_s2b"
    fi
    mv "$_tmp_s2" "$_wiki_path/hot.md"
  else
    rm -f "$_tmp_s2"
  fi

  # 2. Condense Section 1 (Member Repo Map) if > 10 repos or if total word count > 240 words
  _hot_words="$(wc -w < "$_wiki_path/hot.md" 2>/dev/null | tr -d ' ')"
  [ -n "$_hot_words" ] || _hot_words=0
  _num_repos="$(grep -cE '^\* \*\*\[[^]]+\]\(\./repo-[^)]+\)' "$_wiki_path/hot.md" 2>/dev/null || true)"
  [ -n "$_num_repos" ] || _num_repos=0
  if [ "$_num_repos" -gt 10 ] || [ "$_khc_ingested_cnt" -gt 10 ] || [ "$_hot_words" -gt 240 ]; then
    if [ "$_khc_ingested_cnt" -gt 10 ] && [ -n "$_khc_ingested_repos" ]; then
      _condense_count="$_khc_ingested_cnt"
      _repo_names="$_khc_ingested_repos"
    elif [ "$_num_repos" -gt 0 ]; then
      _condense_count="$_num_repos"
      _repo_names="$(grep -E '^\* \*\*\[[^]]+\]\(\./repo-[^)]+\)' "$_wiki_path/hot.md" | sed -e 's/^\* \*\*\[//' -e 's/\].*//' | head -n 10 | tr '\n' ', ' | sed -e 's/, $//')"
    else
      _condense_count=0
      _repo_names=""
    fi

    if [ "$_condense_count" -gt 0 ]; then
      _tmp_b="$(mktemp)"
      if awk -v rnames="$_repo_names" -v nrepos="$_condense_count" -v rdir="$_clean_repos" '
        BEGIN { in_s1=0; replaced=0 }
        /^## 1\. Architecture & Member Repo Map/ { in_s1=1; print; next }
        in_s1 && /^## / { in_s1=0 }
        in_s1 && (/^\* \*\*(\[[^]]+\]\(\.\/repo-|Member Repositories \([0-9]+ repos\):)/) {
          if (!replaced) {
            print "* **Member Repositories (" nrepos " repos):** Autonomous repositories under `" rdir "/`: " rnames ". See [Wiki Index](./index.md#member-repositories)."
            replaced=1
          }
          next
        }
        { print }
      ' "$_wiki_path/hot.md" > "$_tmp_b"; then
        mv "$_tmp_b" "$_wiki_path/hot.md"
      else
        rm -f "$_tmp_b"
      fi
    fi
  fi

  # 3. Final safety cap: if custom prose in hot.md pushes word count > 450 words, truncate trailing lines in custom sections
  _hot_words="$(wc -w < "$_wiki_path/hot.md" 2>/dev/null || echo 0)"
  if [ "$_hot_words" -gt 450 ]; then
    _tmp_cap="$(mktemp)"
    if awk '
      BEGIN { words = 0 }
      /^## [123]\./ { print; next }
      {
        if (words + NF <= 420) {
          print
          words += NF
        }
      }
    ' "$_wiki_path/hot.md" > "$_tmp_cap"; then
      mv "$_tmp_cap" "$_wiki_path/hot.md"
    else
      rm -f "$_tmp_cap"
    fi
  fi
}
