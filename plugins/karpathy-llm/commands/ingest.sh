#!/bin/sh
# shellcheck shell=sh disable=SC2154
# ============================================================================
# toolkit/plugins/karpathy-llm/commands/ingest.sh — Karpathy LLM Wiki Ingest
#
# Syntax: rnex plugin karpathy-llm ingest [--source <path>] [--repo <name>] [--quiet]
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

_source_targets=""
_repo_targets=""
_quiet=0

while [ $# -gt 0 ]; do
  case "$1" in
    --source)
      shift
      [ -n "${1:-}" ] || { echo "Error: --source requires a path argument" >&2; exit 1; }
      _source_targets="${_source_targets:+$_source_targets
}$1"
      ;;
    --source=*)
      _s_val="${1#--source=}"
      [ -n "$_s_val" ] || { echo "Error: --source requires a path argument" >&2; exit 1; }
      _source_targets="${_source_targets:+$_source_targets
}$_s_val"
      ;;
    --repo)
      shift
      [ -n "${1:-}" ] || { echo "Error: --repo requires a repository name" >&2; exit 1; }
      _repo_targets="${_repo_targets:+$_repo_targets
}$1"
      ;;
    --repo=*)
      _r_val="${1#--repo=}"
      [ -n "$_r_val" ] || { echo "Error: --repo requires a repository name" >&2; exit 1; }
      _repo_targets="${_repo_targets:+$_repo_targets
}$_r_val"
      ;;
    -q|--quiet)
      _quiet=1
      ;;
    -h|--help)
      cat <<'HELP_EOF'
Usage: rnex plugin karpathy-llm ingest [options]

Ingest intake sources and repository documentation into the Karpathy LLM Wiki.

Options:
  --source <path>   Ingest a specific markdown file or intake directory
  --repo <name>     Ingest a specific member repository README
  -q, --quiet       Suppress informational output
  -h, --help        Show this help message
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

_today="$(date +%Y-%m-%d 2>/dev/null || date +%F 2>/dev/null || echo "2026-10-15")"

# Ensure baseline control files exist in wiki directory
kl_ensure_wiki_files

# Ingest member repository README via shared _common.sh helper
ingest_repo_readme() {
  kl_ingest_member_readme "$1" "$2" "$3" "$4" 1
  [ "$_quiet" -eq 1 ] || printf '[WIKI] Ingested member repository: %s\n' "$1"
}

# Ingest generic source markdown file
ingest_source_file() {
  _src_abs="$1"
  [ -f "$_src_abs" ] || return 0

  # Compute relative path from workspace root
  case "$_src_abs" in
    "$_root"/*) _src_rel="${_src_abs#"$_root"/}" ;;
    *) _src_rel="$_src_abs" ;;
  esac
  _src_rel="$(printf '%s' "$_src_rel" | sed -e 's#^\./##')"

  _rel_noext="${_src_rel%.*}"
  _s_base="$(basename "$_src_abs" .md)"
  _base_lower="$(printf '%s' "$_s_base" | tr '[:upper:]' '[:lower:]')"

  _matched_source=0
  _is_nested=0
  for _src_root in $(karpathy_get_sources 2>/dev/null || true) "${_raw:-}"; do
    [ -n "$_src_root" ] || continue
    case "$_src_root" in
      *'*'*|*'?'*|*'['*) continue ;;
    esac
    _clean_sroot="$(printf '%s' "$_src_root" | sed -e 's#^\./##' -e 's#/*$##')"
    case "$_src_rel" in
      "$_clean_sroot"/*)
        _matched_source=1
        _inner_path="${_src_rel#"$_clean_sroot"/}"
        case "$_inner_path" in
          */*) _is_nested=1 ;;
        esac
        break
        ;;
    esac
  done

  # If not matched to a configured directory source, check if relative dir has multiple segments
  if [ "$_matched_source" -eq 0 ]; then
    _rel_dir="$(dirname "$_src_rel")"
    case "$_rel_dir" in
      */*) _is_nested=1 ;;
    esac
  fi

  # Derive deterministic, collision-free slug from path
  if [ "$_is_nested" -eq 1 ] || [ "$_base_lower" = "readme" ]; then
    # Nested directory documentation file (e.g. docs/api/README.md -> doc-docs-api-readme.md)
    # or generic readme avoiding wiki namespace collisions
    _norm_slug="$(printf '%s' "$_rel_noext" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -e 's/^-//' -e 's/-$//')"
    case "$_norm_slug" in
      doc-*) _s_slug="$_norm_slug" ;;
      *)     _s_slug="doc-${_norm_slug}" ;;
    esac
  else
    # Top-level documentation file (e.g. docs/roadmap.md -> roadmap.md, docs/top-level.md -> top-level.md)
    _s_slug="$(printf '%s' "$_s_base" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -e 's/^-//' -e 's/-$//')"
    case "$_s_slug" in
      index|hot|_log) _s_slug="doc-${_s_slug}" ;;
    esac
  fi
  _s_target="$_wiki_path/${_s_slug}.md"

  # Title
  _s_title="$(awk '
    /^#[^#]/ {
      sub(/^#[ ]*/, "")
      sub(/[ ]*$/, "")
      print
      exit
    }
  ' "$_src_abs")"
  [ -z "$_s_title" ] && _s_title="$_s_base"

  # Summary
  _s_summary="$(awk '
    NR == 1 && /^#[^#]/ { next }
    /^[ ]*(\[!\[|<img|<!--|---|```)/ { next }
    /^#/ { next }
    NF > 0 {
      gsub(/^[ ]+|[ ]+$/, "")
      print
      exit
    }
  ' "$_src_abs")"
  [ -z "$_s_summary" ] && _s_summary="Intake document ${_s_base}."

  if [ ! -f "$_s_target" ]; then
    cat > "$_s_target" <<PAGE_EOF
---
title: "${_s_title}"
tags: [concept, intake]
last_updated: ${_today}
sources: ["${_src_rel}"]
related: ["index.md"]
extends: []
contradicts: []
mentioned_in: ["index.md", "hot.md"]
---

# ${_s_title}

## Summary
${_s_summary}

## Architecture & Responsibilities
* **Intake Source:** \`${_src_rel}\`
* **Knowledge Domain:** Workspace intake documentation.

## Contextual Links
* See [Wiki Index](./index.md) for master knowledge graph index.
PAGE_EOF
  fi

  # Log operation
  cat >> "$_wiki_path/_log.md" <<LOG_EOF

### Source Ingest: ${_src_rel} — ${_today}
* **Source:** \`${_src_rel}\`
* **Ingested Page:** \`${_s_slug}.md\`
* **Status:** Ingested source document into wiki index and hot cache.
LOG_EOF

  # Update index.md
  if ! grep -q "${_s_slug}\.md" "$_wiki_path/index.md"; then
    _tmp_idx="$(mktemp)"
    _idx_line="* [${_s_title}](./${_s_slug}.md): ${_s_summary}"
    if grep -q "^## Architecture & Concepts" "$_wiki_path/index.md"; then
      if LINE="$_idx_line" awk '
        /^## Architecture & Concepts/ {
          print
          print ENVIRON["LINE"]
          next
        }
        { print }
      ' "$_wiki_path/index.md" > "$_tmp_idx"; then
        mv "$_tmp_idx" "$_wiki_path/index.md"
      else
        rm -f "$_tmp_idx"
      fi
    else
      printf '\n## Architecture & Concepts\n%s\n' "$_idx_line" >> "$_wiki_path/index.md"
    fi
  fi

  # Update hot.md Section 2 (Recent Ingests)
  if ! grep -q "${_s_slug}\.md" "$_wiki_path/hot.md" 2>/dev/null && ! grep -q "${_src_rel}" "$_wiki_path/hot.md" 2>/dev/null; then
    _hot_line="* **${_s_title} (\`${_src_rel}\`):** ${_s_summary}"
    _tmp_hot="$(mktemp)"
    if LINE="$_hot_line" awk '
      /^## 2\. Current Focus & Recent Ingests/ {
        print
        print ENVIRON["LINE"]
        next
      }
      { print }
    ' "$_wiki_path/hot.md" > "$_tmp_hot"; then
      mv "$_tmp_hot" "$_wiki_path/hot.md"
    else
      rm -f "$_tmp_hot"
    fi
  fi

  [ "$_quiet" -eq 1 ] || printf '[WIKI] Ingested source: %s -> %s.md\n' "$_src_rel" "$_s_slug"
}

_ingested_count=0
_ingested_paths=""

# 1. Ingest specifically requested member repository targets
if [ -n "$_repo_targets" ]; then
  while IFS= read -r _rt || [ -n "$_rt" ]; do
    [ -n "$_rt" ] || continue
    kl_resolve_repo_paths "$_rt"

    if [ ! -d "$_kl_repo_path" ]; then
      echo "Warning: Repository '$_rt' directory not found at '$_kl_repo_path'" >&2
      continue
    fi

    _found_readme=0
    for _rm in README.md readme.md README.markdown README; do
      if [ -f "$_kl_repo_path/$_rm" ]; then
        ingest_repo_readme "$_rt" "$_kl_repo_path" "$_rm" "$_kl_repo_rel"
        _ingested_count=$((_ingested_count + 1))
        _ingested_paths="${_ingested_paths:+$_ingested_paths
}${_kl_repo_rel}/${_rm}"
        _found_readme=1
        break
      fi
    done
    if [ "$_found_readme" -eq 0 ]; then
      echo "Warning: No README found in repository '$_rt'" >&2
    fi
  done <<EOF_REPOS
$_repo_targets
EOF_REPOS
fi

# 2. Ingest source targets (explicit --source or all configured sources if no explicit --repo)
if [ -n "$_source_targets" ] || [ -z "$_repo_targets" ]; then
  _arg_source="${_source_targets:-}"
  _tmp_ingest_list="$(mktemp)"

  karpathy_expand_source_files "$_arg_source" > "$_tmp_ingest_list"

  while IFS= read -r _abs_file || [ -n "$_abs_file" ]; do
    [ -n "$_abs_file" ] || continue
    [ -f "$_abs_file" ] || continue

    case "$_abs_file" in
      "$_root"/*) _f_rel="${_abs_file#"$_root"/}" ;;
      *) _f_rel="$_abs_file" ;;
    esac
    _f_rel="$(printf '%s' "$_f_rel" | sed -e 's#^\./##')"

    # Detect if file represents a member repository README
    _is_repo_readme=0
    _r_target_name=""
    _readme_fname="$(basename "$_abs_file")"

    case "$_readme_fname" in
      [Rr][Ee][Aa][Dd][Mm][Ee]*)
        if command -v yaml_list_repos >/dev/null 2>&1; then
          for _r_cand in $(yaml_list_repos 2>/dev/null || true); do
            [ -n "$_r_cand" ] || continue
            kl_resolve_repo_paths "$_r_cand"
            if [ "$_f_rel" = "${_kl_repo_rel}/${_readme_fname}" ]; then
              _is_repo_readme=1
              _r_target_name="$_r_cand"
              break
            fi
          done
        fi
        if [ "$_is_repo_readme" -eq 0 ] && [ -n "${_clean_repos:-}" ]; then
          case "$_f_rel" in
            "${_clean_repos}"/*/"$_readme_fname")
              _repo_part="${_f_rel#"${_clean_repos}"/}"
              _r_target_name="${_repo_part%%/*}"
              _is_repo_readme=1
              ;;
          esac
        fi
        ;;
    esac

    if [ "$_is_repo_readme" -eq 1 ] && [ -n "$_r_target_name" ]; then
      kl_resolve_repo_paths "$_r_target_name"
      ingest_repo_readme "$_r_target_name" "$_kl_repo_path" "$_readme_fname" "$_kl_repo_rel"
      _ingested_count=$((_ingested_count + 1))
      _ingested_paths="${_ingested_paths:+$_ingested_paths
}$_f_rel"
    else
      ingest_source_file "$_abs_file"
      _ingested_count=$((_ingested_count + 1))
      _ingested_paths="${_ingested_paths:+$_ingested_paths
}$_f_rel"
    fi
  done < "$_tmp_ingest_list"
  rm -f "$_tmp_ingest_list"
fi

# Append ingestion summary audit entry to _log.md
if [ "$_ingested_count" -gt 0 ] && [ -f "$_wiki_path/_log.md" ]; then
  cat >> "$_wiki_path/_log.md" <<BATCH_LOG_EOF

### Ingestion Run Summary — ${_today}
* **Total Files Ingested:** ${_ingested_count}
* **Ingested Sources:**
BATCH_LOG_EOF
  printf '%s\n' "$_ingested_paths" | while IFS= read -r _ip; do
    [ -n "$_ip" ] || continue
    printf "  - \`%s\`\n" "$_ip"
  done >> "$_wiki_path/_log.md"
fi

# Enforce ~500-word ceiling on hot.md
kl_condense_hot_cache "$_ingested_count"

[ "$_quiet" -eq 1 ] || printf '[WIKI] Ingest complete.\n'
exit 0
