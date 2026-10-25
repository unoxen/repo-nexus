#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/karpathy-llm/hooks/_common.sh — Shared Karpathy Wiki Hook Bootstrap
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

_wiki="$(get_cfg "wiki_dir" "wiki")"
_wiki="$(printf '%s' "$_wiki" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
[ -n "$_wiki" ] || _wiki="wiki"
_wiki_path="$_root/$_wiki"

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

# Ensure the configured wiki directory and baseline control files (index.md, hot.md, _log.md) exist.
kl_ensure_wiki_files() {
  mkdir -p "$_wiki_path"
  _kew_pdir=""
  if command -v find_plugin_dir >/dev/null 2>&1; then
    _kew_pdir="$(find_plugin_dir "karpathy-llm" 2>/dev/null || true)"
  fi
  if [ -z "$_kew_pdir" ]; then
    for _kew_cand in "$_root/.rnex/plugins/karpathy-llm" "$_root/toolkit/plugins/karpathy-llm"; do
      if [ -d "$_kew_cand/templates" ]; then
        _kew_pdir="$_kew_cand"
        break
      fi
    done
  fi

  for _kew_f in index.md hot.md _log.md; do
    if [ ! -f "$_wiki_path/$_kew_f" ]; then
      if [ -n "$_kew_pdir" ] && [ -f "$_kew_pdir/templates/$_kew_f" ] && command -v plugin_instantiate_template >/dev/null 2>&1; then
        plugin_instantiate_template "karpathy-llm" "$_kew_pdir" "$_kew_pdir/templates/$_kew_f" "$_wiki_path/$_kew_f"
      elif [ -n "$_kew_pdir" ] && [ -f "$_kew_pdir/templates/$_kew_f" ]; then
        sed -e "s|{wiki_dir}|$_wiki|g" -e "s|{raw_dir}|$_raw|g" -e "s|{sources}|\`$_raw/\`|g" "$_kew_pdir/templates/$_kew_f" > "$_wiki_path/$_kew_f"
      fi
    fi
  done

  _kew_today="$(date +%Y-%m-%d 2>/dev/null || date +%F 2>/dev/null || echo "2026-10-15")"
  if [ ! -f "$_wiki_path/index.md" ]; then
    cat > "$_wiki_path/index.md" <<INDEX_INIT
---
title: Wiki Index
last_updated: ${_kew_today}
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
  _today="$(date +%Y-%m-%d 2>/dev/null || date +%F 2>/dev/null || echo "2026-10-15")"

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

  # 2. Parse repository summary (first non-header, non-badge, non-comment line)
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

  if { [ "$_needs_gen" -eq 1 ] || [ "$_m_force_log" -eq 1 ]; } && [ -f "$_wiki_path/_log.md" ]; then
    cat >> "$_wiki_path/_log.md" <<LOG_EOF

### Member Repo Ingest: ${_m_repo} — ${_today}
* **Source:** \`${_rel_source}\`
* **Ingested Page:** \`repo-${_m_repo}.md\`
* **Status:** Ingested atomic member repository page into wiki index and hot cache.
LOG_EOF
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

  # 5. Register in hot cache (hot.md) under Section 1 if not already present
  _is_in_hot=0
  if grep -q "${_rel_loc}" "$_wiki_path/hot.md" 2>/dev/null; then
    _is_in_hot=1
  elif grep -E -q "^\* \*\*Member Repositories \([0-9]+ repos\):.*[ :]${_m_repo}(,|\.|$)" "$_wiki_path/hot.md" 2>/dev/null; then
    _is_in_hot=1
  fi

  if [ -f "$_wiki_path/hot.md" ] && [ "$_is_in_hot" -eq 0 ]; then
    # Ultra-concise summary for bounded hot cache (~500-word ceiling)
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
}

# Enforce strict ~500-word ceiling on hot.md by condensing Section 1 when needed.
# Usage: kl_condense_hot_cache [ingested_count] [ingested_repos_csv]
kl_condense_hot_cache() {
  _khc_ingested_cnt="${1:-0}"
  _khc_ingested_repos="${2:-}"
  [ -f "$_wiki_path/hot.md" ] || return 0

  _hot_words="$(wc -w < "$_wiki_path/hot.md" 2>/dev/null || echo 0)"
  if [ "$_hot_words" -gt 480 ]; then
    _num_repos="$(grep -cE '^\* \*\*[a-zA-Z0-9_.-]+ \(`?'"$_clean_repos"'/' "$_wiki_path/hot.md" 2>/dev/null || echo 0)"
    if [ "$_khc_ingested_cnt" -gt 3 ]; then
      _condense_count="$_khc_ingested_cnt"
      _repo_names="$_khc_ingested_repos"
    elif [ "$_num_repos" -gt 3 ]; then
      _condense_count="$_num_repos"
      _repo_names="$(grep -E '^\* \*\*[a-zA-Z0-9_.-]+ \(`?'"$_clean_repos"'/' "$_wiki_path/hot.md" | sed -e 's/^\* \*\*//' -e 's/ .*//' | tr '\n' ', ' | sed -e 's/, $//')"
    else
      _condense_count=0
      _repo_names=""
    fi

    if [ "$_condense_count" -gt 3 ]; then
      _tmp_b="$(mktemp)"
      if awk -v rnames="$_repo_names" -v nrepos="$_condense_count" -v rdir="$_clean_repos" '
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
}
