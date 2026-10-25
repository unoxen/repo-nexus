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

  _s_base="$(basename "$_src_abs" .md)"
  _s_slug="$(printf '%s' "$_s_base" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -e 's/^-//' -e 's/-$//')"
  case "$_s_slug" in
    index|hot|_log) _s_slug="doc-${_s_slug}" ;;
  esac
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

# Ingest specified repo targets
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

# Ingest specified source targets
if [ -n "$_source_targets" ]; then
  while IFS= read -r _st || [ -n "$_st" ]; do
    [ -n "$_st" ] || continue
    case "$_st" in
      /*) _s_abs="$_st" ;;
      *)  _s_abs="$_root/$_st" ;;
    esac

    if [ -f "$_s_abs" ]; then
      ingest_source_file "$_s_abs"
    elif [ -d "$_s_abs" ]; then
      for _f in "$_s_abs"/*.md; do
        [ -f "$_f" ] || continue
        ingest_source_file "$_f"
      done
    else
      echo "Warning: Source target '$_st' not found" >&2
    fi
  done <<EOF_SOURCES
$_source_targets
EOF_SOURCES
fi

# If neither --repo nor --source specified, ingest all configured sources and enabled member repos
if [ -z "$_repo_targets" ] && [ -z "$_source_targets" ]; then
  # 1. Enabled member repositories
  for _rname in $(yaml_list_repos 2>/dev/null || true); do
    [ -n "$_rname" ] || continue
    yaml_repo_enabled "$_rname" 2>/dev/null || continue
    kl_resolve_repo_paths "$_rname"

    [ -d "$_kl_repo_path" ] || continue
    for _rm in README.md readme.md README.markdown README; do
      if [ -f "$_kl_repo_path/$_rm" ]; then
        ingest_repo_readme "$_rname" "$_kl_repo_path" "$_rm" "$_kl_repo_rel"
        break
      fi
    done
  done

  # 2. Configured intake directories
  if command -v plugin_source_dirs >/dev/null 2>&1; then
    for _sdir in $(plugin_source_dirs "karpathy-llm" 2>/dev/null || true); do
      [ -n "$_sdir" ] || continue
      case "$_sdir" in
        *'*'*|*'?'*|*'['*) continue ;;
      esac
      if [ -d "$_root/$_sdir" ]; then
        for _f in "$_root/$_sdir"/*.md; do
          [ -f "$_f" ] || continue
          ingest_source_file "$_f"
        done
      fi
    done
  fi
fi

# Enforce ~500-word ceiling on hot.md
kl_condense_hot_cache

[ "$_quiet" -eq 1 ] || printf '[WIKI] Ingest complete.\n'
exit 0
