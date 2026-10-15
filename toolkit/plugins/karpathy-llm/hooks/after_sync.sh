#!/bin/sh
set -e

# Exit early if rnex utilities aren't available 
[ -z "$RNEX_ROOT" ] && { echo "Error: RNEX_ROOT not set"; exit 1; }

# Resolve root workspace
_root="$RNEX_ROOT"

# Target directory inside .rnex/ (the internal wiki's Raw intake state)
WIKI_RAW_DIR="$RNEX_ROOT/.rnex/wiki/raw"
mkdir -p "$WIKI_RAW_DIR"

# Helper to read plugin config
get_cfg() {
  _key="$1"; _def="$2"
  _val=""
  if [ -f "$_root/.local.rnex.yaml" ]; then
    _val="$(awk -v k="$_key" '
      /^plugins:/ { in_p=1; next }
      in_p && /^[ ]*karpathy-llm:/ { in_k=1; next }
      in_k && /^[^ ]/ { exit }
      in_k && $0 ~ ("^[ ]*" k ":") {
        sub("^[ ]*" k ":[ ]*", "")
        sub(/[ ]*#.*/, "")
        gsub(/["\047]/, "")
        print
        exit
      }
    ' "$_root/.local.rnex.yaml")"
  fi
  if [ -z "$_val" ] && [ -f "$_root/rnex.yaml" ]; then
    _val="$(awk -v k="$_key" '
      /^plugins:/ { in_p=1; next }
      in_p && /^[ ]*karpathy-llm:/ { in_k=1; next }
      in_k && /^[^ ]/ { exit }
      in_k && $0 ~ ("^[ ]*" k ":") {
        sub("^[ ]*" k ":[ ]*", "")
        sub(/[ ]*#.*/, "")
        gsub(/["\047]/, "")
        print
        exit
      }
    ' "$_root/rnex.yaml")"
  fi
  [ -n "$_val" ] && printf '%s' "$_val" || printf '%s' "$_def"
}

_wiki="$(get_cfg "wiki_dir" ".rnex/wiki")"
_raw="$(get_cfg "raw_dir" "./docs")"

# Clean relative paths
_wiki="$(printf '%s' "$_wiki" | sed -e 's#^/##' -e 's#/$##')"
_raw="$(printf '%s' "$_raw" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"

_wiki_path="$_root/$_wiki"
_raw_path="$_root/$_raw"

mkdir -p "$_wiki_path" "$_raw_path"
[ -f "$_raw_path/.gitkeep" ] || touch "$_raw_path/.gitkeep"

_pdir="${RNEX_PLUGIN_DIR:-$_root/.rnex/plugins/karpathy-llm}"
if [ ! -d "$_pdir/templates" ] && [ -d "$_root/toolkit/plugins/karpathy-llm/templates" ]; then
  _tmpl_dir="$_root/toolkit/plugins/karpathy-llm/templates"
else
  _tmpl_dir="$_pdir/templates"
fi

if [ -f "$_tmpl_dir/index.md" ] && [ ! -f "$_wiki_path/index.md" ]; then
  sed -e "s|{wiki_dir}|$_wiki|g" -e "s|{raw_dir}|$_raw|g" "$_tmpl_dir/index.md" > "$_wiki_path/index.md"
fi
if [ -f "$_tmpl_dir/hot.md" ] && [ ! -f "$_wiki_path/hot.md" ]; then
  sed -e "s|{wiki_dir}|$_wiki|g" -e "s|{raw_dir}|$_raw|g" "$_tmpl_dir/hot.md" > "$_wiki_path/hot.md"
fi
if [ -f "$_tmpl_dir/_log.md" ] && [ ! -f "$_wiki_path/_log.md" ]; then
  sed -e "s|{wiki_dir}|$_wiki|g" -e "s|{raw_dir}|$_raw|g" "$_tmpl_dir/_log.md" > "$_wiki_path/_log.md"
fi

# Ensure template in .rnex/plugins/karpathy-llm/templates
mkdir -p "$_pdir/templates"
if [ -f "$_tmpl_dir/rnex-wiki-page.sample.md" ] && [ ! -f "$_pdir/templates/rnex-wiki-page.template.md" ]; then
  cp "$_tmpl_dir/rnex-wiki-page.sample.md" "$_pdir/templates/rnex-wiki-page.template.md"
fi

# 1. Copy plugin rules and skills into scoped runtime directory
mkdir -p "$RNEX_ROOT/.rnex/plugins/karpathy-llm/rules" "$RNEX_ROOT/.rnex/plugins/karpathy-llm/skills"
_src_k_rules=""
_src_k_skills=""
for _base in "$RNEX_PLUGIN_DIR" "$RNEX_ROOT/toolkit/plugins/karpathy-llm"; do
  [ -d "$_base/rules" ] && [ -z "$_src_k_rules" ] && _src_k_rules="$_base/rules"
  [ -d "$_base/skills" ] && [ -z "$_src_k_skills" ] && _src_k_skills="$_base/skills"
done
if [ -n "$_src_k_rules" ] && [ "$_src_k_rules" != "$RNEX_ROOT/.rnex/plugins/karpathy-llm/rules" ]; then
  cp -R "$_src_k_rules"/. "$RNEX_ROOT/.rnex/plugins/karpathy-llm/rules"/ 2>/dev/null || true
fi
if [ -n "$_src_k_skills" ] && [ "$_src_k_skills" != "$RNEX_ROOT/.rnex/plugins/karpathy-llm/skills" ]; then
  cp -R "$_src_k_skills"/. "$RNEX_ROOT/.rnex/plugins/karpathy-llm/skills"/ 2>/dev/null || true
fi

# 2. Register plugin User Skills via contract helper
if ! command -v rnex_register_user_skill >/dev/null 2>&1; then
  if [ -f "$RNEX_ROOT/.rnex/bin/rnex-env.sh" ]; then
    . "$RNEX_ROOT/.rnex/bin/rnex-env.sh"
  fi
fi

if command -v rnex_register_user_skill >/dev/null 2>&1; then
  for skill_file in "$RNEX_ROOT/.rnex/plugins/karpathy-llm/skills"/*.md; do
    [ -f "$skill_file" ] || continue
    skill_name=$(basename "$skill_file" .md)
    rnex_register_user_skill "$skill_name" ".rnex/plugins/karpathy-llm/skills/${skill_name}.md"
  done
fi

# 3. Append instructions to .rnex/ai-instructions.md
_instr_src=""
for _cand in "$RNEX_PLUGIN_DIR/instructions.md" "$RNEX_ROOT/toolkit/plugins/karpathy-llm/instructions.md"; do
  if [ -f "$_cand" ]; then
    _instr_src="$_cand"
    break
  fi
done

if [ -n "$_instr_src" ] && [ -f "$RNEX_ROOT/.rnex/ai-instructions.md" ]; then
  if ! grep -q "Karpathy LLM Wiki Knowledge Architecture" "$RNEX_ROOT/.rnex/ai-instructions.md" 2>/dev/null; then
    printf '\n\n' >> "$RNEX_ROOT/.rnex/ai-instructions.md"
    cat "$_instr_src" >> "$RNEX_ROOT/.rnex/ai-instructions.md"
  fi
fi

# 4. Parse 'raw_dir' configuration from rnex.yaml/.local.rnex.yaml (Defaults to './docs')
# We check if parsed in RNEX_CONFIG_MERGED (YAML) using a standard grep/sed lookup
RAW_DIR_VAL=$(grep -h -E '^\s*raw_dir:' "$RNEX_ROOT/rnex.yaml" "$RNEX_ROOT/.local.rnex.yaml" 2>/dev/null | tail -n1 | awk -F: '{print $NF}' | awk '{print $1}' | tr -d '"'\''')
[ -z "$RAW_DIR_VAL" ] && RAW_DIR_VAL="$(get_cfg "raw_dir" "./docs")"
RAW_DIR="${RAW_DIR_VAL:-./docs}"

# Clear and sync custom local raw folder files to raw intake (skip if RAW_DIR is a documentation site)
if [ -d "$RNEX_ROOT/$RAW_DIR" ] && [ ! -d "$RNEX_ROOT/$RAW_DIR/.vitepress" ]; then
  _raw_abs="$(cd "$RNEX_ROOT/$RAW_DIR" 2>/dev/null && pwd -P || true)"
  _wiki_raw_abs="$(cd "$WIKI_RAW_DIR" 2>/dev/null && pwd -P || true)"
  if [ -n "$_raw_abs" ] && [ "$_raw_abs" != "$_wiki_raw_abs" ]; then
    find "$RNEX_ROOT/$RAW_DIR" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.json" \) 2>/dev/null | while read -r filepath; do
      filename=$(basename "$filepath")
      # Prevent overwriting standard operational files
      if [ "$filename" != "index.md" ] && [ "$filename" != "hot.md" ] && [ "$filename" != "_log.md" ]; then
        cp "$filepath" "$WIKI_RAW_DIR/$filename"
      fi
    done
  fi
fi

# Ingest member repository README into atomic wiki page, index, and hot cache
ingest_member_readme() {
  _m_repo="$1"
  _m_path="$2"
  _m_readme="$3"
  _src_file="$_m_path/$_m_readme"
  _target_page="$_wiki_path/repo-${_m_repo}.md"
  _today="$(date +%Y-%m-%d 2>/dev/null || date +%F 2>/dev/null || echo "2026-10-15")"

  [ -f "$_src_file" ] || return 0

  # Clean relative paths for source references
  _clean_repos="$(printf '%s' "$REPOS_DIR" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
  _rel_source="${_clean_repos}/${_m_repo}/${_m_readme}"
  _rel_loc="${_clean_repos}/${_m_repo}/"

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

  # 3. Determine if target page needs generation (missing or source newer)
  _needs_gen=0
  if [ ! -f "$_target_page" ]; then
    _needs_gen=1
  elif [ "$_src_file" -nt "$_target_page" ]; then
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
  if [ -f "$_wiki_path/hot.md" ] && ! grep -q "${_rel_loc}" "$_wiki_path/hot.md"; then
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

# 2. Automatically sync README.md from all enabled/cloned member repositories
# Get list of enabled repositories using a secure cross-repo read or `rnex list`
REPOS_DIR_VAL=$(grep -h -E '^\s*repos_dir:' "$RNEX_ROOT/rnex.yaml" "$RNEX_ROOT/.local.rnex.yaml" 2>/dev/null | tail -n1 | awk -F: '{print $NF}' | awk '{print $1}' | tr -d '"'\''')
REPOS_DIR="${REPOS_DIR_VAL:-./repos}"

if [ -d "$RNEX_ROOT/$REPOS_DIR" ]; then
  for repo_path in "$RNEX_ROOT/$REPOS_DIR"/*; do
    [ ! -d "$repo_path" ] && continue
    repo_name=$(basename "$repo_path")
    
    # Check if this repository is explicitly disabled in .local.rnex.yaml or rnex.yaml (block-scoped)
    _is_disabled=""
    for _cfg_file in "$RNEX_ROOT/.local.rnex.yaml" "$RNEX_ROOT/rnex.yaml"; do
      [ -f "$_cfg_file" ] || continue
      _en="$(awk -v repo="$repo_name" '
        /^repos:[ ]*$/ || /^repos:[ ]*#/ { r=1; next }
        r && /^[^ #]/ { r=0 }
        r && match($0, "^  " repo ":[ ]*(#.*)?$") { in_target=1; next }
        in_target && /^  [^ #]/ { in_target=0 }
        in_target && match($0, "^    enabled:[ ]*") {
          line = $0
          sub("^    enabled:[ ]*", "", line)
          sub(/[ ]*#.*$/, "", line)
          gsub(/^["\x27]|["\x27]$/, "", line)
          print line
          exit
        }
      ' "$_cfg_file")"
      if [ -n "$_en" ]; then
        case "$(printf '%s' "$_en" | tr '[:upper:]' '[:lower:]')" in
          false|no|0|disabled|off) _is_disabled=1 ;;
          *) _is_disabled=0 ;;
        esac
        break
      fi
    done
    [ "$_is_disabled" = "1" ] && continue

    # Read and sync any README file with case-insensitive check
    for readme_name in README.md readme.md README.markdown README; do
      if [ -f "$repo_path/$readme_name" ]; then
        # Namespace the copied file with its repo name to prevent conflicts
        cp "$repo_path/$readme_name" "$WIKI_RAW_DIR/README_${repo_name}.md"
        # Ingest member repository README into atomic wiki page, index, and hot cache
        ingest_member_readme "$repo_name" "$repo_path" "$readme_name"
        break
      fi
    done
  done
fi

# 3. Enforce strict ~500-word ceiling on hot.md (condense Section 1 if needed)
if [ -f "$_wiki_path/hot.md" ]; then
  _hot_words="$(wc -w < "$_wiki_path/hot.md" 2>/dev/null || echo 0)"
  if [ "$_hot_words" -gt 480 ]; then
    _num_repos="$(grep -cE '^\* \*\*[a-zA-Z0-9_.-]+ \(`?repos/' "$_wiki_path/hot.md" 2>/dev/null || echo 0)"
    if [ "$_num_repos" -gt 3 ]; then
      _repo_names="$(grep -E '^\* \*\*[a-zA-Z0-9_.-]+ \(`?repos/' "$_wiki_path/hot.md" | sed -e 's/^\* \*\*//' -e 's/ .*//' | tr '\n' ', ' | sed -e 's/, $//')"
      _clean_repos="$(printf '%s' "$REPOS_DIR" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
      _tmp_b="$(mktemp)"
      if awk -v rnames="$_repo_names" -v nrepos="$_num_repos" -v rdir="$_clean_repos" '
        BEGIN { in_s1=0; replaced=0 }
        /^## 1\. Architecture & Member Repo Map/ { in_s1=1; print; next }
        in_s1 && /^## / { in_s1=0 }
        in_s1 && /^\* \*\*[a-zA-Z0-9_.-]+ \(`?repos\// {
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

