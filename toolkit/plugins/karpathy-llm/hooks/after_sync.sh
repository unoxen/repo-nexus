#!/bin/sh
set -e

# Exit early if rnex utilities aren't available 
[ -z "$RNEX_ROOT" ] && { echo "Error: RNEX_ROOT not set"; exit 1; }

# Resolve root workspace
_root="$RNEX_ROOT"


# Helper to read plugin config
get_cfg() {
  _key="$1"; _def="$2"
  _val=""
  for _cfg in "$_root/.local.rnex.yaml" "$_root/rnex.yaml"; do
    [ -f "$_cfg" ] || continue
    _val="$(awk -v plugin="karpathy-llm" -v key="$_key" '
      /^[ \t]*plugins:[ \t]*(#.*)?$/ { in_plugins=1; in_target=0; plugin_indent=-1; next }
      in_plugins && /^[^ \t#]/ { in_plugins=0; in_target=0 }
      !in_plugins { next }
      {
        match($0, /^[ \t]*/)
        indent = RLENGTH
        trimmed = substr($0, indent + 1)
      }
      trimmed ~ /^([#]|$)/ { next }

      in_target && (indent <= plugin_indent) {
        in_target=0
      }

      !in_target {
        k = trimmed
        sub(/:.*/, "", k)
        gsub(/^["\047]|["\047]$/, "", k)
        gsub(/[[:space:]]/, "", k)
        if (k == plugin && trimmed ~ /:[ \t]*(#.*)?$/) {
          in_target=1
          plugin_indent=indent
          next
        }
      }

      in_target && (indent > plugin_indent) {
        k = trimmed
        sub(/:.*/, "", k)
        gsub(/^["\047]|["\047]$/, "", k)
        gsub(/[[:space:]]/, "", k)
        if (k == key && trimmed ~ /:[ \t]*/) {
          val = trimmed
          sub(/^[^:]*:[ \t]*/, "", val)
          if (val ~ /^"[^"]*"/) {
            match(val, /^"[^"]*"/)
            val = substr(val, 2, RLENGTH - 2)
          } else if (val ~ /^\047[^\047]*\047/) {
            match(val, /^\047[^\047]*\047/)
            val = substr(val, 2, RLENGTH - 2)
          } else {
            sub(/[ \t]*#.*$/, "", val)
            sub(/[ \t]+$/, "", val)
          }
          print val
          exit
        }
      }
    ' "$_cfg")"
    [ -n "$_val" ] && break
  done
  [ -n "$_val" ] && printf '%s' "$_val" || printf '%s' "$_def"
}

_wiki="$(get_cfg "wiki_dir" ".rnex/wiki")"
_raw="$(get_cfg "raw_dir" "./docs")"
_ingest_readmes="$(get_cfg "ingest_member_readmes" "true")"

# Clean relative paths
_wiki="$(printf '%s' "$_wiki" | sed -e 's#^/##' -e 's#/$##')"
_raw="$(printf '%s' "$_raw" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"

_wiki_path="$_root/$_wiki"
_raw_path="$_root/$_raw"

mkdir -p "$_wiki_path" "$_raw_path"
[ -f "$_raw_path/.gitkeep" ] || touch "$_raw_path/.gitkeep"

# Clean up obsolete leaked root ./raw and ./wiki directories if non-default paths are configured
if [ "$_raw" != "raw" ] && [ -d "$_root/raw" ]; then
  if ! rmdir "$_root/raw" 2>/dev/null; then
    _clean_raw_leak=1
    for _rf in "$_root/raw"/* "$_root/raw"/.[!.]* "$_root/raw"/..?*; do
      [ -e "$_rf" ] || continue
      _rf_base="$(basename "$_rf")"
      if [ "$_rf_base" = ".gitkeep" ]; then
        continue
      fi
      if [ -f "$_raw_path/$_rf_base" ] && cmp -s "$_rf" "$_raw_path/$_rf_base"; then
        continue
      fi
      _clean_raw_leak=0
      break
    done
    if [ "$_clean_raw_leak" -eq 1 ]; then
      rm -rf "$_root/raw" 2>/dev/null || true
    fi
  fi
fi

if [ "$_wiki" != "wiki" ] && [ -d "$_root/wiki" ]; then
  if ! rmdir "$_root/wiki" 2>/dev/null; then
    _clean_wiki_leak=1
    for _wf in "$_root/wiki"/* "$_root/wiki"/.[!.]* "$_root/wiki"/..?*; do
      [ -e "$_wf" ] || continue
      _wf_base="$(basename "$_wf")"
      case "$_wf_base" in
        index.md|_log.md|hot.md|.gitkeep)
          continue
          ;;
        *)
          if [ -f "$_wiki_path/$_wf_base" ] && cmp -s "$_wf" "$_wiki_path/$_wf_base"; then
            continue
          fi
          _clean_wiki_leak=0
          break
          ;;
      esac
    done
    if [ "$_clean_wiki_leak" -eq 1 ]; then
      rm -rf "$_root/wiki" 2>/dev/null || true
    fi
  fi
fi

# Clean up legacy staging directory only if empty or positively verified as managed duplicate copies
if [ -d "$_wiki_path/raw" ]; then
  if ! rmdir "$_wiki_path/raw" 2>/dev/null; then
    _has_user_content=0
    for _rf in "$_wiki_path/raw"/* "$_wiki_path/raw"/.[!.]* "$_wiki_path/raw"/..?*; do
      [ -e "$_rf" ] || continue
      _rname="$(basename "$_rf")"
      case "$_rname" in
        README_*.md)
          _rrepo="${_rname#README_}"
          _rrepo="${_rrepo%.md}"
          if [ -f "$_root/repos/$_rrepo/README.md" ] && cmp -s "$_rf" "$_root/repos/$_rrepo/README.md"; then
            continue
          fi
          _has_user_content=1
          break
          ;;
        *)
          if [ -f "$_raw_path/$_rname" ] && cmp -s "$_rf" "$_raw_path/$_rname"; then
            continue
          fi
          _has_user_content=1
          break
          ;;
      esac
    done

    if [ "$_has_user_content" -eq 0 ]; then
      rm -rf "${_wiki_path:?}/raw" 2>/dev/null || true
    else
      printf '[WIKI] Warning: %s/raw contains custom or uncommitted files. Preserving directory without deletion.\n' "$_wiki"
    fi
  fi
fi

# 1. Register plugin User Skills via contract helper (with plugin name prefix)
if ! command -v rnex_register_user_skill >/dev/null 2>&1 && ! command -v rnex_generate_user_skill >/dev/null 2>&1; then
  if [ -f "$RNEX_ROOT/.rnex/bin/rnex-env.sh" ]; then
    . "$RNEX_ROOT/.rnex/bin/rnex-env.sh"
  fi
fi

# Clean up stale unprefixed skills
if command -v rnex_unregister_user_skill >/dev/null 2>&1; then
  rnex_unregister_user_skill "wiki-ingest"
  rnex_unregister_user_skill "wiki-lint"
fi

_reg_fn=""
if command -v rnex_generate_user_skill >/dev/null 2>&1; then
  _reg_fn="rnex_generate_user_skill"
elif command -v rnex_register_user_skill >/dev/null 2>&1; then
  _reg_fn="rnex_register_user_skill"
fi

if [ -n "$_reg_fn" ]; then
  for skill_file in "$RNEX_ROOT/.rnex/plugins/karpathy-llm/skills"/*.md; do
    [ -f "$skill_file" ] || continue
    skill_name=$(basename "$skill_file" .md)
    "$_reg_fn" "$skill_name" ".rnex/plugins/karpathy-llm/skills/${skill_name}.md" "karpathy-llm"
  done
fi


# Ingest member repository README into atomic wiki page, index, and hot cache
ingest_member_readme() {
  _m_repo="$1"
  _m_path="$2"
  _m_readme="$3"
  _m_rel_prefix="$4"
  _src_file="$_m_path/$_m_readme"
  _target_page="$_wiki_path/repo-${_m_repo}.md"
  _today="$(date +%Y-%m-%d 2>/dev/null || date +%F 2>/dev/null || echo "2026-10-15")"

  [ -f "$_src_file" ] || return 0

  # Clean relative paths for source references
  _clean_repos="$(printf '%s' "$REPOS_DIR" | sed -e 's#^[[:space:]]*##' -e 's#[[:space:]]*$##' -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
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

    # Append to Operation Log (_log.md)
    if [ -f "$_wiki_path/_log.md" ]; then
      cat >> "$_wiki_path/_log.md" <<LOG_EOF

### Member Repo Ingest: ${_m_repo} — ${_today}
* **Source:** \`${_rel_source}\`
* **Ingested Page:** \`repo-${_m_repo}.md\`
* **Status:** Ingested atomic member repository page into wiki index and hot cache.
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

# 2. Automatically ingest README.md from all registered/enabled member repositories
case "$(printf '%s' "$_ingest_readmes" | tr '[:upper:]' '[:lower:]')" in
  false|no|0|disabled|off) _skip_all_readmes=1 ;;
  *) _skip_all_readmes=0 ;;
esac

_rd=""
for _cfg in "$_root/.local.rnex.yaml" "$_root/rnex.yaml"; do
  [ -f "$_cfg" ] || continue
  _val="$(awk '
    /^[[:space:]]*repos_dir:[ ]*/ {
      sub(/^[[:space:]]*repos_dir:[ ]*/, "")
      sub(/[ ]*#.*/, "")
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      gsub(/^["\047]|["\047]$/, "")
      val=$0
    }
    END { if (val) print val }
  ' "$_cfg")"
  if [ -n "$_val" ]; then
    _rd="$_val"
    break
  fi
done
REPOS_DIR="${_rd:-./repos}"
_clean_repos="$(printf '%s' "$REPOS_DIR" | sed -e 's#^[[:space:]]*##' -e 's#[[:space:]]*$##' -e 's#^\./##' -e 's#^/##' -e 's#/$##')"

list_configured_repos() {
  for _cfg_file in "$_root/.local.rnex.yaml" "$_root/rnex.yaml"; do
    [ -f "$_cfg_file" ] || continue
    awk '
      /^repos:[ ]*$/ || /^repos:[ ]*#/ { r=1; next }
      r && /^[^ #]/ { r=0 }
      r && /^  [a-zA-Z0-9_.-]+:[ ]*(\{\})?[ ]*(#.*)?$/ {
        line = $0
        sub(/^[ ]*/, "", line)
        sub(/:.*/, "", line)
        gsub(/[[:space:]]/, "", line)
        if (length(line) > 0) print line
      }
    ' "$_cfg_file"
  done | awk '!seen[$0]++'
}

_ALL_INGESTED_REPOS=""
_ALL_INGESTED_COUNT=0

if [ "$_skip_all_readmes" -ne 1 ]; then
  for repo_name in $(list_configured_repos); do
    [ -n "$repo_name" ] || continue
    _custom_path=""
    
    # Check if this repository is explicitly disabled in .local.rnex.yaml or rnex.yaml (block-scoped)
    _is_disabled=""
    _repo_ingest=""
    for _cfg_file in "$RNEX_ROOT/.local.rnex.yaml" "$RNEX_ROOT/rnex.yaml"; do
      [ -f "$_cfg_file" ] || continue
      _en="$(awk -v repo="$repo_name" '
        /^repos:[ ]*$/ || /^repos:[ ]*#/ { r=1; next }
        r && /^[^ #]/ { r=0 }
        r && match($0, "^  " repo ":[ ]*(\\{\\})?[ ]*(#.*)?$") { in_target=1; next }
        in_target && /^  [^ #]/ { in_target=0 }
        in_target && match($0, "^    enabled:[ ]*") {
          line = $0
          sub("^    enabled:[ ]*", "", line)
          sub(/[ ]*#.*$/, "", line)
          gsub(/^["\047]|["\047]$/, "", line)
          print line
          exit
        }
      ' "$_cfg_file")"
      if [ -n "$_en" ] && [ -z "$_is_disabled" ]; then
        case "$(printf '%s' "$_en" | tr '[:upper:]' '[:lower:]')" in
          false|no|0|disabled|off) _is_disabled=1 ;;
          *) _is_disabled=0 ;;
        esac
      fi

      _ingest_val="$(awk -v repo="$repo_name" '
        /^repos:[ ]*$/ || /^repos:[ ]*#/ { r=1; next }
        r && /^[^ #]/ { r=0 }
        r && match($0, "^  " repo ":[ ]*(\\{\\})?[ ]*(#.*)?$") { in_target=1; next }
        in_target && /^  [^ #]/ { in_target=0 }
        in_target && match($0, "^    ingest_member_readmes:[ ]*") {
          line = $0
          sub("^    ingest_member_readmes:[ ]*", "", line)
          sub(/[ ]*#.*$/, "", line)
          gsub(/^["\047]|["\047]$/, "", line)
          print line
          exit
        }
      ' "$_cfg_file")"
      if [ -n "$_ingest_val" ] && [ -z "$_repo_ingest" ]; then
        case "$(printf '%s' "$_ingest_val" | tr '[:upper:]' '[:lower:]')" in
          false|no|0|disabled|off) _repo_ingest=0 ;;
          *) _repo_ingest=1 ;;
        esac
      fi

      if [ -z "$_custom_path" ]; then
        _cp="$(awk -v repo="$repo_name" '
          /^repos:[ ]*$/ || /^repos:[ ]*#/ { r=1; next }
          r && /^[^ #]/ { r=0 }
          r && match($0, "^  " repo ":[ ]*(\\{\\})?[ ]*(#.*)?$") { in_target=1; next }
          in_target && (/^[ ]{1,2}[^ #]/ || /^[^ #]/) { in_target=0 }
          in_target && match($0, "^    path:[ ]*") {
            line = $0
            sub("^    path:[ ]*", "", line)
            sub(/[ ]*#.*$/, "", line)
            gsub(/^["\047]|["\047]$/, "", line)
            print line
            exit
          }
        ' "$_cfg_file")"
        [ -n "$_cp" ] && _custom_path="$_cp"
      fi
    done
    [ "$_is_disabled" = "1" ] && continue
    [ "$_repo_ingest" = "0" ] && continue

    # Resolve physical repository path and relative location
    _repo_rel=""
    if [ -n "$_custom_path" ]; then
      case "$_custom_path" in
        /*)
          repo_path="$_custom_path"
          case "$_custom_path" in
            "$_root"/*) _repo_rel="${_custom_path#"$_root"/}" ;;
            *) _repo_rel="$_custom_path" ;;
          esac
          ;;
        *)
          repo_path="$_root/$_custom_path"
          _repo_rel="$_custom_path"
          ;;
      esac
    else
      repo_path="$_root/$REPOS_DIR/$repo_name"
      _repo_rel="${_clean_repos}/${repo_name}"
    fi

    [ -d "$repo_path" ] || continue

    # Read and ingest any README file directly in-place (no staging copy)
    for readme_name in README.md readme.md README.markdown README; do
      if [ -f "$repo_path/$readme_name" ]; then
        ingest_member_readme "$repo_name" "$repo_path" "$readme_name" "$_repo_rel"
        _ALL_INGESTED_REPOS="${_ALL_INGESTED_REPOS:+$_ALL_INGESTED_REPOS, }$repo_name"
        _ALL_INGESTED_COUNT=$((_ALL_INGESTED_COUNT + 1))
        break
      fi
    done
  done
fi

# 3. Enforce strict ~500-word ceiling on hot.md (condense Section 1 if needed)
if [ -f "$_wiki_path/hot.md" ]; then
  _hot_words="$(wc -w < "$_wiki_path/hot.md" 2>/dev/null || echo 0)"
  if [ "$_hot_words" -gt 480 ]; then
    _num_repos="$(grep -cE '^\* \*\*[a-zA-Z0-9_.-]+ \(`?'"$_clean_repos"'/' "$_wiki_path/hot.md" 2>/dev/null || echo 0)"
    if [ "$_ALL_INGESTED_COUNT" -gt 3 ]; then
      _condense_count="$_ALL_INGESTED_COUNT"
      _repo_names="$_ALL_INGESTED_REPOS"
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
fi

