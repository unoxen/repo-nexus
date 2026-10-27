#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/ai.sh — Workspace AI context, .gitignore/.ignore, and skill orchestration
# ============================================================================

# ---- Gitignore & Search Tool Ignore Reconciliation -------------------------

GITIGNORE_MARKER_START="# REPO-NEXUS:START"
GITIGNORE_MARKER_END="# REPO-NEXUS:END"

# Emit the delimited Repo Nexus .gitignore section synced with git.ignore configuration.
_build_rnex_gitignore_section() {
  _active_repos_dir="$(yaml_get_repos_dir 2>/dev/null || printf 'repos')"
  [ -n "$_active_repos_dir" ] || _active_repos_dir="repos"
  cat <<GI_SECTION_EOF
$GITIGNORE_MARKER_START
# Managed by Repo Nexus (rnex) — synced with git.ignore in workspace configuration
# Member repos (managed by rnex, ignored at workspace level)
${_active_repos_dir}/
${_active_repos_dir}/*
!${_active_repos_dir}/.gitkeep

# Recursive Repo Nexus directories (trailing slashes prevent ignoring rnex executable or rnex.yaml)
**/.rnex*/
**/rnex*/
.rnex*/
rnex*/

# Local machine-specific configuration
$RNEX_LOCAL_CONFIG_FILE
.rnex.local.yaml
GI_SECTION_EOF

  _custom_ignores="$(yaml_get_git_ignore 2>/dev/null || true)"
  if [ -n "$_custom_ignores" ]; then
    _added_custom_header=0
    _seen_custom=""
    printf '%s\n' "$_custom_ignores" | while IFS= read -r _ci || [ -n "$_ci" ]; do
      [ -n "$_ci" ] || continue
      case "$_ci" in
        "repos/"|"repos/*"|"!repos/.gitkeep"|"${_active_repos_dir}/"|"${_active_repos_dir}/*"|"!${_active_repos_dir}/.gitkeep"|"**/.rnex*/"|"**/rnex*/"|".rnex*/"|"rnex*/"|"$RNEX_LOCAL_CONFIG_FILE"|".rnex.local.yaml")
          continue
          ;;
      esac
      case "
$_seen_custom
" in
        *"
$_ci
"*) continue ;;
      esac
      _seen_custom="${_seen_custom:+$_seen_custom
}$_ci"
      if [ "$_added_custom_header" -eq 0 ]; then
        printf '\n# Custom entries from git.ignore in workspace configuration\n'
        _added_custom_header=1
      fi
      printf '%s\n' "$_ci"
    done
  fi

  printf '%s\n' "$GITIGNORE_MARKER_END"
}

# Reconcile workspace root .gitignore and .ignore:
# - Maintains a delimited (# REPO-NEXUS:START ... # REPO-NEXUS:END) section in .gitignore
# - Synchronizes the section with git.ignore from rnex.yaml and .local.rnex.yaml
# - Preserves user-authored .gitignore rules outside the managed section
# - Ensures .ignore un-ignores repos/* so ripgrep and AI tools can index member files
reconcile_gitignore() {
  _dir="${1:-$NEXUS_DIR}"
  _gi="$_dir/.gitignore"
  _sec_tmp="$(mktemp)"
  _build_rnex_gitignore_section > "$_sec_tmp"
  _active_repos_dir="$(yaml_get_repos_dir 2>/dev/null || printf 'repos')"
  [ -n "$_active_repos_dir" ] || _active_repos_dir="repos"

  if [ ! -f "$_gi" ]; then
    mv "$_sec_tmp" "$_gi"
    log_ok "Created .gitignore (ignoring ${_active_repos_dir}/, recursive .rnex directories, and $RNEX_LOCAL_CONFIG_FILE)"
  else
    # 1. Strip any legacy lint_trigger_counter entries if present
    if grep -q "lint_trigger_counter" "$_gi" 2>/dev/null; then
      _tmp="$(mktemp)"
      grep -v "lint_trigger_counter" "$_gi" > "$_tmp" && mv "$_tmp" "$_gi"
      log_ok "Removed legacy lint trigger counter entries from .gitignore"
    fi

    # 2. If delimited section exists, replace it in-place with the newly synced section
    if grep -qFx -- "$GITIGNORE_MARKER_START" "$_gi" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk -v s="$GITIGNORE_MARKER_START" -v e="$GITIGNORE_MARKER_END" -v src="$_sec_tmp" '
        $0 == s {
          in_b = 1
          while ((getline line < src) > 0) print line
          close(src)
          next
        }
        $0 == e {
          in_b = 0
          next
        }
        !in_b { print }
      ' "$_gi" > "$_tmp" && mv "$_tmp" "$_gi"
      rm -f "$_sec_tmp"
    else
      # 3. Upgrade legacy un-delimited .gitignore or append managed section to existing user .gitignore
      _user_tmp="$(mktemp)"
      awk -v local_cfg="$RNEX_LOCAL_CONFIG_FILE" -v ard="$_active_repos_dir" '
        /^[ ]*#[ ]*Member repos \(managed by rnex/ { next }
        /^[ ]*#[ ]*Recursive Repo Nexus directories/ { next }
        /^[ ]*#?[ ]*Repo Nexus internal state/ { next }
        /^[ ]*#[ ]*Local machine-specific configuration/ { next }
        /^[ ]*#[ ]*Custom entries from git\.ignore in workspace configuration/ { next }
        $0 == "repos/*" || $0 == "!repos/.gitkeep" || $0 == "repos/" { next }
        $0 == (ard "/*") || $0 == ("!" ard "/.gitkeep") || $0 == (ard "/") { next }
        $0 == "**/.rnex*/" || $0 == "**/rnex*/" || $0 == ".rnex*/" || $0 == "rnex*/" { next }
        $0 == ".rnex" || $0 == "rnex" { next }
        $0 == local_cfg || $0 == ".rnex.local.yaml" { next }
        { lines[++n] = $0 }
        END {
          start = 1
          while (start <= n && lines[start] ~ /^[[:space:]]*$/) start++
          end = n
          while (end >= start && lines[end] ~ /^[[:space:]]*$/) end--
          for (i = start; i <= end; i++) print lines[i]
        }
      ' "$_gi" > "$_user_tmp"

      _tmp="$(mktemp)"
      if [ -s "$_user_tmp" ]; then
        cat "$_user_tmp" > "$_tmp"
        printf '\n' >> "$_tmp"
      fi
      cat "$_sec_tmp" >> "$_tmp"
      mv "$_tmp" "$_gi"
      rm -f "$_user_tmp" "$_sec_tmp"
    fi
  fi

  # Universal search tool ignore file (ripgrep, Claude Code, VS Code, Zed)
  ensure_provider_ignore "$_dir/.ignore" \
    "Member repos (un-ignored for ripgrep, Claude Code, VS Code, and search tools)" \
    "Created .ignore (un-ignoring member repos for search tools)" \
    "!${_active_repos_dir}/*"
}

# Clean managed Repo Nexus ignore block from .gitignore, removing file if empty
clean_rnex_gitignore() {
  _dir="${1:-$NEXUS_DIR}"
  _gi="$_dir/.gitignore"
  [ -f "$_gi" ] || return 0
  if grep -qFx -- "${GITIGNORE_MARKER_START:-# REPO-NEXUS:START}" "$_gi" 2>/dev/null; then
    _user_content="$(awk -v s="${GITIGNORE_MARKER_START:-# REPO-NEXUS:START}" -v e="${GITIGNORE_MARKER_END:-# REPO-NEXUS:END}" '
      $0 == s { in_b = 1; next }
      $0 == e { in_b = 0; next }
      !in_b { print }
    ' "$_gi" | sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d')"
    if [ -z "$_user_content" ]; then
      rm -f "$_gi"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed .gitignore"
    else
      _tmp="$(mktemp)"
      awk -v s="${GITIGNORE_MARKER_START:-# REPO-NEXUS:START}" -v e="${GITIGNORE_MARKER_END:-# REPO-NEXUS:END}" '
        $0 == s { in_b = 1; next }
        $0 == e { in_b = 0; next }
        !in_b { print }
      ' "$_gi" > "$_tmp" && mv "$_tmp" "$_gi"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed Repo Nexus rules from .gitignore"
    fi
  fi
}

# ---- AI Instructions Compilation (.rnex/ai-instructions.md) ----------------

# Resolve the primary instruction file for an AI provider plugin
plugin_get_instruction_file() {
  _pif_name="$1"
  _pif_pdir="${2:-}"
  [ -n "$_pif_pdir" ] || _pif_pdir="$(find_plugin_dir "$_pif_name" 2>/dev/null || true)"
  _pif_file=""
  if [ -n "$_pif_pdir" ]; then
    _pif_file="$(plugin_get_field "$_pif_pdir" "instruction_file" 2>/dev/null || true)"
  fi
  if [ -z "$_pif_file" ]; then
    case "$_pif_name" in
      claude)   _pif_file="CLAUDE.md" ;;
      gemini)   _pif_file="GEMINI.md" ;;
      cursor)   _pif_file=".cursorrules" ;;
      windsurf) _pif_file=".windsurfrules" ;;
      codex)    _pif_file="CODEX.md" ;;
      copilot)  _pif_file=".github/copilot-instructions.md" ;;
      agents|agent) _pif_file="AGENTS.md" ;;
    esac
  fi
  printf '%s' "$_pif_file"
}

# Enumerate primary instruction files for currently enabled AI provider plugins
get_active_provider_instruction_files() {
  _gap_dir="${1:-$NEXUS_DIR}"
  _gap_files=""
  for _p in $(yaml_list_plugins 2>/dev/null || true); do
    [ -n "$_p" ] || continue
    yaml_plugin_enabled "$_p" 2>/dev/null || continue
    _ifile="$(plugin_get_instruction_file "$_p" 2>/dev/null || true)"
    if [ -n "$_ifile" ]; then
      case " $_gap_files " in
        *" $_ifile "*) ;;
        *) _gap_files="${_gap_files:+$_gap_files }$_ifile" ;;
      esac
    fi
  done
  printf '%s' "$_gap_files"
}

# Check if an instruction file contains custom user instructions outside the rnex block
file_has_user_content() {
  _fhuc_file="$1"
  [ -f "$_fhuc_file" ] || return 1
  _content=""
  if grep -qF "${AI_MARKER_START:-<!-- REPO-NEXUS:START -->}" "$_fhuc_file" 2>/dev/null; then
    _content="$(awk -v s="${AI_MARKER_START:-<!-- REPO-NEXUS:START -->}" -v e="${AI_MARKER_END:-<!-- REPO-NEXUS:END -->}" '
      $0 == s { in_b = 1; next }
      $0 == e { in_b = 0; next }
      !in_b { print }
    ' "$_fhuc_file" | sed -e '/^[[:space:]]*$/d')"
  else
    _content="$(grep -v "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$_fhuc_file" 2>/dev/null | grep -v "Multi-Repo AI Workspace Context" | sed -e '/^[[:space:]]*$/d')"
  fi
  [ -n "$_content" ]
}

# Reconcile AI provider instruction files:
# - When provider plugins are enabled (e.g. Gemini, Claude), creates/updates their specific instruction files (GEMINI.md, CLAUDE.md)
# - Only creates AGENTS.md if it is the main instructions file for an enabled AI provider or no provider plugins are enabled
# - Cleans up instruction files that have no user content when their provider is disabled or inactive
reconcile_ai_instructions_files() {
  _raif_dir="${1:-$NEXUS_DIR}"
  _active_files="$(get_active_provider_instruction_files "$_raif_dir" 2>/dev/null || true)"

  if [ -n "$_active_files" ]; then
    # Active AI providers are configured with their own instruction files
    for _af in $_active_files; do
      merge_rnex_instructions "$_raif_dir/$_af"
    done

    # If AGENTS.md is not an active provider instruction file, clean rnex instructions from it
    # (deleting it if solely rnex-managed, or stripping the rnex block if user content exists)
    case " $_active_files " in
      *" AGENTS.md "*) ;;
      *)
        if [ -f "$_raif_dir/AGENTS.md" ]; then
          clean_rnex_instructions "$_raif_dir/AGENTS.md"
        fi
        ;;
    esac
  else
    # No provider plugins enabled: AGENTS.md serves as the default main instructions file
    merge_rnex_instructions "$_raif_dir/AGENTS.md"
  fi

  # For any existing instruction files on disk that are NOT currently active:
  # Clean rnex instructions (removing file if empty outside block, or stripping rnex block)
  for _if in CLAUDE.md GEMINI.md CODEX.md .cursorrules .windsurfrules .github/copilot-instructions.md; do
    case " $_active_files " in
      *" $_if "*) ;;
      *)
        if [ -f "$_raif_dir/$_if" ]; then
          clean_rnex_instructions "$_raif_dir/$_if"
        fi
        ;;
    esac
  done
}

# Return 0 if a plugin is an IDE/AI provider integration (explicitly declares
# type: provider or owns a top-level instruction file such as CLAUDE.md).
# Provider setup docs are never compiled into .rnex/ai-instructions.md.
plugin_is_provider() {
  _pip_name="$1"
  _pip_pdir="${2:-}"
  [ -n "$_pip_pdir" ] || _pip_pdir="$(find_plugin_dir "$_pip_name" 2>/dev/null || true)"
  if [ -n "$_pip_pdir" ] && [ -f "$_pip_pdir/plugin.yaml" ]; then
    _pip_type="$(plugin_get_field "$_pip_pdir" "type" 2>/dev/null || true)"
    case "$_pip_type" in
      provider) return 0 ;;
      workflow) return 1 ;;
    esac
  fi
  [ -n "$(plugin_get_instruction_file "$_pip_name" "$_pip_pdir" 2>/dev/null || true)" ]
}

# Escape a value for safe use inside a Markdown table cell.
_ai_md_cell() {
  printf '%s' "$1" | sed -e 's/|/\\|/g'
}

# Join newline-separated items into a "`a`, `b`" Markdown list on one line.
_ai_md_code_list() {
  awk 'NF { printf "%s`%s`", (n++ ? ", " : ""), $0 } END { if (n) printf "\n" }'
}

# Emit instruction files of enabled non-provider, non-built-in plugins (custom workflow plugins).
_ai_emit_workflow_plugin_instructions() {
  _aewp_dir="$1"; _aewp_p="$2"
  _aewp_pdir="$(find_plugin_dir "$_aewp_p" 2>/dev/null || true)"
  _aewp_files=""
  if [ -n "$_aewp_pdir" ] && [ -f "$_aewp_pdir/plugin.yaml" ]; then
    for _aewp_item in $(plugin_list_instructions "$_aewp_pdir" 2>/dev/null || true); do
      _aewp_src="$(printf '%s' "${_aewp_item%%:*}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [ -n "$_aewp_src" ] || continue
      if [ -f "$_aewp_dir/.rnex/plugins/$_aewp_p/$_aewp_src" ]; then
        _aewp_files="${_aewp_files:+$_aewp_files }$_aewp_dir/.rnex/plugins/$_aewp_p/$_aewp_src"
      elif [ -f "$_aewp_pdir/$_aewp_src" ]; then
        _aewp_files="${_aewp_files:+$_aewp_files }$_aewp_pdir/$_aewp_src"
      fi
    done
  fi
  if [ -z "$_aewp_files" ]; then
    if [ -f "$_aewp_dir/.rnex/plugins/$_aewp_p/instructions.md" ]; then
      _aewp_files="$_aewp_dir/.rnex/plugins/$_aewp_p/instructions.md"
    elif [ -n "$_aewp_pdir" ] && [ -f "$_aewp_pdir/instructions.md" ]; then
      _aewp_files="$_aewp_pdir/instructions.md"
    fi
  fi
  for _aewp_f in $_aewp_files; do
    printf '\n### Plugin Directives (`%s`)\n' "$_aewp_p"
    # Demote headings so plugin docs nest under Section 4.
    sed -e 's/^\(#\{1,\}\) /\1## /' "$_aewp_f"
  done
}

# Render the full deterministic contents of .rnex/ai-instructions.md to stdout.
# Output depends only on the merged configuration and RNEX_VERSION.
render_ai_instructions() {
  _rai_dir="${1:-$NEXUS_DIR}"
  (
    if [ -z "${NEXUS_DIR:-}" ] || [ "$_rai_dir" != "${NEXUS_DIR:-}" ]; then
      NEXUS_DIR="$_rai_dir"
      WORKSPACE_YAML="$_rai_dir/${RNEX_CONFIG_FILE:-rnex.yaml}"
      WORKSPACE_LOCAL_YAML="$_rai_dir/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
      export NEXUS_DIR WORKSPACE_YAML WORKSPACE_LOCAL_YAML
    fi
    _rai_rd="$(yaml_get_repos_dir 2>/dev/null || true)"
    [ -n "$_rai_rd" ] || _rai_rd="repos"
    _rai_ws="$(yaml_get_top_level "name" 2>/dev/null || true)"
    [ -n "$_rai_ws" ] || _rai_ws="$(basename "$_rai_dir")"
    _rai_plugins="$(yaml_list_enabled_plugins_sorted 2>/dev/null || true)"

    _rai_kp=0
    _rai_wiki=""
    _rai_src_dirs=""
    if printf '%s\n' "$_rai_plugins" | grep -qx "karpathy-llm"; then
      _rai_kp=1
      _rai_wiki="$(yaml_get_merged_plugin_config "karpathy-llm" "wiki_dir" "wiki" 2>/dev/null | sed -n '1p')"
      _rai_wiki="${_rai_wiki%/}"
      [ -n "$_rai_wiki" ] || _rai_wiki="wiki"
      _rai_src_dirs="$(yaml_get_merged_plugin_config "karpathy-llm" "sources" 2>/dev/null | grep -v '[*?]' | sed -e 's#/*$#/#' | _ai_md_code_list)"
    fi

    # Header & Section 1
    printf '# Repo Nexus Workspace Instructions (rnex v%s)\n\n' "${RNEX_VERSION:-unknown}"
    printf '> Pre-compiled from merged workspace configuration (`.local.rnex.yaml` > `rnex.yaml`).\n\n'
    printf '## 1. Strict Operating Constraints\n'
    printf -- '- **NO CONFIG READS**: DO NOT read or search for rnex.yaml or .local.rnex.yaml. The complete merged configuration is embedded in Section 2.\n'
    printf -- '- **READ FILES ONCE**: Read each file at most once per session. Never re-read a file already in context.\n'
    if [ "$_rai_kp" -eq 1 ]; then
      printf -- '- **NO BLIND SCANS**: Never run broad directory scans or unbounded searches across `%s/`%s.\n' "$_rai_rd" "${_rai_src_dirs:+ or raw intake directories ($_rai_src_dirs)}"
    else
      printf -- '- **NO BLIND SCANS**: Never run broad directory scans or unbounded searches across `%s/`.\n' "$_rai_rd"
    fi

    # Section 2
    printf '\n## 2. Merged Workspace Configuration\n'
    printf -- '- **Workspace**: `%s`\n' "$_rai_ws"
    printf -- '- **Repositories Root**: `%s/`\n' "$_rai_rd"
    _rai_pl="$(printf '%s\n' "$_rai_plugins" | _ai_md_code_list)"
    printf -- '- **Enabled Plugins**: %s\n' "${_rai_pl:-_none_}"

    _rai_rows=""
    _rai_disabled=""
    for _rai_r in $(yaml_list_all_repos_sorted 2>/dev/null || true); do
      if ! is_enabled_val "$(yaml_get_merged_repo_field "$_rai_r" "enabled" "true")"; then
        _rai_disabled="${_rai_disabled}${_rai_r}
"
        continue
      fi
      _rai_br="$(yaml_get_merged_repo_field "$_rai_r" "branch" "main")"
      _rai_mode="READ-WRITE"
      is_truthy "$(yaml_get_merged_repo_field "$_rai_r" "readonly" "false")" && _rai_mode="READ-ONLY"
      _rai_desc="$(_ai_md_cell "$(yaml_get_merged_repo_field "$_rai_r" "description" "")")"
      _rai_rows="${_rai_rows}| \`${_rai_r}\` | \`${_rai_rd}/${_rai_r}/\` | \`${_rai_br}\` | \`${_rai_mode}\` | ${_rai_desc} |
"
    done

    printf '\n### Active Member Repositories\n'
    if [ -n "$_rai_rows" ]; then
      printf '| Repository | Path | Branch | Mode | Description |\n'
      printf '| :--- | :--- | :--- | :--- | :--- |\n'
      printf '%s' "$_rai_rows"
    else
      printf '_No active member repositories._\n'
    fi
    if [ -n "$_rai_disabled" ]; then
      printf '\n- **Disabled Repositories (Do Not Access)**: %s\n' "$(printf '%s' "$_rai_disabled" | _ai_md_code_list)"
    fi

    if [ "$_rai_kp" -eq 1 ]; then
      _rai_srcs="$(yaml_get_merged_plugin_config "karpathy-llm" "sources" 2>/dev/null | _ai_md_code_list)"
      printf '\n### Resolved Knowledge Base (`karpathy-llm`)\n'
      printf -- '- **Curated Wiki Path**: `%s/`\n' "$_rai_wiki"
      printf -- '- **Raw Intake Sources**: %s *(read-only inputs used strictly during `rnex plugin karpathy-llm ingest`; do not browse during normal tasks)*\n' "${_rai_srcs:-_none_}"
    fi

    # Section 3
    printf '\n## 3. Mandatory Execution Sequence\n'
    printf 'Execute these steps in strict order:\n'
    _rai_n=1
    if [ "$_rai_kp" -eq 1 ]; then
      printf '1. **Step 1 — Read Wiki Hot Cache**: Read `%s/hot.md` first for workspace architecture, repository boundaries, and active contracts.\n' "$_rai_wiki"
      printf '2. **Step 2 — Lookup Topic in Wiki Index**: If task details are not fully covered in `%s/hot.md`, read `%s/index.md` and read only the relevant atomic page(s) in `%s/`. Do NOT read raw intake sources%s or `%s/` before completing Steps 1–2.\n' "$_rai_wiki" "$_rai_wiki" "$_rai_wiki" "${_rai_src_dirs:+ ($_rai_src_dirs)}" "$_rai_rd"
      _rai_n=3
    fi
    printf '%s. **Step %s — Targeted Repository Access**: Inspect or modify only the specific files in active `%s/<name>/` required for the task. Never modify or commit inside `READ-ONLY` repositories.\n' "$_rai_n" "$_rai_n" "$_rai_rd"
    _rai_n=$((_rai_n + 1))
    printf '%s. **Step %s — Git & Maintenance**: Commit and push inside `%s/<name>/`. Run `rnex sync` if workspace state changes.\n' "$_rai_n" "$_rai_n" "$_rai_rd"

    # Section 4
    printf '\n## 4. Coding & Wiki Directives\n'
    if [ -d "$_rai_dir/.rnex/skills" ] && [ -n "$(ls -A "$_rai_dir/.rnex/skills" 2>/dev/null)" ]; then
      printf -- '- **Skills**: `.rnex/skills/` (load a skill only when its task applies).\n'
    fi
    if [ -d "$_rai_dir/.rnex/agents" ] && [ -n "$(ls -A "$_rai_dir/.rnex/agents" 2>/dev/null)" ]; then
      printf -- '- **Subagents**: `.rnex/agents/`.\n'
    fi
    if [ "$_rai_kp" -eq 1 ]; then
      printf -- '- **Behavioral Rules**: (1) State assumptions and surface trade-offs before coding; (2) Prefer minimal, non-speculative code; (3) Make surgical edits touching only required lines; (4) Verify changes against concrete goals.\n'
      printf -- '- **Wiki Operations**: Never edit `%s/` files ad-hoc. To ingest raw sources or validate wiki frontmatter/links, run `rnex plugin karpathy-llm ingest` or `rnex plugin karpathy-llm lint` (or load `.rnex/plugins/karpathy-llm/skills/` only when executing ingestion/linting).\n' "$_rai_wiki"
    fi

    for _rai_p in $_rai_plugins; do
      [ "$_rai_p" = "karpathy-llm" ] && continue
      plugin_is_provider "$_rai_p" && continue
      _ai_emit_workflow_plugin_instructions "$_rai_dir" "$_rai_p"
    done
  )
}

# Compile the unified .rnex/ai-instructions.md file consumed by AI coding agents.
# Writes atomically and only replaces the file when content changes.
build_ai_instructions() {
  _dir="${1:-$NEXUS_DIR}"
  _ai_file="$_dir/.rnex/ai-instructions.md"
  mkdir -p "$_dir/.rnex"
  _out_tmp="$(mktemp "$_dir/.rnex/.ai-instructions.XXXXXX")"
  render_ai_instructions "$_dir" > "$_out_tmp"
  if [ -f "$_ai_file" ] && cmp -s "$_out_tmp" "$_ai_file"; then
    rm -f "$_out_tmp"
  else
    mv "$_out_tmp" "$_ai_file"
  fi
}

generate_ai_instructions() {
  build_ai_instructions "$@"
}

# ---- Multi-Root IDE Workspace (.code-workspace) ----------------------------

# Generate and maintain a multi-root VS Code / Cursor workspace file (.code-workspace).
# Adds workspace root and each active member repository as first-class workspace folders.
sync_code_workspace() {
  [ -n "$CODE_WORKSPACE_FILE" ] || return 0
  _ws_path="$NEXUS_DIR/$CODE_WORKSPACE_FILE"
  _root_name="$(basename "$NEXUS_DIR")"

  _f_tmp="$(mktemp)"

  printf '    {\n      "name": "%s (Workspace Root)",\n      "path": "."\n    }' "$_root_name" > "$_f_tmp"

  _repos_rel="${REPOS_DIR#"$NEXUS_DIR"/}"
  _repos_rel="${_repos_rel#./}"
  [ -n "$_repos_rel" ] || _repos_rel="repos"

  yaml_list_repos | while read -r _rname; do
    [ -n "$_rname" ] || continue
    if yaml_repo_enabled "$_rname"; then
      _rdir="$(resolve_repo_path "$_rname")"
      if [ -d "$_rdir" ]; then
        printf ',\n    {\n      "name": "%s",\n      "path": "%s/%s"\n    }' "$_rname" "$_repos_rel" "$_rname" >> "$_f_tmp"
      fi
    fi
  done

  if [ ! -f "$_ws_path" ]; then
    {
      printf '{\n  "folders": [\n'
      cat "$_f_tmp"
      printf '\n  ],\n  "settings": {\n    "search.exclude": {\n      "**/node_modules": true,\n      "**/.git": true\n    }\n  }\n}\n'
    } > "$_ws_path"
    rm -f "$_f_tmp"
    log_ok "Created $CODE_WORKSPACE_FILE (VS Code / Cursor multi-root workspace)"
    return 0
  fi

  if grep -q '"folders"[ ]*:' "$_ws_path" 2>/dev/null; then
    _tmp_out="$(mktemp)"
    awk -v f_src="$_f_tmp" '
      BEGIN { in_f = 0 }
      /"folders"[ ]*:[ ]*\[/ {
        in_f = 1
        print "  \"folders\": ["
        while ((getline line < f_src) > 0) print line
        close(f_src)
        next
      }
      in_f {
        if (/\]/) {
          in_f = 0
          has_comma = ($0 ~ /,[ ]*$/) ? "," : ""
          print "  ]" has_comma
        }
        next
      }
      { print }
    ' "$_ws_path" > "$_tmp_out" && mv "$_tmp_out" "$_ws_path"
    rm -f "$_f_tmp"
    log_ok "Updated folders in $CODE_WORKSPACE_FILE"
  else
    {
      printf '{\n  "folders": [\n'
      cat "$_f_tmp"
      printf '\n  ],\n  "settings": {\n    "search.exclude": {\n      "**/node_modules": true,\n      "**/.git": true\n    }\n  }\n}\n'
    } > "$_ws_path"
    rm -f "$_f_tmp"
    log_ok "Updated $CODE_WORKSPACE_FILE"
  fi
}

# ---- Provider Skill Directory & Base Asset Synchronization -----------------

write_rnex_env_script() {
  _dir="${1:-$NEXUS_DIR}"
  _bin_dir="$_dir/.rnex/bin"
  mkdir -p "$_bin_dir"
  _env_script="$_bin_dir/rnex-env.sh"
  _src_sdk=""
  for _cand in \
    "${RNEX_LIB_DIR:-}/sdk.sh" \
    "$SCRIPT_LOCATION/lib/sdk.sh" \
    "$(dirname "$SCRIPT_LOCATION")/lib/sdk.sh" \
    "$_dir/lib/sdk.sh"; do
    if [ -n "$_cand" ] && [ -f "$_cand" ]; then
      _src_sdk="$_cand"
      break
    fi
  done
  if [ -n "$_src_sdk" ]; then
    cp "$_src_sdk" "$_env_script"
  fi
  chmod +x "$_env_script" 2>/dev/null || true
}

get_active_provider_skill_dirs() {
  _dirs=""
  for _p in $(yaml_list_plugins 2>/dev/null || true); do
    [ -n "$_p" ] || continue
    yaml_plugin_enabled "$_p" 2>/dev/null || continue
    if provider_option_enabled "$_p" "skills" 2>/dev/null; then
      _sdir="$(plugin_get_skill_dir "$_p")"
      if [ -n "$_sdir" ]; then
        case " $_dirs " in
          *" $_sdir "*) ;;
          *) _dirs="${_dirs:+$_dirs }$_sdir" ;;
        esac
      fi
    fi
  done
  printf '%s' "$_dirs"
}

# Synchronize built-in core agentic skills into .rnex/skills/ and register
# zero-logic user skill pointers across all active AI assistant directories.
sync_rnex_base_assets() {
  _src_toolkit=""
  if [ -d "$SCRIPT_LOCATION/toolkit" ]; then
    _src_toolkit="$SCRIPT_LOCATION/toolkit"
  elif [ -d "$(dirname "$SCRIPT_LOCATION")/toolkit" ]; then
    _src_toolkit="$(dirname "$SCRIPT_LOCATION")/toolkit"
  elif [ -d "$NEXUS_DIR/toolkit" ]; then
    _src_toolkit="$NEXUS_DIR/toolkit"
  fi

  # Purge obsolete .rnex/prompts/ and .rnex/workflows/
  rm -rf "$NEXUS_DIR/.rnex/prompts" "$NEXUS_DIR/.rnex/workflows" 2>/dev/null || true

  # Ensure .rnex/skills exists
  mkdir -p "$NEXUS_DIR/.rnex/skills"

  # Clean old skill subdirectories if any exist in .rnex/skills/
  for _item in "$NEXUS_DIR/.rnex/skills"/*; do
    [ -e "$_item" ] || continue
    [ -d "$_item" ] && rm -rf "$_item"
  done

  # Sync base skills to .rnex/skills/
  if [ -n "$_src_toolkit" ] && [ -d "$_src_toolkit/skills" ]; then
    cp -f "$_src_toolkit"/skills/*.md "$NEXUS_DIR/.rnex/skills/" 2>/dev/null || true
  fi

  # Purge any plugin-declared skills that may have been placed in core .rnex/skills/
  for _pdir in $(list_all_available_plugin_dirs 2>/dev/null || true); do
    if [ -d "$_pdir/skills" ]; then
      for _psk in "$_pdir/skills"/*.md; do
        [ -f "$_psk" ] || continue
        _sbase="$(basename "$_psk")"
        _sname="$(basename "$_psk" .md)"
        rm -f "$NEXUS_DIR/.rnex/skills/$_sbase" "$NEXUS_DIR/.rnex/skills/rnex-$_sbase" 2>/dev/null || true
        for _p_dir in $(get_active_provider_skill_dirs 2>/dev/null || true); do
          rm -f "$NEXUS_DIR/$_p_dir/rnex-$_sbase" 2>/dev/null || true
          rm -rf "$NEXUS_DIR/$_p_dir/rnex-$_sname" 2>/dev/null || true
        done
      done
    fi
  done

  # Register core User Skills across active provider directories
  for _sk_file in "$NEXUS_DIR/.rnex/skills"/*.md; do
    [ -f "$_sk_file" ] || continue
    _sk_name="$(basename "$_sk_file" .md)"
    rnex_register_user_skill "$_sk_name" ".rnex/skills/${_sk_name}.md"
  done
}

sync_skills() {
  write_rnex_env_script "$NEXUS_DIR"
  sync_rnex_base_assets
}
