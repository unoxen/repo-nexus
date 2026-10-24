#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/karpathy-llm/commands/ingest.sh — Karpathy LLM Wiki Ingest
#
# Syntax: rnex plugin karpathy-llm ingest [--source <path>] [--repo <name>] [--quiet]
# ============================================================================
set -e

_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
RNEX_ROOT="$_root"
NEXUS_DIR="$_root"
WORKSPACE_YAML="${WORKSPACE_YAML:-$_root/rnex.yaml}"
WORKSPACE_LOCAL_YAML="${WORKSPACE_LOCAL_YAML:-$_root/.local.rnex.yaml}"
export RNEX_ROOT NEXUS_DIR WORKSPACE_YAML WORKSPACE_LOCAL_YAML

# Load core/yaml/plugins libraries if not already loaded
if ! command -v yaml_plugin_get >/dev/null 2>&1; then
  _cand_dirs="${RNEX_LIB_DIR:-} $_root/lib $(dirname "$0")/../../../../lib"
  for _cand in $_cand_dirs; do
    if [ -n "$_cand" ] && [ -f "$_cand/yaml.sh" ]; then
      RNEX_LIB_DIR="$(cd "$_cand" 2>/dev/null && pwd -P)"
      export RNEX_LIB_DIR
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/core.sh" 2>/dev/null || true
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/yaml.sh" 2>/dev/null || true
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/plugins.sh" 2>/dev/null || true
      break
    fi
  done
fi

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

# Resolve configured wiki directory
_wiki="$(yaml_plugin_get "karpathy-llm" "wiki_dir" 2>/dev/null || true)"
[ -n "$_wiki" ] || _wiki="wiki"
_wiki="$(printf '%s' "$_wiki" | sed -e 's#^/##' -e 's#/$##')"
_wiki_path="$_root/$_wiki"
mkdir -p "$_wiki_path"

REPOS_DIR="$(yaml_get_top_level "repos_dir" "./repos")"
_clean_repos="$(printf '%s' "$REPOS_DIR" | sed -e 's#^[[:space:]]*##' -e 's#[[:space:]]*$##' -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
[ -n "$_clean_repos" ] || _clean_repos="repos"

_today="$(date +%Y-%m-%d 2>/dev/null || date +%F 2>/dev/null || echo "2026-10-15")"

# Ensure baseline control files exist in wiki directory
if [ ! -f "$_wiki_path/index.md" ]; then
  cat > "$_wiki_path/index.md" <<INDEX_INIT
---
title: Wiki Index
last_updated: ${_today}
---

# Wiki Index

Master navigation index for the Karpathy LLM Wiki.

## Overview & Status
* **Rolling Cache:** [\`hot.md\`](./hot.md) — Fast ~500-word orientation cache.
* **Operation Log:** [\`_log.md\`](./_log.md) — Timestamped ingest & maintenance history.

## Member Repositories

## Architecture & Concepts

INDEX_INIT
fi

if [ ! -f "$_wiki_path/hot.md" ]; then
  cat > "$_wiki_path/hot.md" <<HOT_INIT
# Hot Context (Rolling ~500-Word Cache)

> Fast orientation cache for AI agents. Strictly bounded under ~500 words.

## 1. Architecture & Member Repo Map
* **Workspace Overview:** Karpathy LLM Wiki active.

## 2. Current Focus & Recent Ingests
* **Active Tasks:** Ingest operations active.

## 3. Key Contracts & Boundaries
* **Atomic Pages:** Curated pages with typed frontmatter relations under \`${_wiki}/\`.
HOT_INIT
fi

if [ ! -f "$_wiki_path/_log.md" ]; then
  cat > "$_wiki_path/_log.md" <<LOG_INIT
# Karpathy Wiki Operation Log

Append-only audit trail recording all ingest and maintenance runs.

---
LOG_INIT
fi

# Ingest member repository README
ingest_repo_readme() {
  _m_repo="$1"
  _m_path="$2"
  _m_readme="$3"
  _m_rel_prefix="$4"
  _src_file="$_m_path/$_m_readme"
  _target_page="$_wiki_path/repo-${_m_repo}.md"

  [ -f "$_src_file" ] || return 0

  if [ -n "$_m_rel_prefix" ]; then
    _clean_rel="$(printf '%s' "$_m_rel_prefix" | sed -e 's#^[[:space:]]*##' -e 's#[[:space:]]*$##' -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
    _rel_source="${_clean_rel}/${_m_readme}"
    _rel_loc="${_clean_rel}/"
  else
    _rel_source="${_clean_repos}/${_m_repo}/${_m_readme}"
    _rel_loc="${_clean_repos}/${_m_repo}/"
  fi

  # Title
  _m_title="$(awk '
    /^#[^#]/ {
      sub(/^#[ ]*/, "")
      sub(/[ ]*$/, "")
      print
      exit
    }
  ' "$_src_file")"
  [ -z "$_m_title" ] && _m_title="Member Repo: ${_m_repo}"

  # Summary
  _m_summary="$(awk '
    NR == 1 && /^#[^#]/ { next }
    /^[ ]*(\[!\[|<img|<!--|---|```)/ { next }
    /^#/ { next }
    NF > 0 {
      gsub(/^[ ]+|[ ]+$/, "")
      print
      exit
    }
  ' "$_src_file")"
  [ -z "$_m_summary" ] && _m_summary="Core architecture, contracts, and implementation for member repository ${_m_repo}."

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

  # Write or update target page
  if [ ! -f "$_target_page" ]; then
    cat > "$_target_page" <<PAGE_EOF
---
title: "Member Repo: ${_m_repo}"
tags: [member-repo, ${_m_repo}]
last_updated: ${_today}
sources: ["${_rel_source}"]
related: ${_nav_related}
extends: ${_nav_extends}
contradicts: []
mentioned_in: ["index.md", "hot.md"]
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
  fi

  # Log operation
  cat >> "$_wiki_path/_log.md" <<LOG_EOF

### Member Repo Ingest: ${_m_repo} — ${_today}
* **Source:** \`${_rel_source}\`
* **Ingested Page:** \`repo-${_m_repo}.md\`
* **Status:** Ingested atomic member repository page into wiki index and hot cache.
LOG_EOF

  # Update index.md
  if ! grep -q "repo-${_m_repo}\.md" "$_wiki_path/index.md"; then
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
    else
      printf '\n## Member Repositories\n%s\n' "$_idx_line" >> "$_wiki_path/index.md"
    fi
  fi

  # Update hot.md
  _is_in_hot=0
  if grep -q "${_rel_loc}" "$_wiki_path/hot.md" 2>/dev/null; then
    _is_in_hot=1
  elif grep -E -q "^\* \*\*Member Repositories \([0-9]+ repos\):.*[ :]${_m_repo}(,|\.|$)" "$_wiki_path/hot.md" 2>/dev/null; then
    _is_in_hot=1
  fi

  if [ "$_is_in_hot" -eq 0 ]; then
    _hot_summary="$(printf '%s' "$_m_summary" | sed -e 's/[.?!][[:space:]].*//' -e 's/[.?!]$//' | awk '{
      out=""
      for (i=1; i<=NF && i<=7; i++) {
        out = (out == "") ? $i : out " " $i
      }
      print out
    }')"
    [ -z "$_hot_summary" ] && _hot_summary="Member repository"
    _hot_line="* **${_m_repo} (\`${_rel_loc}\`):** ${_hot_summary}."
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

  [ "$_quiet" -eq 1 ] || printf '[WIKI] Ingested member repository: %s\n' "$_m_repo"
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
    _r_path=""
    _r_rel=""
    _cpath="$(yaml_get "$_rt" "path" 2>/dev/null || true)"
    if [ -n "$_cpath" ]; then
      case "$_cpath" in
        /*) _r_path="$_cpath"; _r_rel="$_cpath" ;;
        *)  _r_path="$_root/$_cpath"; _r_rel="$_cpath" ;;
      esac
    else
      _r_path="$_root/$_clean_repos/$_rt"
      _r_rel="${_clean_repos}/${_rt}"
    fi

    if [ ! -d "$_r_path" ]; then
      echo "Warning: Repository '$_rt' directory not found at '$_r_path'" >&2
      continue
    fi

    _found_readme=0
    for _rm in README.md readme.md README.markdown README; do
      if [ -f "$_r_path/$_rm" ]; then
        ingest_repo_readme "$_rt" "$_r_path" "$_rm" "$_r_rel"
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

    _cpath="$(yaml_get "$_rname" "path" 2>/dev/null || true)"
    if [ -n "$_cpath" ]; then
      case "$_cpath" in
        /*) _r_path="$_cpath"; _r_rel="$_cpath" ;;
        *)  _r_path="$_root/$_cpath"; _r_rel="$_cpath" ;;
      esac
    else
      _r_path="$_root/$_clean_repos/$_rname"
      _r_rel="${_clean_repos}/${_rname}"
    fi

    [ -d "$_r_path" ] || continue
    for _rm in README.md readme.md README.markdown README; do
      if [ -f "$_r_path/$_rm" ]; then
        ingest_repo_readme "$_rname" "$_r_path" "$_rm" "$_r_rel"
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
if [ -f "$_wiki_path/hot.md" ]; then
  _hot_words="$(wc -w < "$_wiki_path/hot.md" 2>/dev/null || echo 0)"
  if [ "$_hot_words" -gt 480 ]; then
    _num_repos="$(grep -cE '^\* \*\*[a-zA-Z0-9_.-]+ \(`?'"$_clean_repos"'/' "$_wiki_path/hot.md" 2>/dev/null || echo 0)"
    if [ "$_num_repos" -gt 3 ]; then
      _repo_names="$(grep -E '^\* \*\*[a-zA-Z0-9_.-]+ \(`?'"$_clean_repos"'/' "$_wiki_path/hot.md" | sed -e 's/^\* \*\*//' -e 's/ .*//' | tr '\n' ', ' | sed -e 's/, $//')"
      _tmp_b="$(mktemp)"
      if awk -v rnames="$_repo_names" -v nrepos="$_num_repos" -v rdir="$_clean_repos" '
        BEGIN { in_s1=0; replaced=0 }
        /^## 1\. Architecture & Member Repo Map/ { in_s1=1; print; next }
        in_s1 && /^## / { in_s1=0 }
        in_s1 && (/^\* \*\*[a-zA-Z0-9_.-]+ \(`?[^\/]+\// || /^\* \*\*Member Repositories \([0-9]+ repos\):/) {
          if (!replaced) {
            print "* **Member Repositories (" nrepos " repos):** Autonomous repositories under `" rdir "/`: " rnames ". See [Wiki Index](./index.md#member-repositories) for individual architecture pages."
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
fi

[ "$_quiet" -eq 1 ] || printf '[WIKI] Ingest complete.\n'
exit 0
